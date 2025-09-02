package cn.manstep.phonemirrorBox;

/**
 * JNI Interface for libopenH264decoder.so - H.264 Video Decoder
 * Reconstructed from native symbols and function signatures
 */
public class OpenH264Decoder {
    
    // Native decoder handle
    private long nativeHandle = 0;
    
    // Load the native library
    static {
        System.loadLibrary("openH264decoder");
    }
    
    /**
     * Initialize the H.264 decoder
     * @param width expected frame width
     * @param height expected frame height
     * @return status code (0 = success, negative = error)
     */
    public native int nativeInit(int width, int height);
    
    /**
     * Destroy the decoder and free resources
     */
    public native void nativeDestroy();
    
    /**
     * Decode H.264 frame data
     * @param encodedData H.264 encoded frame data
     * @param encodedSize size of encoded data
     * @param outputBuffer YUV output buffer (YUV420P format)
     * @param outputSize size of output buffer
     * @return decoded frame size or error code
     */
    public native int decodeFrame(byte[] encodedData, int encodedSize, 
                                 byte[] outputBuffer, int outputSize);
    
    /**
     * Decode H.264 frame with offset
     * @param encodedData H.264 encoded frame data
     * @param encodedSize size of encoded data
     * @param offset offset in encoded data
     * @param outputBuffer YUV output buffer
     * @param outputSize size of output buffer
     * @return decoded frame size or error code
     */
    public native int decodeFrameOffset(byte[] encodedData, int encodedSize, int offset,
                                       byte[] outputBuffer, int outputSize);
    
    /**
     * Get decoded frame width
     * @return frame width in pixels
     */
    public native int getWidth();
    
    /**
     * Get decoded frame height
     * @return frame height in pixels  
     */
    public native int getHeight();
    
    // Java wrapper methods
    public boolean initialize(int width, int height) {
        return nativeInit(width, height) == 0;
    }
    
    public void destroy() {
        if (nativeHandle != 0) {
            nativeDestroy();
            nativeHandle = 0;
        }
    }
    
    public int decode(byte[] h264Data, byte[] yuvOutput) {
        if (h264Data == null || yuvOutput == null) {
            return -1;
        }
        return decodeFrame(h264Data, h264Data.length, yuvOutput, yuvOutput.length);
    }
}