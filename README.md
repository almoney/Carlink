Open-source Projection Android App for Apple CarPlay and Android Auto using the Carlinkit CPC200-CCPA adapter.

Apple CarPlay and Android Auto projection

[Carlinkit CPC200-CCPA (Amazon US)](https://a.co/d/d1eatDz)


About This Project:

Carlink is a modernization of the original "Carplay" project by Abuharsky, designed as an open-source alternative to the proprietary Carlinkit AutoKit application. This project provides:

- USB Host Communication: Direct USB protocol implementation for CPC200-CCPA control
- Hardware-Accelerated Video: H.264 rendering with MediaCodec and OpenGL ES2

Credits & Prior Works

This project builds upon the foundational research and implementations from:

- [Carplay by Abuharsky](https://github.com/abuharsky/carplay) - Original Android implementation
- [Node-Carplay by Rhysmorgan134](https://github.com/rhysmorgan134/node-CarPlay) - Protocol reverse engineering
- [Pi-Carplay by f-io](https://github.com/f-io/pi-carplay) - Raspberry Pi implementation
- [PyCarplay by Electric-Monk](https://github.com/electric-monk/pycarplay) - Python implementation


Project Structure:

```
carlink/
├── lib/                          - Flutter plugin implementation
│   ├── carlink.dart             - Main API (421 lines)
│   ├── carlink_method_channel.dart - Native messaging bridge
│   ├── carlink_platform_interface.dart - Platform abstraction
│   ├── driver/                  - CPC200-CCPA protocol implementation
│   │   ├── adaptr_driver.dart   - Protocol orchestration, initialization
│   │   ├── readable.dart        - Message parsing (13 types)
│   │   ├── sendable.dart        - Message serialization
│   │   └── usb/
│   │       └── usb_device_wrapper.dart - USB lifecycle management
│   ├── console_log_listener.dart - Console logging
│   ├── file_log_manager.dart    - File-based logging with rotation
│   ├── logging_lifecycle_manager.dart - Logging coordination
│   ├── log.dart                 - Centralized logging system
│   ├── common.dart              - Shared utilities
│   └── usb.dart                 - USB abstractions
├── android/                      - Native Android implementation
│   └── src/main/kotlin/com/carlink/
│       ├── CarlinkPlugin.kt     - FlutterPlugin entry point
│       ├── handlers/            - Modular method call handlers
│       │   ├── MethodCallDispatcher.kt
│       │   ├── UsbDeviceHandler.kt
│       │   ├── BulkTransferHandler.kt
│       │   ├── VideoHandler.kt
│       │   └── DisplayMetricsHandler.kt
│       ├── UsbDeviceManager.kt  - USB device discovery
│       ├── BulkTransferManager.kt - USB I/O operations
│       ├── VideoTextureManager.kt - Texture lifecycle
│       ├── H264Renderer.java    - MediaCodec, Intel QuickSync
│       ├── PacketRingByteBuffer.java - 16MB ring buffer
│       ├── TextureRender.java   - OpenGL ES2 rendering
│       ├── OutputSurface.java   - EGL surface management
│       ├── CarLinkMessage.java  - Protocol message wrapper
│       ├── CarLinkMessageHeader.java - Message header parsing
│       ├── AppExecutors.java    - Thread pool management
│       └── LogCallback.java     - Native logging bridge
├── example/                      - Example Android application
│   ├── lib/
│   │   ├── main.dart            - App entry point
│   │   ├── main_page.dart       - Video projection UI
│   │   ├── settings_page.dart   - Tabbed settings interface
│   │   ├── theme.dart           - Material theme configuration
│   │   ├── immersive_preference.dart - Fullscreen settings
│   │   └── settings/            - Modular settings components
│   │       ├── status_tab_content.dart
│   │       ├── control_tab_content.dart
│   │       ├── logs_tab_content.dart
│   │       ├── status_monitor.dart
│   │       ├── logging_preferences.dart
│   │       ├── enhanced_sharing.dart
│   │       ├── settings_enums.dart
│   │       ├── settings_tab_base.dart
│   │       ├── delete_confirmation_dialog.dart
│   │       ├── export_warning_dialog.dart
│   │       └── transfer_dialog.dart
│   └── android/                 - Build from here for APK/AAB
└── docs/                         - Technical documentation
    ├── project.md               - Comprehensive technical analysis
    ├── Firmware/                - CPC200-CCPA specifications
    ├── GM/                      - GM infotainment specs
    └── Autokit_reference_only/  - Original AutoKit reference

```

Development Environment:

- Android Studio: Narwhal 2025.1.2+ (includes JDK 21)
- Flutter: ≥3.32.0 with Dart ≥3.8.0
- Java/JDK: Version 21 (bundled with Android Studio)
- Gradle: 8.12.1 with AGP 8.12.1
- Kotlin: 2.2.0

Android

- Minimum SDK: API 32 (Android 12L)
- Target SDK: API 34 (Android 14)
- Compile SDK: API 36 (Android 15)
- NDK: 27.0.12077973


Note: Flutter must be installed as both an Android Studio plugin AND as a standalone SDK. See [Flutter installation guide](https://docs.flutter.dev/install/manual).

Building from Source:


Quick Start:

1. Configure Application Identity

   Edit `project_config.gradle` in the root directory:
   ```gradle
   myApplicationId = "com.your.app"      // Your unique package name
   myApplicationName = "Carlink"          // App display name
   myVersionCode = 1                      // Play Store version code
   myVersionName = "1.0.0"                // User-visible version
   ```

   The build system automatically:
   - Generates package structure from `TEMPLATE_PACKAGE`
   - Creates `MainActivity.kt` with correct package name
   - Cleans up old package directories

2. Load Flutter + Dart SDKs
   - With Flutter and Dart installed in your terminal
   - Within `Carlink/example/android/`, run:
     ```bash
     flutter clean && flutter pub get && ./gradlew clean
     ```
   - This prepares the directory for building APKs and troubleshooting

3. Build with Android Studio

   - Open project directory: `Carlink/example/android`
   - Wait for Gradle sync to complete
   - Build → Build Bundle(s) / APK(s) → Build APK
   - Or use terminal: `./gradlew assembleRelease`


Features:

- Video Projection
  - Hardware-accelerated H.264 rendering with MediaCodec
  - Intel QuickSync optimization with fallback to generic decoders
  - Multitouch input support (1-10 simultaneous touch points)
  - Adaptive buffer pools (6-20 buffers based on resolution)
  - Low-latency mode for Android 12+ (16-29ms total pipeline)

- Settings UI (Modular Architecture)
  - Status Tab: Adapter status monitoring
  - Control Tab: Device control commands (disconnect phone, close adapter, reset renderer, reset/reinit adapter)
  - Logs Tab: File logging management with 7 configurable log levels
  - Bulk file operations and enhanced sharing (AAOS compatible)
  - Responsive design (mobile/tablet/desktop breakpoints)
  - Immersive fullscreen mode toggle
  - Theme system with Material Design

- Logging System
  - Tag-based filtering (12 categories: USB, PLATFORM, VIDEO, AUDIO, etc.)
  - Console output with session IDs and ISO8601 timestamps
  - File logging with automatic rotation (5MB max, 7-day retention)
  - Queue-based non-blocking architecture
  - Dual output: console + persistent file storage

- Performance Monitoring
  - FPS tracking with 30-second intervals
  - Buffer utilization statistics
  - USB throughput monitoring
  - Codec performance metrics


Current Limitations:

- Audio Processing: CPC200-CCPA is initialized in video-only mode (`audioTransferMode` disabled)
  - Audio protocol parsing is implemented (7 audio formats supported)
  - Missing: `AudioTrack` playback and `AudioRecord` microphone capture
  - This is an app limitation, not adapter hardware limitation

- **Platform Support**: Android-only implementation
  - No iOS, web, macOS, or Linux native support
  - Linux/macOS entries in pubspec.yaml are placeholders only

My Hardware:

Primary Test Platform:
- Vehicle: Chevrolet 2024 Silverado
- Radio: GM AAOS (gminfo3.7-3.8, RPO: IOK)
- Radio: GM AAOS Build Y181
- Processor: Intel Atom x7-A3960 (x86_64)
- Display: 2400x960 ultra-wide
- GPU: Intel HD Graphics 505 (18 EUs, Intel QuickSync optimized)
- Adapter: CPC200-CCPA A15W (verified)

Compatibility Notes:
- Apple CarPlay 
- Android Auto (Might need to do initial pairing with Autokit App)
- - Android Auto has resolution limitations by Google design.
- H.264 rendering includes Intel QuickSync optimizations but works with generic decoders
- Adaptive buffer pools automatically adjust for different resolutions
- Tested on AAOS but should work on standard Android 12L+ devices
- Your results may vary with different hardware configurations

-- Documentation

The `docs/` directory contains technical documentation:

- [docs/project.md](docs/project.md) - Comprehensive technical analysis (optimized for AI ingestion)
- [docs/Firmware/](docs/Firmware/) - CPC200-CCPA adapter specifications and protocol details
- [docs/GM/](docs/GM/) - GM infotainment (gminfo3.7) technical specifications
- [docs/Autokit_reference_only/](docs/Autokit_reference_only/) - Original Carlinkit AutoKit reference implementation

These documents provide detailed information about:
- CPC200-CCPA protocol (16-byte header, 13 message types, 51+ commands)
- Hardware specifications (ARM32, 128MB RAM, WM8960/AC6966 audio codecs etc)
- Audio pipeline architecture (7 audio formats, bidirectional processing)
- Video processing (H.264 hardware acceleration, resolution negotiation)
- USB bulk transfer implementation and error recovery

Architecture & Performance

Flutter Plugin Layer:

- `lib/carlink.dart` - Main API with lifecycle management (421 lines)
- `lib/carlink_method_channel.dart` - Native messaging bridge (357 lines)
- `lib/carlink_platform_interface.dart` - Platform abstraction (130 lines)
- `lib/driver/adaptr_driver.dart` - CPC200-CCPA protocol orchestration (375 lines)
- `lib/driver/readable.dart` - Message parsing for 13 protocol message types (446 lines)
- `lib/driver/sendable.dart` - Message serialization (Touch, MultiTouch, Commands) (375 lines)
- `lib/driver/usb/usb_device_wrapper.dart` - USB device lifecycle management (355 lines)
- `lib/log.dart` - Centralized logging with tag filtering (324 lines)
- `lib/file_log_manager.dart` - File-based logging with rotation (422 lines)

Android Native Layer (Handler-Based Architecture):

- `CarlinkPlugin.kt` - FlutterPlugin entry point
- `handlers/MethodCallDispatcher.kt` - Routes method calls to specialized handlers
- `handlers/UsbDeviceHandler.kt` - USB device lifecycle management
- `handlers/BulkTransferHandler.kt` - USB read/write operations
- `handlers/VideoHandler.kt` - Video texture management
- `handlers/DisplayMetricsHandler.kt` - Screen resolution detection
- `UsbDeviceManager.kt` - USB device discovery and permissions
- `BulkTransferManager.kt` - Bulk transfer retry logic and error recovery
- `VideoTextureManager.kt` - Texture lifecycle coordination
- `H264Renderer.java` - MediaCodec integration with adaptive buffer pools (6-20 buffers)
- `PacketRingByteBuffer.java` - 16MB ring buffer with dynamic resize
- `TextureRender.java` - OpenGL ES2 external texture rendering
- `OutputSurface.java` - EGL surface management
- `CarLinkMessage.java` - Protocol message wrapper
- `CarLinkMessageHeader.java` - Message header parsing

**Example Application:**

- `example/lib/main.dart` - App entry point with logging initialization (99 lines)
- `example/lib/main_page.dart` - Video projection with multitouch processing (361 lines)
- `example/lib/settings_page.dart` - Tabbed settings interface (148 lines)
- `example/lib/theme.dart` - Material Design theme configuration
- `example/lib/immersive_preference.dart` - Fullscreen mode persistence
- `example/lib/settings/` - 11 modular settings components:
  - `status_tab_content.dart` - Real-time adapter status display
  - `control_tab_content.dart` - Device control commands
  - `logs_tab_content.dart` - Log file management UI
  - `status_monitor.dart` - Adapter status polling service
  - `logging_preferences.dart` - Log level persistence
  - `enhanced_sharing.dart` - AAOS-compatible file sharing
  - And 5 dialog components for user interactions

Performance Characteristics

- Video Latency: 16-29ms total (H.264 decode: 8-15ms, protocol: 1-2ms, OpenGL: 3-5ms)
- Touch Latency: <16ms touch-to-USB transmission
- Memory Footprint: ~3.45MB active processing
- CPU Usage: 36-58% during active streaming (on Intel Atom x7-A3960)
- Buffer Management: Adaptive pool sizing based on resolution (6-20 buffers)

Important Notes

Modifying Dart Protocol Code

Exercise caution when modifying `lib/driver/adaptr_driver.dart`, `lib/driver/readable.dart`, or `lib/driver/sendable.dart` files. The CPC200-CCPA communication protocol is based on reverse engineering from several years ago when Carlinkit App+firmware was decrypted. 

The initialization sequence and communication logic must remain compatible with the adapter firmware. Breaking changes can prevent the adapter from functioning correctly.

Firmware Limitations

Adding new adapter features is not currently possible without reverse engineering the latest Carlinkit firmware. The adapter's capabilities are limited to what was documented during the original App+firmware decryption.

For firmware research: [CPC200-CCPA-Firmware-Dump repository](https://github.com/lvalen91/CPC200-CCPA-Firmware-Dump)

Centralized Build Configuration

All version numbers, SDK levels, and package identifiers are managed in `project_config.gradle`. This file is the single source of truth for:
- Application ID and display name
- Version code and version name
- SDK levels (min, target, compile)
- Kotlin, Gradle, and Java versions

Update this file before publishing to Google Play Store. The automated build system handles package generation and cleanup.


Future Development

Planned (No Timeline):

- Audio Support
  - AudioTrack playback implementation
  - AudioRecord microphone capture
  - Volume control and audio focus management
  - Real-time sample rate conversion
  
While enabling Audio support is relatively easy. Having it handle the different audio streams without the app slowing down to a crawl.... Yea, thats the hangup.

Support & Issues

Consider this repo AS-IS without any support, do with it as you please. Updates are pushed out as I find things to fix, add, or remove. So Fork it or copy and make your own repo, MIT license and all that.
