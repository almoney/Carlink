package com.carlink.handlers

/**
 * MicrophoneHandler - Handles microphone capture operations for CPC200-CCPA voice input.
 *
 * PURPOSE:
 * Routes Flutter platform method calls for microphone capture to the MicrophoneCaptureManager.
 * Provides a clean interface for starting, stopping, and reading microphone data for
 * Siri/voice assistant and phone call audio.
 *
 * RESPONSIBILITIES:
 * - startMicrophoneCapture: Start capturing with specified format
 * - stopMicrophoneCapture: Stop capturing and release resources
 * - readMicrophoneData: Read captured PCM data from ring buffer
 * - getMicrophoneStats: Get capture statistics
 * - isMicrophoneCapturing: Check capture state
 *
 * THREAD SAFETY:
 * All method calls arrive on the main thread via Flutter's MethodChannel.
 * The MicrophoneCaptureManager handles thread synchronization internally.
 *
 * @param microphoneManager MicrophoneCaptureManager instance for capture operations
 * @param logCallback Callback for logging microphone operations
 */

import com.carlink.LogCallback
import com.carlink.MicrophoneCaptureManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result

class MicrophoneHandler(
    private val microphoneManager: MicrophoneCaptureManager?,
    private val logCallback: LogCallback,
) {
    /**
     * Handles microphone-related method calls.
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
            "startMicrophoneCapture" -> {
                handleStartCapture(call, result)
                true
            }
            "stopMicrophoneCapture" -> {
                handleStopCapture(result)
                true
            }
            "readMicrophoneData" -> {
                handleReadData(call, result)
                true
            }
            "getMicrophoneStats" -> {
                handleGetStats(result)
                true
            }
            "isMicrophoneCapturing" -> {
                handleIsCapturing(result)
                true
            }
            "hasMicrophonePermission" -> {
                handleHasPermission(result)
                true
            }
            "getMicrophoneDecodeType" -> {
                handleGetDecodeType(result)
                true
            }
            else -> false
        }

    /**
     * Start microphone capture with the specified format.
     *
     * Arguments:
     * - decodeType (Int): CPC200-CCPA decode type (3=phone, 5=siri, 6=enhanced, 7=stereo)
     *
     * Returns true if capture started successfully.
     */
    private fun handleStartCapture(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val manager = microphoneManager ?: return result.error(
                "MicrophoneManagerError",
                "MicrophoneCaptureManager not initialized",
                null,
            )

            val decodeType = call.argument<Int>("decodeType") ?: 5  // Default to Siri format

            val success = manager.start(decodeType)
            if (success) {
                logCallback.log("[MIC_HANDLER] Capture started with decodeType=$decodeType")
            } else {
                logCallback.log("[MIC_HANDLER] Failed to start capture")
            }
            result.success(success)
        } catch (e: Exception) {
            logCallback.log("[MIC_HANDLER] Start capture error: ${e.message}")
            result.error("MicrophoneStartError", "Failed to start capture: ${e.message}", null)
        }
    }

    /**
     * Stop microphone capture and release resources.
     */
    private fun handleStopCapture(result: Result) {
        try {
            microphoneManager?.stop()
            logCallback.log("[MIC_HANDLER] Capture stopped")
            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[MIC_HANDLER] Stop capture error: ${e.message}")
            result.error("MicrophoneStopError", "Failed to stop capture: ${e.message}", null)
        }
    }

    /**
     * Read captured PCM audio data from the ring buffer.
     *
     * Arguments:
     * - maxBytes (Int): Maximum bytes to read (default: 1920 = 60ms at 16kHz mono)
     *
     * Returns ByteArray with PCM data, or null if no data available.
     */
    private fun handleReadData(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val manager = microphoneManager ?: return result.error(
                "MicrophoneManagerError",
                "MicrophoneCaptureManager not initialized",
                null,
            )

            val maxBytes = call.argument<Int>("maxBytes") ?: 1920

            val data = manager.readChunk(maxBytes)
            result.success(data)
        } catch (e: Exception) {
            logCallback.log("[MIC_HANDLER] Read data error: ${e.message}")
            result.error("MicrophoneReadError", "Failed to read data: ${e.message}", null)
        }
    }

    /**
     * Get microphone capture statistics.
     *
     * Returns a map containing capture statistics.
     */
    private fun handleGetStats(result: Result) {
        try {
            val stats = microphoneManager?.getStats() ?: mapOf(
                "isCapturing" to false,
                "error" to "MicrophoneCaptureManager not initialized",
            )
            result.success(stats)
        } catch (e: Exception) {
            logCallback.log("[MIC_HANDLER] Get stats error: ${e.message}")
            result.error("MicrophoneStatsError", "Failed to get stats: ${e.message}", null)
        }
    }

    /**
     * Check if microphone is currently capturing.
     *
     * Returns true if capturing.
     */
    private fun handleIsCapturing(result: Result) {
        val isCapturing = microphoneManager?.isCapturing() ?: false
        result.success(isCapturing)
    }

    /**
     * Check if microphone permission is granted.
     *
     * Returns true if RECORD_AUDIO permission is granted.
     */
    private fun handleHasPermission(result: Result) {
        val hasPermission = microphoneManager?.hasPermission() ?: false
        result.success(hasPermission)
    }

    /**
     * Get the current decode type for active capture.
     *
     * Returns decodeType (3, 5, 6, or 7) or -1 if not capturing.
     */
    private fun handleGetDecodeType(result: Result) {
        val decodeType = microphoneManager?.getCurrentDecodeType() ?: -1
        result.success(decodeType)
    }
}
