package com.carlink.handlers

/**
 * MethodCallDispatcher - Routes Flutter platform method calls to specialized handlers
 *
 * PURPOSE:
 * Serves as the central dispatcher for all Flutter platform method calls in the Carlink plugin.
 * This class implements the Single Responsibility Principle by delegating domain-specific
 * operations to specialized handler classes, greatly improving maintainability and testability.
 *
 * ARCHITECTURE:
 * The dispatcher uses a chain-of-responsibility pattern, attempting to handle each method call
 * with domain-specific handlers in sequence:
 * 1. DisplayMetricsHandler - Display and window metrics
 * 2. VideoHandler - Flutter texture and H.264 rendering
 * 3. UsbDeviceHandler - USB device lifecycle and configuration
 * 4. BulkTransferHandler - USB bulk transfers and reading loop
 *
 * BENEFITS OF THIS DESIGN:
 * - Separation of Concerns: Each handler manages one domain
 * - Testability: Handlers can be unit tested in isolation
 * - Maintainability: Easy to locate and modify specific functionality
 * - Extensibility: New handlers can be added without modifying existing code
 * - Readability: CarlinkPlugin.kt is dramatically simplified
 *
 * THREAD SAFETY:
 * All method calls arrive on the main thread via Flutter's MethodChannel.
 * Individual handlers manage their own thread safety and async operations.
 *
 * @param displayHandler Handler for display metrics operations
 * @param videoHandler Handler for video texture operations
 * @param usbDeviceHandler Handler for USB device operations
 * @param bulkTransferHandler Handler for bulk transfer operations
 */
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result

class MethodCallDispatcher(
    private val displayHandler: DisplayMetricsHandler,
    private val videoHandler: VideoHandler,
    private val usbDeviceHandler: UsbDeviceHandler,
    private val bulkTransferHandler: BulkTransferHandler,
) : MethodChannel.MethodCallHandler {
    /**
     * Routes method calls to the appropriate specialized handler.
     *
     * The routing uses a chain-of-responsibility pattern where each handler
     * returns true if it handled the call, false otherwise. If no handler
     * handles the call, result.notImplemented() is returned.
     *
     * @param call The method call from Flutter
     * @param result The result callback to Flutter
     */
    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        val handled =
            displayHandler.handle(call, result) ||
                videoHandler.handle(call, result) ||
                usbDeviceHandler.handle(call, result) ||
                bulkTransferHandler.handle(call, result)

        if (!handled) {
            result.notImplemented()
        }
    }
}
