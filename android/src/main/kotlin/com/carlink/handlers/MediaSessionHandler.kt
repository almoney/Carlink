package com.carlink.handlers

import com.carlink.LogCallback
import com.carlink.MediaSessionManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result

/**
 * MediaSessionHandler - Handles MediaSession operations for AAOS integration.
 *
 * PURPOSE:
 * Routes Flutter platform method calls for MediaSession to the MediaSessionManager.
 * Provides interface for updating now-playing metadata and playback state from Dart.
 *
 * RESPONSIBILITIES:
 * - updateMediaMetadata: Update now-playing info (title, artist, album, art)
 * - updatePlaybackState: Update playing/paused state
 * - setMediaSessionActive: Activate/deactivate the session
 *
 * THREAD SAFETY:
 * All method calls arrive on the main thread via Flutter's MethodChannel.
 */
class MediaSessionHandler(
    private val mediaSessionManager: MediaSessionManager?,
    private val logCallback: LogCallback,
) {
    /**
     * Handles MediaSession-related method calls.
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
            "updateMediaMetadata" -> {
                handleUpdateMetadata(call, result)
                true
            }
            "updatePlaybackState" -> {
                handleUpdatePlaybackState(call, result)
                true
            }
            "setMediaSessionConnecting" -> {
                handleSetConnecting(result)
                true
            }
            "setMediaSessionStopped" -> {
                handleSetStopped(result)
                true
            }
            else -> false
        }

    /**
     * Update now-playing metadata.
     *
     * Arguments:
     * - title (String?): Song title or lyrics
     * - artist (String?): Artist name
     * - album (String?): Album name
     * - appName (String?): Source app name
     * - albumArt (ByteArray?): Album cover image
     * - duration (Long?): Track duration in milliseconds
     */
    private fun handleUpdateMetadata(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val manager = mediaSessionManager ?: return result.error(
                "MediaSessionError",
                "MediaSessionManager not initialized",
                null,
            )

            val title = call.argument<String>("title")
            val artist = call.argument<String>("artist")
            val album = call.argument<String>("album")
            val appName = call.argument<String>("appName")
            val albumArt = call.argument<ByteArray>("albumArt")
            val duration = call.argument<Number>("duration")?.toLong() ?: 0L

            manager.updateMetadata(
                title = title,
                artist = artist,
                album = album,
                appName = appName,
                albumArt = albumArt,
                duration = duration,
            )

            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[MEDIA_HANDLER] Update metadata error: ${e.message}")
            result.error("MediaSessionError", "Failed to update metadata: ${e.message}", null)
        }
    }

    /**
     * Update playback state.
     *
     * Arguments:
     * - isPlaying (Boolean): Whether media is currently playing
     * - position (Long?): Current playback position in milliseconds
     */
    private fun handleUpdatePlaybackState(
        call: MethodCall,
        result: Result,
    ) {
        try {
            val manager = mediaSessionManager ?: return result.error(
                "MediaSessionError",
                "MediaSessionManager not initialized",
                null,
            )

            val isPlaying = call.argument<Boolean>("isPlaying") ?: false
            val position = call.argument<Number>("position")?.toLong() ?: 0L

            manager.updatePlaybackState(isPlaying, position)

            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[MEDIA_HANDLER] Update playback state error: ${e.message}")
            result.error("MediaSessionError", "Failed to update playback state: ${e.message}", null)
        }
    }

    /**
     * Set session state to connecting.
     */
    private fun handleSetConnecting(result: Result) {
        try {
            mediaSessionManager?.setStateConnecting()
            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[MEDIA_HANDLER] Set connecting error: ${e.message}")
            result.error("MediaSessionError", "Failed to set connecting state: ${e.message}", null)
        }
    }

    /**
     * Set session state to stopped.
     */
    private fun handleSetStopped(result: Result) {
        try {
            mediaSessionManager?.setStateStopped()
            result.success(null)
        } catch (e: Exception) {
            logCallback.log("[MEDIA_HANDLER] Set stopped error: ${e.message}")
            result.error("MediaSessionError", "Failed to set stopped state: ${e.message}", null)
        }
    }
}
