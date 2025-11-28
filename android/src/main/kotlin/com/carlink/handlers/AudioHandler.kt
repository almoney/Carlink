package com.carlink.handlers

/**
 * AudioHandler - Handles audio playback operations for CPC200-CCPA audio streams
 *
 * PURPOSE:
 * Routes Flutter platform method calls for audio playback to the DualStreamAudioManager.
 * Provides a clean interface for initializing, controlling, and monitoring audio playback
 * from CarPlay/Android Auto projection streams with support for simultaneous Media and
 * Navigation audio.
 *
 * RESPONSIBILITIES:
 * - initializeAudio: Initialize the dual-stream audio system
 * - writeAudio: Write PCM audio data to appropriate stream (media/nav)
 * - setAudioVolume: Adjust playback volume
 * - setAudioDucking: Set volume ducking for navigation prompts
 * - getAudioStats: Get playback performance statistics
 * - releaseAudio: Release all audio resources
 *
 * THREAD SAFETY:
 * All method calls arrive on the main thread via Flutter's MethodChannel.
 * The DualStreamAudioManager handles thread synchronization internally.
 *
 * @param dualAudioManager DualStreamAudioManager instance for audio operations
 * @param logCallback Callback for logging audio operations
 */
import com.carlink.DualStreamAudioManager
import com.carlink.LogCallback
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result

class AudioHandler(
    private val dualAudioManager: DualStreamAudioManager?,
    private val logCallback: LogCallback,
) {
    /**
     * Handles audio-related method calls.
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
            "initializeAudio" -> {
                handleInitializeAudio(result)
                true
            }
            "startAudio" -> {
                // Start is automatic with DualStreamAudioManager
                result.success(true)
                true
            }
            "stopAudio" -> {
                handleStopAudio(result)
                true
            }
            "pauseAudio" -> {
                // Pause not directly supported - use stop
                handleStopAudio(result)
                true
            }
            "writeAudio" -> {
                handleWriteAudio(call, result)
                true
            }
            "setAudioVolume" -> {
                handleSetVolume(call, result)
                true
            }
            "setAudioDucking" -> {
                handleSetDucking(call, result)
                true
            }
            "getAudioStats" -> {
                handleGetStats(result)
                true
            }
            "releaseAudio" -> {
                handleReleaseAudio(result)
                true
            }
            "isAudioPlaying" -> {
                handleIsPlaying(result)
                true
            }
            "stopAudioStream" -> {
                handleStopAudioStream(call, result)
                true
            }
            else -> false
        }

    /**
     * Initialize the dual-stream audio system.
     *
     * Returns true if initialization succeeded.
     */
    private fun handleInitializeAudio(result: Result) {
        try {
            val manager = dualAudioManager ?: return result.error(
                "AudioManagerError",
                "DualStreamAudioManager not initialized",
                null,
            )

            val success = manager.initialize()
            result.success(success)
        } catch (e: Exception) {
            logCallback.log("[AUDIO] Failed to initialize audio: ${e.message}")
            result.error("AudioInitError", "Failed to initialize audio: ${e.message}", null)
        }
    }

    /**
     * Stop audio playback and release resources.
     */
    private fun handleStopAudio(result: Result) {
        try {
            dualAudioManager?.release()
            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[AUDIO] Failed to stop audio: ${e.message}")
            result.error("AudioStopError", "Failed to stop audio: ${e.message}", null)
        }
    }

    /**
     * Write PCM audio data to the appropriate stream.
     *
     * Arguments:
     * - data (ByteArray): PCM audio samples (16-bit)
     * - decodeType (Int): CPC200-CCPA decode type for format detection (1-7)
     * - audioType (Int): Stream type (1=media, 2=navigation)
     * - volume (Double): Volume level (0.0 to 1.0) - used for ducking detection
     *
     * Returns number of bytes written to buffer.
     */
    private fun handleWriteAudio(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val manager = dualAudioManager ?: return result.error(
                "AudioManagerError",
                "DualStreamAudioManager not initialized",
                null,
            )

            val data = call.argument<ByteArray>("data")
                ?: return result.error("IllegalArgument", "Missing required argument: data", null)

            val decodeType = call.argument<Int>("decodeType") ?: 4
            val audioType = call.argument<Int>("audioType") ?: 1  // Default to media
            val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()

            // If volume < 1.0, apply ducking (adapter sends ducking via volume field)
            if (volume < 1.0f && audioType == 1) {
                manager.setDucking(volume)
            }

            val bytesWritten = manager.writeAudio(data, audioType, decodeType)
            result.success(bytesWritten)
        } catch (e: Exception) {
            logCallback.log("[AUDIO] Failed to write audio: ${e.message}")
            result.error("AudioWriteError", "Failed to write audio: ${e.message}", null)
        }
    }

    /**
     * Set playback volume.
     *
     * Arguments:
     * - volume (Double): Volume level (0.0 to 1.0)
     * - audioType (Int): Stream type (1=media, 2=navigation), defaults to media
     */
    private fun handleSetVolume(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val volume = call.argument<Double>("volume")
                ?: return result.error("IllegalArgument", "Missing required argument: volume", null)

            val audioType = call.argument<Int>("audioType") ?: 1

            when (audioType) {
                1 -> dualAudioManager?.setMediaVolume(volume.toFloat())
                2 -> dualAudioManager?.setNavVolume(volume.toFloat())
                else -> dualAudioManager?.setMediaVolume(volume.toFloat())
            }

            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[AUDIO] Failed to set volume: ${e.message}")
            result.error("AudioVolumeError", "Failed to set volume: ${e.message}", null)
        }
    }

    /**
     * Set volume ducking level.
     *
     * Arguments:
     * - duckLevel (Double): Ducking level (0.0 to 1.0), e.g., 0.2 = 20% volume
     */
    private fun handleSetDucking(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val duckLevel = call.argument<Double>("duckLevel")
                ?: return result.error("IllegalArgument", "Missing required argument: duckLevel", null)

            dualAudioManager?.setDucking(duckLevel.toFloat())
            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[AUDIO] Failed to set ducking: ${e.message}")
            result.error("AudioDuckingError", "Failed to set ducking: ${e.message}", null)
        }
    }

    /**
     * Get audio playback statistics.
     *
     * Returns a map containing playback statistics for both streams.
     */
    private fun handleGetStats(result: Result) {
        try {
            val stats = dualAudioManager?.getStats() ?: mapOf(
                "isPlaying" to false,
                "error" to "DualStreamAudioManager not initialized",
            )
            result.success(stats)
        } catch (e: Exception) {
            logCallback.log("[AUDIO] Failed to get stats: ${e.message}")
            result.error("AudioStatsError", "Failed to get audio stats: ${e.message}", null)
        }
    }

    /**
     * Release all audio resources.
     */
    private fun handleReleaseAudio(result: Result) {
        try {
            dualAudioManager?.release()
            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[AUDIO] Failed to release audio: ${e.message}")
            result.error("AudioReleaseError", "Failed to release audio: ${e.message}", null)
        }
    }

    /**
     * Check if audio is currently playing.
     *
     * Returns true if any audio stream is playing.
     */
    private fun handleIsPlaying(result: Result) {
        val isPlaying = dualAudioManager?.isPlaying() ?: false
        result.success(isPlaying)
    }

    /**
     * Stop (pause) a specific audio stream.
     *
     * This is critical for AAOS volume control. When an audio stream ends (e.g., nav prompt
     * finishes), the corresponding AudioTrack must be paused so AAOS CarAudioService
     * deprioritizes that audio context for volume key handling.
     *
     * Without this, a nav track left in PLAYING state causes volume keys to control
     * NAVIGATION volume instead of MEDIA volume, appearing "stuck".
     *
     * Arguments:
     * - audioType (Int): Stream type to stop
     *   - 1 = Media (USAGE_MEDIA)
     *   - 2 = Navigation (USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
     *   - 3 = Phone call (USAGE_VOICE_COMMUNICATION)
     *   - 4 = Voice/Siri (USAGE_ASSISTANT)
     */
    private fun handleStopAudioStream(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val audioType = call.argument<Int>("audioType") ?: 1

            when (audioType) {
                1 -> {
                    dualAudioManager?.stopMediaTrack()
                    logCallback.log("[AUDIO] Media stream stopped via platform call")
                }
                2 -> {
                    dualAudioManager?.stopNavTrack()
                    logCallback.log("[AUDIO] Navigation stream stopped via platform call")
                }
                3 -> {
                    dualAudioManager?.stopCallTrack()
                    logCallback.log("[AUDIO] Call stream stopped via platform call")
                }
                4 -> {
                    dualAudioManager?.stopVoiceTrack()
                    logCallback.log("[AUDIO] Voice stream stopped via platform call")
                }
                else -> {
                    logCallback.log("[AUDIO] Unknown audioType $audioType for stopAudioStream")
                }
            }
            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[AUDIO] Failed to stop audio stream: ${e.message}")
            result.error("AudioStopError", "Failed to stop audio stream: ${e.message}", null)
        }
    }
}
