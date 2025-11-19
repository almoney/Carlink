/**
 * H264DecoderNative.h  
 * C++ Header for libopenH264decoder.so - OpenH264 Video Decoder
 * Reconstructed from native symbols and OpenH264 API
 */

#ifndef H264DECODER_NATIVE_H
#define H264DECODER_NATIVE_H

#include <jni.h>
#include <stdint.h>

// OpenH264 decoder structures (simplified)
struct SBufferInfo {
    int iBufferStatus;           // 0: one frame data is not ready; 1: one frame data is ready  
    unsigned long long uiInBsTimeStamp; // input bit stream timestamp
    unsigned long long uiOutYuvTimeStamp; // output yuv timestamp
    int iTemporalId;            // temporal ID
    int iNalCount;              // NAL count
    int iNalLengthInByte[128];  // NAL length array
};

struct SDecodingParam {
    char* pFileNameRestructed;   // file name of reconstructed frame used for PSNR calculation based debug
    unsigned int uiCpuLoad;      // CPU load  
    unsigned char uiTargetDqLayer; // Setting target dq layer id
    unsigned char uiErrorConMethod; // Error concealment method
    unsigned char uiEcActiveIdc;   // Whether active error concealment feature or not
    unsigned char bParseOnly;      // decoder for parse only, no reconstruction. When it is true, SPS/PPS size should not exceed SPS_PPS_BS_SIZE (128). Otherwise, it will return error info
    int sVideoProperty;           // video stream property
};

// H.264 decoder class
class H264Decoder {
private:
    void* decoder_handle_;        // OpenH264 decoder instance
    bool initialized_;
    int frame_width_;
    int frame_height_;
    
    // Decoded frame buffers
    uint8_t* yuv_buffer_;
    size_t yuv_buffer_size_;
    
    // Decoder parameters
    SDecodingParam decoding_param_;
    
public:
    H264Decoder();
    ~H264Decoder();
    
    // Initialize decoder
    int Initialize(int width, int height);
    
    // Destroy decoder and cleanup
    void Destroy();
    
    // Decode H.264 frame
    int DecodeFrame(const uint8_t* encoded_data, int encoded_size,
                   uint8_t* output_buffer, int output_size);
    
    // Decode frame with offset
    int DecodeFrameOffset(const uint8_t* encoded_data, int encoded_size, 
                         int offset, uint8_t* output_buffer, int output_size);
    
    // Get frame dimensions
    int GetWidth() const { return frame_width_; }
    int GetHeight() const { return frame_height_; }
    
    // Get YUV buffer info
    size_t GetYUVBufferSize() const;
    
private:
    // Internal helper methods
    int InitializeDecoder();
    void CleanupDecoder();
    int ProcessDecodedFrame(uint8_t** yuv_data, SBufferInfo* buffer_info,
                           uint8_t* output_buffer, int output_size);
};

// JNI function declarations
extern "C" {
    
    /**
     * Initialize the H.264 decoder
     * Java signature: (II)I
     */
    JNIEXPORT jint JNICALL
    Java_cn_manstep_phonemirrorBox_OpenH264Decoder_nativeInit(JNIEnv* env, jobject thiz,
        jint width, jint height);
    
    /**
     * Destroy the decoder
     * Java signature: ()V
     */
    JNIEXPORT void JNICALL
    Java_cn_manstep_phonemirrorBox_OpenH264Decoder_nativeDestroy(JNIEnv* env, jobject thiz);
    
    /**
     * Decode H.264 frame
     * Java signature: ([BI[BI)I
     */
    JNIEXPORT jint JNICALL
    Java_cn_manstep_phonemirrorBox_OpenH264Decoder_decodeFrame(JNIEnv* env, jobject thiz,
        jbyteArray encoded_data, jint encoded_size, 
        jbyteArray output_buffer, jint output_size);
    
    /**
     * Decode frame with offset
     * Java signature: ([BII[BI)I  
     */
    JNIEXPORT jint JNICALL
    Java_cn_manstep_phonemirrorBox_OpenH264Decoder_decodeFrameOffset(JNIEnv* env, jobject thiz,
        jbyteArray encoded_data, jint encoded_size, jint offset,
        jbyteArray output_buffer, jint output_size);
    
    /**
     * Get decoded frame width
     * Java signature: ()I
     */
    JNIEXPORT jint JNICALL
    Java_cn_manstep_phonemirrorBox_OpenH264Decoder_getWidth(JNIEnv* env, jobject thiz);
    
    /**
     * Get decoded frame height
     * Java signature: ()I
     */
    JNIEXPORT jint JNICALL
    Java_cn_manstep_phonemirrorBox_OpenH264Decoder_getHeight(JNIEnv* env, jobject thiz);
}

// OpenH264 API functions (from symbols)
extern "C" {
    // Decoder creation and destruction
    int WelsCreateDecoder(void** ppDecoder);
    void WelsDestroyDecoder(void* pDecoder);
    
    // Decoder initialization
    long WelsInitDecoder(void* pDecoder, const SDecodingParam* pParam);
    long WelsUninitDecoder(void* pDecoder);
    
    // Frame decoding
    int DecodeFrame2(void* pDecoder, 
                    const unsigned char* pSrc, const int iSrcLen,
                    unsigned char** ppDst, SBufferInfo* pDstInfo);
    
    // Decoder configuration
    long SetOption(void* pDecoder, int eOptionId, void* pOption);
    long GetOption(void* pDecoder, int eOptionId, void* pOption);
}

// Utility functions
namespace {
    // Convert NAL units for decoder
    int ConvertAnnexBToNALU(const uint8_t* annexb_data, int annexb_size,
                           uint8_t* nalu_data, int* nalu_size);
    
    // YUV format conversion
    void ConvertYUV420ToRGB(const uint8_t* yuv_data, int width, int height,
                           uint8_t* rgb_data);
    
    // Frame validation
    bool IsValidH264Frame(const uint8_t* data, int size);
    
    // Error handling
    const char* GetDecoderErrorString(int error_code);
}

// Error codes
#define H264_SUCCESS                0
#define H264_ERROR_INIT_FAILED     -1
#define H264_ERROR_INVALID_PARAM   -2
#define H264_ERROR_DECODE_FAILED   -3
#define H264_ERROR_NO_MEMORY       -4
#define H264_ERROR_INVALID_FRAME   -5

// Frame format constants
#define YUV420P_PLANES             3
#define H264_MAX_WIDTH            4096
#define H264_MAX_HEIGHT           2160
#define H264_MIN_WIDTH             16
#define H264_MIN_HEIGHT            16

#endif // H264DECODER_NATIVE_H