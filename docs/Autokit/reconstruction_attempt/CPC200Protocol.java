package cn.manstep.phonemirror.protocol;

import cn.manstep.phonemirror.connection.ConnectionNative;

/**
 * CPC200-CCPA Protocol Implementation
 * Reconstructed from BoxHelper deobfuscation analysis
 * Handles communication with Carlinkit CPC200-CCPA devices
 */
public class CPC200Protocol {
    
    // USB Device Identifiers
    public static final int CARLINKIT_VENDOR_ID = 0x1314;  // 4884 decimal
    public static final int CPC200_PRODUCT_ID = 0x1520;   // Common CPC200 product ID
    
    // Protocol Constants
    public static final int PROTOCOL_MAGIC = 0x55AA55AA;  // 1437226410 decimal
    public static final int HEADER_SIZE = 16;
    public static final int MAX_PACKET_SIZE = 8192;
    
    // Command Types
    public static final byte CMD_SESSION = 0x01;
    public static final byte CMD_HEARTBEAT = (byte) 0xAA;
    public static final byte CMD_BOX_SETTINGS = 0x19;
    public static final byte CMD_SOFTWARE_VERSION = (byte) 0xCC;
    
    // Session Configuration
    private int sessionWidth = 1920;
    private int sessionHeight = 1080;
    private int sessionFPS = 60;
    private int sessionFormat = 1;  // H.264
    private int maxPacketSize = 8192;
    private int protocolVersion = 1;
    
    private long deviceHandle = -1;
    private boolean connected = false;
    
    /**
     * Initialize connection to CPC200-CCPA device
     * @return true if connection successful
     */
    public boolean connect() {
        // Initialize USB subsystem
        if (ConnectionNative.initializeUSB() != 0) {
            return false;
        }
        
        // Open device
        deviceHandle = ConnectionNative.openDevice(CARLINKIT_VENDOR_ID, CPC200_PRODUCT_ID);
        if (deviceHandle < 0) {
            return false;
        }
        
        // Claim interface 0
        if (ConnectionNative.claimInterface(deviceHandle, 0) != 0) {
            ConnectionNative.closeDevice(deviceHandle);
            return false;
        }
        
        connected = true;
        return true;
    }
    
    /**
     * Disconnect from CPC200-CCPA device
     */
    public void disconnect() {
        if (connected && deviceHandle >= 0) {
            ConnectionNative.releaseInterface(deviceHandle, 0);
            ConnectionNative.closeDevice(deviceHandle);
            ConnectionNative.shutdownUSB();
            connected = false;
        }
    }
    
    /**
     * Send session initialization command
     * @return true if successful
     */
    public boolean initializeSession() {
        if (!connected) return false;
        
        byte[] sessionData = createSessionPacket();
        return sendPacket(CMD_SESSION, sessionData);
    }
    
    /**
     * Send heartbeat to keep connection alive
     * @return true if successful
     */
    public boolean sendHeartbeat() {
        if (!connected) return false;
        
        byte[] heartbeat = new byte[0]; // Empty payload for heartbeat
        return sendPacket(CMD_HEARTBEAT, heartbeat);
    }
    
    /**
     * Send box settings configuration
     * @param settings configuration data
     * @return true if successful
     */
    public boolean sendBoxSettings(byte[] settings) {
        if (!connected) return false;
        
        return sendPacket(CMD_BOX_SETTINGS, settings);
    }
    
    /**
     * Request software version information
     * @return version data or null on error
     */
    public byte[] getSoftwareVersion() {
        if (!connected) return null;
        
        if (sendPacket(CMD_SOFTWARE_VERSION, new byte[0])) {
            return receivePacket();
        }
        return null;
    }
    
    /**
     * Create session configuration packet (28 bytes)
     */
    private byte[] createSessionPacket() {
        byte[] packet = new byte[28];
        int offset = 0;
        
        // Write session parameters in little-endian format
        writeInt32LE(packet, offset, sessionWidth); offset += 4;
        writeInt32LE(packet, offset, sessionHeight); offset += 4;
        writeInt32LE(packet, offset, sessionFPS); offset += 4;
        writeInt32LE(packet, offset, sessionFormat); offset += 4;
        writeInt32LE(packet, offset, maxPacketSize); offset += 4;
        writeInt32LE(packet, offset, protocolVersion); offset += 4;
        writeInt32LE(packet, offset, 0); // Reserved field
        
        return packet;
    }
    
    /**
     * Send protocol packet with header
     */
    private boolean sendPacket(byte command, byte[] payload) {
        byte[] header = new byte[HEADER_SIZE];
        int offset = 0;
        
        // Protocol magic number
        writeInt32LE(header, offset, PROTOCOL_MAGIC); offset += 4;
        
        // Command
        header[offset++] = command;
        
        // Payload length
        writeInt32LE(header, offset, payload.length); offset += 4;
        
        // Padding/reserved
        while (offset < HEADER_SIZE) {
            header[offset++] = 0;
        }
        
        // Send header
        if (ConnectionNative.bulkTransfer(deviceHandle, 0x01, header, header.length, 5000) != header.length) {
            return false;
        }
        
        // Send payload if present
        if (payload.length > 0) {
            return ConnectionNative.bulkTransfer(deviceHandle, 0x01, payload, payload.length, 5000) == payload.length;
        }
        
        return true;
    }
    
    /**
     * Receive protocol packet
     */
    private byte[] receivePacket() {
        byte[] header = new byte[HEADER_SIZE];
        
        // Receive header
        if (ConnectionNative.bulkTransfer(deviceHandle, 0x81, header, header.length, 5000) != header.length) {
            return null;
        }
        
        // Parse header
        int magic = readInt32LE(header, 0);
        if (magic != PROTOCOL_MAGIC) {
            return null;
        }
        
        int payloadLength = readInt32LE(header, 8);
        if (payloadLength <= 0 || payloadLength > MAX_PACKET_SIZE) {
            return payloadLength == 0 ? new byte[0] : null;
        }
        
        // Receive payload
        byte[] payload = new byte[payloadLength];
        if (ConnectionNative.bulkTransfer(deviceHandle, 0x81, payload, payload.length, 5000) != payload.length) {
            return null;
        }
        
        return payload;
    }
    
    // Utility methods for little-endian byte operations
    private void writeInt32LE(byte[] buffer, int offset, int value) {
        buffer[offset] = (byte)(value & 0xFF);
        buffer[offset + 1] = (byte)((value >> 8) & 0xFF);
        buffer[offset + 2] = (byte)((value >> 16) & 0xFF);  
        buffer[offset + 3] = (byte)((value >> 24) & 0xFF);
    }
    
    private int readInt32LE(byte[] buffer, int offset) {
        return (buffer[offset] & 0xFF) |
               ((buffer[offset + 1] & 0xFF) << 8) |
               ((buffer[offset + 2] & 0xFF) << 16) |
               ((buffer[offset + 3] & 0xFF) << 24);
    }
    
    // Getters and setters for session configuration
    public void setSessionResolution(int width, int height) {
        this.sessionWidth = width;
        this.sessionHeight = height;
    }
    
    public void setSessionFPS(int fps) {
        this.sessionFPS = fps;
    }
    
    public boolean isConnected() {
        return connected;
    }
}