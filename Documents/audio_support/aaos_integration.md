# AAOS Audio Integration

This document covers Android Automotive OS (AAOS) specific audio integration, focusing on CarAudioService interactions, volume control, and audio context management.

## Overview

AAOS handles audio differently than standard Android. The `CarAudioService` manages:
- **Volume Groups**: Separate volume controls for different audio contexts
- **Active Player Tracking**: Monitors `AudioTrack` states to determine which context is "active"
- **Audio Focus**: Coordinates between multiple audio sources

Carlink must interact correctly with these systems to ensure proper volume control behavior.

---

## Volume Groups and CarAudioContext

AAOS organizes audio into **volume groups** based on `AudioAttributes.USAGE`:

| AudioAttributes USAGE | CarAudioContext | Volume Group | Priority |
|-----------------------|-----------------|--------------|----------|
| `USAGE_VOICE_COMMUNICATION` | CALL | Call Volume | Highest |
| `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE` | NAVIGATION | Nav Volume | High |
| `USAGE_ASSISTANT` | VOICE_COMMAND | Voice Volume | Medium |
| `USAGE_MEDIA` | MUSIC | Media Volume | Low |

When the user presses volume keys, AAOS determines which volume group to adjust based on:
1. **Active players** - AudioTracks in `PLAYSTATE_PLAYING`
2. **Priority order** - Defined in `CarVolume.AUDIO_CONTEXT_VOLUME_PRIORITY`

The highest-priority active context receives the volume adjustment.

---

## The "Stuck Volume" Problem

### Symptoms
- User plays music (Media volume works)
- Navigation prompt plays
- After nav prompt ends, volume keys still control Navigation volume
- User cannot adjust Media volume without going to settings

### Root Cause

When an `AudioTrack` is created and `play()` is called, AAOS sees it as an "active player":

```
GMCarVolumeDialogImpl: Found a new active media playback.
AudioPlaybackConfiguration piid:95 state:started
attr:AudioAttributes: usage=USAGE_ASSISTANCE_NAVIGATION_GUIDANCE
```

If the track remains in `PLAYSTATE_PLAYING` after the audio stream ends, AAOS continues to prioritize that context for volume control.

### Evidence from Logcat

Timeline from `logcat_recording_2025-11-26_21-49-57.txt`:

| Line | Event | Volume Group |
|------|-------|--------------|
| 158645 | Media track started | - |
| 160291 | Volume key pressed | **group 5** (Media) |
| 171643 | Nav track started | - |
| 177695 | Volume key pressed | **group 1** (Nav) |
| 178133-188557 | Multiple volume presses | **group 1** (stuck!) |
| 230646 | Nav track released | - |
| 264287 | Volume key pressed | **group 5** (Media) |

The nav track remained in `state:started` from line 171643 to 230646 (~60,000 lines), causing volume to be "stuck" on group 1 (Navigation).

---

## The Fix: Track Lifecycle Management

### Solution

Pause `AudioTrack` instances when their corresponding audio stream ends. This changes the track state from `PLAYSTATE_PLAYING` to `PLAYSTATE_PAUSED`, telling AAOS the context is no longer active.

### Implementation

#### 1. DualStreamAudioManager.kt - Stop Methods

```kotlin
/**
 * Pause navigation AudioTrack when nav audio stream ends.
 * Called when AudioNaviStop command is received from the adapter.
 */
fun stopNavTrack() {
    synchronized(lock) {
        navTrack?.let { track ->
            if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                track.pause()
                log("[AUDIO] Nav track paused - stream ended, AAOS will deprioritize NAVIGATION context")
            }
        }
        navStarted = false
    }
}

// Similar methods for stopVoiceTrack(), stopCallTrack(), stopMediaTrack()
```

#### 2. AudioHandler.kt - Platform Channel Handler

```kotlin
"stopAudioStream" -> {
    val audioType = call.argument<Int>("audioType") ?: 1
    when (audioType) {
        1 -> dualAudioManager?.stopMediaTrack()
        2 -> dualAudioManager?.stopNavTrack()
        3 -> dualAudioManager?.stopCallTrack()
        4 -> dualAudioManager?.stopVoiceTrack()
    }
    result.success(null)
}
```

#### 3. carlink.dart - Command Handling

```dart
case AudioCommand.AudioNaviStop:
    // Pause nav track so AAOS deprioritizes NAVIGATION context
    await CarlinkPlatform.instance.stopAudioStream(audioType: 2);
    break;

case AudioCommand.AudioSiriStop:
    await _stopMicrophoneCapture();
    await CarlinkPlatform.instance.stopAudioStream(audioType: 4);
    break;

case AudioCommand.AudioPhonecallStop:
    await _stopMicrophoneCapture();
    await CarlinkPlatform.instance.stopAudioStream(audioType: 3);
    break;
```

### Why pause() Instead of stop()?

| Method | Effect | Use Case |
|--------|--------|----------|
| `pause()` | State → PAUSED, buffer preserved | Stream may restart soon |
| `stop()` | State → STOPPED, buffer flushed | Stream definitely ended |
| `release()` | Track destroyed | App shutting down |

Using `pause()` allows quick resume when the same stream type restarts, avoiding audio glitches. The track is automatically resumed when new audio data arrives via `ensureNavTrack()` / `ensureVoiceTrack()` etc.

---

## AudioTrack Creation and AAOS Mapping

Carlink creates AudioTracks with specific `USAGE` constants that map to AAOS CarAudioContext:

```kotlin
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
}
```

---

## Audio Routing: Adapter audioType vs State Machine

### Previous Approach (Buggy)

The app used a state machine (`_currentAudioStreamContext`) to track the "current" audio context, overriding the adapter's `audioType` field:

```dart
// Old code - caused interleaving issues
audioType: _currentAudioStreamContext,  // State-tracked
```

This caused problems when streams were interleaved (e.g., nav prompt during Siri response). Packets from one stream would be routed to the wrong AudioTrack.

### Current Approach (Fixed)

The adapter correctly tags each packet with `audioType`, so we trust it directly:

```dart
// Current code - correct routing
audioType: message.audioType,  // From adapter packet
```

Log evidence showing adapter sends correct audioType:
```
AudioType: 1 (Media) - 3,568 packets
AudioType: 2 (Navigation) - 217 packets
```

See `audio_pipeline.md` for details on the white noise bug this fixed.

---

## Debugging AAOS Audio Issues

### Useful Logcat Filters

```bash
# CarAudioService and volume events
adb logcat -s CarAudioService:V CarVolume:V GMCarVolumeDialogImpl:V

# AudioPlaybackConfiguration changes (track state)
adb logcat | grep -E "AudioPlaybackConfiguration|volume group"

# Focus changes
adb logcat -s CarAudioFocus:V AudioFocus:V
```

### Key Log Patterns

**Track Started:**
```
Found a new active media playback. AudioPlaybackConfiguration piid:95
state:started attr:AudioAttributes: usage=USAGE_ASSISTANCE_NAVIGATION_GUIDANCE
```

**Track Stopped:**
```
Audio playback is changed, config=AudioPlaybackConfiguration piid:95
state:stopped attr:AudioAttributes: usage=USAGE_ASSISTANCE_NAVIGATION_GUIDANCE
```

**Volume Group Selection:**
```
volume group = 1, maxVolumeCap = 63, minVolumeCap = 0
```
(group 1 = Navigation, group 5 = Media on GM infotainment)

---

## Future Considerations

### AudioFocus Management

While not strictly required for AAOS (per Google docs: "the vehicle shouldn't depend on the focus system"), proper AudioFocus management could improve:
- Coordination with other apps
- Proper ducking behavior
- Android 15+ compliance (focus required for background playback)

### Potential AudioFocus Implementation

```kotlin
// Request focus before starting playback
val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
    .setAudioAttributes(audioAttributes)
    .setOnAudioFocusChangeListener { /* handle focus loss */ }
    .build()
audioManager.requestAudioFocus(focusRequest)

// Abandon focus when stream ends
audioManager.abandonAudioFocusRequest(focusRequest)
```

This is not currently implemented but may be needed for:
- Android 15+ (SDK 35) where focus is required
- Better interaction with other AAOS audio sources

---

## References

- [AAOS Volume Management](https://source.android.com/docs/automotive/audio/volume-management)
- [AAOS Audio Focus](https://source.android.com/docs/automotive/audio/audio-focus)
- [Android Audio Focus Guide](https://developer.android.com/media/optimize/audio-focus)
- [CarAudioService Source](https://android.googlesource.com/platform/packages/services/Car/+/master/service/src/com/android/car/audio/CarAudioService.java)

---

## Changelog

### November 2025
- **Fix**: Added track lifecycle management to resolve "stuck volume" issue
  - Added `stopNavTrack()`, `stopVoiceTrack()`, `stopCallTrack()`, `stopMediaTrack()` in `DualStreamAudioManager.kt`
  - Added `stopAudioStream` platform channel method
  - Call `stopAudioStream()` on all `Audio*Stop` commands in `carlink.dart`
  - Logcat evidence confirmed fix resolves AAOS active player tracking issue
