package com.carlink.handlers

/**
 * UsbDeviceHandler - Handles USB device lifecycle and configuration operations
 *
 * PURPOSE:
 * Manages USB device discovery, permissions, connections, and configuration for CPC200-CCPA
 * wireless CarPlay/Android Auto adapters. This handler provides a clean interface to the
 * underlying UsbDeviceManager without exposing its internal complexity.
 *
 * RESPONSIBILITIES:
 * - getDeviceList: Scan and list available USB devices
 * - getDeviceDescription: Get detailed device information
 * - hasPermission: Check if app has permission for a device
 * - requestPermission: Request USB device permission from user
 * - openDevice: Open USB device connection
 * - closeDevice: Close USB device connection
 * - resetDevice: Reset USB device
 * - getConfiguration: Get USB configuration details
 * - setConfiguration: Set active USB configuration
 * - claimInterface: Claim USB interface for exclusive access
 * - releaseInterface: Release USB interface
 *
 * THREAD SAFETY:
 * All methods are called on the main thread via Flutter's MethodChannel.
 * Permission callbacks are handled asynchronously but delivered to the main thread.
 *
 * NOTE:
 * This handler is a thin delegation layer to UsbDeviceManager. All logging is performed
 * by the UsbDeviceManager itself, which has its own LogCallback for comprehensive USB
 * operation logging.
 *
 * @param usbDeviceManager UsbDeviceManager instance for device operations
 */
import com.carlink.UsbDeviceManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result

class UsbDeviceHandler(
    private val usbDeviceManager: UsbDeviceManager?,
) {
    /**
     * Handles USB device-related method calls.
     *
     * @param call The method call from Flutter
     * @param result The result callback
     * @return true if the method was handled, false otherwise
     */
    fun handle(
        call: MethodCall,
        result: Result,
    ): Boolean =
        when (call.method) {
            "getDeviceList" -> {
                handleGetDeviceList(result)
                true
            }
            "getDeviceDescription" -> {
                handleGetDeviceDescription(call, result)
                true
            }
            "hasPermission" -> {
                handleHasPermission(call, result)
                true
            }
            "requestPermission" -> {
                handleRequestPermission(call, result)
                true
            }
            "openDevice" -> {
                handleOpenDevice(call, result)
                true
            }
            "closeDevice" -> {
                handleCloseDevice(result)
                true
            }
            "resetDevice" -> {
                handleResetDevice(result)
                true
            }
            "getConfiguration" -> {
                handleGetConfiguration(call, result)
                true
            }
            "setConfiguration" -> {
                handleSetConfiguration(call, result)
                true
            }
            "claimInterface" -> {
                handleClaimInterface(call, result)
                true
            }
            "releaseInterface" -> {
                handleReleaseInterface(call, result)
                true
            }
            else -> false
        }

    private fun requireManager(result: Result): UsbDeviceManager? {
        if (usbDeviceManager == null) {
            result.error("IllegalState", "usbDeviceManager null", null)
        }
        return usbDeviceManager
    }

    /**
     * Gets a list of all connected USB devices.
     *
     * Returns a list of maps, each containing:
     * - identifier (String): Unique device identifier
     * - vendorId (Int): USB vendor ID
     * - productId (Int): USB product ID
     * - configurationCount (Int): Number of configurations
     */
    private fun handleGetDeviceList(result: Result) {
        val manager = requireManager(result) ?: return
        val usbDeviceList = manager.getDeviceList()
        result.success(usbDeviceList)
    }

    /**
     * Gets detailed description of a specific USB device.
     *
     * Arguments:
     * - device (Map): Device info containing "identifier" key
     * - requestPermission (Boolean): Whether to request permission if not granted
     *
     * Returns detailed device information including interfaces and endpoints.
     * Result is delivered asynchronously via callback.
     *
     * Errors:
     * - USBError: If device description retrieval fails
     */
    private fun handleGetDeviceDescription(
        call: MethodCall,
        result: Result,
    ) {
        val manager = requireManager(result) ?: return

        val deviceMap =
            call.argument<Map<String, Any>>("device")
                ?: return result.error("IllegalArgument", "Missing required argument: device", null)
        val identifier =
            deviceMap["identifier"] as? String
                ?: return result.error("IllegalArgument", "Device map missing 'identifier' key", null)
        val requestPermission =
            call.argument<Boolean>("requestPermission")
                ?: return result.error("IllegalArgument", "Missing required argument: requestPermission", null)

        manager.getDeviceDescription(identifier, requestPermission) { descResult ->
            descResult.fold(
                onSuccess = { description -> result.success(description) },
                onFailure = { error -> result.error("USBError", error.message, null) },
            )
        }
    }

    /**
     * Checks if the app has permission for the specified USB device.
     *
     * Arguments:
     * - identifier (String): Device identifier
     *
     * Returns true if permission is granted, false otherwise.
     */
    private fun handleHasPermission(
        call: MethodCall,
        result: Result,
    ) {
        val manager = requireManager(result) ?: return
        val identifier =
            call.argument<String>("identifier")
                ?: return result.error("IllegalArgument", "Missing required argument: identifier", null)

        result.success(manager.hasPermission(identifier))
    }

    /**
     * Requests USB device permission from the user.
     *
     * Arguments:
     * - identifier (String): Device identifier
     *
     * Returns true if permission is granted, false if denied.
     * Result is delivered asynchronously via callback.
     */
    private fun handleRequestPermission(
        call: MethodCall,
        result: Result,
    ) {
        val manager = requireManager(result) ?: return
        val identifier =
            call.argument<String>("identifier")
                ?: return result.error("IllegalArgument", "Missing required argument: identifier", null)

        manager.requestPermission(identifier) { granted ->
            result.success(granted)
        }
    }

    /**
     * Opens a USB device connection.
     *
     * Arguments:
     * - identifier (String): Device identifier
     *
     * Returns true if device opened successfully, false otherwise.
     */
    private fun handleOpenDevice(
        call: MethodCall,
        result: Result,
    ) {
        val manager = requireManager(result) ?: return
        val identifier =
            call.argument<String>("identifier")
                ?: return result.error("IllegalArgument", "Missing required argument: identifier", null)

        val success = manager.openDevice(identifier)
        result.success(success)
    }

    /**
     * Closes the current USB device connection.
     *
     * Returns null on success.
     */
    private fun handleCloseDevice(result: Result) {
        val manager = requireManager(result) ?: return
        manager.closeDevice()
        result.success(null)
    }

    /**
     * Resets the current USB device.
     *
     * Returns true if reset was successful, false otherwise.
     */
    private fun handleResetDevice(result: Result) {
        val manager = requireManager(result) ?: return
        val success = manager.resetDevice()
        result.success(success)
    }

    /**
     * Gets USB configuration details by index.
     *
     * Arguments:
     * - index (Int): Configuration index
     *
     * Returns configuration details map.
     *
     * Errors:
     * - IllegalState: If device not opened or configuration not found
     */
    private fun handleGetConfiguration(
        call: MethodCall,
        result: Result,
    ) {
        val manager = requireManager(result) ?: return
        val index =
            call.argument<Int>("index")
                ?: return result.error("IllegalArgument", "Missing required argument: index", null)

        val configuration = manager.getConfiguration(index)
        if (configuration != null) {
            result.success(configuration)
        } else {
            result.error("IllegalState", "Device not opened or configuration not found", null)
        }
    }

    /**
     * Sets the active USB configuration.
     *
     * Arguments:
     * - index (Int): Configuration index to set
     *
     * Returns true if configuration was set successfully, false otherwise.
     */
    private fun handleSetConfiguration(
        call: MethodCall,
        result: Result,
    ) {
        val manager = requireManager(result) ?: return
        val index =
            call.argument<Int>("index")
                ?: return result.error("IllegalArgument", "Missing required argument: index", null)

        val success = manager.setConfiguration(index)
        result.success(success)
    }

    /**
     * Claims a USB interface for exclusive access.
     *
     * Arguments:
     * - id (Int): Interface ID
     * - alternateSetting (Int): Alternate setting number
     *
     * Returns true if interface was claimed successfully.
     *
     * Errors:
     * - IllegalArgument: If interface not found
     * - USBError: If claiming failed
     */
    private fun handleClaimInterface(
        call: MethodCall,
        result: Result,
    ) {
        val manager = requireManager(result) ?: return
        val id =
            call.argument<Int>("id")
                ?: return result.error("IllegalArgument", "Missing required argument: id", null)
        val alternateSetting =
            call.argument<Int>("alternateSetting")
                ?: return result.error("IllegalArgument", "Missing required argument: alternateSetting", null)

        manager.claimInterface(id, alternateSetting).fold(
            onSuccess = { success -> result.success(success) },
            onFailure = { error ->
                when (error) {
                    is IllegalArgumentException -> result.error("IllegalArgument", error.message, null)
                    else -> result.error("USBError", error.message, null)
                }
            },
        )
    }

    /**
     * Releases a previously claimed USB interface.
     *
     * Arguments:
     * - id (Int): Interface ID
     * - alternateSetting (Int): Alternate setting number
     *
     * Returns true if interface was released successfully, false otherwise.
     */
    private fun handleReleaseInterface(
        call: MethodCall,
        result: Result,
    ) {
        val manager = requireManager(result) ?: return
        val id =
            call.argument<Int>("id")
                ?: return result.error("IllegalArgument", "Missing required argument: id", null)
        val alternateSetting =
            call.argument<Int>("alternateSetting")
                ?: return result.error("IllegalArgument", "Missing required argument: alternateSetting", null)

        val success = manager.releaseInterface(id, alternateSetting)
        result.success(success)
    }
}
