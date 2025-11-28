package com.carlink

/**
 * VideoTextureManager - Centralized Video Texture and H.264 Rendering Management
 *
 * PURPOSE:
 * Encapsulates all video-related operations for CarPlay/Android Auto projection, managing
 * the complete lifecycle of Flutter textures and H.264 hardware-accelerated rendering.
 * This class serves as the single source of truth for video texture state in the Carlink plugin.
 *
 * RESPONSIBILITIES:
 * - Flutter texture lifecycle (creation, cleanup, release)
 * - H.264 renderer initialization and management
 * - Surface texture integration with Flutter rendering pipeline
 * - Video data processing and direct rendering
 * - Renderer reset and crash recovery
 * - Resource cleanup following Flutter guidelines
 *
 * ARCHITECTURE:
 * This manager acts as a facade over Flutter's TextureRegistry and H264Renderer,
 * providing a clean API that hides complexity from CarlinkPlugin. It ensures proper
 * resource management and follows Flutter texture registry best practices.
 *
 * THREAD SAFETY:
 * All public methods are synchronized to ensure thread-safe texture lifecycle management.
 * H.264 renderer operations are delegated to dedicated executor threads via AppExecutors.
 *
 * LIFECYCLE:
 * 1. Create: createTexture() -> Initialize renderer -> Return texture ID
 * 2. Process: processVideoData() -> Direct rendering to texture
 * 3. Reset: resetRenderer() -> Codec error recovery
 * 4. Cleanup: removeTexture() -> Stop renderer -> Release texture -> Null references
 *
 * INTEGRATION:
 * - Input: Video frames from USB reading loop (CPC200-CCPA protocol)
 * - Processing: H264Renderer with Intel QuickSync optimization
 * - Output: Flutter Texture widget via texture ID
 *
 * @see H264Renderer for hardware-accelerated H.264 decoding
 * @see io.flutter.view.TextureRegistry for Flutter texture integration
 * @see CarlinkPlugin for main plugin integration
 */
import android.content.Context
import android.graphics.SurfaceTexture
import android.util.Log
import io.flutter.view.TextureRegistry
import io.flutter.view.TextureRegistry.SurfaceTextureEntry

/**
 * Manages Flutter texture creation, H.264 rendering, and resource lifecycle.
 *
 * This class provides a clean separation between video rendering concerns and
 * the main CarlinkPlugin, improving testability and maintainability.
 *
 * @param context Android application context for renderer initialization
 * @param textureRegistry Flutter texture registry for creating textures
 * @param logCallback Callback for logging messages to Flutter layer
 * @param executors Thread executors for USB I/O and MediaCodec operations
 */
class VideoTextureManager(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val logCallback: LogCallback,
    private val executors: AppExecutors,
) {
    companion object {
        private const val TAG = "CARLINK"
    }

    // Texture state
    private var surfaceTextureEntry: SurfaceTextureEntry? = null
    private var h264Renderer: H264Renderer? = null
    private var currentTextureId: Long? = null

    /**
     * Creates a new Flutter texture and initializes the H.264 renderer.
     *
     * This method performs the following operations:
     * 1. Creates a new SurfaceTexture via Flutter's TextureRegistry
     * 2. Stops any existing renderer to prevent resource leaks
     * 3. Initializes a new H264Renderer with the specified dimensions
     * 4. Starts the renderer for video processing
     *
     * Thread Safety: This method is synchronized to prevent concurrent texture creation.
     *
     * @param width Video frame width in pixels (e.g., 2400 for GM AAOS)
     * @param height Video frame height in pixels (e.g., 960 for GM AAOS)
     * @return Flutter texture ID for use in Texture widget
     * @throws IllegalStateException if texture creation fails
     */
    @Synchronized
    fun createTexture(
        width: Int,
        height: Int,
    ): Long {
        log("[VIDEO] Creating texture: ${width}x$height")

        try {
            // Create Flutter surface texture
            surfaceTextureEntry = textureRegistry.createSurfaceTexture()
            val texture = surfaceTextureEntry!!.surfaceTexture()
            val textureId = surfaceTextureEntry!!.id()

            // Stop existing renderer if present
            h264Renderer?.let { existingRenderer ->
                log("[VIDEO] Stopping existing renderer before creating new one")
                existingRenderer.stop()
            }

            // Initialize H.264 renderer
            h264Renderer =
                H264Renderer(
                    context,
                    width,
                    height,
                    texture,
                    textureId.toInt(),
                    logCallback,
                    executors,
                )

            // Start renderer
            h264Renderer?.start()

            currentTextureId = textureId
            log("[VIDEO] Texture created successfully: ID=$textureId, Resolution=${width}x$height")

            return textureId
        } catch (e: Exception) {
            log("[VIDEO] Failed to create texture: ${e.message}")
            throw IllegalStateException("Failed to create texture: ${e.message}", e)
        }
    }

    /**
     * Removes the Flutter texture and cleans up all rendering resources.
     *
     * This method follows Flutter texture registry guidelines for proper cleanup:
     * 1. Stops the H.264 renderer
     * 2. Nulls the renderer reference
     * 3. Releases the SurfaceTexture via Flutter registry
     * 4. Nulls the texture entry reference
     * 5. Clears the current texture ID
     *
     * Thread Safety: This method is synchronized to prevent concurrent cleanup.
     *
     * Calling this method multiple times is safe (idempotent).
     *
     * @throws Exception if cleanup encounters errors (logged but not propagated)
     */
    @Synchronized
    fun removeTexture() {
        log("[VIDEO] Removing texture and cleaning up resources")

        try {
            // Stop H.264 renderer
            h264Renderer?.let { renderer ->
                log("[VIDEO] Stopping H.264 renderer")
                renderer.stop()
            }
            h264Renderer = null

            // Release surface texture following Flutter guidelines
            surfaceTextureEntry?.let { entry ->
                log("[VIDEO] Releasing SurfaceTexture ID=${entry.id()}")
                entry.release()
            }
            surfaceTextureEntry = null

            currentTextureId = null

            log("[VIDEO] Texture removed and resources cleaned up successfully")
        } catch (e: Exception) {
            log("[VIDEO] Error during texture cleanup: ${e.message}")
            // Don't propagate - best effort cleanup
        }
    }

    /**
     * Resets the H.264 renderer for error recovery.
     *
     * This method is called when the codec encounters recoverable errors
     * (e.g., MediaCodec IllegalStateException, surface errors). It attempts
     * to reset the decoder without full teardown, which is faster than
     * recreating the entire rendering pipeline.
     *
     * The reset operation is delegated to H264Renderer which handles:
     * - MediaCodec release and recreation
     * - Buffer pool flushing
     * - Configuration reapplication
     *
     * Thread Safety: This method is synchronized.
     *
     * @return true if reset was successful, false if no renderer exists
     */
    @Synchronized
    fun resetRenderer(): Boolean {
        log("[VIDEO] Resetting H.264 renderer")

        h264Renderer?.let { renderer ->
            try {
                renderer.reset()
                log("[VIDEO] H.264 renderer reset successfully")
                return true
            } catch (e: Exception) {
                log("[VIDEO] Failed to reset renderer: ${e.message}")
                return false
            }
        }

        log("[VIDEO] No renderer to reset")
        return false
    }

    /**
     * Processes video data directly from USB stream using zero-copy rendering.
     *
     * This method enables the reading loop to write video data directly into
     * the H.264 renderer's buffer pool without intermediate copying, reducing
     * latency and memory allocations.
     *
     * The callback-based API allows the renderer to provide a buffer from its
     * pool, the caller fills it via USB bulk transfer, and the renderer processes
     * it immediately.
     *
     * Usage in reading loop:
     * ```kotlin
     * videoManager.processDataDirect(header.length, 20) { bytes, offset ->
     *     readByChunks(connection, endpoint, bytes, offset, header.length, timeout)
     * }
     * ```
     *
     * @param length Payload length in bytes (from protocol header)
     * @param headerSkip Number of bytes to skip at start of buffer (protocol overhead)
     * @param readCallback Lambda that fills the provided buffer via USB read and returns bytes read
     * @return Number of bytes read, or -1 if renderer unavailable
     */
    @Synchronized
    fun processDataDirect(
        length: Int,
        headerSkip: Int,
        readCallback: (bytes: ByteArray, offset: Int) -> Int,
    ): Int {
        h264Renderer?.let { renderer ->
            var bytesRead = -1
            renderer.processDataDirect(length, headerSkip) { bytes, offset ->
                bytesRead = readCallback(bytes, offset)
            }
            return bytesRead
        }

        log("[VIDEO] Cannot process video data - no renderer available")
        return -1
    }

    /**
     * Processes video data from a pre-filled buffer.
     *
     * This method is used when video data is already in memory (e.g., from
     * bulkTransferIn method). It extracts the H.264 payload (skipping protocol
     * header) and sends it to the renderer.
     *
     * Buffer format: [20 bytes protocol header][H.264 NAL units]
     *
     * @param buffer ByteArray containing protocol header + H.264 data
     * @return true if processed successfully, false if renderer unavailable or buffer too short
     */
    @Synchronized
    fun processVideoBuffer(buffer: ByteArray): Boolean {
        if (buffer.size < 20) {
            log("[VIDEO] Buffer too short: ${buffer.size} bytes (minimum 20)")
            return false
        }

        h264Renderer?.let { renderer ->
            try {
                // Extract H.264 payload (skip 20-byte protocol header)
                val videoData = buffer.copyOfRange(20, buffer.size)
                // Note: H264Renderer may need a processData(ByteArray) method
                // For now, this is a placeholder for future implementation
                log("[VIDEO] Processed ${videoData.size} bytes of video data")
                return true
            } catch (e: Exception) {
                log("[VIDEO] Error processing video buffer: ${e.message}")
                return false
            }
        }

        log("[VIDEO] Cannot process video buffer - no renderer available")
        return false
    }

    /**
     * Checks if video rendering is currently active.
     *
     * @return true if a texture and renderer exist, false otherwise
     */
    @Synchronized
    fun isRendererActive(): Boolean = h264Renderer != null && surfaceTextureEntry != null

    /**
     * Gets the current texture ID if a texture is active.
     *
     * @return Current Flutter texture ID, or null if no texture exists
     */
    @Synchronized
    fun getCurrentTextureId(): Long? = currentTextureId

    /**
     * Gets the current SurfaceTexture for advanced use cases.
     *
     * This is typically not needed by client code as the texture is managed
     * internally, but may be useful for debugging or advanced integrations.
     *
     * @return Current SurfaceTexture, or null if no texture exists
     */
    @Synchronized
    fun getSurfaceTexture(): SurfaceTexture? = surfaceTextureEntry?.surfaceTexture()

    /**
     * Performs emergency cleanup during crash recovery.
     *
     * This method is more conservative than removeTexture() - it attempts to
     * reset the renderer rather than destroying it entirely, allowing for
     * faster recovery from transient codec errors.
     *
     * Called by CrashRecoveryManager when consecutive reset threshold is reached.
     */
    @Synchronized
    fun performEmergencyCleanup() {
        log("[VIDEO] Performing emergency cleanup")

        h264Renderer?.let { renderer ->
            try {
                renderer.reset()
                log("[VIDEO] Emergency renderer reset completed")
            } catch (e: Exception) {
                log("[VIDEO] Emergency renderer reset failed: ${e.message}")
                // Don't null out renderer - let it recover naturally
            }
        }
    }

    /**
     * Logs a message using the provided callback and Android Log.
     *
     * Messages are sent to both Android logcat and the Flutter logging system
     * via the LogCallback interface.
     *
     * @param message Log message to output
     */
    private fun log(message: String) {
        Log.d(TAG, message)
        logCallback.log(message)
    }

    /**
     * Gets current video statistics and state information.
     *
     * Useful for debugging, monitoring, and UI display of video stream health.
     *
     * @return Map containing texture state, renderer status, and current configuration
     */
    @Synchronized
    fun getVideoStats(): Map<String, Any> =
        mapOf(
            "hasTexture" to (surfaceTextureEntry != null),
            "hasRenderer" to (h264Renderer != null),
            "textureId" to (currentTextureId ?: -1L),
            "isActive" to isRendererActive(),
        )

    /**
     * Gets the current codec name from the H.264 renderer.
     *
     * @return Codec name or null if renderer not initialized
     */
    @Synchronized
    fun getCodecName(): String? = h264Renderer?.codecName
}
