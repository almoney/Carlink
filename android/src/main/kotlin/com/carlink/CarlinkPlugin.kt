package com.carlink

/**
 * CarlinkPlugin - Flutter Platform Integration for Carlink Android
 *
 * PURPOSE:
 * This plugin bridges Flutter/Dart with Android native USB and video capabilities to enable
 * communication with CPC200-CCPA wireless CarPlay/Android Auto adapters. It handles the complete
 * lifecycle of USB device interaction, real-time H.264 video streaming, and hardware resource
 * management.
 *
 * CORE RESPONSIBILITIES:
 * - Plugin Lifecycle: Initialization and cleanup of all managers and handlers
 * - Callback Routing: Routes callbacks from BulkTransferHandler to Flutter layer
 * - Error Recovery: Automatic MediaCodec reset detection and emergency cleanup for stability
 * - Resource Management: Buffer pooling, thread executors, and proper cleanup to prevent leaks
 *
 * REFACTORED ARCHITECTURE:
 * - MethodCallDispatcher: Routes platform method calls to specialized handlers
 * - DisplayMetricsHandler: Display and window metrics operations
 * - VideoHandler: Flutter texture and H.264 rendering operations
 * - UsbDeviceHandler: USB device lifecycle and configuration operations
 * - BulkTransferHandler: USB bulk transfers and reading loop operations
 * - UsbDeviceManager: Handles device discovery, permissions, and connection lifecycle
 * - BulkTransferManager: Manages USB bulk transfers with retry logic and error recovery
 * - VideoTextureManager: Manages Flutter textures and H.264 rendering
 * - AppExecutors: Thread management for USB I/O and MediaCodec operations
 *
 * THREAD SAFETY:
 * Uses dedicated executor threads for USB I/O operations with synchronized access to shared
 * resources. Main thread callbacks ensure Flutter communication happens on the correct thread.
 */
import android.content.Context
import android.util.Log
import com.carlink.handlers.BulkTransferCallbacks
import com.carlink.handlers.BulkTransferHandler
import com.carlink.handlers.DisplayMetricsHandler
import com.carlink.handlers.MethodCallDispatcher
import com.carlink.handlers.UsbDeviceHandler
import com.carlink.handlers.VideoHandler
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

private const val TAG = "CARLINK"

/** CarlinkPlugin */
class CarlinkPlugin :
    FlutterPlugin,
    BulkTransferCallbacks {
    private lateinit var channel: MethodChannel

    // Manager instances (refactored architecture)
    private var videoManager: VideoTextureManager? = null
    private var usbDeviceManager: UsbDeviceManager? = null
    private var bulkTransferManager: BulkTransferManager? = null

    // Method call dispatcher and handlers
    private var methodCallDispatcher: MethodCallDispatcher? = null

    // Error recovery tracking
    private var lastResetTime: Long = 0
    private var consecutiveResets: Int = 0
    private val resetThreshold = 3 // Trigger cleanup after 3 resets
    private val resetWindowMs = 30000 // 30 seconds window

    private var applicationContext: Context? = null

    private val executors: AppExecutors = AppExecutors()

    // Buffer pool for common sizes to reduce GC pressure
    private val bufferPool = mutableMapOf<Int, MutableList<ByteArray>>()
    private val maxPoolSize = 10 // Maximum buffers per size

    // Lifecycle state tracking to prevent MethodChannel usage after detachment
    @Volatile
    private var isAttachedToEngine = false

    // Latch for coordinating reading loop shutdown
    private var readingLoopLatch: java.util.concurrent.CountDownLatch? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "carlink")
        isAttachedToEngine = true

        applicationContext = flutterPluginBinding.applicationContext

        // Critical null check: applicationContext should never be null in normal circumstances
        // If it is null, fail fast with clear error logging
        if (applicationContext == null) {
            Log.e(TAG, "[PLUGIN] CRITICAL ERROR: applicationContext is null in onAttachedToEngine")
            Log.e(TAG, "[PLUGIN] Plugin initialization FAILED - managers will not be initialized")
            isAttachedToEngine = false
            return
        }

        // Initialize managers with proper dependency injection
        val context = applicationContext!!
        val logCallback = LogCallback { message -> log(message) }
        val usbManager = context.getSystemService(android.hardware.usb.UsbManager::class.java)

        // Initialize USB device manager
        usbDeviceManager = UsbDeviceManager(context, usbManager, logCallback)
        log("[PLUGIN] UsbDeviceManager initialized")

        // Initialize bulk transfer manager
        bulkTransferManager = BulkTransferManager(logCallback)
        log("[PLUGIN] BulkTransferManager initialized")

        // Initialize video texture manager
        videoManager =
            VideoTextureManager(
                context,
                flutterPluginBinding.textureRegistry,
                logCallback,
                executors,
            )
        log("[PLUGIN] VideoTextureManager initialized")

        // Initialize method call handlers and dispatcher
        val displayHandler = DisplayMetricsHandler(context, logCallback)
        val videoHandler = VideoHandler(videoManager, logCallback)
        val usbDeviceHandler = UsbDeviceHandler(usbDeviceManager)
        val bulkTransferHandler =
            BulkTransferHandler(
                usbDeviceManager,
                bulkTransferManager,
                videoManager,
                executors,
                // BulkTransferCallbacks
                this,
            )

        methodCallDispatcher =
            MethodCallDispatcher(
                displayHandler,
                videoHandler,
                usbDeviceHandler,
                bulkTransferHandler,
            )

        channel.setMethodCallHandler(methodCallDispatcher)
        log("[PLUGIN] MethodCallDispatcher initialized with all handlers")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Mark as detached FIRST to prevent new channel invocations
        isAttachedToEngine = false

        // Wait for reading loop to finish if active
        readingLoopLatch?.let { latch ->
            try {
                log("[PLUGIN] Waiting for reading loop to finish before detachment...")
                val finished = latch.await(2, java.util.concurrent.TimeUnit.SECONDS)
                if (!finished) {
                    log("[PLUGIN] Reading loop did not finish in time - proceeding with cleanup")
                }
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
                log("[PLUGIN] Interrupted while waiting for reading loop: ${e.message}")
            }
            readingLoopLatch = null
        }

        channel.setMethodCallHandler(null)
        clearBufferPool()

        // Cleanup USB device manager
        try {
            usbDeviceManager?.cleanup()
            usbDeviceManager = null
            log("[PLUGIN] UsbDeviceManager cleaned up during plugin detachment")
        } catch (e: IllegalStateException) {
            log("[PLUGIN] USB device in invalid state during cleanup: ${e.message}")
        } catch (e: SecurityException) {
            log("[PLUGIN] Permission denied during USB cleanup: ${e.message}")
        }

        // Cleanup bulk transfer manager
        bulkTransferManager = null
        log("[PLUGIN] BulkTransferManager cleaned up during plugin detachment")

        // Cleanup video texture resources using manager
        try {
            videoManager?.removeTexture()
            videoManager = null
            log("[PLUGIN] Video texture resources cleaned up during plugin detachment")
        } catch (e: IllegalStateException) {
            log("[PLUGIN] MediaCodec in invalid state during cleanup: ${e.message}")
        } catch (e: android.media.MediaCodec.CodecException) {
            log("[PLUGIN] Codec error during cleanup: ${e.message}")
        }

        // Following Android threading guidelines: shutdown executors to prevent memory leaks
        try {
            executors.shutdown()
            // Give executors time to finish gracefully
            if (!executors.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)) {
                log("Executors did not terminate gracefully, forcing shutdown")
                executors.shutdownNow()
            }
            log("[PLUGIN] AppExecutors instance shut down during plugin detachment")
        } catch (e: InterruptedException) {
            // Re-cancel if current thread also interrupted and preserve interrupt status
            Thread.currentThread().interrupt()
            log("Executor shutdown interrupted: ${e.message}")
            executors.shutdownNow()
        } catch (e: SecurityException) {
            log("Security error during executor shutdown: ${e.message}")
        }

        applicationContext = null
    }

    // ==================== BulkTransferCallbacks Implementation ====================

    override fun isAttached(): Boolean = isAttachedToEngine

    override fun onLog(message: String) {
        log(message)
    }

    override fun onReadingLoopMessage(
        type: Int,
        data: ByteArray?,
    ) {
        if (data != null) {
            safeInvokeMethod("onReadingLoopMessage", mapOf("type" to type, "data" to data))
        } else {
            safeInvokeMethod("onReadingLoopMessage", mapOf("type" to type))
        }
    }

    override fun onReadingLoopError(error: String) {
        // Check if this is a recoverable error and track for error recovery
        if (isRecoverableError(error)) {
            handleCodecReset()
        }

        safeInvokeMethod("onReadingLoopError", error)
    }

    override fun getPooledBuffer(size: Int): ByteArray = getPooledBufferInternal(size)

    override fun returnPooledBuffer(buffer: ByteArray) {
        returnPooledBufferInternal(buffer)
    }

    // ==================== Internal Methods ====================

    /**
     * Safely invokes a method on the Flutter MethodChannel.
     *
     * This method prevents crashes from calling the channel after detachment by:
     * 1. Checking attachment state before invocation
     * 2. Using try-catch to handle RejectedExecutionException from shutdown executors
     * 3. Double-checking attachment state after thread switch
     *
     * @param method The method name to invoke
     * @param arguments The arguments to pass (can be null)
     */
    private fun safeInvokeMethod(
        method: String,
        arguments: Any?,
    ) {
        if (!isAttachedToEngine) {
            Log.w(TAG, "[CHANNEL] Skipping $method - plugin detached")
            return
        }

        try {
            executors.mainThread().execute {
                // Double-check after thread switch to prevent race conditions
                if (isAttachedToEngine) {
                    try {
                        channel.invokeMethod(method, arguments)
                    } catch (e: IllegalStateException) {
                        Log.e(TAG, "[CHANNEL] Invalid state invoking $method: ${e.message}")
                    } catch (e: IllegalArgumentException) {
                        Log.e(TAG, "[CHANNEL] Invalid arguments for $method: ${e.message}")
                    }
                } else {
                    Log.w(TAG, "[CHANNEL] Skipping $method - plugin detached during thread switch")
                }
            }
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            // Executor already shutdown - expected during plugin detachment
            Log.w(TAG, "[CHANNEL] Cannot invoke $method - executor shutdown")
        }
    }

    private fun log(message: String) {
        Log.d(TAG, message)
        safeInvokeMethod("onLogMessage", message)
    }

    private fun isRecoverableError(error: String): Boolean =
        when {
            // MediaCodec-specific errors that typically indicate recoverable issues
            error.contains("reset codec", ignoreCase = true) -> true
            error.contains("MediaCodec", ignoreCase = true) &&
                error.contains("IllegalStateException") -> true
            error.contains("CodecException", ignoreCase = true) -> true
            // Surface texture related errors that may be recoverable
            error.contains("Surface", ignoreCase = true) &&
                error.contains("invalid") -> true
            else -> false
        }

    /**
     * Handles MediaCodec reset tracking with thread-safe error recovery.
     *
     * Synchronized to prevent race conditions when multiple USB read threads
     * encounter errors simultaneously. Protects consecutiveResets and lastResetTime
     * from concurrent read-modify-write operations.
     */
    @Synchronized
    private fun handleCodecReset() {
        val currentTime = System.currentTimeMillis()

        // Reset counter if outside the window
        if (currentTime - lastResetTime > resetWindowMs) {
            consecutiveResets = 0
        }

        consecutiveResets++
        lastResetTime = currentTime

        log("[ERROR RECOVERY] Reset count: $consecutiveResets in window")

        // If we've hit the threshold, perform complete cleanup
        if (consecutiveResets >= resetThreshold) {
            log("[ERROR RECOVERY] Threshold reached, performing complete system cleanup")
            performEmergencyCleanup()
            consecutiveResets = 0 // Reset counter after cleanup
        }
    }

    private fun getPooledBufferInternal(size: Int): ByteArray {
        synchronized(bufferPool) {
            val pool = bufferPool[size]
            return if (pool != null && pool.isNotEmpty()) {
                pool.removeAt(pool.size - 1)
            } else {
                ByteArray(size)
            }
        }
    }

    private fun returnPooledBufferInternal(buffer: ByteArray) {
        synchronized(bufferPool) {
            val size = buffer.size
            val pool = bufferPool.getOrPut(size) { mutableListOf() }
            if (pool.size < maxPoolSize) {
                // Clear buffer for security before returning to pool
                buffer.fill(0)
                pool.add(buffer)
            }
        }
    }

    private fun clearBufferPool() {
        synchronized(bufferPool) {
            bufferPool.clear()
        }
    }

    private fun performEmergencyCleanup() {
        try {
            log("[EMERGENCY CLEANUP] Starting conservative system cleanup")

            // Clear buffer pool to free memory
            clearBufferPool()

            // Reset video renderer using manager
            videoManager?.performEmergencyCleanup()

            // Close USB connection properly using device manager
            try {
                usbDeviceManager?.closeDevice() // Releases all system resources
            } catch (e: IllegalStateException) {
                log("[EMERGENCY CLEANUP] USB device state error: ${e.message}")
            } catch (e: SecurityException) {
                log("[EMERGENCY CLEANUP] USB permission error: ${e.message}")
            }

            log("[EMERGENCY CLEANUP] Conservative cleanup finished")

            // Notify Flutter layer about the cleanup
            safeInvokeMethod("onEmergencyCleanup", null)
        } catch (e: IllegalStateException) {
            log("[EMERGENCY CLEANUP] State error: ${e.message}")
        } catch (e: SecurityException) {
            log("[EMERGENCY CLEANUP] Permission error: ${e.message}")
        } catch (e: OutOfMemoryError) {
            log("[EMERGENCY CLEANUP] Out of memory: ${e.message}")
        }
    }

    override fun setReadingLoopLatch(latch: java.util.concurrent.CountDownLatch) {
        readingLoopLatch = latch
    }
}
