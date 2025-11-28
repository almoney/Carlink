# Release 86 Audio Fixes

**Date:** 2025-11-27
**Analysis Sessions:** 1-6
**Status:** Implemented

---

## Executive Summary

Analysis of 6 test sessions revealed 8 systemic audio issues affecting CarPlay projection on AAOS. All issues have been identified, root-caused, and fixed. The fixes address:

- Siri tone not playing after first invocation
- No audio after USB disconnect/reconnect
- Microphone data loss during Siri
- Accumulating audio underruns (800-10,000+)
- Premature audio cutoff

---

## Issues Identified

### Issue #1: AudioTrack Paused and Never Resumed
**Sessions:** 4, 6
**Severity:** CRITICAL

**Symptom:** Siri activation tone heard on first invocation only. Subsequent Siri activations produced no audio output.

**Root Cause:** When `AudioSiriStop` command was received, the voice AudioTrack was paused via `track.pause()`. On subsequent Siri activations, the `ensureVoiceTrack()` method checked if the format matched but never detected the paused state, so `track.play()` was never called.

**Evidence:**
```
16:30:32.606 > _SendPhoneCommandToCar: StartRecordMic(1)  // Siri started
16:30:39.456 > Voice track paused - stream ended         // Track paused
16:31:31.762 > _SendPhoneCommandToCar: StartRecordMic(1)  // 2nd Siri - no audio
```

**Fix Location:** `DualStreamAudioManager.kt:478-616`

**Fix:** Added paused track detection and resume in all `ensureXxxTrack()` methods:
```kotlin
// Resume paused track if same format
mediaTrack?.let { track ->
    if (track.playState == AudioTrack.PLAYSTATE_PAUSED && mediaFormat == format) {
        track.play()
        mediaStarted = false // Reset pre-fill for smooth resume
        log("[AUDIO] Resumed paused media track")
        return
    }
}
```

---

### Issue #2: DualStreamAudioManager Not Reinitialized After USB Disconnect
**Sessions:** 3, 5
**Severity:** CRITICAL

**Symptom:** No audio playback after USB cable disconnection and reconnection. Navigation prompts not heard.

**Root Cause:** When USB disconnected, `release()` was called destroying all AudioTracks. However, `_audioInitialized` in Dart remained `true`, so `initializeAudio()` was never called on reconnect.

**Evidence:**
```
16:14:25.929 > [AUDIO_CONTEXT] Stream context changed to NAVIGATION (2)
16:14:26.318 > RAW AUDIO RX: Type=0x07 Len=11532  // Data received but not played
// No "Created NAV AudioTrack" log - manager was null
```

**Fix Location:** `carlink.dart:252-263`

**Fix:** Reset `_audioInitialized` in `stop()` and use `releaseAudio()` instead of `stopAudio()`:
```dart
if (_audioInitialized) {
    try {
        await CarlinkPlatform.instance.releaseAudio();
        logInfo('Audio released on stop', tag: 'AUDIO');
    } catch (e) {
        logError('Failed to release audio: $e', tag: 'AUDIO');
    }
    _audioInitialized = false; // Force reinitialization on next start()
}
```

---

### Issue #3: Microphone Buffer Overrun
**Sessions:** 6
**Severity:** HIGH

**Symptom:** Siri heard user press button (tone played) but voice commands not recognized. Log showed `Buffer overrun: wrote 0 of 640 bytes`.

**Root Cause:** Mic ring buffer was 120ms (16,320 bytes). Kotlin captured audio at 50 chunks/second (20ms each), but Dart's timer-based polling via platform channel couldn't keep up when main thread was blocked. Buffer filled completely, new data was lost.

**Evidence:**
```
16:40:11.041 > [MIC] Capture started: 16000Hz 1ch buffer=16320B
16:40:12.695 > [MIC] Buffer overrun: wrote 639 of 640 bytes  // FIRST WARNING
16:40:12.997 > [MIC] Buffer overrun: wrote 0 of 640 bytes    // TOTAL LOSS
16:40:13.301 > [MIC] Buffer overrun: wrote 0 of 640 bytes
```

**Fix Location:** `MicrophoneCaptureManager.kt:113-116`

**Fix:** Increased buffer capacity from 120ms to 500ms:
```kotlin
// Increased from 120ms to 500ms to prevent buffer overruns
private val bufferCapacityMs = 500  // 500ms ring buffer for jitter tolerance
```

---

### Issue #4: Accumulating Audio Underruns
**Sessions:** 1, 3, 6
**Severity:** HIGH

**Symptom:** 800-10,000+ underruns accumulated during sessions. Audio quality degraded with glitches and pops. In extreme cases, ANR crashes occurred.

**Root Cause:** Underruns were detected and logged but no recovery action was taken. Once buffer drained below threshold, it never recovered because playback continued consuming data faster than it arrived.

**Evidence:**
```
16:30:00 > 200 underruns
16:35:00 > 777 underruns
16:35:02 > 800+ underruns  // Accumulating ~10/second
```

**Fix Location:** `DualStreamAudioManager.kt:125-127,845-849`

**Fix:** Added underrun recovery mechanism that resets pre-fill when underruns exceed threshold:
```kotlin
private val underrunRecoveryThreshold = 10
private val prefillThresholdMs = 150  // Increased from 100ms

// In playback thread:
if (newUnderruns >= underrunRecoveryThreshold && buffer.fillLevelMs() < 50) {
    mediaStarted = false // Force pre-fill again
    log("[AUDIO_RECOVERY] Resetting media pre-fill due to $newUnderruns underruns")
}
```

---

### Issue #5: Microphone Permission Not Requested
**Sessions:** 6
**Severity:** HIGH

**Symptom:** First 4 Siri invocations failed silently. User discovered mic permission was not granted at 4:33 PM.

**Root Cause:** App checked permission with `hasMicrophonePermission()` but never requested it. When permission was denied, capture silently failed with no user feedback.

**Evidence:**
```
16:30:33.161 > [MIC] Permission check result: false
16:30:33.161 > [MIC] Microphone permission not granted
16:31:32.346 > [MIC] Permission check result: false  // Still not granted
16:32:32.187 > [MIC] Permission check result: false
16:33:31.748 > [MIC] Permission check result: false
```

**Fix Location:** `carlink.dart:206-221`

**Fix:** Added early permission check in `start()` with user-visible logging:
```dart
if (_microphoneEnabled) {
    try {
        final hasMicPermission = await CarlinkPlatform.instance.hasMicrophonePermission();
        if (!hasMicPermission) {
            logInfo('Microphone permission not granted - Siri/voice features may not work', tag: 'MIC');
        }
    } catch (e) {
        logError('Failed to check microphone permission: $e', tag: 'MIC');
    }
}
```

**Note:** Actual permission request dialog should be shown by host app UI.

---

### Issue #6: Aggressive Full Release on Any Error
**Sessions:** 1, 2
**Severity:** MEDIUM

**Symptom:** 72+ audio pipeline resets in Session 1. Every USB hiccup caused complete AudioTrack destruction and recreation.

**Root Cause:** `release()` method destroyed all 4 AudioTracks unconditionally. Even temporary USB transfer errors triggered full teardown.

**Fix Location:** `DualStreamAudioManager.kt:450-504`

**Fix:** Added `suspendPlayback()` and `resumePlayback()` for temporary disconnections:
```kotlin
fun suspendPlayback() {
    synchronized(lock) {
        log("[AUDIO] Suspending playback (retaining tracks)")
        mediaTrack?.let { if (it.playState == AudioTrack.PLAYSTATE_PLAYING) it.pause() }
        navTrack?.let { if (it.playState == AudioTrack.PLAYSTATE_PLAYING) it.pause() }
        voiceTrack?.let { if (it.playState == AudioTrack.PLAYSTATE_PLAYING) it.pause() }
        callTrack?.let { if (it.playState == AudioTrack.PLAYSTATE_PLAYING) it.pause() }
        // Reset pre-fill flags
        mediaStarted = false; navStarted = false; voiceStarted = false; callStarted = false
    }
}
```

---

### Issue #7: Ring Buffer Drops New Data When Full
**Sessions:** 1, 2, 4
**Severity:** MEDIUM

**Symptom:** Buffer overflow count reached 568 in Session 4. Audio data arrived but was silently dropped when buffer was full (during track pause).

**Root Cause:** `AudioRingBuffer.write()` returned 0 when buffer was full, discarding new data. For real-time audio, this is wrong - old data should be discarded to keep stream current.

**Evidence:**
```
16:31:42.345 > [AUDIO_STATS] fill=99.99% overflow=568  // Buffer full, data dropped
```

**Fix Location:** `AudioRingBuffer.kt:80-93`

**Fix:** Changed to overwrite-oldest pattern:
```kotlin
fun write(data: ByteArray, offset: Int, length: Int): Int {
    var available = availableForWrite()

    // Overwrite-oldest pattern for real-time audio
    if (available < length) {
        val toDiscard = length - available
        readPos = (readPos + toDiscard) % capacity  // Discard oldest
        discardedBytes += toDiscard
        overflowCount++
        available = length
    }
    // ... write new data
}
```

---

### Issue #8: Premature Stream Stop Commands
**Sessions:** 1, 2
**Severity:** LOW

**Symptom:** Navigation audio stopped after 1-3 seconds. Siri tone cut short.

**Root Cause:** Adapter sent `AudioNaviStop` very quickly after `AudioNaviStart`. App immediately paused the track, cutting off audio that was still in the buffer.

**Fix Location:** `DualStreamAudioManager.kt:133-141,396-441`

**Fix:** Added minimum playback duration enforcement:
```kotlin
private val minNavPlayDurationMs = 300
private val minVoicePlayDurationMs = 200

fun stopNavTrack() {
    synchronized(lock) {
        navTrack?.let { track ->
            if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                val playDuration = System.currentTimeMillis() - navStartTime
                val bufferLevel = navBuffer?.fillLevelMs() ?: 0

                if (playDuration < minNavPlayDurationMs && bufferLevel > 50) {
                    log("[AUDIO] Ignoring premature nav stop, buffer has ${bufferLevel}ms data")
                    return
                }
                track.pause()
            }
        }
    }
}
```

---

## Files Modified

| File | Lines Changed | Description |
|------|---------------|-------------|
| `DualStreamAudioManager.kt` | ~150 | Track resume, underrun recovery, suspend/resume, min duration |
| `MicrophoneCaptureManager.kt` | 4 | Buffer size increase |
| `AudioRingBuffer.kt` | 25 | Overwrite-oldest pattern |
| `carlink.dart` | 30 | Audio reinit, permission check |

---

## Testing Recommendations

1. **Siri Multi-Invocation Test**
   - Invoke Siri 5+ times consecutively
   - Verify tone plays every time
   - Verify voice recognition works

2. **USB Disconnect/Reconnect Test**
   - Start media playback
   - Disconnect USB cable
   - Reconnect USB cable
   - Verify audio resumes without manual intervention

3. **Extended Playback Test**
   - Play media for 30+ minutes
   - Monitor underrun count (should stay low)
   - Invoke Siri periodically
   - Verify no ANR crashes

4. **Siri During Music Test**
   - Play music
   - Invoke Siri
   - Speak voice command
   - Verify voice recognized correctly
   - Verify music resumes after Siri

---

## References

- [Android AudioTrack API](https://developer.android.com/reference/android/media/AudioTrack)
- [AAOS Audio Documentation](https://source.android.com/docs/devices/automotive/audio)
- [AudioFlinger restartIfDisabled](https://android.googlesource.com/platform/frameworks/av/+/4d231dc0ee34380956c71cbe18a750e487a69601%5E!/)
- Session analysis documents in `Documents/Troubleshooting/release_86/`
