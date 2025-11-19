package com.carlink.handlers

/**
 * BulkTransferHandler - Handles USB bulk transfer operations and reading loop
 *
 * PURPOSE:
 * Manages USB bulk data transfers for CPC200-CCPA protocol communication. This handler
 * encapsulates the complex reading loop that processes video and control data from the
 * wireless CarPlay/Android Auto adapter.
 *
 * RESPONSIBILITIES:
 * - startReadingLoop: Start continuous USB reading for CPC200-CCPA messages
 * - stopReadingLoop: Stop the reading loop gracefully
 * - bulkTransferIn: Perform one-time bulk IN transfer
 * - bulkTransferOut: Perform one-time bulk OUT transfer
 *
 * READING LOOP ARCHITECTURE:
 * The reading loop runs on a dedicated USB IN executor thread and:
 * 1. Reads 16-byte CarLink message headers
 * 2. Validates frame sizes (max 1MB per project spec)
 * 3. Routes video data directly to VideoTextureManager for zero-copy rendering
 * 4. Uses buffer pooling for non-video data to reduce GC pressure
 * 5. Handles errors and triggers emergency cleanup when needed
 *
 * THREAD SAFETY:
 * - Method calls arrive on the main thread via Flutter's MethodChannel
 * - Reading loop executes on USB IN executor thread
 * - Callbacks to Flutter are dispatched to main thread via executors
 *
 * @param usbDeviceManager UsbDeviceManager for device access
 * @param bulkTransferManager BulkTransferManager for transfer operations
 * @param videoManager VideoTextureManager for video data processing
 * @param executors AppExecutors for thread management
 * @param callbacks Callbacks for reading loop events and logging
 */
import android.hardware.usb.UsbEndpoint
import com.carlink.AppExecutors
import com.carlink.BulkTransferManager
import com.carlink.CarLinkMessageHeader
import com.carlink.UsbDeviceManager
import com.carlink.VideoTextureManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import java.nio.ByteBuffer

/**
 * Callbacks for BulkTransferHandler events.
 */
interface BulkTransferCallbacks {
    /**
     * Checks if the plugin is still attached to the Flutter engine.
     * Used to prevent invoking methods on detached channels.
     */
    fun isAttached(): Boolean

    fun onLog(message: String)

    fun onReadingLoopMessage(
        type: Int,
        data: ByteArray?,
    )

    fun onReadingLoopError(error: String)

    fun getPooledBuffer(size: Int): ByteArray

    fun returnPooledBuffer(buffer: ByteArray)

    /**
     * Sets the CountDownLatch for coordinating reading loop shutdown.
     * The latch is counted down when the reading loop exits.
     */
    fun setReadingLoopLatch(latch: java.util.concurrent.CountDownLatch)
}

class BulkTransferHandler(
    private val usbDeviceManager: UsbDeviceManager?,
    private val bulkTransferManager: BulkTransferManager?,
    private val videoManager: VideoTextureManager?,
    private val executors: AppExecutors,
    private val callbacks: BulkTransferCallbacks,
) {
    @Volatile
    private var readLoopRunning = false

    /**
     * Handles bulk transfer-related method calls.
     *
     * @param call The method call from Flutter
     * @param result The result callback
     * @return true if the method was handled, false otherwise
     */
    fun handle(
        call: MethodCall,
        result: Result,
    ): Boolean =
        when (call.method) {
            "startReadingLoop" -> {
                handleStartReadingLoop(call, result)
                true
            }
            "stopReadingLoop" -> {
                handleStopReadingLoop(result)
                true
            }
            "bulkTransferIn" -> {
                handleBulkTransferIn(call, result)
                true
            }
            "bulkTransferOut" -> {
                handleBulkTransferOut(call, result)
                true
            }
            else -> false
        }

    /**
     * Stops the reading loop gracefully.
     *
     * Sets the running flag to false, which causes the loop to exit after
     * the current iteration completes.
     */
    private fun handleStopReadingLoop(result: Result) {
        readLoopRunning = false
        result.success(null)
    }

    /**
     * Starts the continuous USB reading loop for CPC200-CCPA protocol messages.
     *
     * Arguments:
     * - endpoint (Map): Endpoint info with "endpointNumber" and "direction" keys
     * - timeout (Int): USB transfer timeout in milliseconds
     *
     * The reading loop processes:
     * - Video data (type 0x06): Direct rendering via VideoTextureManager
     * - Other messages: Buffered and forwarded to Dart layer
     *
     * Errors:
     * - IllegalState: If loop already running, managers not initialized, or device not connected
     */
    private fun handleStartReadingLoop(
        call: MethodCall,
        result: Result,
    ) {
        if (readLoopRunning) {
            return result.error("IllegalState", "readingLoop running", null)
        }

        val usbManager =
            usbDeviceManager
                ?: return result.error("IllegalState", "usbDeviceManager null", null)
        val transferManager =
            bulkTransferManager
                ?: return result.error("IllegalState", "bulkTransferManager null", null)

        val connection =
            usbManager.getCurrentConnection()
                ?: return result.error("IllegalState", "usbDeviceConnection null", null)

        val endpointMap =
            call.argument<Map<String, Any>>("endpoint")
                ?: return result.error("IllegalArgument", "Missing required argument: endpoint", null)
        val endpointNumber =
            endpointMap["endpointNumber"] as? Int
                ?: return result.error("IllegalArgument", "Endpoint map missing 'endpointNumber'", null)
        val direction =
            endpointMap["direction"] as? Int
                ?: return result.error("IllegalArgument", "Endpoint map missing 'direction'", null)

        val endpoint =
            usbManager.findEndpoint(endpointNumber, direction)
                ?: return result.error("IllegalState", "endpoint not found", null)

        val timeout =
            call.argument<Int>("timeout")
                ?: return result.error("IllegalArgument", "Missing required argument: timeout", null)

        // Create latch for coordinating shutdown
        val latch = java.util.concurrent.CountDownLatch(1)
        callbacks.setReadingLoopLatch(latch)

        // Start reading loop on USB IN executor
        executors.usbIn().execute {
            try {
                runReadingLoop(transferManager, connection, endpoint, timeout)
            } finally {
                // Always count down the latch when loop exits
                latch.countDown()
            }
        }

        result.success(null)
    }

    /**
     * Main reading loop that processes CPC200-CCPA protocol messages.
     *
     * This is the critical data path for CarPlay/Android Auto projection:
     * 1. Read 16-byte header
     * 2. Parse header to get message type and payload length
     * 3. Validate payload size (max 1MB)
     * 4. Route video data directly to renderer (zero-copy)
     * 5. Buffer non-video data using pooled buffers
     * 6. Forward messages to Dart layer
     */
    private fun runReadingLoop(
        transferManager: BulkTransferManager,
        connection: android.hardware.usb.UsbDeviceConnection,
        endpoint: UsbEndpoint,
        timeout: Int,
    ) {
        callbacks.onLog("[USB] Read loop started")
        readLoopRunning = true

        var streamingNotified = false

        // Allocate reusable header buffer outside loop to reduce GC pressure
        val headerBuffer = ByteBuffer.allocate(CarLinkMessageHeader.MESSAGE_LENGTH)

        var actualLength: Int

        while (readLoopRunning) {
            // Read 16-byte header
            headerBuffer.clear()
            actualLength =
                transferManager.readByChunks(
                    connection,
                    endpoint,
                    headerBuffer.array(),
                    0,
                    CarLinkMessageHeader.MESSAGE_LENGTH,
                    timeout,
                )

            if (actualLength < 0) {
                break
            }

            try {
                val header = CarLinkMessageHeader.parseFrom(headerBuffer)

                if (header.length > 0) {
                    // Validate header.length against maximum expected frame size to prevent buffer overflow
                    val maxFrameSize = 1048576 // 1MB maximum per project documentation
                    if (header.length > maxFrameSize) {
                        callbacks.onLog(
                            "[SECURITY] Rejected oversized video frame: " +
                                "${header.length} bytes (max: $maxFrameSize)",
                        )
                        // Skip this frame and continue processing
                        skipOversizedFrame(transferManager, connection, endpoint, header.length, timeout)
                        continue
                    }

                    // Video data direct render using VideoTextureManager
                    if (header.isVideoData) {
                        actualLength =
                            videoManager?.processDataDirect(header.length, 20) { bytes, offset ->
                                transferManager.readByChunks(
                                    connection,
                                    endpoint,
                                    bytes,
                                    offset,
                                    header.length,
                                    timeout,
                                )
                            } ?: -1

                        if (actualLength < 0) {
                            if (actualLength == -1) {
                                callbacks.onLog("[VIDEO] Failed to process video data - renderer not available")
                            }
                            break
                        }

                        // Notify once when video streaming starts (only if still attached)
                        if (!streamingNotified && callbacks.isAttached()) {
                            streamingNotified = true
                            callbacks.onReadingLoopMessage(header.type, ByteArray(0))
                        }
                    } else {
                        // Use pooled buffer for better memory management
                        val bodyBytes = callbacks.getPooledBuffer(header.length)
                        try {
                            actualLength =
                                transferManager.readByChunks(
                                    connection,
                                    endpoint,
                                    bodyBytes,
                                    0,
                                    header.length,
                                    timeout,
                                )

                            if (actualLength < 0) {
                                break
                            }

                            // Create copy for callback since we'll return buffer to pool
                            // Only send callback if still attached to prevent crashes
                            if (callbacks.isAttached()) {
                                val dataCopy =
                                    if (actualLength == header.length) {
                                        bodyBytes.copyOf()
                                    } else {
                                        bodyBytes.copyOf(actualLength)
                                    }
                                callbacks.onReadingLoopMessage(header.type, dataCopy)
                            }
                        } finally {
                            callbacks.returnPooledBuffer(bodyBytes)
                        }
                    }
                } else {
                    // Message with no payload - only send if still attached
                    if (callbacks.isAttached()) {
                        callbacks.onReadingLoopMessage(header.type, null)
                    }
                }
            } catch (e: Exception) {
                // Only send error if still attached
                if (callbacks.isAttached()) {
                    callbacks.onReadingLoopError(e.toString())
                }
                break
            }
        }

        callbacks.onLog("[USB] Read loop stopped")
        readLoopRunning = false

        // Only send final error if still attached
        if (callbacks.isAttached()) {
            callbacks.onReadingLoopError("USBReadError readingLoopError error, return actualLength=-1")
        }
    }

    /**
     * Skips an oversized frame by reading it in chunks without processing.
     */
    private fun skipOversizedFrame(
        transferManager: BulkTransferManager,
        connection: android.hardware.usb.UsbDeviceConnection,
        endpoint: UsbEndpoint,
        frameSize: Int,
        timeout: Int,
    ) {
        val skipBuffer = ByteArray(minOf(frameSize, 65536)) // Skip in 64KB chunks
        var remaining = frameSize
        while (remaining > 0) {
            val toSkip = minOf(remaining, skipBuffer.size)
            val skipped = transferManager.readByChunks(connection, endpoint, skipBuffer, 0, toSkip, timeout)
            if (skipped < 0) break
            remaining -= skipped
        }
    }

    /**
     * Performs a one-time bulk IN transfer.
     *
     * Arguments:
     * - isVideoData (Boolean): Whether the data should be processed as video
     * - endpoint (Map): Endpoint info with "endpointNumber" and "direction"
     * - maxLength (Int): Maximum bytes to read
     * - timeout (Int): Transfer timeout in milliseconds
     *
     * Returns the transferred data (ByteArray) or empty array for video data.
     *
     * Errors:
     * - IllegalArgument: If parameters are invalid (maxLength/timeout <= 0)
     * - IllegalState: If managers not initialized or device not connected
     * - USBReadError: If transfer fails
     */
    private fun handleBulkTransferIn(
        call: MethodCall,
        result: Result,
    ) {
        val isVideoData =
            call.argument<Boolean>("isVideoData")
                ?: return result.error("IllegalArgument", "Missing required argument: isVideoData", null)
        val usbManager =
            usbDeviceManager
                ?: return result.error("IllegalState", "usbDeviceManager null", null)
        val transferManager =
            bulkTransferManager
                ?: return result.error("IllegalState", "bulkTransferManager null", null)
        val connection =
            usbManager.getCurrentConnection()
                ?: return result.error("IllegalState", "usbDeviceConnection null", null)

        val endpointMap =
            call.argument<Map<String, Any>>("endpoint")
                ?: return result.error("IllegalArgument", "Missing required argument: endpoint", null)
        val maxLength =
            call.argument<Int>("maxLength")
                ?: return result.error("IllegalArgument", "Missing required argument: maxLength", null)
        val timeout =
            call.argument<Int>("timeout")
                ?: return result.error("IllegalArgument", "Missing required argument: timeout", null)

        val endpointNumber =
            endpointMap["endpointNumber"] as? Int
                ?: return result.error("IllegalArgument", "Endpoint map missing 'endpointNumber'", null)
        val direction =
            endpointMap["direction"] as? Int
                ?: return result.error("IllegalArgument", "Endpoint map missing 'direction'", null)

        val endpoint =
            usbManager.findEndpoint(endpointNumber, direction)
                ?: return result.error("IllegalState", "endpoint not found", null)

        // Validate parameters
        if (maxLength <= 0) {
            return result.error("IllegalArgument", "maxLength must be positive", null)
        }
        if (timeout <= 0) {
            return result.error("IllegalArgument", "timeout must be positive", null)
        }

        executors.usbIn().execute {
            try {
                val buffer = transferManager.performBulkTransferIn(connection, endpoint, maxLength, timeout)

                executors.mainThread().execute {
                    if (buffer == null) {
                        result.error("USBReadError", "bulkTransferIn failed after retries", null)
                    } else {
                        if (isVideoData) {
                            // Process video data using VideoTextureManager
                            val processed = videoManager?.processVideoBuffer(buffer) ?: false

                            if (processed) {
                                result.success(ByteArray(0))
                            } else {
                                result.error(
                                    "USBReadError",
                                    "Video processing failed - renderer not available or buffer too short",
                                    null,
                                )
                            }
                        } else {
                            result.success(buffer)
                        }
                    }
                }
            } catch (e: Exception) {
                executors.mainThread().execute {
                    result.error("USBReadError", "Exception during bulk transfer: ${e.message}", null)
                }
            }
        }
    }

    /**
     * Performs a one-time bulk OUT transfer.
     *
     * Arguments:
     * - endpoint (Map): Endpoint info with "endpointNumber" and "direction"
     * - data (ByteArray): Data to send
     * - timeout (Int): Transfer timeout in milliseconds
     *
     * Returns the number of bytes actually transferred (Int).
     *
     * Errors:
     * - IllegalArgument: If data is empty or timeout <= 0
     * - IllegalState: If managers not initialized or device not connected
     * - USBWriteError: If transfer fails
     */
    private fun handleBulkTransferOut(
        call: MethodCall,
        result: Result,
    ) {
        val usbManager =
            usbDeviceManager
                ?: return result.error("IllegalState", "usbDeviceManager null", null)
        val transferManager =
            bulkTransferManager
                ?: return result.error("IllegalState", "bulkTransferManager null", null)
        val connection =
            usbManager.getCurrentConnection()
                ?: return result.error("IllegalState", "usbDeviceConnection null", null)

        val endpointMap =
            call.argument<Map<String, Any>>("endpoint")
                ?: return result.error("IllegalArgument", "Missing required argument: endpoint", null)
        val timeout =
            call.argument<Int>("timeout")
                ?: return result.error("IllegalArgument", "Missing required argument: timeout", null)
        val data =
            call.argument<ByteArray>("data")
                ?: return result.error("IllegalArgument", "Missing required argument: data", null)

        val endpointNumber =
            endpointMap["endpointNumber"] as? Int
                ?: return result.error("IllegalArgument", "Endpoint map missing 'endpointNumber'", null)
        val direction =
            endpointMap["direction"] as? Int
                ?: return result.error("IllegalArgument", "Endpoint map missing 'direction'", null)

        val endpoint =
            usbManager.findEndpoint(endpointNumber, direction)
                ?: return result.error("IllegalState", "endpoint not found", null)

        // Validate parameters
        if (data.isEmpty()) {
            return result.error("IllegalArgument", "data cannot be empty", null)
        }
        if (timeout <= 0) {
            return result.error("IllegalArgument", "timeout must be positive", null)
        }

        executors.usbOut().execute {
            try {
                val actualLength = transferManager.performBulkTransferOut(connection, endpoint, data, timeout)

                executors.mainThread().execute {
                    if (actualLength < 0) {
                        result.error("USBWriteError", "bulkTransferOut error, actualLength=$actualLength", null)
                    } else {
                        result.success(actualLength)
                    }
                }
            } catch (e: Exception) {
                executors.mainThread().execute {
                    result.error("USBWriteError", "Exception during bulk transfer: ${e.message}", null)
                }
            }
        }
    }
}
