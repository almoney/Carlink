package cn.manstep.phonemirror.connection;

/**
 * JNI Interface for libconnection.so - USB Communication Library
 * Reconstructed from native symbols - Uses libusb for USB device communication
 * This handles CPC200-CCPA protocol communication with Carlinkit devices
 */
public class ConnectionNative {
    
    // Load the native library
    static {
        System.loadLibrary("connection");
    }
    
    // Native library lifecycle (JNI_OnLoad/JNI_OnUnLoad are called automatically)
    
    /**
     * Initialize USB subsystem
     * @return status code (0 = success)
     */
    public static native int initializeUSB();
    
    /**
     * Shutdown USB subsystem and cleanup resources
     */
    public static native void shutdownUSB();
    
    /**
     * Open USB device by vendor/product ID
     * @param vendorId USB vendor ID (e.g., 0x1314 for Carlinkit)
     * @param productId USB product ID
     * @return device handle or negative error code
     */
    public static native long openDevice(int vendorId, int productId);
    
    /**
     * Close USB device
     * @param deviceHandle handle from openDevice()
     */
    public static native void closeDevice(long deviceHandle);
    
    /**
     * Claim USB interface for exclusive access
     * @param deviceHandle USB device handle
     * @param interfaceNumber interface to claim (usually 0)
     * @return status code (0 = success)
     */
    public static native int claimInterface(long deviceHandle, int interfaceNumber);
    
    /**
     * Release USB interface
     * @param deviceHandle USB device handle  
     * @param interfaceNumber interface to release
     * @return status code
     */
    public static native int releaseInterface(long deviceHandle, int interfaceNumber);
    
    /**
     * Perform bulk USB transfer
     * @param deviceHandle USB device handle
     * @param endpoint endpoint address (0x81 for IN, 0x01 for OUT)
     * @param data data buffer
     * @param length data length
     * @param timeout timeout in milliseconds
     * @return bytes transferred or negative error code
     */
    public static native int bulkTransfer(long deviceHandle, int endpoint, 
                                         byte[] data, int length, int timeout);
    
    /**
     * Perform control USB transfer
     * @param deviceHandle USB device handle
     * @param requestType request type flags
     * @param request request code
     * @param value wValue parameter
     * @param index wIndex parameter  
     * @param data data buffer
     * @param length data length
     * @param timeout timeout in milliseconds
     * @return bytes transferred or negative error code
     */
    public static native int controlTransfer(long deviceHandle, int requestType, 
                                           int request, int value, int index,
                                           byte[] data, int length, int timeout);
    
    /**
     * Check if kernel driver is active on interface
     * @param deviceHandle USB device handle
     * @param interfaceNumber interface number
     * @return 1 if active, 0 if not active, negative on error
     */
    public static native int isKernelDriverActive(long deviceHandle, int interfaceNumber);
    
    /**
     * Detach kernel driver from interface
     * @param deviceHandle USB device handle
     * @param interfaceNumber interface number
     * @return status code (0 = success)
     */
    public static native int detachKernelDriver(long deviceHandle, int interfaceNumber);
    
    /**
     * Attach kernel driver to interface
     * @param deviceHandle USB device handle
     * @param interfaceNumber interface number
     * @return status code (0 = success)  
     */
    public static native int attachKernelDriver(long deviceHandle, int interfaceNumber);
    
    /**
     * Get USB device descriptor
     * @param deviceHandle USB device handle
     * @return descriptor data or null on error
     */
    public static native byte[] getDeviceDescriptor(long deviceHandle);
    
    /**
     * Clear endpoint halt condition
     * @param deviceHandle USB device handle
     * @param endpoint endpoint address
     * @return status code (0 = success)
     */
    public static native int clearHalt(long deviceHandle, int endpoint);
}