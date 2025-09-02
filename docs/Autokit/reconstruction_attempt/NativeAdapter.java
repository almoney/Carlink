package com.xtour.audioprocess;

/**
 * JNI Interface for libAudioProcess.so - WebRTC-based Audio Processing
 * Reconstructed from native symbols and function signatures
 */
public class NativeAdapter {
    
    // Load the native library
    static {
        System.loadLibrary("AudioProcess");
    }
    
    /**
     * Initialize the WebRTC audio processing engine
     * @return status code (0 = success)
     */
    public native int initializeEngine();
    
    /**
     * Notify the engine to start audio processing
     * @return status code
     */
    public native int notifyStart();
    
    /**
     * Notify the engine to stop audio processing  
     * @return status code
     */
    public native int notifyStop();
    
    /**
     * Process audio data buffer
     * @param inputBuffer raw audio data input
     * @param outputBuffer processed audio data output
     * @param bufferSize size of audio buffer
     * @param sampleRate audio sample rate (e.g., 48000)
     * @param channels number of audio channels (1=mono, 2=stereo)
     * @return bytes processed or error code
     */
    public native int processData(byte[] inputBuffer, byte[] outputBuffer, 
                                 int bufferSize, int sampleRate, int channels);
    
    /**
     * Process single audio frame
     * @param inputFrame single frame of audio data
     * @param outputFrame processed frame output
     * @param frameSize size of audio frame
     * @return status code
     */
    public native int processDataSingle(byte[] inputFrame, byte[] outputFrame, int frameSize);
    
    /**
     * Get native library version string
     * @return version information
     */
    public native String stringFromJNI();
}