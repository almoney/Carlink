package com.carlink

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.Process
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

private const val TAG = "CARLINK_AUDIO"

/**
 * Audio stream type identifiers from CPC200-CCPA protocol.
 */
object AudioStreamType {
    const val MEDIA = 1       // Music, podcasts, etc.
    const val NAVIGATION = 2  // Turn-by-turn directions
    const val PHONE_CALL = 3  // Phone calls (exclusive)
    const val SIRI = 4        // Voice assistant (exclusive)
}

/**
 * DualStreamAudioManager - Handles multiple audio streams with AAOS CarAudioContext integration.
 *
 * PURPOSE:
 * Provides stable, uninterrupted audio playback for CarPlay/Android Auto projection
 * by using separate AudioTracks for each stream type, with ring buffers to absorb
 * USB packet jitter. Each stream uses the appropriate USAGE constant for proper
 * AAOS routing to CarAudioContext.
 *
 * ARCHITECTURE:
 * ```
 * USB Thread (non-blocking)
 *     │
 *     ├──► Media Ring Buffer (250ms) ──► Media AudioTrack
 *     │                                    (USAGE_MEDIA → CarAudioContext.MUSIC)
 *     │
 *     ├──► Nav Ring Buffer (120ms) ──► Nav AudioTrack
 *     │                                  (USAGE_ASSISTANCE_NAVIGATION_GUIDANCE → CarAudioContext.NAVIGATION)
 *     │
 *     ├──► Voice Ring Buffer (150ms) ──► Voice AudioTrack
 *     │                                    (USAGE_ASSISTANT → CarAudioContext.VOICE_COMMAND)
 *     │
 *     └──► Call Ring Buffer (150ms) ──► Call AudioTrack
 *                                         (USAGE_VOICE_COMMUNICATION → CarAudioContext.CALL)
 *     │
 *     └──► Playback Thread (THREAD_PRIORITY_URGENT_AUDIO)
 *             reads from all buffers, writes to AudioTracks
 * ```
 *
 * AAOS CarAudioContext Mapping:
 * - USAGE_MEDIA (1) → MUSIC context
 * - USAGE_ASSISTANCE_NAVIGATION_GUIDANCE (12) → NAVIGATION context
 * - USAGE_ASSISTANT (16) → VOICE_COMMAND context
 * - USAGE_VOICE_COMMUNICATION (2) → CALL context
 *
 * KEY FEATURES:
 * - Lock-free ring buffers absorb 500-1200ms packet gaps from adapter
 * - Non-blocking writes from USB thread
 * - Dedicated high-priority playback thread
 * - Independent volume control per stream (ducking support)
 * - Automatic format switching per stream
 * - Proper AAOS audio routing via CarAudioContext
 *
 * THREAD SAFETY:
 * - writeAudio() called from USB thread (non-blocking)
 * - Playback thread handles AudioTrack writes
 * - Volume/ducking can be called from any thread
 */
class DualStreamAudioManager(
    private val logCallback: LogCallback,
) {
    // Audio tracks for each stream type (maps to AAOS CarAudioContext)
    private var mediaTrack: AudioTrack? = null      // USAGE_MEDIA → MUSIC
    private var navTrack: AudioTrack? = null        // USAGE_ASSISTANCE_NAVIGATION_GUIDANCE → NAVIGATION
    private var voiceTrack: AudioTrack? = null      // USAGE_ASSISTANT → VOICE_COMMAND
    private var callTrack: AudioTrack? = null       // USAGE_VOICE_COMMUNICATION → CALL

    // Ring buffers for jitter compensation (one per stream)
    private var mediaBuffer: AudioRingBuffer? = null   // 250ms for music
    private var navBuffer: AudioRingBuffer? = null     // 120ms for nav prompts
    private var voiceBuffer: AudioRingBuffer? = null   // 150ms for voice assistant
    private var callBuffer: AudioRingBuffer? = null    // 150ms for phone calls

    // Current audio format per stream
    private var mediaFormat: AudioFormatConfig? = null
    private var navFormat: AudioFormatConfig? = null
    private var voiceFormat: AudioFormatConfig? = null
    private var callFormat: AudioFormatConfig? = null

    // Volume control
    private var mediaVolume: Float = 1.0f
    private var navVolume: Float = 1.0f
    private var voiceVolume: Float = 1.0f
    private var callVolume: Float = 1.0f
    private var isDucked: Boolean = false
    private var duckLevel: Float = 0.2f  // 20% volume when ducked

    // Playback thread
    private var playbackThread: AudioPlaybackThread? = null
    private val isRunning = AtomicBoolean(false)

    // Statistics
    private var startTime: Long = 0
    private var mediaUnderruns: Int = 0
    private var navUnderruns: Int = 0
    private var voiceUnderruns: Int = 0
    private var callUnderruns: Int = 0
    private var writeCount: Long = 0  // DEBUG: Counter for periodic logging
    private var lastStatsLog: Long = 0  // DEBUG: Timestamp of last stats log
    private var zeroPacketsFiltered: Long = 0  // Count of zero-filled packets filtered

    // Buffer size multiplier (5x minimum for USB jitter tolerance)
    private val bufferMultiplier = 5

    // Playback chunk size in bytes (5ms of audio at 48kHz stereo)
    private val playbackChunkSize = 48000 * 2 * 2 * 5 / 1000  // ~960 bytes

    // Pre-fill threshold: minimum buffer level (ms) before starting playback
    // Prevents initial underruns by ensuring buffer has enough data
    // Increased from 100ms to 150ms based on Session 3/6 underrun analysis
    private val prefillThresholdMs = 150

    // Underrun recovery threshold: if this many underruns occur in a short period,
    // reset pre-fill to allow buffer to refill before resuming playback
    private val underrunRecoveryThreshold = 10

    // Track whether each stream has started playing (for pre-fill logic)
    @Volatile private var mediaStarted = false
    @Volatile private var navStarted = false

    // Track start times for minimum playback duration enforcement
    // Prevents premature stop when adapter sends stop command too quickly
    @Volatile private var navStartTime: Long = 0
    @Volatile private var voiceStartTime: Long = 0

    // Minimum playback duration (ms) before allowing stream stop
    // This fixes premature nav/Siri audio cutoff observed in Sessions 1-2
    private val minNavPlayDurationMs = 300
    private val minVoicePlayDurationMs = 200
    @Volatile private var voiceStarted = false
    @Volatile private var callStarted = false

    private val lock = Any()

    /**
     * Initialize the audio manager and start playback thread.
     */
    fun initialize(): Boolean {
        synchronized(lock) {
            if (isRunning.get()) {
                log("[AUDIO] Already initialized")
                return true
            }

            try {
                startTime = System.currentTimeMillis()
                isRunning.set(true)

                // Start playback thread
                playbackThread = AudioPlaybackThread().also { it.start() }

                log("[AUDIO] DualStreamAudioManager initialized")
                return true
            } catch (e: Exception) {
                log("[AUDIO] ERROR: Failed to initialize: ${e.message}")
                isRunning.set(false)
                return false
            }
        }
    }

    /**
     * Check if audio data is entirely zero-filled (invalid/uninitialized data).
     *
     * Real audio, even during silent moments, contains dithering noise.
     * Packets that are exactly 0x00 for every byte indicate adapter issues.
     *
     * Samples multiple positions for efficiency (O(1) check).
     */
    private fun isZeroFilledAudio(data: ByteArray): Boolean {
        if (data.size < 16) return false

        // Sample 5 positions across the buffer
        val positions = intArrayOf(
            0,
            (data.size * 0.25).toInt() and 0x7FFFFFFE,  // Align to 2-byte boundary
            (data.size * 0.5).toInt() and 0x7FFFFFFE,
            (data.size * 0.75).toInt() and 0x7FFFFFFE,
            (data.size - 8) and 0x7FFFFFFE,
        )

        for (pos in positions) {
            if (pos + 4 > data.size) continue
            // Check 4 consecutive bytes - if any non-zero, it's real audio
            if (data[pos] != 0.toByte() ||
                data[pos + 1] != 0.toByte() ||
                data[pos + 2] != 0.toByte() ||
                data[pos + 3] != 0.toByte()
            ) {
                return false
            }
        }
        return true
    }

    /**
     * Write audio data to the appropriate stream buffer (non-blocking).
     *
     * Called from USB thread. Never blocks.
     *
     * @param data PCM audio data (16-bit)
     * @param audioType Stream type (1=media, 2=navigation)
     * @param decodeType CPC200-CCPA format type (1-7)
     * @return Number of bytes written to buffer
     */
    fun writeAudio(data: ByteArray, audioType: Int, decodeType: Int): Int {
        if (!isRunning.get()) return -1

        // Filter zero-filled packets (adapter firmware issue / uninitialized data)
        // This is a secondary defense; primary filtering is in Dart layer
        if (isZeroFilledAudio(data)) {
            zeroPacketsFiltered++
            if (zeroPacketsFiltered == 1L || zeroPacketsFiltered % 100 == 0L) {
                Log.w(TAG, "[AUDIO_FILTER] Filtered $zeroPacketsFiltered zero-filled packets")
            }
            return 0  // Return 0 to indicate no bytes written (not an error)
        }

        writeCount++

        // DEBUG: Log every 500th packet with first bytes and buffer stats
        if (writeCount % 500 == 1L) {
            val firstBytes = data.take(16).joinToString(" ") { String.format("%02X", it) }
            val bufferStats = mediaBuffer?.let {
                "fill=${it.fillLevelMs()}ms overflow=${it.overflowCount} underflow=${it.underflowCount}"
            } ?: "no-buffer"
            Log.i(TAG, "[AUDIO_DEBUG] write#$writeCount size=${data.size} type=$audioType decode=$decodeType first16=[$firstBytes] $bufferStats")
        }

        // DEBUG: Log buffer stats every 10 seconds
        val now = System.currentTimeMillis()
        if (now - lastStatsLog > 10000) {
            lastStatsLog = now
            mediaBuffer?.let {
                Log.i(TAG, "[AUDIO_STATS] mediaBuffer: fill=${it.fillLevelMs()}ms/${it.fillLevel() * 100}% written=${it.totalBytesWritten} read=${it.totalBytesRead} overflow=${it.overflowCount} underflow=${it.underflowCount}")
            }
        }

        // Route to appropriate AudioTrack based on stream type
        // Each stream maps to a specific AAOS CarAudioContext for proper vehicle integration
        return when (audioType) {
            AudioStreamType.MEDIA -> {
                // USAGE_MEDIA → CarAudioContext.MUSIC
                ensureMediaTrack(decodeType)
                mediaBuffer?.write(data) ?: -1
            }
            AudioStreamType.NAVIGATION -> {
                // USAGE_ASSISTANCE_NAVIGATION_GUIDANCE → CarAudioContext.NAVIGATION
                ensureNavTrack(decodeType)
                navBuffer?.write(data) ?: -1
            }
            AudioStreamType.SIRI -> {
                // USAGE_ASSISTANT → CarAudioContext.VOICE_COMMAND
                ensureVoiceTrack(decodeType)
                voiceBuffer?.write(data) ?: -1
            }
            AudioStreamType.PHONE_CALL -> {
                // USAGE_VOICE_COMMUNICATION → CarAudioContext.CALL
                ensureCallTrack(decodeType)
                callBuffer?.write(data) ?: -1
            }
            else -> {
                // Default to media stream for unknown types
                ensureMediaTrack(decodeType)
                mediaBuffer?.write(data) ?: -1
            }
        }
    }

    /**
     * Set volume ducking state.
     *
     * Called when adapter sends Len=16 volume packets.
     *
     * @param targetVolume Target volume (0.0 to 1.0), typically 0.2 during nav
     */
    fun setDucking(targetVolume: Float) {
        synchronized(lock) {
            isDucked = targetVolume < 1.0f
            duckLevel = targetVolume.coerceIn(0.0f, 1.0f)

            val effectiveVolume = if (isDucked) mediaVolume * duckLevel else mediaVolume
            mediaTrack?.setVolume(effectiveVolume)

            if (isDucked) {
                log("[AUDIO] Media ducked to ${(duckLevel * 100).toInt()}%")
            } else {
                log("[AUDIO] Media volume restored to ${(mediaVolume * 100).toInt()}%")
            }
        }
    }

    /**
     * Set media stream volume.
     *
     * @param volume Volume level (0.0 to 1.0)
     */
    fun setMediaVolume(volume: Float) {
        synchronized(lock) {
            mediaVolume = volume.coerceIn(0.0f, 1.0f)
            val effectiveVolume = if (isDucked) mediaVolume * duckLevel else mediaVolume
            mediaTrack?.setVolume(effectiveVolume)
        }
    }

    /**
     * Set navigation stream volume.
     *
     * @param volume Volume level (0.0 to 1.0)
     */
    fun setNavVolume(volume: Float) {
        synchronized(lock) {
            navVolume = volume.coerceIn(0.0f, 1.0f)
            navTrack?.setVolume(navVolume)
        }
    }

    /**
     * Check if audio is currently playing.
     */
    fun isPlaying(): Boolean {
        return isRunning.get() && (
            mediaTrack?.playState == AudioTrack.PLAYSTATE_PLAYING ||
            navTrack?.playState == AudioTrack.PLAYSTATE_PLAYING ||
            voiceTrack?.playState == AudioTrack.PLAYSTATE_PLAYING ||
            callTrack?.playState == AudioTrack.PLAYSTATE_PLAYING
        )
    }

    /**
     * Get statistics about audio playback.
     */
    fun getStats(): Map<String, Any> {
        synchronized(lock) {
            val durationMs = if (startTime > 0) System.currentTimeMillis() - startTime else 0

            return mapOf(
                "isRunning" to isRunning.get(),
                "durationSeconds" to durationMs / 1000.0,
                "mediaVolume" to mediaVolume,
                "navVolume" to navVolume,
                "voiceVolume" to voiceVolume,
                "callVolume" to callVolume,
                "isDucked" to isDucked,
                "duckLevel" to duckLevel,
                "mediaFormat" to (mediaFormat?.let { "${it.sampleRate}Hz ${it.channelCount}ch" } ?: "none"),
                "navFormat" to (navFormat?.let { "${it.sampleRate}Hz ${it.channelCount}ch" } ?: "none"),
                "voiceFormat" to (voiceFormat?.let { "${it.sampleRate}Hz ${it.channelCount}ch" } ?: "none"),
                "callFormat" to (callFormat?.let { "${it.sampleRate}Hz ${it.channelCount}ch" } ?: "none"),
                "mediaBuffer" to (mediaBuffer?.getStats() ?: emptyMap()),
                "navBuffer" to (navBuffer?.getStats() ?: emptyMap()),
                "voiceBuffer" to (voiceBuffer?.getStats() ?: emptyMap()),
                "callBuffer" to (callBuffer?.getStats() ?: emptyMap()),
                "mediaUnderruns" to mediaUnderruns,
                "navUnderruns" to navUnderruns,
                "voiceUnderruns" to voiceUnderruns,
                "callUnderruns" to callUnderruns,
            )
        }
    }

    // ========== Stream Stop Methods ==========
    //
    // These methods pause individual AudioTracks when their corresponding stream ends
    // (e.g., AudioNaviStop command received). This is critical for AAOS volume control:
    //
    // AAOS CarAudioService determines which volume group to adjust based on "active players"
    // (AudioTracks in PLAYSTATE_PLAYING). If a track remains in PLAYING state after its
    // audio stream ends, AAOS continues to prioritize that context for volume control.
    //
    // Example: Nav track left in PLAYING state after nav prompt ends causes volume keys
    // to control NAVIGATION volume instead of MEDIA volume, appearing "stuck".
    //
    // Using pause() instead of stop() preserves the buffer and allows quick resume
    // when the stream restarts, avoiding audio glitches.

    /**
     * Pause navigation AudioTrack when nav audio stream ends.
     * Called when AudioNaviStop command is received from the adapter.
     *
     * Enforces minimum playback duration to prevent premature cutoff when adapter
     * sends stop command too quickly (observed in Sessions 1-2).
     */
    fun stopNavTrack() {
        synchronized(lock) {
            navTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    // Check minimum playback duration
                    val playDuration = System.currentTimeMillis() - navStartTime
                    val bufferLevel = navBuffer?.fillLevelMs() ?: 0

                    if (playDuration < minNavPlayDurationMs && bufferLevel > 50) {
                        log("[AUDIO] Ignoring premature nav stop after ${playDuration}ms, buffer has ${bufferLevel}ms data")
                        return
                    }

                    track.pause()
                    log("[AUDIO] Nav track paused after ${playDuration}ms - stream ended, AAOS will deprioritize NAVIGATION context")
                }
            }
            navStarted = false
        }
    }

    /**
     * Pause voice assistant AudioTrack when Siri/voice stream ends.
     * Called when AudioSiriStop command is received from the adapter.
     *
     * Enforces minimum playback duration to prevent premature Siri tone cutoff.
     */
    fun stopVoiceTrack() {
        synchronized(lock) {
            voiceTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    // Check minimum playback duration
                    val playDuration = System.currentTimeMillis() - voiceStartTime
                    val bufferLevel = voiceBuffer?.fillLevelMs() ?: 0

                    if (playDuration < minVoicePlayDurationMs && bufferLevel > 50) {
                        log("[AUDIO] Ignoring premature voice stop after ${playDuration}ms, buffer has ${bufferLevel}ms data")
                        return
                    }

                    track.pause()
                    log("[AUDIO] Voice track paused after ${playDuration}ms - stream ended, AAOS will deprioritize VOICE_COMMAND context")
                }
            }
            voiceStarted = false
        }
    }

    /**
     * Pause phone call AudioTrack when call audio stream ends.
     * Called when AudioPhonecallStop command is received from the adapter.
     */
    fun stopCallTrack() {
        synchronized(lock) {
            callTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                    log("[AUDIO] Call track paused - stream ended, AAOS will deprioritize CALL context")
                }
            }
            callStarted = false
        }
    }

    /**
     * Pause media AudioTrack when media stream ends.
     * Called when AudioMediaStop or AudioOutputStop command is received.
     */
    fun stopMediaTrack() {
        synchronized(lock) {
            mediaTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                    log("[AUDIO] Media track paused - stream ended")
                }
            }
            mediaStarted = false
        }
    }

    /**
     * Suspend playback without releasing resources.
     *
     * Use this instead of release() for temporary disconnections (USB hiccups).
     * Tracks are paused but retained, allowing quick resume without reinitialization.
     * This prevents the 72+ pipeline resets observed in Session 1.
     */
    fun suspendPlayback() {
        synchronized(lock) {
            log("[AUDIO] Suspending playback (retaining tracks)")

            mediaTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                }
            }
            navTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                }
            }
            voiceTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                }
            }
            callTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                }
            }

            // Reset pre-fill flags so tracks wait for buffer to fill before resuming
            mediaStarted = false
            navStarted = false
            voiceStarted = false
            callStarted = false

            log("[AUDIO] Playback suspended - tracks paused but retained")
        }
    }

    /**
     * Resume playback after suspension.
     *
     * Only resumes tracks that have data in their buffers.
     */
    fun resumePlayback() {
        synchronized(lock) {
            log("[AUDIO] Resuming playback")

            // Tracks will be resumed automatically by ensureXxxTrack() when data arrives
            // Just log the current state for debugging
            val states = listOf(
                "media=${mediaTrack?.playState ?: "null"}",
                "nav=${navTrack?.playState ?: "null"}",
                "voice=${voiceTrack?.playState ?: "null"}",
                "call=${callTrack?.playState ?: "null"}",
            )
            log("[AUDIO] Track states: ${states.joinToString(", ")}")
        }
    }

    /**
     * Stop playback and release all resources.
     */
    fun release() {
        synchronized(lock) {
            log("[AUDIO] Releasing DualStreamAudioManager")

            isRunning.set(false)

            // Stop playback thread
            playbackThread?.interrupt()
            try {
                playbackThread?.join(1000)
            } catch (e: InterruptedException) {
                // Ignore
            }
            playbackThread = null

            // Release all audio tracks
            releaseMediaTrack()
            releaseNavTrack()
            releaseVoiceTrack()
            releaseCallTrack()

            // Clear all buffers
            mediaBuffer?.clear()
            navBuffer?.clear()
            voiceBuffer?.clear()
            callBuffer?.clear()
            mediaBuffer = null
            navBuffer = null
            voiceBuffer = null
            callBuffer = null

            log("[AUDIO] DualStreamAudioManager released")
        }
    }

    // ========== Private Methods ==========

    private fun ensureMediaTrack(decodeType: Int) {
        val format = AudioFormats.fromDecodeType(decodeType)

        synchronized(lock) {
            // Resume paused track if same format (Fix for Siri tone not heard after first invocation)
            mediaTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PAUSED && mediaFormat == format) {
                    track.play()
                    mediaStarted = false // Reset pre-fill for smooth resume
                    log("[AUDIO] Resumed paused media track (same format ${format.sampleRate}Hz)")
                    return
                }
            }

            // Check if format changed
            if (mediaFormat != format) {
                log("[AUDIO] Media format change: ${mediaFormat?.sampleRate ?: 0}Hz -> ${format.sampleRate}Hz")
                releaseMediaTrack()
                mediaFormat = format

                // Create new ring buffer for this format
                // 500ms buffer absorbs USB packet jitter (gaps up to 1200ms observed)
                mediaBuffer = AudioRingBuffer(
                    capacityMs = 500,
                    sampleRate = format.sampleRate,
                    channels = format.channelCount,
                )

                // Create AudioTrack with USAGE_MEDIA → CarAudioContext.MUSIC
                mediaTrack = createAudioTrack(format, AudioStreamType.MEDIA)
                mediaTrack?.play()
            }
        }
    }

    private fun ensureNavTrack(decodeType: Int) {
        val format = AudioFormats.fromDecodeType(decodeType)

        synchronized(lock) {
            // Resume paused track if same format
            navTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PAUSED && navFormat == format) {
                    track.play()
                    navStarted = false // Reset pre-fill for smooth resume
                    navStartTime = System.currentTimeMillis() // Track start time for min duration
                    log("[AUDIO] Resumed paused nav track (same format ${format.sampleRate}Hz)")
                    return
                }
            }

            // Check if format changed
            if (navFormat != format) {
                log("[AUDIO] Nav format change: ${navFormat?.sampleRate ?: 0}Hz -> ${format.sampleRate}Hz")
                releaseNavTrack()
                navFormat = format

                // Create new ring buffer for this format
                // 200ms buffer for navigation prompts (lower latency than media)
                navBuffer = AudioRingBuffer(
                    capacityMs = 200,
                    sampleRate = format.sampleRate,
                    channels = format.channelCount,
                )

                // Create AudioTrack with USAGE_ASSISTANCE_NAVIGATION_GUIDANCE → CarAudioContext.NAVIGATION
                navTrack = createAudioTrack(format, AudioStreamType.NAVIGATION)
                navTrack?.play()
                navStartTime = System.currentTimeMillis() // Track start time for min duration
            }
        }
    }

    private fun ensureVoiceTrack(decodeType: Int) {
        val format = AudioFormats.fromDecodeType(decodeType)

        synchronized(lock) {
            // Resume paused track if same format (critical for Siri tone on subsequent invocations)
            voiceTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PAUSED && voiceFormat == format) {
                    track.play()
                    voiceStarted = false // Reset pre-fill for smooth resume
                    voiceStartTime = System.currentTimeMillis() // Track start time for min duration
                    log("[AUDIO] Resumed paused voice track (same format ${format.sampleRate}Hz)")
                    return
                }
            }

            // Check if format changed
            if (voiceFormat != format) {
                log("[AUDIO] Voice format change: ${voiceFormat?.sampleRate ?: 0}Hz -> ${format.sampleRate}Hz")
                releaseVoiceTrack()
                voiceFormat = format

                // Create new ring buffer for this format
                // 250ms buffer for voice assistant responses
                voiceBuffer = AudioRingBuffer(
                    capacityMs = 250,
                    sampleRate = format.sampleRate,
                    channels = format.channelCount,
                )

                // Create AudioTrack with USAGE_ASSISTANT → CarAudioContext.VOICE_COMMAND
                voiceTrack = createAudioTrack(format, AudioStreamType.SIRI)
                voiceTrack?.play()
                voiceStartTime = System.currentTimeMillis() // Track start time for min duration
            }
        }
    }

    private fun ensureCallTrack(decodeType: Int) {
        val format = AudioFormats.fromDecodeType(decodeType)

        synchronized(lock) {
            // Resume paused track if same format
            callTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PAUSED && callFormat == format) {
                    track.play()
                    callStarted = false // Reset pre-fill for smooth resume
                    log("[AUDIO] Resumed paused call track (same format ${format.sampleRate}Hz)")
                    return
                }
            }

            // Check if format changed
            if (callFormat != format) {
                log("[AUDIO] Call format change: ${callFormat?.sampleRate ?: 0}Hz -> ${format.sampleRate}Hz")
                releaseCallTrack()
                callFormat = format

                // Create new ring buffer for this format
                // 250ms buffer for phone call audio
                callBuffer = AudioRingBuffer(
                    capacityMs = 250,
                    sampleRate = format.sampleRate,
                    channels = format.channelCount,
                )

                // Create AudioTrack with USAGE_VOICE_COMMUNICATION → CarAudioContext.CALL
                callTrack = createAudioTrack(format, AudioStreamType.PHONE_CALL)
                callTrack?.play()
            }
        }
    }

    /**
     * Create an AudioTrack with the appropriate USAGE constant for AAOS CarAudioContext mapping.
     *
     * AAOS CarAudioContext Mapping:
     * - USAGE_MEDIA (1) → MUSIC context
     * - USAGE_ASSISTANCE_NAVIGATION_GUIDANCE (12) → NAVIGATION context
     * - USAGE_ASSISTANT (16) → VOICE_COMMAND context
     * - USAGE_VOICE_COMMUNICATION (2) → CALL context
     */
    private fun createAudioTrack(format: AudioFormatConfig, streamType: Int): AudioTrack? {
        try {
            val minBufferSize = AudioTrack.getMinBufferSize(
                format.sampleRate,
                format.channelConfig,
                format.encoding,
            )

            if (minBufferSize == AudioTrack.ERROR || minBufferSize == AudioTrack.ERROR_BAD_VALUE) {
                log("[AUDIO] ERROR: Invalid buffer size for ${format.sampleRate}Hz")
                return null
            }

            // Use larger buffer for jitter tolerance
            val bufferSize = minBufferSize * bufferMultiplier

            // Select AudioAttributes based on stream type for proper AAOS CarAudioContext routing
            val (usage, contentType, streamName) = when (streamType) {
                AudioStreamType.MEDIA -> Triple(
                    AudioAttributes.USAGE_MEDIA,              // → CarAudioContext.MUSIC
                    AudioAttributes.CONTENT_TYPE_MUSIC,
                    "MEDIA",
                )
                AudioStreamType.NAVIGATION -> Triple(
                    AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE,  // → CarAudioContext.NAVIGATION
                    AudioAttributes.CONTENT_TYPE_SPEECH,
                    "NAV",
                )
                AudioStreamType.SIRI -> Triple(
                    AudioAttributes.USAGE_ASSISTANT,          // → CarAudioContext.VOICE_COMMAND
                    AudioAttributes.CONTENT_TYPE_SPEECH,
                    "VOICE",
                )
                AudioStreamType.PHONE_CALL -> Triple(
                    AudioAttributes.USAGE_VOICE_COMMUNICATION,  // → CarAudioContext.CALL
                    AudioAttributes.CONTENT_TYPE_SPEECH,
                    "CALL",
                )
                else -> Triple(
                    AudioAttributes.USAGE_MEDIA,
                    AudioAttributes.CONTENT_TYPE_MUSIC,
                    "UNKNOWN",
                )
            }

            val audioAttributes = AudioAttributes.Builder()
                .setUsage(usage)
                .setContentType(contentType)
                .build()

            val audioFormat = AudioFormat.Builder()
                .setSampleRate(format.sampleRate)
                .setChannelMask(format.channelConfig)
                .setEncoding(format.encoding)
                .build()

            val track = AudioTrack.Builder()
                .setAudioAttributes(audioAttributes)
                .setAudioFormat(audioFormat)
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .build()

            // Set initial volume based on stream type
            val volume = when (streamType) {
                AudioStreamType.MEDIA -> if (isDucked) mediaVolume * duckLevel else mediaVolume
                AudioStreamType.NAVIGATION -> navVolume
                AudioStreamType.SIRI -> voiceVolume
                AudioStreamType.PHONE_CALL -> callVolume
                else -> 1.0f
            }
            track.setVolume(volume)

            log("[AUDIO] Created $streamName AudioTrack: ${format.sampleRate}Hz ${format.channelCount}ch buffer=${bufferSize}B usage=$usage")

            return track
        } catch (e: Exception) {
            log("[AUDIO] ERROR: Failed to create AudioTrack: ${e.message}")
            return null
        }
    }

    private fun releaseMediaTrack() {
        try {
            mediaTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.stop()
                }
                track.release()
            }
        } catch (e: Exception) {
            log("[AUDIO] ERROR: Failed to release media track: ${e.message}")
        }
        mediaTrack = null
        mediaFormat = null
        mediaStarted = false  // Reset pre-fill flag for next track
    }

    private fun releaseNavTrack() {
        try {
            navTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.stop()
                }
                track.release()
            }
        } catch (e: Exception) {
            log("[AUDIO] ERROR: Failed to release nav track: ${e.message}")
        }
        navTrack = null
        navFormat = null
        navStarted = false  // Reset pre-fill flag for next track
    }

    private fun releaseVoiceTrack() {
        try {
            voiceTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.stop()
                }
                track.release()
            }
        } catch (e: Exception) {
            log("[AUDIO] ERROR: Failed to release voice track: ${e.message}")
        }
        voiceTrack = null
        voiceFormat = null
        voiceStarted = false  // Reset pre-fill flag for next track
    }

    private fun releaseCallTrack() {
        try {
            callTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.stop()
                }
                track.release()
            }
        } catch (e: Exception) {
            log("[AUDIO] ERROR: Failed to release call track: ${e.message}")
        }
        callTrack = null
        callFormat = null
        callStarted = false  // Reset pre-fill flag for next track
    }

    private fun log(message: String) {
        Log.d(TAG, message)
        logCallback.log(message)
    }

    /**
     * Dedicated audio playback thread.
     *
     * Runs at THREAD_PRIORITY_URGENT_AUDIO for consistent scheduling.
     * Reads from ring buffers and writes to AudioTracks.
     *
     * Each stream has its own tempBuffer to prevent any potential data corruption
     * when multiple streams are active simultaneously (e.g., nav during music).
     */
    private inner class AudioPlaybackThread : Thread("AudioPlayback") {
        // Separate buffers per stream to prevent data corruption during interleaved playback
        private val mediaTempBuffer = ByteArray(playbackChunkSize)
        private val navTempBuffer = ByteArray(playbackChunkSize)
        private val voiceTempBuffer = ByteArray(playbackChunkSize)
        private val callTempBuffer = ByteArray(playbackChunkSize)

        override fun run() {
            // Set high priority for audio thread
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            log("[AUDIO] Playback thread started with URGENT_AUDIO priority")

            while (isRunning.get() && !isInterrupted) {
                try {
                    var didWork = false

                    // Process media buffer
                    mediaBuffer?.let { buffer ->
                        mediaTrack?.let { track ->
                            if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                                // Pre-fill check: wait for minimum buffer level before first playback
                                if (!mediaStarted) {
                                    val fillMs = buffer.fillLevelMs()
                                    if (fillMs < prefillThresholdMs) {
                                        // Not enough data yet, skip this iteration
                                        return@let
                                    }
                                    mediaStarted = true
                                    log("[AUDIO] Media pre-fill complete: ${fillMs}ms buffered, starting playback")
                                }

                                val available = buffer.availableForRead()
                                if (available > 0) {
                                    val toRead = minOf(available, playbackChunkSize)
                                    val bytesRead = buffer.read(mediaTempBuffer, 0, toRead)
                                    if (bytesRead > 0) {
                                        val written = track.write(mediaTempBuffer, 0, bytesRead)
                                        if (written < 0) {
                                            handleTrackError("MEDIA", written)
                                        }
                                        didWork = true
                                    }
                                }

                                // Check for underruns and trigger recovery if needed
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    val underruns = track.underrunCount
                                    if (underruns > mediaUnderruns) {
                                        val newUnderruns = underruns - mediaUnderruns
                                        mediaUnderruns = underruns
                                        log("[AUDIO_UNDERRUN] Media underrun detected: +$newUnderruns (total: $underruns)")

                                        // Recovery: If many underruns and buffer critically low, reset pre-fill
                                        if (newUnderruns >= underrunRecoveryThreshold && buffer.fillLevelMs() < 50) {
                                            mediaStarted = false // Force pre-fill again
                                            log("[AUDIO_RECOVERY] Resetting media pre-fill due to $newUnderruns underruns, buffer=${buffer.fillLevelMs()}ms")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Process navigation buffer
                    navBuffer?.let { buffer ->
                        navTrack?.let { track ->
                            if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                                // Pre-fill check for navigation (shorter threshold for lower latency)
                                if (!navStarted) {
                                    val fillMs = buffer.fillLevelMs()
                                    if (fillMs < prefillThresholdMs / 2) {
                                        return@let
                                    }
                                    navStarted = true
                                    log("[AUDIO] Nav pre-fill complete: ${fillMs}ms buffered, starting playback")
                                }

                                val available = buffer.availableForRead()
                                if (available > 0) {
                                    val toRead = minOf(available, playbackChunkSize)
                                    val bytesRead = buffer.read(navTempBuffer, 0, toRead)
                                    if (bytesRead > 0) {
                                        val written = track.write(navTempBuffer, 0, bytesRead)
                                        if (written < 0) {
                                            handleTrackError("NAV", written)
                                        }
                                        didWork = true
                                    }
                                }

                                // Check for underruns
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    val underruns = track.underrunCount
                                    if (underruns > navUnderruns) {
                                        val newUnderruns = underruns - navUnderruns
                                        navUnderruns = underruns
                                        log("[AUDIO_UNDERRUN] Nav underrun detected: +$newUnderruns (total: $underruns)")
                                    }
                                }
                            }
                        }
                    }

                    // Process voice assistant buffer (USAGE_ASSISTANT → CarAudioContext.VOICE_COMMAND)
                    voiceBuffer?.let { buffer ->
                        voiceTrack?.let { track ->
                            if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                                // Pre-fill check for voice assistant
                                if (!voiceStarted) {
                                    val fillMs = buffer.fillLevelMs()
                                    if (fillMs < prefillThresholdMs / 2) {
                                        return@let
                                    }
                                    voiceStarted = true
                                    log("[AUDIO] Voice pre-fill complete: ${fillMs}ms buffered, starting playback")
                                }

                                val available = buffer.availableForRead()
                                if (available > 0) {
                                    val toRead = minOf(available, playbackChunkSize)
                                    val bytesRead = buffer.read(voiceTempBuffer, 0, toRead)
                                    if (bytesRead > 0) {
                                        val written = track.write(voiceTempBuffer, 0, bytesRead)
                                        if (written < 0) {
                                            handleTrackError("VOICE", written)
                                        }
                                        didWork = true
                                    }
                                }

                                // Check for underruns
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    val underruns = track.underrunCount
                                    if (underruns > voiceUnderruns) {
                                        val newUnderruns = underruns - voiceUnderruns
                                        voiceUnderruns = underruns
                                        log("[AUDIO_UNDERRUN] Voice underrun detected: +$newUnderruns (total: $underruns)")
                                    }
                                }
                            }
                        }
                    }

                    // Process phone call buffer (USAGE_VOICE_COMMUNICATION → CarAudioContext.CALL)
                    callBuffer?.let { buffer ->
                        callTrack?.let { track ->
                            if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                                // Pre-fill check for phone calls
                                if (!callStarted) {
                                    val fillMs = buffer.fillLevelMs()
                                    if (fillMs < prefillThresholdMs / 2) {
                                        return@let
                                    }
                                    callStarted = true
                                    log("[AUDIO] Call pre-fill complete: ${fillMs}ms buffered, starting playback")
                                }

                                val available = buffer.availableForRead()
                                if (available > 0) {
                                    val toRead = minOf(available, playbackChunkSize)
                                    val bytesRead = buffer.read(callTempBuffer, 0, toRead)
                                    if (bytesRead > 0) {
                                        val written = track.write(callTempBuffer, 0, bytesRead)
                                        if (written < 0) {
                                            handleTrackError("CALL", written)
                                        }
                                        didWork = true
                                    }
                                }

                                // Check for underruns
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    val underruns = track.underrunCount
                                    if (underruns > callUnderruns) {
                                        val newUnderruns = underruns - callUnderruns
                                        callUnderruns = underruns
                                        log("[AUDIO_UNDERRUN] Call underrun detected: +$newUnderruns (total: $underruns)")
                                    }
                                }
                            }
                        }
                    }

                    // Small sleep if no work done to prevent busy-waiting
                    if (!didWork) {
                        sleep(5)
                    }
                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    Log.e(TAG, "[AUDIO] Playback thread error: ${e.message}")
                }
            }

            log("[AUDIO] Playback thread stopped")
        }

        private fun handleTrackError(streamType: String, errorCode: Int) {
            when (errorCode) {
                AudioTrack.ERROR_DEAD_OBJECT -> {
                    Log.e(TAG, "[AUDIO] $streamType AudioTrack dead, needs reinitialization")
                }
                AudioTrack.ERROR_INVALID_OPERATION -> {
                    Log.e(TAG, "[AUDIO] $streamType AudioTrack invalid operation")
                }
                else -> {
                    Log.e(TAG, "[AUDIO] $streamType AudioTrack write error: $errorCode")
                }
            }
        }
    }
}
