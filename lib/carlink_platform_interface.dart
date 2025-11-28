import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'carlink_method_channel.dart';
import 'usb.dart';

abstract class CarlinkPlatform extends PlatformInterface {
  /// Constructs a CarlinkPlatform.
  CarlinkPlatform() : super(token: _token);

  static final Object _token = Object();

  static CarlinkPlatform _instance = MethodChannelCarlink();

  /// The default instance of [CarlinkPlatform] to use.
  ///
  /// Defaults to [MethodChannelCarlink].
  static CarlinkPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [CarlinkPlatform] when
  /// they register themselves.
  static set instance(CarlinkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  static void setLogHandler(Function(String)? logHandler) {
    (_instance as MethodChannelCarlink).setLogHandler(logHandler);
  }

  /// Set handlers for media control events from AAOS/steering wheel.
  ///
  /// These callbacks are invoked when the user presses media buttons on
  /// the steering wheel or interacts with the AAOS system media UI.
  static void setMediaControlHandlers({
    Function()? onPlay,
    Function()? onPause,
    Function()? onStop,
    Function()? onNext,
    Function()? onPrevious,
  }) {
    (_instance as MethodChannelCarlink).setMediaControlHandlers(
      onPlay: onPlay,
      onPause: onPause,
      onStop: onStop,
      onNext: onNext,
      onPrevious: onPrevious,
    );
  }

  Future<void> startReadingLoop(
    UsbEndpoint endpoint,
    int timeout, {
    required Function(int, Uint8List?) onMessage,
    required Function(String) onError,
  }) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> stopReadingLoop() async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<Map<String, dynamic>> getDisplayMetrics() async {
    throw UnimplementedError('getDisplayMetrics() has not been implemented.');
  }

  /// Returns window bounds information from Android WindowManager.
  ///
  /// Returns a map containing:
  /// - `width`, `height`: Full window dimensions (physical pixels)
  /// - `usableWidth`, `usableHeight`: Area minus system UI (physical pixels)
  /// - `insetsTop`, `insetsBottom`, `insetsLeft`, `insetsRight`: System UI insets (physical pixels)
  ///
  /// In immersive mode, usable area equals full window dimensions.
  /// In non-immersive mode, usable area excludes system bars and display cutouts.
  Future<Map<String, dynamic>> getWindowBounds() async {
    throw UnimplementedError('getWindowBounds() has not been implemented.');
  }

  Future<int> createTexture(int width, int height) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> removeTexture() async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> resetH264Renderer() async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Gets the current codec name from the H.264 renderer.
  ///
  /// Returns the codec name (e.g., "OMX.Intel.VideoDecoder.AVC (Intel Quick Sync)")
  /// or null if the renderer is not initialized.
  Future<String?> getCodecName() async {
    throw UnimplementedError('getCodecName() has not been implemented.');
  }

  Future<void> processData(Uint8List data) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<List<UsbDevice>> getDeviceList() async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<List<UsbDeviceDescription>> getDevicesWithDescription({
    bool requestPermission = true,
  }) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<UsbDeviceDescription> getDeviceDescription(
    UsbDevice usbDevice, {
    bool requestPermission = true,
  }) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> hasPermission(UsbDevice usbDevice) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> requestPermission(UsbDevice usbDevice) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> openDevice(UsbDevice usbDevice) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> closeDevice() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> resetDevice() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<UsbConfiguration> getConfiguration(int index) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> setConfiguration(UsbConfiguration config) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> claimInterface(UsbInterface intf) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<bool> releaseInterface(UsbInterface intf) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<Uint8List> bulkTransferIn(
    UsbEndpoint endpoint,
    int maxLength,
    int timeout, {
    bool isVideoData = false,
  }) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<int> bulkTransferOut(
    UsbEndpoint endpoint,
    Uint8List data,
    int timeout,
  ) async {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  // ==================== Audio Playback Methods ====================

  /// Initialize audio playback with the specified decode type.
  ///
  /// [decodeType] is the CPC200-CCPA audio format (1-7):
  /// - 1-2: 44100Hz stereo (music)
  /// - 3: 8000Hz mono (phone calls)
  /// - 4: 48000Hz stereo (high-quality, default)
  /// - 5: 16000Hz mono (Siri/voice)
  /// - 6: 24000Hz mono (enhanced voice)
  /// - 7: 16000Hz stereo (stereo voice)
  Future<bool> initializeAudio({int decodeType = 4}) async {
    throw UnimplementedError('initializeAudio() has not been implemented.');
  }

  /// Start audio playback.
  Future<bool> startAudio() async {
    throw UnimplementedError('startAudio() has not been implemented.');
  }

  /// Stop audio playback and flush buffers.
  Future<void> stopAudio() async {
    throw UnimplementedError('stopAudio() has not been implemented.');
  }

  /// Pause audio playback.
  Future<void> pauseAudio() async {
    throw UnimplementedError('pauseAudio() has not been implemented.');
  }

  /// Write PCM audio data for playback.
  ///
  /// [data] is the raw PCM audio samples (16-bit).
  /// [decodeType] is the CPC200-CCPA audio format for automatic format switching.
  /// [audioType] is the stream type (1=media, 2=navigation, 3=phone, 4=siri).
  /// [volume] is the playback volume (0.0 to 1.0).
  ///
  /// Returns the number of bytes written to the ring buffer.
  Future<int> writeAudio(
    Uint8List data, {
    int decodeType = 4,
    int audioType = 1,
    double volume = 1.0,
  }) async {
    throw UnimplementedError('writeAudio() has not been implemented.');
  }

  /// Set audio ducking level for navigation prompts.
  ///
  /// [duckLevel] is the volume multiplier (0.0 to 1.0).
  /// When navigation audio plays, media is ducked to this level.
  /// Pass 1.0 to restore full volume.
  Future<void> setAudioDucking(double duckLevel) async {
    throw UnimplementedError('setAudioDucking() has not been implemented.');
  }

  /// Set audio playback volume.
  ///
  /// [volume] is the volume level (0.0 to 1.0).
  Future<void> setAudioVolume(double volume) async {
    throw UnimplementedError('setAudioVolume() has not been implemented.');
  }

  /// Check if audio is currently playing.
  Future<bool> isAudioPlaying() async {
    throw UnimplementedError('isAudioPlaying() has not been implemented.');
  }

  /// Get audio playback statistics.
  Future<Map<String, dynamic>> getAudioStats() async {
    throw UnimplementedError('getAudioStats() has not been implemented.');
  }

  /// Release all audio resources.
  Future<void> releaseAudio() async {
    throw UnimplementedError('releaseAudio() has not been implemented.');
  }

  /// Stop (pause) a specific audio stream.
  ///
  /// This is critical for AAOS volume control. When an audio stream ends
  /// (e.g., nav prompt finishes), the corresponding AudioTrack must be paused
  /// so AAOS CarAudioService deprioritizes that audio context for volume keys.
  ///
  /// Without this, a nav track left in PLAYING state causes volume keys to
  /// control NAVIGATION volume instead of MEDIA volume, appearing "stuck".
  ///
  /// [audioType] specifies which stream to stop:
  /// - 1 = Media (USAGE_MEDIA)
  /// - 2 = Navigation (USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
  /// - 3 = Phone call (USAGE_VOICE_COMMUNICATION)
  /// - 4 = Voice/Siri (USAGE_ASSISTANT)
  Future<void> stopAudioStream({required int audioType}) async {
    throw UnimplementedError('stopAudioStream() has not been implemented.');
  }

  // ==================== Microphone Capture Methods ====================

  /// Start microphone capture with the specified decode type.
  ///
  /// [decodeType] is the CPC200-CCPA voice format:
  /// - 3: 8000Hz mono (phone calls)
  /// - 5: 16000Hz mono (Siri/voice assistant, default)
  /// - 6: 24000Hz mono (enhanced voice)
  /// - 7: 16000Hz stereo (stereo voice)
  ///
  /// Returns true if capture started successfully.
  Future<bool> startMicrophoneCapture({int decodeType = 5}) async {
    throw UnimplementedError(
        'startMicrophoneCapture() has not been implemented.');
  }

  /// Stop microphone capture and release resources.
  Future<void> stopMicrophoneCapture() async {
    throw UnimplementedError(
        'stopMicrophoneCapture() has not been implemented.');
  }

  /// Read captured PCM audio data from the ring buffer.
  ///
  /// [maxBytes] is the maximum bytes to read (default: 1920 = 60ms at 16kHz mono).
  ///
  /// Returns ByteArray with PCM data, or null if no data available.
  Future<Uint8List?> readMicrophoneData({int maxBytes = 1920}) async {
    throw UnimplementedError('readMicrophoneData() has not been implemented.');
  }

  /// Check if microphone is currently capturing.
  Future<bool> isMicrophoneCapturing() async {
    throw UnimplementedError(
        'isMicrophoneCapturing() has not been implemented.');
  }

  /// Check if microphone permission is granted.
  Future<bool> hasMicrophonePermission() async {
    throw UnimplementedError(
        'hasMicrophonePermission() has not been implemented.');
  }

  /// Get the current decode type for active capture.
  ///
  /// Returns decodeType (3, 5, 6, or 7) or -1 if not capturing.
  Future<int> getMicrophoneDecodeType() async {
    throw UnimplementedError(
        'getMicrophoneDecodeType() has not been implemented.');
  }

  /// Get microphone capture statistics.
  Future<Map<String, dynamic>> getMicrophoneStats() async {
    throw UnimplementedError('getMicrophoneStats() has not been implemented.');
  }

  // ==================== MediaSession Methods (AAOS Integration) ====================

  /// Update now-playing metadata for AAOS media source.
  ///
  /// This updates the MediaSession metadata visible in AAOS system UI,
  /// cluster display, and media widgets.
  ///
  /// [title] Song title or lyrics
  /// [artist] Artist name
  /// [album] Album name
  /// [appName] Source app name (e.g., "Spotify", "Apple Music")
  /// [albumArt] Album cover image bytes (JPEG/PNG)
  /// [duration] Track duration in milliseconds (0 if unknown)
  Future<void> updateMediaMetadata({
    String? title,
    String? artist,
    String? album,
    String? appName,
    Uint8List? albumArt,
    int duration = 0,
  }) async {
    throw UnimplementedError('updateMediaMetadata() has not been implemented.');
  }

  /// Update playback state for AAOS media source.
  ///
  /// [isPlaying] Whether media is currently playing
  /// [position] Current playback position in milliseconds
  Future<void> updatePlaybackState({
    required bool isPlaying,
    int position = 0,
  }) async {
    throw UnimplementedError(
        'updatePlaybackState() has not been implemented.');
  }

  /// Set MediaSession state to connecting/buffering.
  Future<void> setMediaSessionConnecting() async {
    throw UnimplementedError(
        'setMediaSessionConnecting() has not been implemented.');
  }

  /// Set MediaSession state to stopped/idle.
  Future<void> setMediaSessionStopped() async {
    throw UnimplementedError(
        'setMediaSessionStopped() has not been implemented.');
  }
}
