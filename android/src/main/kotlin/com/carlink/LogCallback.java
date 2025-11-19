package com.carlink;

/**
   * Callback interface for logging messages from native Android components to the Flutter layer.
   *
   * This interface provides a decoupled logging mechanism that allows Java/Kotlin components
   * (such as H264Renderer and PacketRingByteBuffer) to send diagnostic messages without
   * direct coupling to Flutter's platform channel or logging system.
   *
   * The callback is typically implemented by CarlinkPlugin, which forwards log messages
   * to the Dart/Flutter logging infrastructure for unified application-wide logging.
   *
   * Usage example:
   * <pre>
   * LogCallback callback = message -> Log.d(TAG, message);
   * H264Renderer renderer = new H264Renderer(context, width, height, texture, id, callback);
   * </pre>
   */
public interface LogCallback {

    public void log(String message);
}
