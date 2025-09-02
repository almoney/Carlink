# AutoKit Native Libraries - Reconstructed Code

This directory contains human-readable reconstructions of the AutoKit APK's native libraries, extracted from the deobfuscated binaries.

## Files Generated

### Java Interfaces
- **`NativeAdapter.java`** - JNI interface for WebRTC audio processing
- **`OpenH264Decoder.java`** - JNI interface for H.264 video decoding  
- **`ConnectionNative.java`** - JNI interface for USB communication
- **`CPC200Protocol.java`** - High-level CPC200-CCPA protocol implementation

### C++ Headers
- **`AudioProcessNative.h`** - WebRTC-based audio processing engine
- **`H264DecoderNative.h`** - OpenH264 video decoder implementation
- **`USBConnectionNative.h`** - libusb-based USB communication layer

## Library Analysis Summary

### libAudioProcess.so
- **Language**: C++ with WebRTC framework
- **Purpose**: Real-time audio processing for CarPlay
- **Key Features**:
  - Echo cancellation (AEC)
  - Noise suppression
  - Gain control
  - 48kHz/16-bit audio processing
  - JNI bridge to `com.xtour.audioprocess.NativeAdapter`

### libopenH264decoder.so  
- **Language**: C++ with OpenH264 library
- **Purpose**: Hardware-accelerated H.264 video decoding
- **Key Features**:
  - Real-time H.264 frame decoding
  - YUV420P output format
  - Support for offset-based decoding
  - JNI bridge to `cn.manstep.phonemirrorBox.OpenH264Decoder`

### libconnection.so
- **Language**: C++ with libusb-1.0
- **Purpose**: USB communication with CPC200-CCPA devices
- **Key Features**:
  - libusb-based USB device management
  - Carlinkit device detection (VID: 0x1314)
  - Bulk transfer operations
  - Kernel driver management

## Protocol Implementation

### CPC200-CCPA Protocol
- **Magic Number**: 0x55AA55AA (1437226410)
- **Header Size**: 16 bytes
- **Commands**:
  - `0x01` - Session initialization
  - `0xAA` - Heartbeat
  - `0x19` - Box settings
  - `0xCC` - Software version
- **Session Parameters**: Resolution, FPS, format configuration

## Reconstruction Methods

1. **Symbol Analysis**: Extracted function names and signatures using `objdump` and `nm`
2. **String Analysis**: Identified API calls and error messages using `strings`
3. **Cross-referencing**: Matched native symbols with deobfuscated Java classes
4. **Protocol Analysis**: Reconstructed from BoxHelper APK deobfuscation
5. **Framework Recognition**: Identified WebRTC and OpenH264 usage patterns

## Usage Notes

- These reconstructions are based on symbol analysis and may not reflect exact implementation details
- Function signatures are inferred from JNI naming conventions and symbol tables
- Some internal implementation details are approximated based on common patterns
- Error handling and edge cases may differ from original implementation

## Architecture Overview

```
Android Application Layer (Java)
        ↓ JNI
Native Libraries (C++)
        ↓ 
System Libraries (WebRTC, OpenH264, libusb)
        ↓
Hardware (USB, Audio, Video)
```

The reconstruction reveals a sophisticated multimedia processing architecture optimized for automotive CarPlay/Android Auto applications with real-time audio/video processing and USB-based device communication.