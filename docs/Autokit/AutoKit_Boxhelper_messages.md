# CPC200-CCPA Protocol Message Translation Guide

## Overview

This guide provides complete human-readable translations for all CPC200-CCPA protocol messages discovered through reverse engineering AutoKit and BoxHelper APKs. Each message includes hex values, purposes, data structures, and implementation examples.

---

## Primary Protocol Implementation Files:

  1. BoxHelper APK (USB Communication Core)

  /boxhelper_analysis/boxhelper_decompiled/sources/b/a/a/c.java (207 lines)
  Contains:
  - Session initialization (Command 0x01) - lines 144-177
  - USB bulk transfer implementation - lines 124-142, 179-206
  - Device detection (VID 0x1314) - lines 66-110
  - Heartbeat timer setup - references to scheduleAtFixedRate

  2. Message Processor

  /boxhelper_analysis/boxhelper_decompiled/sources/b/a/a/d.java (95 lines)
  Contains:
  - Protocol header parsing (0x55AA55AA) - lines 25-41
  - Message reception loop - lines 20-94
  - Command processing for 0x01, 0x19, 0xCC - lines 42-78
  - Buffer management and validation

  3. Protocol Data Structure

  /boxhelper_analysis/boxhelper_decompiled/sources/b/a/a/k.java (28 lines)
  Contains:
  - 28-byte session configuration structure
  - Default values (width=800, height=480, fps=30)
  - ByteBuffer setup for little-endian protocol

  4. Touch Input System

  /hwtouch_decompiled/sources/com/hewei/phonemirror/touch/HWTouch.java (449 lines)
  Contains:
  - Touch command values (0=DOWN, 1=MOVE, 2=UP, etc.) - lines 36-42
  - Network setup (127.0.0.1:8878) - lines 27-28
  - Touch coordinate processing - lines 220-257

### Message-Specific Locations:

####  Session Management (0x01 Open, 0xAA Heartbeat):

  File: b/a/a/c.java
  // Lines 144-177: Session initialization
  public void b() {
      // Configure session parameters
      kVar.f751a = 800;        // Width
      kVar.f752b = 480;        // Height  
      kVar.f753c = 30;         // FPS
      kVar.f = 255;            // Version

      // Create protocol header (Command 0x01)
      byteBufferAllocate.putInt(0, 1437226410);  // 0x55AA55AA
      byteBufferAllocate.putInt(4, 28);          // Payload length
      byteBufferAllocate.putInt(8, 1);           // Command 0x01
      byteBufferAllocate.putInt(12, 1 ^ (-1));   // Checksum
  }

####  Message Processing (0x19, 0xCC responses):

  File: b/a/a/d.java
  // Lines 42-78: Protocol message handling
  if (i3 == 204) {  // 0xCC - Software Version
      if (32 == i2) {
          cVar.e.a(1, new String(byteBuffer.array(), 0, 18, "ISO-8859-1"));
      }
  } else if (i3 == 25) {  // 0x19 - BoxSettings
      if (i2 >= 4) {
          cVar.e.a(3, new String(byteBuffer.array(), 0, i2, "ISO-8859-1"));
      }
  }

####  Touch Input (0x05 Touch commands):

  File: HWTouch.java
  // Lines 36-42: Touch action constants
  private static final int TOUCH_DOWN = 0;
  private static final int TOUCH_MOVE = 1;
  private static final int TOUCH_UP = 2;
  private static final int TOUCH_MENU = 3;
  private static final int TOUCH_HOME = 4;
  private static final int TOUCH_BACK = 5;

  // Lines 220-257: Touch event processing
  private static void sendAction(int i, float f, float f2) {
      switch (i) {
          case 0: touchDown(f, f2); break;
          case 1: touchMove(f, f2); break;
          case 2: touchUp(f, f2); break;
          // ... etc
      }
  }

###  Native Library References:

####  Audio Processing (0x07 AudioData):

  Files containing JNI references:
  /native_libs/libAudioProcess.so (2,645,680 bytes)
  JNI Methods discovered:
  - Java_com_xtour_audioprocess_NativeAdapter_processData
  - Java_com_xtour_audioprocess_NativeAdapter_init

####  Video Processing (0x06 VideoData):

  Files containing H.264 processing:
  /native_libs/libopenH264decoder.so (456,272 bytes)
  JNI Methods discovered:
  - Java_cn_manstep_phonemirrorBox_OpenH264Decoder_decodeFrame
  - Java_cn_manstep_phonemirrorBox_OpenH264Decoder_nativeInit

 ### Additional Protocol References:

 #### UI Handler (Message routing):

  /boxhelper_analysis/boxhelper_decompiled/sources/b/a/a/g.java (92 lines)
  Contains:
  - Message type handling (types 1, 2, 3)
  - UI update coordination for protocol responses

####  Service Integration:

  /mirrorcoper_analysis/mirrorcoper_decompiled/sources/com/manstep/someservice/ChangeOrientationService.java
  Contains:
  - Socket communication (127.0.0.1:4242) - line 88
  - Protocol command processing - lines 58-81
  - Heartbeat and session management

###  Files NOT Containing Protocol Info:

  These files do NOT contain the core protocol message definitions:
  - AutoKit main classes.dex (obfuscated) - Contains higher-level service logic
  - Screen capture libraries (libscreencap*.so) - Android-specific capture, not protocol
  - Protection libraries (libjiagu*.so) - 360 Jiagu protection only

##  Key Code Locations Summary:

  | Message Type    | File                  | Lines          | Content                                     |
  |-----------------|-----------------------|----------------|---------------------------------------------|
  | 0x01 Open       | b/a/a/c.java          | 144-177        | Session initialization with 28-byte payload |
  | 0x05 Touch      | HWTouch.java          | 36-42, 220-257 | Touch constants and processing              |
  | 0x07 Audio      | libAudioProcess.so    | JNI exports    | Native audio processing                     |
  | 0x06 Video      | libopenH264decoder.so | JNI exports    | Native H.264 decoding                       |
  | 0x19 Settings   | b/a/a/d.java          | 72-78          | JSON configuration handling                 |
  | 0xAA Heartbeat  | b/a/a/c.java          | 118-122        | Timer scheduling (2-second intervals)       |
  | 0xCC Version    | b/a/a/d.java          | 42-49          | 18-character version string parsing         |
  | Protocol Header | b/a/a/d.java          | 25-41          | 0x55AA55AA magic number validation          |

  The core protocol implementation is primarily concentrated in the BoxHelper APK rather than the main AutoKit
  APK, with BoxHelper serving as the USB communication layer that AutoKit's higher-level services communicate
  with. It might be pulled from adapter and used during normal Autokit apk operation.


## 1. Protocol Header Structure

### **Standard Message Header (16 bytes)**
```
Offset  | Size | Field    | Value/Description
--------|------|----------|------------------
0x00    | 4    | Magic    | 0x55AA55AA (1437226410 decimal)
0x04    | 4    | Length   | Payload size (0 to 1048576 bytes)
0x08    | 4    | Command  | Message type (see tables below)
0x0C    | 4    | Checksum | Command XOR 0xFFFFFFFF (~Command)
```

**Header Validation:**
- Magic must equal `0x55AA55AA`
- Checksum must equal `Command ^ 0xFFFFFFFF`
- Length must be ≤ 1048576 (1MB)
- Byte order: Little-endian

---

## 2. Host to Device (h2d) Messages

### **0x01 - Open (Session Initialization)**
```
Command: 0x01
Hex: 55 AA 55 AA 1C 00 00 00 01 00 00 00 FE FF FF FF
Payload Size: 28 bytes
Purpose: Initialize CPC200-CCPA session with display parameters
```

**Payload Structure (28 bytes):**
```
Offset | Size | Field      | AutoKit Value | Description
-------|------|------------|---------------|-------------
0x00   | 4    | Width      | 800 (0x320)   | Display width in pixels
0x04   | 4    | Height     | 480 (0x1E0)   | Display height in pixels  
0x08   | 4    | FPS        | 30 (0x1E)     | Target frame rate
0x0C   | 4    | Format     | 5             | Video format identifier
0x10   | 4    | PktMax     | 49152 (0xC000)| Max packet size (48KB)
0x14   | 4    | Version    | 255 (0xFF)    | Protocol version
0x18   | 4    | Mode       | 2             | Operation mode
```

**Example Raw Message:**
```hex
55 AA 55 AA 1C 00 00 00 01 00 00 00 FE FF FF FF
20 03 00 00 E0 01 00 00 1E 00 00 00 05 00 00 00
00 C0 00 00 FF 00 00 00 02 00 00 00
```

### **0x05 - Touch (Single Touch Input)**
```
Command: 0x05
Hex: 55 AA 55 AA 10 00 00 00 05 00 00 00 FA FF FF FF
Payload Size: 16 bytes
Purpose: Send single touch/mouse input to device
```

**Payload Structure (16 bytes):**
```
Offset | Size | Field    | Values        | Description
-------|------|----------|---------------|-------------
0x00   | 4    | Action   | 0=Down,1=Move,2=Up,3=Menu,4=Home,5=Back | Touch action
0x04   | 4    | X        | 0.0-1.0 float | Normalized X coordinate
0x08   | 4    | Y        | 0.0-1.0 float | Normalized Y coordinate  
0x0C   | 4    | Flags    | 0             | Additional flags (reserved)
```

**Touch Actions:**
- `0x00` - TOUCH_DOWN: Press down
- `0x01` - TOUCH_MOVE: Move while pressed
- `0x02` - TOUCH_UP: Release
- `0x03` - TOUCH_MENU: Menu button
- `0x04` - TOUCH_HOME: Home button
- `0x05` - TOUCH_BACK: Back button

### **0x07 - AudioData (Audio Upload)**
```
Command: 0x07
Hex: 55 AA 55 AA XX XX XX XX 07 00 00 00 F8 FF FF FF
Payload Size: Variable
Purpose: Upload audio data (microphone) to device
```

**Payload Structure:**
```
Offset | Size     | Field     | Description
-------|----------|-----------|-------------
0x00   | 4        | DecType   | Decode type/format
0x04   | 4        | Volume    | Volume level (0-255)
0x08   | 4        | AudType   | Audio type identifier
0x0C   | Variable | AudioData | Raw PCM audio data
```

### **0x08 - Command (Control Commands)**
```
Command: 0x08
Hex: 55 AA 55 AA 04 00 00 00 08 00 00 00 F7 FF FF FF
Payload Size: 4 bytes
Purpose: Send control commands to device
```

**Known Control Commands:**
```
Payload Value | Purpose
--------------|----------
0x01 00 00 00 | Start session
0x02 00 00 00 | Stop session
0x03 00 00 00 | Reset connection
0x04 00 00 00 | Query status
```

### **0x09 - LogoType (UI Branding)**
```
Command: 0x09  
Hex: 55 AA 55 AA 04 00 00 00 09 00 00 00 F6 FF FF FF
Payload Size: 4 bytes
Purpose: Set UI branding/logo type
```

### **0x0F - DiscPhone (Disconnect Phone)**
```
Command: 0x0F
Hex: 55 AA 55 AA 00 00 00 00 0F 00 00 00 F0 FF FF FF
Payload Size: 0 bytes
Purpose: Gracefully disconnect phone session
```

### **0x15 - CloseDongle (Terminate Adapter)**
```
Command: 0x15
Hex: 55 AA 55 AA 00 00 00 00 15 00 00 00 EA FF FF FF
Payload Size: 0 bytes
Purpose: Shut down CPC200-CCPA adapter completely
```

### **0x17 - MultiTouch (Multi-finger Touch)**
```
Command: 0x17
Hex: 55 AA 55 AA XX XX XX XX 17 00 00 00 E8 FF FF FF
Payload Size: Variable
Purpose: Send multi-touch input data
```

**Payload Structure:**
```
Offset | Size | Field       | Description
-------|------|-------------|-------------
0x00   | 4    | TouchCount  | Number of touch points (1-10)
0x04   | 16   | TouchPoint1 | First touch point (Action,X,Y,ID)
0x14   | 16   | TouchPoint2 | Second touch point (if count > 1)
...    | ...  | ...         | Additional touch points
```

### **0x19 - BoxSettings (Configuration Update)**
```
Command: 0x19
Hex: 55 AA 55 AA XX XX XX XX 19 00 00 00 E6 FF FF FF
Payload Size: Variable (JSON string)
Purpose: Update adapter configuration settings
```

**Example JSON Payload:**
```json
{
  "uuid": "12345678-1234-1234-1234-123456789abc",
  "MFD": "CarlinKit", 
  "boxType": "CPC200-CCPA",
  "productType": "A15W",
  "OemName": "AutoBox",
  "wifiSSID": "AutoBox-76d4",
  "wifiPassword": "12345678"
}
```

### **0x99 - SendFile (File Transfer)**
```
Command: 0x99
Hex: 55 AA 55 AA XX XX XX XX 99 00 00 00 66 FF FF FF  
Payload Size: Variable
Purpose: Send file to adapter storage
```

**Payload Structure:**
```
Offset   | Size     | Field       | Description
---------|----------|-------------|-------------
0x00     | 4        | NameLen     | Filename length
0x04     | NameLen  | FileName    | UTF-8 filename
Variable | 4        | ContentLen  | File content length
Variable | ContentLen| FileContent | Raw file data
```

### **0xAA - HeartBeat (Keep-Alive)**
```
Command: 0xAA (170 decimal)
Hex: 55 AA 55 AA 00 00 00 00 AA 00 00 00 55 FF FF FF
Payload Size: 0 bytes  
Purpose: Maintain connection (sent every 2 seconds)
Timing: Scheduled every 2000ms when session active
```

---

## 3. Device to Host (d2h) Messages

### **0x02 - Plugged (Phone Connection Status)**
```
Command: 0x02
Response to: Session initialization
Payload Size: 4 or 8 bytes
Purpose: Report phone connection status
```

**Payload Structure:**
```
Offset | Size | Field  | Values | Description
-------|------|--------|--------|-------------
0x00   | 4    | Status | 0/1    | 0=Disconnected, 1=Connected  
0x04   | 4    | Extra  | ?      | Additional status info (optional)
```

### **0x03 - Phase (Operation State)**
```
Command: 0x03  
Payload Size: 4 bytes
Purpose: Report current operational phase/state
```

**Known Phase Values:**
```
Value | Phase Description
------|------------------
0x00  | Idle/Standby
0x01  | Initializing
0x02  | Active/Connected
0x03  | Error state
0x04  | Shutting down
```

### **0x04 - Unplugged (Phone Disconnection)**
```
Command: 0x04
Payload Size: 0 bytes
Purpose: Notify that phone has been disconnected
```

### **0x06 - VideoData (H.264 Video Stream)**
```
Command: 0x06
Payload Size: Variable (up to 1MB)  
Purpose: Deliver H.264 video frame data
```

**Payload Structure:**
```
Offset   | Size     | Field     | Description
---------|----------|-----------|-------------
0x00     | 4        | Width     | Frame width
0x04     | 4        | Height    | Frame height  
0x08     | 4        | Flags     | Frame flags (keyframe, etc.)
0x0C     | 4        | Length    | H.264 data length
0x10     | 4        | Unknown   | Reserved/padding
0x14     | Variable | H264Data  | Raw H.264 NAL units
```

**Frame Flags:**
- `0x01` - Keyframe (I-frame)
- `0x02` - P-frame
- `0x04` - B-frame
- `0x08` - SPS/PPS data

### **0x07 - AudioData (PCM Audio Stream)**
```
Command: 0x07
Payload Size: Variable
Purpose: Deliver PCM audio data from device
```

**Payload Structure:**
```
Offset   | Size     | Field     | Description
---------|----------|-----------|-------------
0x00     | 4        | DecType   | Audio decode type
0x04     | 4        | Volume    | Current volume (0-255)
0x08     | 4        | AudType   | Audio stream type
0x0C     | Variable | AudioData | Raw PCM data
```

**Audio Types:**
- `1,2`: 44.1kHz, 2ch, 16-bit
- `3`: 8kHz, 1ch, 16-bit  
- `4`: 48kHz, 2ch, 16-bit
- `5`: 16kHz, 1ch, 16-bit
- `6`: 24kHz, 1ch, 16-bit
- `7`: 16kHz, 2ch, 16-bit

### **0x08 - Command (Status Response)**
```
Command: 0x08
Payload Size: 4 bytes
Purpose: Response to control commands (0x08 h2d)
```

### **0x0A-0x0E - NetMeta (Network Metadata)**
```
Commands: 0x0A, 0x0B, 0x0C, 0x0D, 0x0E
Payload Size: Variable  
Purpose: Bluetooth/WiFi network information
```

### **0x14 - MfgInfo (Device Information)**
```
Command: 0x14 (20 decimal)
Payload Size: Variable
Purpose: Manufacturer and device information
```

**Typical Information:**
- Hardware version
- Firmware version  
- Serial number
- Manufacture date
- Capabilities

### **0x19 - BoxSettings (Configuration Response)**  
```
Command: 0x19 (25 decimal)
Payload Size: Variable (JSON string)
Purpose: Current adapter configuration
Triggered by: Configuration query or update
```

**Example Response:**
```json
{
  "uuid": "12345678-1234-1234-1234-123456789abc",
  "MFD": "CarlinKit",
  "boxType": "CPC200-CCPA", 
  "productType": "A15W",
  "OemName": "AutoBox",
  "firmwareVersion": "2025.02.25.1521",
  "hardwareVersion": "1.0",
  "wifiMAC": "AA:BB:CC:DD:EE:FF",
  "bluetoothMAC": "AA:BB:CC:DD:EE:FE"
}
```

### **0x2A - MediaData (Media Metadata)**
```
Command: 0x2A (42 decimal)
Payload Size: Variable
Purpose: Media information and album art
```

### **0xCC - SwVer (Software Version)**
```
Command: 0xCC (204 decimal)  
Payload Size: 32 bytes
Purpose: Software/firmware version information
```

**Payload Structure:**
```
Offset | Size | Field        | Description
-------|------|--------------|-------------
0x00   | 18   | VersionStr   | Version string (ISO-8859-1)
0x12   | 1    | CodeChar     | Version code character
0x13   | 13   | Reserved     | Padding/reserved
```

**Example Version String:**
`"2025.02.25.1521\0\0A"`
- Version: `2025.02.25.1521`
- Code: `A`

---

## 4. CarPlay/iAP2 Extended Messages

### **Phone to Device (p2d)**

#### **0x4155 - CallStateUpd (Call State Update)**
```
Command: 0x4155
Purpose: Update call state information
```

#### **0x4E0D - WirelessCPUpd (Wireless CarPlay Update)**
```
Command: 0x4E0D  
Purpose: Wireless CarPlay session updates
```

#### **0x4E0E - TransNotify (Transport Notification)**
```
Command: 0x4E0E
Purpose: Transport layer notifications
```

#### **0x5001 - NowPlaying (Media Information)**
```
Command: 0x5001
Purpose: Current playing media information
```

#### **0x5702 - ReqWifiCfg (WiFi Configuration Request)**
```
Command: 0x5702
Purpose: Request WiFi configuration
```

#### **0xFFFA - StartLocInfo (Location Request)**
```
Command: 0xFFFA
Purpose: Request GPS/location information
```

### **Device to Phone (d2p)**

#### **0x5000 - StartNowPlayUpd (Initialize Media Updates)**
```
Command: 0x5000
Payload Size: 44 bytes
Purpose: Initialize now playing updates
```

#### **0x5703 - WifiCfgInfo (WiFi Configuration Response)**
```
Command: 0x5703
Payload Size: 44 bytes  
Purpose: WiFi configuration information
```

---

## 5. Android Auto Messages

### **0x16 - APScreenOpVideoConfig (Video Configuration)**
```
Command: 0x16 (22 decimal)
Purpose: Android Auto video configuration
```

### **0x56 - APScreenOpVideoConfig (Video Setup)**
```
Command: 0x56 (86 decimal)  
Purpose: Android Auto video setup
```

---

## 6. Message Construction Examples

### **Sending Session Open (0x01)**
```python
import struct

def create_open_message(width=800, height=480, fps=30):
    # Header
    magic = 0x55AA55AA
    length = 28
    command = 0x01
    checksum = command ^ 0xFFFFFFFF
    
    header = struct.pack('<IIII', magic, length, command, checksum)
    
    # Payload  
    payload = struct.pack('<IIIIIII',
        width,      # Display width
        height,     # Display height
        fps,        # Frame rate
        5,          # Format
        49152,      # Max packet (48KB)
        255,        # Version
        2           # Mode
    )
    
    return header + payload
```

### **Sending Heartbeat (0xAA)**
```python  
def create_heartbeat():
    magic = 0x55AA55AA
    length = 0
    command = 0xAA
    checksum = command ^ 0xFFFFFFFF
    
    return struct.pack('<IIII', magic, length, command, checksum)
```

### **Sending Touch Event (0x05)**
```python
def create_touch_event(action, x, y):
    # Header
    magic = 0x55AA55AA
    length = 16  
    command = 0x05
    checksum = command ^ 0xFFFFFFFF
    
    header = struct.pack('<IIII', magic, length, command, checksum)
    
    # Payload
    payload = struct.pack('<Ifff', action, x, y, 0)
    
    return header + payload
```

---

## 7. Message Flow Examples

### **Session Establishment Flow**
```
1. Host → Device: 0x01 Open (session parameters)
2. Device → Host: 0x02 Plugged (connection accepted)
3. Device → Host: 0xCC SwVer (version information)  
4. Device → Host: 0x19 BoxSettings (configuration)
5. Host → Device: 0xAA HeartBeat (every 2 seconds)
```

### **Touch Input Flow**
```
1. Host → Device: 0x05 Touch (TOUCH_DOWN, x, y)
2. Host → Device: 0x05 Touch (TOUCH_MOVE, x2, y2)
3. Host → Device: 0x05 Touch (TOUCH_UP, x2, y2)
```

### **Media Streaming Flow**
```
1. Device → Host: 0x06 VideoData (H.264 frame)
2. Device → Host: 0x07 AudioData (PCM samples)
3. Host → Device: 0x07 AudioData (microphone data)
```

### **Graceful Shutdown Flow**
```
1. Host → Device: 0x0F DiscPhone (disconnect session)
2. Device → Host: 0x04 Unplugged (acknowledgment)
3. Host → Device: 0x15 CloseDongle (shutdown adapter)
```

---

## 8. Error Handling

### **Invalid Message Detection**
```python
def validate_message(data):
    if len(data) < 16:
        return False, "Message too short"
    
    header = struct.unpack('<IIII', data[:16])
    magic, length, command, checksum = header
    
    if magic != 0x55AA55AA:
        return False, f"Invalid magic: 0x{magic:08X}"
    
    if checksum != (command ^ 0xFFFFFFFF):
        return False, f"Invalid checksum: 0x{checksum:08X}"
    
    if length > 1048576:
        return False, f"Payload too large: {length}"
    
    return True, "Valid"
```

### **Common Error Responses**
- **Invalid Command**: Device ignores unknown commands
- **Invalid Payload**: Device may disconnect
- **Missing Heartbeat**: Device disconnects after ~10 seconds
- **Invalid Session**: Device sends 0x04 Unplugged

---

## 9. Debugging and Analysis

### **Message Capture Commands**
```bash
# Capture USB traffic (requires root)
tcpdump -i usbmon1 -w capture.pcap

# Analyze with Wireshark custom dissector
wireshark capture.pcap

# Extract messages from AutoKit logs
adb logcat | grep -E "(0x55AA55AA|1437226410)"
```

### **Message Hex Dump Analysis**
```
Example captured message:
55 AA 55 AA 1C 00 00 00 01 00 00 00 FE FF FF FF
20 03 00 00 E0 01 00 00 1E 00 00 00 05 00 00 00  
00 C0 00 00 FF 00 00 00 02 00 00 00

Breakdown:
55 AA 55 AA = Magic (0x55AA55AA)
1C 00 00 00 = Length (28 bytes)
01 00 00 00 = Command (0x01 Open)
FE FF FF FF = Checksum (~0x01)
20 03 00 00 = Width (800)
E0 01 00 00 = Height (480)
1E 00 00 00 = FPS (30)
05 00 00 00 = Format (5)
00 C0 00 00 = PktMax (49152)
FF 00 00 00 = Version (255)  
02 00 00 00 = Mode (2)
```

This guide provides complete human-readable translations for all discovered CPC200-CCPA protocol messages, enabling developers to understand and implement compatible communication systems.
