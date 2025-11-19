/**
 * AudioProcessNative.h
 * C++ Header for libAudioProcess.so - WebRTC Audio Processing Engine
 * Reconstructed from native symbols and WebRTC function signatures
 */

#ifndef AUDIOPROCESS_NATIVE_H
#define AUDIOPROCESS_NATIVE_H

#include <jni.h>
#include <stdint.h>

// WebRTC includes (inferred from symbols)
namespace webrtc {
    class AudioFrame;
    class AudioBuffer;
    class AudioProcessing;
    class EchoCancellation;
    class NoiseSuppression; 
    class GainControl;
}

// Audio processing engine class
class AudioProcessEngine {
private:
    webrtc::AudioProcessing* audio_processing_;
    webrtc::AudioBuffer* audio_buffer_;
    bool initialized_;
    bool started_;
    
    // Audio parameters
    int sample_rate_;
    int channels_;
    int frames_per_buffer_;
    
public:
    AudioProcessEngine();
    ~AudioProcessEngine();
    
    // Initialize the WebRTC audio processing engine
    int Initialize(int sample_rate = 48000, int channels = 1);
    
    // Start/stop audio processing
    int Start();
    int Stop();
    
    // Process audio data
    int ProcessData(const uint8_t* input_data, uint8_t* output_data, 
                   size_t buffer_size, int sample_rate, int channels);
    
    // Process single audio frame
    int ProcessFrame(const uint8_t* input_frame, uint8_t* output_frame, 
                    size_t frame_size);
    
    // Configuration methods
    void EnableEchoCancellation(bool enable);
    void EnableNoiseSuppression(bool enable);
    void EnableGainControl(bool enable);
    
    // Utility methods
    bool IsInitialized() const { return initialized_; }
    bool IsStarted() const { return started_; }
    const char* GetVersionString() const;
};

// Global engine instance
extern AudioProcessEngine* g_audio_engine;

// JNI function declarations
extern "C" {
    
    /**
     * Initialize the WebRTC audio processing engine
     * Java signature: ()I
     */
    JNIEXPORT jint JNICALL
    Java_com_xtour_audioprocess_NativeAdapter_initializeEngine(JNIEnv* env, jobject thiz);
    
    /**
     * Notify the engine to start processing
     * Java signature: ()I
     */
    JNIEXPORT jint JNICALL
    Java_com_xtour_audioprocess_NativeAdapter_notifyStart(JNIEnv* env, jobject thiz);
    
    /**
     * Notify the engine to stop processing
     * Java signature: ()I
     */
    JNIEXPORT jint JNICALL
    Java_com_xtour_audioprocess_NativeAdapter_notifyStop(JNIEnv* env, jobject thiz);
    
    /**
     * Process audio data buffer
     * Java signature: ([B[BIII)I
     */
    JNIEXPORT jint JNICALL
    Java_com_xtour_audioprocess_NativeAdapter_processData(JNIEnv* env, jobject thiz,
        jbyteArray input_buffer, jbyteArray output_buffer, 
        jint buffer_size, jint sample_rate, jint channels);
    
    /**
     * Process single audio frame
     * Java signature: ([B[BI)I
     */
    JNIEXPORT jint JNICALL
    Java_com_xtour_audioprocess_NativeAdapter_processDataSingle(JNIEnv* env, jobject thiz,
        jbyteArray input_frame, jbyteArray output_frame, jint frame_size);
    
    /**
     * Get version string
     * Java signature: ()Ljava/lang/String;
     */
    JNIEXPORT jstring JNICALL
    Java_com_xtour_audioprocess_NativeAdapter_stringFromJNI(JNIEnv* env, jobject thiz);
}

// WebRTC AEC (Acoustic Echo Cancellation) functions
extern "C" {
    void* WebRtcAec_Create();
    int WebRtcAec_Init(void* aec_inst, int sample_freq, int scSampFreq);
    void WebRtcAec_Free(void* aec_inst);
    int WebRtcAec_BufferFarend(void* aec_inst, const float* farend, size_t nrOfSamples);
    int WebRtcAec_Process(void* aec_inst, const float* const* nearend, 
                         size_t num_bands, float* const* out, size_t nrOfSamples,
                         int16_t msInSndCardBuf, int32_t skew);
}

// Audio buffer utilities
namespace {
    // Convert Java byte array to native audio data
    void ConvertJavaToNative(JNIEnv* env, jbyteArray java_array, 
                           uint8_t** native_data, size_t* data_size);
    
    // Convert native audio data to Java byte array
    jbyteArray ConvertNativeToJava(JNIEnv* env, const uint8_t* native_data, 
                                  size_t data_size);
    
    // Audio format conversion utilities
    void ConvertS16ToFloat(const int16_t* src, float* dst, size_t samples);
    void ConvertFloatToS16(const float* src, int16_t* dst, size_t samples);
}

// Error codes
#define AUDIO_SUCCESS           0
#define AUDIO_ERROR_INIT       -1
#define AUDIO_ERROR_NOT_INIT   -2
#define AUDIO_ERROR_INVALID    -3
#define AUDIO_ERROR_PROCESSING -4

#endif // AUDIOPROCESS_NATIVE_H