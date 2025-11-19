package com.carlink;

/**
   * Immutable container for a complete CPC200-CCPA protocol message.
   *
   * <p>This class represents a fully parsed protocol message consisting of a 16-byte
   * header and variable-length payload data. Messages are received from the CPC200-CCPA
   * adapter over USB and contain various data types including video frames, audio packets,
   * and control commands for Android Auto/CarPlay projection.
   *
   * <p>The header ({@link CarLinkMessageHeader}) provides message metadata (type, length,
   * checksums), while the data buffer contains the actual payload. Both fields are final
   * and immutable for thread-safe usage across the plugin's communication pipeline.
   *
   * <p>Typical usage:
   * <pre>{@code
   * // Parse header from USB stream
   * CarLinkMessageHeader header = CarLinkMessageHeader.parseFrom(headerBuffer);
   * // Read payload based on header length
   * ByteBuffer payload = readPayload(header.getLength());
   * // Create complete message
   * CarLinkMessage message = new CarLinkMessage(header, payload);
   * }</pre>
   *
   * @see CarLinkMessageHeader
   * @since API 32
   */
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public class CarLinkMessage {
    public final CarLinkMessageHeader header;
    public final ByteBuffer data;

    public CarLinkMessage(CarLinkMessageHeader header, ByteBuffer data){
        this.header = header;
        this.data = data;
    }
}
