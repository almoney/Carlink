# Carlink Audio Pipeline Documentation

## Overview

The Carlink audio pipeline handles **bidirectional** real-time PCM audio for CarPlay/Android Auto projection via the CPC200-CCPA USB adapter:

- **RX (Playback):** Audio from adapter → app → device speakers (Media, Navigation, Phone, Siri)
- **TX (Microphone):** Audio from device mic → app → adapter → CarPlay/Android Auto (Siri, phone calls)

The architecture supports multiple simultaneous audio streams with jitter compensation, volume ducking, and zero-packet filtering.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CPC200-CCPA USB Adapter                           │
│                    (Wireless CarPlay/Android Auto Dongle)                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ USB Bulk Transfer (Type=0x07)
                                      │ Audio packets with 12-byte header
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Dart Layer (Flutter)                               │
│  ┌─────────────────────┐    ┌─────────────────────────────────────────────┐ │
│  │ readable.dart       │───▶│ carlink.dart (_processAudioData)            │ │
│  │ AudioData Parser    │    │  ├── Zero-packet filtering                  │ │
│  │ (parses header)     │    │  ├── Format change handling                 │ │
│  └─────────────────────┘    │  └── Platform channel dispatch              │ │
│                             └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ Flutter MethodChannel
                                      │ (writeAudio, initializeAudio, etc.)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Android Native Layer (Kotlin)                        │
│  ┌────────────────────┐    ┌─────────────────────────────────────────────┐  │
│  │   AudioHandler     │───▶│           DualStreamAudioManager            │  │
│  │ (MethodCall Router)│    │  ├── Zero-packet filtering (secondary)      │  │
│  └────────────────────┘    │  │                                          │  │
│                             │  ┌─────────────────┐ ┌─────────────────┐   │  │
│                             │  │ Media Ring Buf  │ │  Nav Ring Buf   │   │  │
│                             │  │   (250ms)       │ │    (120ms)      │   │  │
│                             │  └────────┬────────┘ └────────┬────────┘   │  │
│                             │           │                   │            │  │
│                             │  ┌────────▼────────┐ ┌────────▼────────┐   │  │
│                             │  │ Media AudioTrack│ │  Nav AudioTrack │   │  │
│                             │  │ (USAGE_MEDIA)   │ │ (USAGE_NAV)     │   │  │
│                             │  └─────────────────┘ └─────────────────┘   │  │
│                             │           │                   │            │  │
│                             │           └─────────┬─────────┘            │  │
│                             │                     │                      │  │
│                             │        AudioPlaybackThread                 │  │
│                             │    (THREAD_PRIORITY_URGENT_AUDIO)         │  │
│                             └─────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ Android Audio HAL
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Hardware Audio Output                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Audio Packet Format (CPC200-CCPA Protocol)

### Packet Header Structure

Audio packets arrive via USB with message type `0x07`. The audio data payload has the following structure:

| Offset | Size | Type    | Field       | Description                          |
|--------|------|---------|-------------|--------------------------------------|
| 0      | 4    | UInt32  | decodeType  | Audio format identifier (1-7)        |
| 4      | 4    | Float32 | volume      | Volume level (0.0-1.0)               |
| 8      | 4    | UInt32  | audioType   | Stream type (1=Media, 2=Nav, etc.)   |
| 12     | N    | Bytes   | data        | PCM audio samples (16-bit)           |

### Packet Variants

| Payload Size | Description                        | Data Content                |
|--------------|------------------------------------|-----------------------------|
| 13 bytes     | Audio command (start/stop)         | 1-byte command ID           |
| 16 bytes     | Volume ducking signal              | 4-byte float duration       |
| >12 bytes    | Audio samples                      | 16-bit PCM samples          |

### Audio Format Types (decodeType)

| Type | Sample Rate | Channels | Use Case                    |
|------|-------------|----------|-----------------------------|
| 1    | 44100 Hz    | 2 (Stereo) | Music playback            |
| 2    | 44100 Hz    | 2 (Stereo) | Music playback (alt)      |
| 3    | 8000 Hz     | 1 (Mono)   | Phone calls               |
| 4    | 48000 Hz    | 2 (Stereo) | High-quality audio (default) |
| 5    | 16000 Hz    | 1 (Mono)   | Siri/Voice assistant      |
| 6    | 24000 Hz    | 1 (Mono)   | Enhanced voice            |
| 7    | 16000 Hz    | 2 (Stereo) | Stereo voice              |

### Audio Stream Types (audioType)

| Type | Name       | Description                     | Android AudioAttributes         |
|------|------------|---------------------------------|---------------------------------|
| 1    | Media      | Music, podcasts, audiobooks     | USAGE_MEDIA, CONTENT_TYPE_MUSIC |
| 2    | Navigation | Turn-by-turn directions         | USAGE_ASSISTANCE_NAVIGATION_GUIDANCE |
| 3    | Phone Call | Voice calls (exclusive)         | Routed to Media track           |
| 4    | Siri       | Voice assistant (exclusive)     | Routed to Media track           |

### Audio Commands (command byte when payload=13)

| ID | Command             | Description                    |
|----|---------------------|--------------------------------|
| 1  | AudioOutputStart    | General audio output starting  |
| 2  | AudioOutputStop     | General audio output stopping  |
| 3  | AudioInputConfig    | Microphone configuration       |
| 4  | AudioPhonecallStart | Phone call audio starting      |
| 5  | AudioPhonecallStop  | Phone call audio stopping      |
| 6  | AudioNaviStart      | Navigation audio starting      |
| 7  | AudioNaviStop       | Navigation audio stopping      |
| 8  | AudioSiriStart      | Voice assistant starting       |
| 9  | AudioSiriStop       | Voice assistant stopping       |
| 10 | AudioMediaStart     | Media playback starting        |
| 11 | AudioMediaStop      | Media playback stopping        |
| 12 | AudioAlertStart     | Alert/notification starting    |
| 13 | AudioAlertStop      | Alert/notification stopping    |

---

## Microphone TX Protocol (App → Adapter)

### Overview

Microphone audio is sent from the app to the CPC200-CCPA adapter using the same message type (`0x07 AudioData`) as audio playback, but in the reverse direction. The adapter forwards this audio to CarPlay/Android Auto for Siri, Google Assistant, and phone calls.

### Microphone Trigger Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CPC200-CCPA USB Adapter                           │
│               Sends AudioSiriStart (8) or AudioPhonecallStart (4)           │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Dart Layer (Flutter)                               │
│  carlink.dart receives AudioData command → starts microphone capture         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Android Native Layer (Kotlin)                        │
│  MicrophoneCaptureManager.kt                                                 │
│  ├── AudioRecord (16kHz, mono, 16-bit PCM)                                   │
│  ├── AudioRingBuffer (120ms jitter compensation)                            │
│  └── High-priority capture thread (THREAD_PRIORITY_URGENT_AUDIO)            │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ Platform Channel (readMicrophoneData)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Dart Layer (Flutter)                               │
│  carlink.dart: 20ms send loop reads PCM → wraps in SendAudio → USB write     │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ USB Bulk Transfer (Type=0x07)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CPC200-CCPA USB Adapter                           │
│                    Routes audio to CarPlay/Android Auto                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### SendAudio Message Structure (App → Adapter)

**IMPORTANT:** Parameters are based on pi-carplay reference implementation (known-working).

| Offset | Size | Type    | Field       | Value | Description                          |
|--------|------|---------|-------------|-------|--------------------------------------|
| 0      | 4    | UInt32  | decodeType  | 5     | 16kHz mono (always)                  |
| 4      | 4    | Float32 | volume      | 0.0   | Always 0.0 per pi-carplay            |
| 8      | 4    | UInt32  | audioType   | 3     | Siri/voice input (always)            |
| 12     | N    | Bytes   | data        | -     | PCM audio samples (16-bit S16_LE)    |

**Critical Notes:**
- Both Siri and phone calls use **identical parameters** (decodeType=5, audioType=3, volume=0.0)
- The distinction between Siri and phone calls is handled by the adapter based on which command triggered the capture
- These values were determined by analyzing pi-carplay, NOT from Autokit documentation (which is outdated)

### Microphone Audio Format

| Parameter | Value | Notes |
|-----------|-------|-------|
| Sample Rate | 16000 Hz | Matches decodeType=5 |
| Channels | 1 (mono) | Voice input is always mono |
| Bit Depth | 16-bit | Signed little-endian (S16_LE) |
| Send Interval | 20ms | ~50 packets/second |
| Packet Size | 640 bytes | 20ms of 16kHz mono audio |

### Microphone Control Commands

| Trigger Command | Action |
|-----------------|--------|
| AudioSiriStart (8) | Start microphone capture with decodeType=5, audioType=3 |
| AudioPhonecallStart (4) | Start microphone capture with decodeType=5, audioType=3 |
| AudioSiriStop (9) | Stop microphone capture |
| AudioPhonecallStop (5) | Stop microphone capture |

### Implementation Details

**`lib/driver/sendable.dart` - SendAudio class:**

```dart
class SendAudio extends SendableMessageWithPayload {
  final Uint8List data;
  final int decodeType;
  final int audioType;
  final double volume;

  SendAudio(
    this.data, {
    this.decodeType = 5,   // 16kHz mono (matches pi-carplay)
    this.audioType = 3,    // Siri/voice input (matches pi-carplay)
    this.volume = 0.0,     // Always 0.0 (matches pi-carplay)
  }) : super(MessageType.AudioData);

  @override
  ByteData getPayload() {
    final audioData = ByteData(12)
      ..setUint32(0, decodeType, Endian.little)
      ..setFloat32(4, volume, Endian.little)
      ..setUint32(8, audioType, Endian.little);
    return Uint8List.fromList([
      ...audioData.buffer.asUint8List(),
      ...data,
    ]).buffer.asByteData();
  }
}
```

**`lib/carlink.dart` - Microphone send loop:**

```dart
Future<void> _sendMicrophoneData() async {
  if (!_isMicrophoneCapturing || _adaptrDriver == null) return;

  // Read 20ms of audio (640 bytes at 16kHz mono)
  final micData = await CarlinkPlatform.instance.readMicrophoneData(maxBytes: 640);

  if (micData != null && micData.isNotEmpty) {
    await _adaptrDriver!.send(
      SendAudio(
        micData,
        decodeType: 5,   // 16kHz mono
        audioType: 3,    // Siri/voice input
      ),
    );
  }
}
```

### Reference: pi-carplay Implementation

The microphone protocol parameters were determined by analyzing the pi-carplay project, a known-working Node.js/TypeScript implementation for macOS and Linux:

**Source:** `pi-carplay/src/main/carplay/messages/sendable.ts`

```typescript
export class SendAudio extends SendableMessageWithPayload {
  getPayload(): Buffer {
    const audioData = Buffer.alloc(12)
    audioData.writeUInt32LE(5, 0)      // decodeType = 5
    audioData.writeFloatLE(0.0, 4)     // volume = 0.0
    audioData.writeUInt32LE(3, 8)      // audioType = 3
    return Buffer.concat([audioData, Buffer.from(this.data.buffer)])
  }
}
```

**Source:** `pi-carplay/src/main/audio/Microphone.ts`

```typescript
private readonly rate: number = 16000
private readonly channels: number = 1
private readonly format: string = 'S16_LE'
```

---

## Pipeline Components

### 1. Dart Layer

#### `lib/driver/readable.dart` - AudioData Message Parser

Parses incoming USB packets into structured `AudioData` messages:

```dart
class AudioData extends Message {
  late final AudioCommand? command;    // Start/stop commands
  late final int decodeType;           // Format (1-7)
  late final double volume;            // Volume level
  late final double? volumeDuration;   // Ducking duration (Len=16 packets)
  late final int audioType;            // Stream type (1-4)
  late final Uint16List? data;         // PCM samples
}
```

**Parsing Logic:**
- Reads 12-byte header (decodeType, volume, audioType)
- Remaining bytes determine packet type:
  - 1 byte → Audio command
  - 4 bytes → Volume ducking duration
  - >4 bytes → PCM audio samples

#### `lib/carlink.dart` - Audio Processing

Main audio processing in `_processAudioData()` (line 547):

```dart
Future<void> _processAudioData(AudioData message) async {
  // Handle volume ducking packets (Len=16)
  if (message.volumeDuration != null && _audioInitialized) {
    await CarlinkPlatform.instance.setAudioDucking(message.volume);
    return;
  }

  // Skip commands and empty data
  if (!_audioEnabled || message.command != null) return;
  final audioData = message.data;
  if (audioData == null || audioData.isEmpty) return;

  // Initialize audio if format changed
  final formatChanged = _currentAudioDecodeType != message.decodeType;
  if (!_audioInitialized || formatChanged) {
    _audioInitialized = await CarlinkPlatform.instance
        .initializeAudio(decodeType: message.decodeType);
    _currentAudioDecodeType = message.decodeType;
  }

  // Convert Uint16List to Uint8List - use view to exclude 12-byte header
  final pcmBytes = Uint8List.view(
    audioData.buffer,
    audioData.offsetInBytes,   // Start at actual audio data
    audioData.lengthInBytes,   // Only include audio data length
  );

  // Filter zero-filled packets (adapter firmware issue)
  if (_isZeroFilledAudio(pcmBytes)) {
    _zeroPacketCount++;
    return;  // Skip invalid packets
  }

  // Write to native AudioTrack via platform channel
  await CarlinkPlatform.instance.writeAudio(
    pcmBytes,
    decodeType: message.decodeType,
    audioType: message.audioType,
    volume: 1.0,  // Hardcoded - adapter sends 0.0
  );
}
```

##### Zero-Packet Detection (`_isZeroFilledAudio()`)

Filters out invalid zero-filled packets from the adapter:

```dart
bool _isZeroFilledAudio(Uint8List pcmData) {
  if (pcmData.length < 16) return false;

  // Sample 5 positions across the buffer for efficiency
  final positions = [
    0,
    (pcmData.length * 0.25).toInt() & ~1,  // 25%, aligned
    (pcmData.length * 0.5).toInt() & ~1,   // 50%, aligned
    (pcmData.length * 0.75).toInt() & ~1,  // 75%, aligned
    (pcmData.length - 8) & ~1,             // Near end, aligned
  ];

  for (final pos in positions) {
    if (pos + 4 > pcmData.length) continue;
    // If any sampled bytes are non-zero, it's real audio
    if (pcmData[pos] != 0 || pcmData[pos + 1] != 0 ||
        pcmData[pos + 2] != 0 || pcmData[pos + 3] != 0) {
      return false;
    }
  }
  return true;  // All zeros = invalid packet
}
```

#### `lib/carlink_method_channel.dart` - Platform Channel

Communicates with Android native code via Flutter MethodChannel:

| Method | Parameters | Description |
|--------|------------|-------------|
| `initializeAudio` | decodeType | Initialize audio system |
| `writeAudio` | data, decodeType, audioType, volume | Write PCM samples |
| `setAudioDucking` | duckLevel | Set media ducking level |
| `setAudioVolume` | volume | Set playback volume |
| `stopAudio` | - | Stop playback |
| `releaseAudio` | - | Release resources |
| `getAudioStats` | - | Get playback statistics |

---

### 2. Android Native Layer

#### `AudioHandler.kt` - Method Call Router

Routes Flutter platform calls to `DualStreamAudioManager`:

```kotlin
class AudioHandler(
    private val dualAudioManager: DualStreamAudioManager?,
    private val logCallback: LogCallback,
) {
    fun handle(call: MethodCall, result: Result): Boolean {
        when (call.method) {
            "writeAudio" -> handleWriteAudio(call, result)
            "setAudioDucking" -> handleSetDucking(call, result)
            // ... other methods
        }
    }
}
```

#### `DualStreamAudioManager.kt` - Dual-Stream Audio Engine

Core audio management with separate streams for Media and Navigation:

```kotlin
class DualStreamAudioManager(private val logCallback: LogCallback) {
    // Separate AudioTracks per stream
    private var mediaTrack: AudioTrack? = null
    private var navTrack: AudioTrack? = null

    // Ring buffers for jitter compensation
    private var mediaBuffer: AudioRingBuffer? = null  // 250ms
    private var navBuffer: AudioRingBuffer? = null    // 120ms

    // Dedicated playback thread
    private var playbackThread: AudioPlaybackThread? = null
}
```

**Key Features:**
- **Non-blocking writes**: USB thread writes directly to ring buffers
- **Separate AudioTracks**: Media and Navigation have independent playback
- **Volume ducking**: Automatic media volume reduction during navigation
- **Format switching**: Per-stream format changes without cross-contamination
- **Zero-packet filtering**: Secondary defense against invalid adapter data

#### `AudioRingBuffer.kt` - Jitter Compensation Buffer

Lock-free ring buffer for absorbing USB packet timing variations:

```kotlin
class AudioRingBuffer(
    private val capacityMs: Int,    // Buffer size in milliseconds
    private val sampleRate: Int,    // Audio sample rate
    private val channels: Int,      // 1=mono, 2=stereo
) {
    fun write(data: ByteArray): Int  // Non-blocking, returns bytes written
    fun read(out: ByteArray): Int    // Non-blocking, returns bytes read
    fun availableForRead(): Int      // Bytes ready for playback
    fun fillLevelMs(): Int           // Current buffer level in ms
}
```

**Buffer Sizing:**
- Media: 250ms (absorbs adapter gaps up to 1200ms observed)
- Navigation: 120ms (lower latency for prompts)

#### `AudioPlaybackThread` - High-Priority Playback

Dedicated thread running at `THREAD_PRIORITY_URGENT_AUDIO`:

```kotlin
private inner class AudioPlaybackThread : Thread("AudioPlayback") {
    override fun run() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)

        while (isRunning.get() && !isInterrupted) {
            // Read from media buffer → write to media AudioTrack
            // Read from nav buffer → write to nav AudioTrack
            // Sleep briefly if no data
        }
    }
}
```

---

## Volume Ducking

When navigation audio plays, the adapter sends "ducking packets" (Len=16) to reduce media volume:

### Ducking Packet Format

| Bytes 0-3 | Bytes 4-7 | Bytes 8-11 | Bytes 12-15 |
|-----------|-----------|------------|-------------|
| decodeType | volume (float) | audioType | duration (float) |

**Example Ducking Sequence:**
```
15:24:08.826 > Len=16 [02 00 00 00 ce cc 4c 3e ...] → volume=0.2 (duck to 20%)
15:24:12.089 > Len=16 [02 00 00 00 00 00 80 3f ...] → volume=1.0 (restore)
```

### Ducking Implementation

```kotlin
fun setDucking(targetVolume: Float) {
    isDucked = targetVolume < 1.0f
    duckLevel = targetVolume.coerceIn(0.0f, 1.0f)

    val effectiveVolume = if (isDucked) mediaVolume * duckLevel else mediaVolume
    mediaTrack?.setVolume(effectiveVolume)
}
```

---

## Thread Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Thread Diagram                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  USB I/O Thread                                                 │
│  ├── BulkTransferHandler.readLoop()                             │
│  ├── Receives USB packets                                       │
│  └── Calls DualStreamAudioManager.writeAudio() [non-blocking]   │
│       ├── Routes to mediaBuffer or navBuffer                    │
│       └── Returns immediately                                   │
│                                                                 │
│  AudioPlaybackThread (URGENT_AUDIO priority)                    │
│  ├── Polls both ring buffers                                    │
│  ├── Writes to MediaTrack / NavTrack                            │
│  └── Sleeps 5ms if no data available                            │
│                                                                 │
│  Main Thread                                                    │
│  ├── Flutter MethodChannel calls                                │
│  ├── Volume/ducking changes                                     │
│  └── Initialize/release operations                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## AudioTrack Configuration

### Media Track
```kotlin
AudioAttributes.Builder()
    .setUsage(AudioAttributes.USAGE_MEDIA)
    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
    .build()

AudioTrack.Builder()
    .setBufferSizeInBytes(minBufferSize * 5)  // 5x for USB jitter
    .setTransferMode(AudioTrack.MODE_STREAM)
    .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
    .build()
```

### Navigation Track
```kotlin
AudioAttributes.Builder()
    .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
    .build()
```

---

## Statistics & Monitoring

### Available Statistics (via `getAudioStats()`)

| Statistic | Description |
|-----------|-------------|
| `isRunning` | Playback active |
| `durationSeconds` | Total playback time |
| `mediaVolume` | Current media volume |
| `navVolume` | Current navigation volume |
| `isDucked` | Media currently ducked |
| `duckLevel` | Current ducking level |
| `mediaFormat` | Current media format (e.g., "48000Hz 2ch") |
| `navFormat` | Current navigation format |
| `mediaBuffer.fillLevelMs` | Media buffer fill in ms |
| `navBuffer.fillLevelMs` | Navigation buffer fill in ms |
| `mediaUnderruns` | Media AudioTrack underruns |
| `navUnderruns` | Navigation AudioTrack underruns |
| `zeroPacketsFiltered` | Zero-filled packets discarded (Android layer) |

### Internal Counters (Dart Layer)

| Counter | Description |
|---------|-------------|
| `_audioPacketCount` | Total valid audio packets processed |
| `_zeroPacketCount` | Zero-filled packets filtered (Dart layer) |

---

## Error Handling

### Recoverable Errors

| Error | Recovery Action |
|-------|-----------------|
| `AudioTrack.ERROR_DEAD_OBJECT` | Reinitialize AudioTrack |
| Format change during playback | Release and recreate AudioTrack |
| Ring buffer overflow | Drop oldest data (logged) |
| Ring buffer underflow | Silence gap (logged) |
| Zero-filled audio packet | Skip packet (logged periodically) |

### Emergency Cleanup

Triggered after 3 consecutive MediaCodec resets within 30 seconds:

```kotlin
fun performEmergencyCleanup() {
    clearBufferPool()
    dualAudioManager?.release()
    videoManager?.performEmergencyCleanup()
    usbDeviceManager?.closeDevice()
}
```

---

## Performance Characteristics

### Observed Packet Timing

From log analysis:

| Metric | Value |
|--------|-------|
| Typical packet interval | 60-70ms |
| Max media gap | 11.5 seconds (during phone/Siri) |
| Max navigation gap | 200ms |
| Packet size (typical) | 11,520 bytes (5,760 samples) |

### Buffer Sizing Rationale

| Buffer | Size | Rationale |
|--------|------|-----------|
| Media ring buffer | 250ms | Absorbs 1200ms gaps from adapter |
| Navigation ring buffer | 120ms | Lower latency for prompts |
| AudioTrack buffer | 5x min | USB streaming jitter tolerance |

---

## File Reference

### Audio Playback (RX)

| File | Layer | Purpose |
|------|-------|---------|
| `lib/driver/readable.dart:221` | Dart | AudioData message parser |
| `lib/carlink.dart:510` | Dart | `_isZeroFilledAudio()` - zero-packet detection |
| `lib/carlink.dart:547` | Dart | `_processAudioData()` - main audio processing |
| `lib/carlink_method_channel.dart:516` | Dart | Platform channel audio methods |
| `lib/carlink_platform_interface.dart:189` | Dart | Audio API interface |
| `android/.../AudioHandler.kt` | Android | Method call routing |
| `android/.../DualStreamAudioManager.kt:133` | Android | `isZeroFilledAudio()` - secondary filtering |
| `android/.../DualStreamAudioManager.kt:169` | Android | `writeAudio()` - buffer routing |
| `android/.../AudioRingBuffer.kt` | Android | Jitter compensation |
| `android/.../CarlinkPlugin.kt` | Android | Plugin lifecycle |

### Microphone TX

| File | Layer | Purpose |
|------|-------|---------|
| `lib/driver/sendable.dart:177` | Dart | SendAudio message class (decodeType=5, audioType=3, volume=0.0) |
| `lib/carlink.dart:787` | Dart | AudioSiriStart/AudioPhonecallStart handlers |
| `lib/carlink.dart:389` | Dart | `_startMicrophoneCapture()` - microphone control |
| `lib/carlink.dart:450` | Dart | `_sendMicrophoneData()` - 20ms send loop |
| `lib/carlink_method_channel.dart` | Dart | Platform channel mic methods |
| `android/.../MicrophoneCaptureManager.kt` | Android | AudioRecord capture, ring buffer |
| `android/.../MicrophoneHandler.kt` | Android | Method call routing for mic |
| `android/.../AudioRingBuffer.kt` | Android | 120ms jitter compensation buffer |

---

## Known Issues & Fixes

### Audio White Noise/Static Bug (Fixed: 2025-11-26)

#### Symptoms
- Random white noise/static occurring during audio playback (Apple Music, podcasts, navigation)
- No observable pattern or trigger - occurred intermittently during normal playback
- Activating Siri would temporarily "fix" the issue until it recurred
- Issue present even on fresh app start with only media audio (no format changes)

#### Root Cause

**Buffer view aliasing bug in Dart layer (`lib/carlink.dart`)**

When parsing audio packets, the `AudioData` class creates a `Uint16List` view starting at byte offset 12 (after the header):

```dart
// In AudioData constructor (readable.dart:246)
audioData = data.buffer.asUint16List(12);  // View starting at byte 12
```

However, when converting to bytes for the platform channel, the code incorrectly accessed the **entire underlying buffer**:

```dart
// BUGGY CODE (carlink.dart:555)
final pcmBytes = audioData.buffer.asUint8List();  // Gets ENTIRE buffer from offset 0!
```

The issue: `audioData.buffer` returns the **original ByteBuffer**, not a view. Calling `.asUint8List()` without arguments returns **all bytes from offset 0**, which includes the 12-byte packet header.

#### Impact

Each audio packet (11,532 bytes total) was being sent as:
- **12 bytes of header data** (decodeType, volume, audioType) - interpreted as PCM audio
- **11,520 bytes of actual audio**

The header bytes when interpreted as 16-bit PCM samples:
```
02 00 00 00 00 00 00 00 01 00 00 00
│         │         │
└─ decodeType=2     └─ audioType=1
          └─ volume=0.0
```

These produce very low sample values (0, 1, 2) which manifest as **clicks, pops, and static noise**.

At ~15 packets/second, this injected **180 bytes of garbage per second** into the audio stream.

#### Why Siri Temporarily Fixed It

Siri activation triggers:
1. Format change (44100Hz stereo → 16000Hz mono)
2. AudioTrack destruction and recreation
3. New ring buffer allocation

This effectively "reset" the audio pipeline, clearing any accumulated corruption. The issue would return as playback continued.

#### Diagnostic Evidence

Debug logging confirmed the bug:

**Dart side:**
```
AUDIO_DEBUG: pkt#1 fullBuf=11532 offset=12 len=11520 first16=[02 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00]
```

**Kotlin side received:**
```
[AUDIO_DEBUG] write#1 size=11532 first16=[02 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00]
```

The first 12 bytes (`02 00 00 00 00 00 00 00 01 00 00 00`) are clearly the packet header, not audio samples.

#### Fix Applied

```dart
// FIXED CODE (carlink.dart:555-562)
final pcmBytes = Uint8List.view(
  audioData.buffer,
  audioData.offsetInBytes,   // Start at actual audio data offset
  audioData.lengthInBytes,   // Only include audio data length
);
```

This correctly extracts only the PCM audio portion:
- **Before:** 11,532 bytes sent (header + audio)
- **After:** 11,520 bytes sent (audio only)

#### Verification

After the fix, debug logs show:
```
AUDIO_DEBUG: pkt#1 size=11520 first16=[xx xx xx xx ...]  ← Actual PCM samples
```

The first bytes are now varying PCM sample values, not the static header pattern.

---

### Zero-Filled Audio Packet Issue (Fixed: 2025-11-26)

#### Symptoms
- Intermittent noise/static during audio playback, even after the header bug was fixed
- Noise would occur at app startup and randomly during playback sessions
- Moving USB mouse or other USB activity could sometimes clear the noise
- Activating Siri would temporarily "fix" the issue

#### Root Cause

**Adapter firmware sends zero-filled audio packets**

The USB adapter intermittently sends audio packets where the PCM payload is entirely `0x0000` for every sample:

```
[AUDIO] RAW AUDIO RX: Type=0x07 Len=11532 Data=AudioData [02 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00...]
                                                          │  header (valid)  │  PCM data (all zeros - invalid)
```

This is **not a code bug** - the adapter itself sends these packets due to:
- Uninitialized audio buffers at startup
- Firmware state issues during session
- Unknown timing/synchronization problems

#### Why Zero Packets Are Invalid

Real audio, even during silent moments in a song or podcast pause, contains:
- **Dithering noise** - small random values added during encoding
- **Recording noise floor** - ambient noise from microphone/source
- **Codec artifacts** - small variations from compression

Legitimate "silence" looks like: `[fe ff 01 00 ff ff 02 00 01 00 fe ff ...]` (small variations around zero)

Invalid packets look like: `[00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00...]` (exactly zero)

The probability of real audio having every sample at exactly `0x0000` across 11,520 bytes is essentially zero.

#### Diagnostic Evidence

Log analysis showed ~444 zero-filled packets in one session:

**At startup (08:31:51):**
```
RAW AUDIO RX: ... [02 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00 00 00 00 00...]
```
First 8 audio packets after connection were all zeros.

**Mid-session burst (08:33:25-08:33:30):**
```
RAW AUDIO RX: ... [02 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00 00 00 00 00...]
```
~90+ consecutive zero packets over 5+ seconds, causing audible noise.

#### Fix Applied

**Two-layer filtering implemented:**

**1. Dart Layer (Primary) - `lib/carlink.dart:510`:**
```dart
bool _isZeroFilledAudio(Uint8List pcmData) {
  // Sample 5 positions across buffer for O(1) check
  final positions = [0, 25%, 50%, 75%, end];
  for (final pos in positions) {
    if (any bytes at pos are non-zero) return false;
  }
  return true;  // All zeros = invalid
}
```

**2. Android Layer (Secondary) - `DualStreamAudioManager.kt:133`:**
```kotlin
private fun isZeroFilledAudio(data: ByteArray): Boolean {
  // Same sampling logic as Dart layer
  // Filters any packets that slip through
}
```

#### Detection Logic

- Samples 5 positions across the packet (start, 25%, 50%, 75%, near end)
- Checks 4 consecutive bytes at each position
- If **all** sampled positions are exactly zero → invalid packet → skip
- If **any** sampled position has non-zero bytes → valid audio → play

This is O(1) regardless of packet size (only checks 20 bytes per packet).

#### Verification

With filtering enabled, logs show:
```
[AUDIO] AUDIO_FILTER: Skipped 1 zero-filled packets (adapter sending empty audio)
[AUDIO] AUDIO_FILTER: Skipped 50 zero-filled packets (adapter sending empty audio)
```

Zero packets are now silently discarded instead of being played as noise.

---

### Microphone Input Not Working (Fixed: 2025-11-26)

#### Symptoms
- Siri would activate but time out - "Siri does not hear anything"
- Phone calls connected but caller could not hear anything
- Microphone capture was working (real PCM data captured from Android AudioRecord)
- USB writes were succeeding (668-byte packets sent successfully)

#### Root Cause

**Incorrect microphone TX protocol parameters**

The microphone audio was being sent with wrong `audioType` and `volume` values that didn't match what the CPC200-CCPA adapter firmware expected.

**Investigation Process:**

1. Initial firmware log analysis suggested `audioType=1` for voice commands
2. However, testing showed microphone still not working with `audioType=1`
3. Analyzed pi-carplay (a known-working macOS/Linux implementation) as reference
4. Discovered pi-carplay uses different parameters that work correctly

#### pi-carplay Reference Implementation

From `/pi-carplay/src/main/carplay/messages/sendable.ts`:

```typescript
export class SendAudio extends SendableMessageWithPayload {
  getPayload(): Buffer {
    const audioData = Buffer.alloc(12)
    audioData.writeUInt32LE(5, 0)      // decodeType = 5 (16kHz mono)
    audioData.writeFloatLE(0.0, 4)     // volume = 0.0 (NOT 1.0!)
    audioData.writeUInt32LE(3, 8)      // audioType = 3 (NOT 1!)
    return Buffer.concat([audioData, Buffer.from(this.data.buffer)])
  }
}
```

From `/pi-carplay/src/main/audio/Microphone.ts`:

```typescript
private readonly rate: number = 16000     // 16kHz
private readonly channels: number = 1     // mono
private readonly format: string = 'S16_LE'  // signed 16-bit little-endian
```

**Key Finding:** pi-carplay uses **identical parameters** for both Siri AND phone calls:
- `decodeType = 5` (16kHz mono)
- `audioType = 3` (Siri/voice input)
- `volume = 0.0`

#### Parameter Comparison

| Parameter | Our Code (Before) | pi-carplay | Our Code (After) |
|-----------|-------------------|------------|------------------|
| decodeType (Siri) | 5 | 5 | 5 ✓ |
| decodeType (Phone) | **3** | 5 | 5 ✓ |
| audioType (Siri) | **1** | 3 | 3 ✓ |
| audioType (Phone) | **2** | 3 | 3 ✓ |
| volume | **1.0** | 0.0 | 0.0 ✓ |

#### Fix Applied

**`lib/driver/sendable.dart` - SendAudio class:**

```dart
// BEFORE (broken)
SendAudio(
  this.data, {
  this.decodeType = 5,
  this.audioType = 1,  // Wrong!
  this.volume = 1.0,   // Wrong!
})

// AFTER (matches pi-carplay)
SendAudio(
  this.data, {
  this.decodeType = 5,
  this.audioType = 3,  // Siri/voice input (matches pi-carplay)
  this.volume = 0.0,   // Always 0.0 (matches pi-carplay)
})
```

**`lib/carlink.dart` - Microphone trigger handlers:**

```dart
// BEFORE (broken)
case AudioCommand.AudioSiriStart:
  await _startMicrophoneCapture(decodeType: 5, audioType: 1);
case AudioCommand.AudioPhonecallStart:
  await _startMicrophoneCapture(decodeType: 3, audioType: 2);  // Wrong format!

// AFTER (matches pi-carplay)
case AudioCommand.AudioSiriStart:
  await _startMicrophoneCapture(decodeType: 5, audioType: 3);
case AudioCommand.AudioPhonecallStart:
  await _startMicrophoneCapture(decodeType: 5, audioType: 3);  // Same as Siri!
```

#### Verification

After matching pi-carplay's parameters:
- Siri voice recognition works correctly
- Phone calls transmit voice in both directions
- All microphone input scenarios functional

#### Lesson Learned

The Autokit documentation and firmware log analysis suggested different `audioType` values than what actually works. **pi-carplay served as a reliable reference implementation** since it's a known-working project with the same CPC200-CCPA adapter.

When protocol documentation is unclear or outdated, reference implementations are invaluable.
