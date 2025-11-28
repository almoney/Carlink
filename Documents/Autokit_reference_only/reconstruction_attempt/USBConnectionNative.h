/**
 * USBConnectionNative.h
 * C++ Header for libconnection.so - USB Communication Library  
 * Reconstructed from libusb symbols and CPC200-CCPA protocol analysis
 */

#ifndef USB_CONNECTION_NATIVE_H
#define USB_CONNECTION_NATIVE_H

#include <jni.h>
#include <stdint.h>
#include <libusb-1.0/libusb.h>

// Forward declarations
struct libusb_context;
struct libusb_device;
struct libusb_device_handle; 
struct libusb_transfer;

// USB device constants
#define CARLINKIT_VENDOR_ID     0x1314  // 4884 decimal
#define CPC200_PRODUCT_ID       0x1520  // Common CPC200 product ID
#define USB_INTERFACE_NUMBER    0
#define USB_ENDPOINT_IN         0x81    // Bulk IN endpoint
#define USB_ENDPOINT_OUT        0x01    // Bulk OUT endpoint
#define USB_TIMEOUT_MS          5000

// Transfer buffer sizes
#define USB_MAX_PACKET_SIZE     8192
#define USB_CONTROL_BUFFER_SIZE 256

// USB connection manager class
class USBConnectionManager {
private:
    libusb_context* usb_context_;
    libusb_device_handle* device_handle_;
    libusb_device** device_list_;
    
    bool initialized_;
    bool connected_;
    
    // Device info
    int vendor_id_;
    int product_id_;
    int interface_number_;
    
    // Transfer management
    libusb_transfer* async_transfer_;
    bool async_mode_;
    
public:
    USBConnectionManager();
    ~USBConnectionManager();
    
    // USB subsystem lifecycle
    int Initialize();
    void Shutdown();
    
    // Device management
    libusb_device_handle* OpenDevice(int vendor_id, int product_id);
    void CloseDevice(libusb_device_handle* handle);
    
    // Interface management
    int ClaimInterface(libusb_device_handle* handle, int interface_number);
    int ReleaseInterface(libusb_device_handle* handle, int interface_number);
    
    // Data transfer
    int BulkTransfer(libusb_device_handle* handle, unsigned char endpoint,
                    unsigned char* data, int length, int timeout);
    
    int ControlTransfer(libusb_device_handle* handle, 
                       uint8_t request_type, uint8_t request,
                       uint16_t value, uint16_t index,
                       unsigned char* data, uint16_t length, int timeout);
    
    // Kernel driver management
    int IsKernelDriverActive(libusb_device_handle* handle, int interface_number);
    int DetachKernelDriver(libusb_device_handle* handle, int interface_number);
    int AttachKernelDriver(libusb_device_handle* handle, int interface_number);
    
    // Device enumeration
    int GetDeviceList(libusb_device*** device_list);
    void FreeDeviceList(libusb_device** device_list, int unref_devices);
    
    // Device info
    int GetDeviceDescriptor(libusb_device_handle* handle, 
                           struct libusb_device_descriptor* desc);
    
    // Endpoint management
    int ClearHalt(libusb_device_handle* handle, unsigned char endpoint);
    int ResetDevice(libusb_device_handle* handle);
    
    // Async transfers
    int SubmitAsyncTransfer(libusb_device_handle* handle, 
                           unsigned char endpoint, unsigned char* buffer,
                           int length, libusb_transfer_cb_fn callback, 
                           void* user_data, int timeout);
    
    // Error handling
    const char* GetErrorName(int error_code);
    const char* GetErrorString(int error_code);
};

// Global USB manager instance
extern USBConnectionManager* g_usb_manager;

// JNI callback functions
extern "C" {
    
    /**
     * Called when native library is loaded
     */
    JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved);
    
    /**
     * Called when native library is unloaded
     */
    JNIEXPORT void JNICALL JNI_OnUnLoad(JavaVM* vm, void* reserved);
}

// Libusb function wrappers (matching symbols found)
extern "C" {
    
    // Context management
    int libusb_init(libusb_context** ctx);
    void libusb_exit(libusb_context* ctx);
    
    // Device management
    ssize_t libusb_get_device_list(libusb_context* ctx, libusb_device*** list);
    void libusb_free_device_list(libusb_device** list, int unref_devices);
    int libusb_open(libusb_device* dev, libusb_device_handle** dev_handle);
    void libusb_close(libusb_device_handle* dev_handle);
    
    // Interface management
    int libusb_claim_interface(libusb_device_handle* dev_handle, int interface_number);
    int libusb_release_interface(libusb_device_handle* dev_handle, int interface_number);
    
    // Data transfers
    int libusb_bulk_transfer(libusb_device_handle* dev_handle,
                            unsigned char endpoint, unsigned char* data,
                            int length, int* actual_length, unsigned int timeout);
    
    int libusb_control_transfer(libusb_device_handle* dev_handle,
                               uint8_t request_type, uint8_t bRequest,
                               uint16_t wValue, uint16_t wIndex,
                               unsigned char* data, uint16_t wLength,
                               unsigned int timeout);
    
    // Kernel driver management
    int libusb_kernel_driver_active(libusb_device_handle* dev_handle, int interface_number);
    int libusb_detach_kernel_driver(libusb_device_handle* dev_handle, int interface_number);
    int libusb_attach_kernel_driver(libusb_device_handle* dev_handle, int interface_number);
    
    // Device descriptors
    int libusb_get_device_descriptor(libusb_device* dev, 
                                   struct libusb_device_descriptor* desc);
    int libusb_get_config_descriptor(libusb_device* dev, uint8_t config_index,
                                   struct libusb_config_descriptor** config);
    void libusb_free_config_descriptor(struct libusb_config_descriptor* config);
    
    // Endpoint management
    int libusb_clear_halt(libusb_device_handle* dev_handle, unsigned char endpoint);
    int libusb_reset_device(libusb_device_handle* dev_handle);
    
    // Error handling
    const char* libusb_error_name(int errcode);
    const char* libusb_strerror(enum libusb_error errcode);
    
    // Event handling
    int libusb_handle_events(libusb_context* ctx);
    int libusb_handle_events_timeout(libusb_context* ctx, struct timeval* tv);
    
    // Transfer management  
    struct libusb_transfer* libusb_alloc_transfer(int iso_packets);
    void libusb_free_transfer(struct libusb_transfer* transfer);
    int libusb_submit_transfer(struct libusb_transfer* transfer);
    int libusb_cancel_transfer(struct libusb_transfer* transfer);
}

// USB device filtering
namespace {
    // Check if device matches Carlinkit VID/PID
    bool IsCarlinKitDevice(const struct libusb_device_descriptor& desc);
    
    // Validate device has expected interface configuration
    bool ValidateDeviceConfiguration(libusb_device_handle* handle);
    
    // Get device string descriptors
    int GetDeviceStrings(libusb_device_handle* handle, 
                        char* manufacturer, char* product, char* serial);
}

// Protocol integration
class CPC200ProtocolHandler {
private:
    USBConnectionManager* usb_manager_;
    libusb_device_handle* device_handle_;
    
public:
    CPC200ProtocolHandler(USBConnectionManager* manager);
    ~CPC200ProtocolHandler();
    
    // High-level protocol operations
    bool ConnectToCPC200Device();
    void DisconnectFromDevice();
    
    bool SendProtocolPacket(uint8_t command, const uint8_t* payload, int length);
    int ReceiveProtocolPacket(uint8_t* buffer, int buffer_size, int timeout_ms);
    
    // CPC200-specific commands
    bool InitializeSession(int width, int height, int fps);
    bool SendHeartbeat();
    bool RequestDeviceInfo();
};

// Error codes
#define USB_SUCCESS                 0
#define USB_ERROR_INIT_FAILED      -1
#define USB_ERROR_DEVICE_NOT_FOUND -2
#define USB_ERROR_ACCESS_DENIED    -3  
#define USB_ERROR_TRANSFER_FAILED  -4
#define USB_ERROR_TIMEOUT          -5
#define USB_ERROR_INVALID_PARAM    -6

#endif // USB_CONNECTION_NATIVE_H