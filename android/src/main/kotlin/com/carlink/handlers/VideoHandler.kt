package com.carlink.handlers

/**
 * VideoHandler - Handles Flutter texture and H.264 video rendering operations
 *
 * PURPOSE:
 * Manages the lifecycle of Flutter textures and H.264 video rendering for CarPlay/Android Auto
 * projection. This handler provides a clean interface for texture creation, removal, and renderer
 * management without exposing internal VideoTextureManager complexity.
 *
 * RESPONSIBILITIES:
 * - createTexture: Initialize Flutter texture with specified dimensions
 * - removeTexture: Clean up texture and rendering resources
 * - resetH264Renderer: Recover from MediaCodec errors by resetting the renderer
 *
 * THREAD SAFETY:
 * All methods are called on the main thread via Flutter's MethodChannel.
 * The VideoTextureManager handles thread synchronization internally.
 *
 * @param videoManager VideoTextureManager instance for texture operations
 * @param logCallback Callback for logging video operations
 */
import com.carlink.LogCallback
import com.carlink.VideoTextureManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result

class VideoHandler(
    private val videoManager: VideoTextureManager?,
    private val logCallback: LogCallback,
) {
    /**
     * Handles video-related method calls.
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
            "createTexture" -> {
                handleCreateTexture(call, result)
                true
            }
            "removeTexture" -> {
                handleRemoveTexture(result)
                true
            }
            "resetH264Renderer" -> {
                handleResetRenderer(result)
                true
            }
            else -> false
        }

    /**
     * Creates a new Flutter texture with the specified dimensions.
     *
     * Arguments:
     * - width (Int): Video frame width in pixels
     * - height (Int): Video frame height in pixels
     *
     * Returns the texture ID (Long) for use in Flutter's Texture widget.
     *
     * Errors:
     * - VideoManagerError: If VideoTextureManager is not initialized
     * - TextureCreationError: If texture creation fails
     */
    private fun handleCreateTexture(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val width =
                call.argument<Int>("width")
                    ?: return result.error("IllegalArgument", "Missing required argument: width", null)
            val height =
                call.argument<Int>("height")
                    ?: return result.error("IllegalArgument", "Missing required argument: height", null)

            val textureId =
                videoManager?.createTexture(width, height)
                    ?: return result.error(
                        "VideoManagerError",
                        "VideoTextureManager not initialized",
                        null,
                    )

            result.success(textureId)
        } catch (e: Exception) {
            logCallback.log("[VIDEO] Failed to create texture: ${e.message}")
            result.error("TextureCreationError", "Failed to create texture: ${e.message}", null)
        }
    }

    /**
     * Removes the current Flutter texture and cleans up all rendering resources.
     *
     * This includes stopping the H.264 renderer and releasing the SurfaceTexture.
     * Safe to call multiple times (idempotent).
     *
     * Returns null on success.
     *
     * Errors:
     * - TextureCleanupError: If cleanup fails
     */
    private fun handleRemoveTexture(result: Result) {
        try {
            videoManager?.removeTexture()
            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[VIDEO] Error removing texture: ${e.message}")
            result.error("TextureCleanupError", "Failed to remove texture: ${e.message}", null)
        }
    }

    /**
     * Resets the H.264 renderer to recover from MediaCodec errors.
     *
     * This is typically called when the renderer encounters codec exceptions or
     * surface invalidation. The renderer will be stopped and restarted with the
     * same configuration.
     *
     * Returns true if reset was successful, false otherwise.
     */
    private fun handleResetRenderer(result: Result) {
        val success = videoManager?.resetRenderer() ?: false
        result.success(success)
    }
}
