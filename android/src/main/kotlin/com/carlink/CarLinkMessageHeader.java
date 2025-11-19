package com.carlink;

/**
 * PURPOSE:
 * This class is the gatekeeper for all CPC200-CCPA adapter communication. Every message
 * exchanged between the Android device and the CarPlay/Android Auto adapter begins with
 * this 16-byte header. It ensures data integrity by validating the protocol's magic number
 * and checksum, extracts the payload type and length, and enables the app to distinguish
 * between control commands (handshake, heartbeat) and media streams (H.264 video).
 * Without valid header parsing, the adapter communication chain breaks entirely.
 *
 * ROLE IN PROJECT:
 * - Entry point for all incoming adapter messages before payload processing
 * - Prevents corrupted/malicious data from reaching video decoders or control logic
 * - Works with PacketRingByteBuffer to frame variable-length messages from USB stream
 * - Used by AdapterDriver to route messages to appropriate handlers (video/audio/control)
 *
 * CPC200-CCPA protocol communication, following the format:
 * - Magic: 0x55AA55AA (4 bytes)
 * - Length: Payload size (4 bytes)
 * - Type: Message type (4 bytes)
 * - Checksum: Type XOR 0xFFFFFFFF (4 bytes)
 * 
 * Immutable representation of a CPC200-CCPA protocol message header.
 * ...
 */
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Objects;

public final class CarLinkMessageHeader {

      /** Standard message header length in bytes */
      public static final int MESSAGE_LENGTH = 16;

      /** Protocol magic number identifier */
      private static final int MAGIC = 0x55AA55AA;

      /** Video data message type identifier */
      private static final int VIDEO_DATA_TYPE = 6;

      /** Mask for unsigned 32-bit integer operations */
      private static final long UNSIGNED_INT_MASK = 0xFFFFFFFFL;

      // Immutable fields for thread safety
      private final int length;
      private final int type;

      /**
       * Constructs a new CarLinkMessageHeader with specified parameters.
       *
       * @param length the payload length in bytes (must be >= 0)
       * @param type the message type identifier
       * @throws IllegalArgumentException if length is negative
       */
      public CarLinkMessageHeader(int length, int type) {
          if (length < 0) {
              throw new IllegalArgumentException("Length cannot be negative: " + length);
          }
          this.length = length;
          this.type = type;
      }

      /**
       * Creates a CarLinkMessageHeader by parsing data from a ByteBuffer.
       *
       * <p>This method expects exactly 16 bytes of data in little-endian format.
       * The buffer position will be advanced by 16 bytes upon successful parsing.
       *
       * @param buffer the ByteBuffer containing header data (must not be null)
       * @return a new CarLinkMessageHeader instance
       * @throws IllegalArgumentException if buffer is null or doesn't contain exactly 16 bytes
       * @throws ProtocolException if header validation fails
       */
      public static CarLinkMessageHeader parseFrom(ByteBuffer buffer) throws ProtocolException {
          Objects.requireNonNull(buffer, "Buffer cannot be null");

          if (buffer.remaining() < MESSAGE_LENGTH) {
              throw new IllegalArgumentException(
                  String.format("Insufficient buffer data - Expected %d bytes, got %d",
                              MESSAGE_LENGTH, buffer.remaining()));
          }

          // Create a slice to avoid modifying original buffer's position/order
          ByteBuffer slice = buffer.slice();
          slice.limit(MESSAGE_LENGTH);
          slice.order(ByteOrder.LITTLE_ENDIAN);
          buffer.position(buffer.position() + MESSAGE_LENGTH);

          try {
              int magic = slice.getInt();
              if (magic != MAGIC) {
                  throw new ProtocolException(
                      String.format("Invalid protocol magic - Expected 0x%08X, received 0x%08X",
                                  MAGIC, magic));
              }

              int length = slice.getInt();
              int type = slice.getInt();
              int typeCheck = slice.getInt();

              // Validate checksum using proper unsigned arithmetic
              long expectedChecksum = (~type) & UNSIGNED_INT_MASK;
              long actualChecksum = typeCheck & UNSIGNED_INT_MASK;

              if (actualChecksum != expectedChecksum) {
                  throw new ProtocolException(
                      String.format("Invalid header checksum - Expected 0x%08X, received 0x%08X",
                                  expectedChecksum, actualChecksum));
              }

              return new CarLinkMessageHeader(length, type);

          } catch (java.nio.BufferUnderflowException e) {
              throw new ProtocolException("Unexpected end of buffer while parsing header", e);
          }
      }

      /**
       * Checks if this header represents a video data message.
       *
       * @return true if this is a video data message (type 6), false otherwise
       */
      public boolean isVideoData() {
          return type == VIDEO_DATA_TYPE;
      }

      /**
       * Returns the payload length.
       *
       * @return the payload length in bytes (always >= 0)
       */
      public int getLength() {
          return length;
      }

      /**
       * Returns the message type identifier.
       *
       * @return the message type
       */
      public int getType() {
          return type;
      }

      @Override
      public boolean equals(Object obj) {
          if (this == obj) return true;
          if (obj == null || getClass() != obj.getClass()) return false;

          CarLinkMessageHeader that = (CarLinkMessageHeader) obj;
          return length == that.length && type == that.type;
      }

      @Override
      public int hashCode() {
          return Objects.hash(length, type);
      }

      @Override
      public String toString() {
          return String.format("CarLinkMessageHeader{type=0x%02X, length=%d, isVideo=%s}",
                             type, length, isVideoData());
      }

      /**
       * Custom exception for CPC200-CCPA protocol violations.
       *
       * <p>This checked exception is thrown when header parsing or validation fails,
       * indicating malformed or corrupted protocol data.
       */
      public static final class ProtocolException extends Exception {

          private static final long serialVersionUID = 1L;

          /**
           * Constructs a ProtocolException with the specified message.
           *
           * @param message the detail message
           */
          public ProtocolException(String message) {
              super(message);
          }

          /**
           * Constructs a ProtocolException with the specified message and cause.
           *
           * @param message the detail message
           * @param cause the underlying cause
           */
          public ProtocolException(String message, Throwable cause) {
              super(message, cause);
          }
      }
  }
