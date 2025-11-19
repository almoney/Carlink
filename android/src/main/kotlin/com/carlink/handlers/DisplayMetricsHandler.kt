package com.carlink.handlers

/**
 * DisplayMetricsHandler - Handles display and window metrics requests
 *
 * PURPOSE:
 * Provides display hardware information and window bounds for video sizing calculations.
 * This handler encapsulates Android's display metrics and window insets APIs to provide
 * accurate screen dimensions for CarPlay/Android Auto projection.
 *
 * RESPONSIBILITIES:
 * - getDisplayMetrics: Hardware display resolution, DPI, density, refresh rate
 * - getWindowBounds: Window bounds with system insets (status bar, navigation bar, cutouts)
 *
 * THREAD SAFETY:
 * All methods are called on the main thread via Flutter's MethodChannel.
 *
 * @param context Android application context for accessing WindowManager
 * @param logCallback Callback for logging display information
 */
import android.content.Context
import android.util.DisplayMetrics
import android.view.WindowManager
import com.carlink.LogCallback
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result

class DisplayMetricsHandler(
    private val context: Context,
    private val logCallback: LogCallback,
) {
    /**
     * Handles display-related method calls.
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
            "getDisplayMetrics" -> {
                handleGetDisplayMetrics(result)
                true
            }
            "getWindowBounds" -> {
                handleGetWindowBounds(result)
                true
            }
            else -> false
        }

    /**
     * Gets hardware display metrics including resolution, DPI, and refresh rate.
     *
     * Returns a map containing:
     * - widthPixels: Display width in pixels
     * - heightPixels: Display height in pixels
     * - densityDpi: Screen density in DPI
     * - density: Logical density (scale factor)
     * - scaledDensity: Font scaling factor
     * - xdpi: Physical pixels per inch in X dimension
     * - ydpi: Physical pixels per inch in Y dimension
     * - refreshRate: Display refresh rate in Hz
     */
    private fun handleGetDisplayMetrics(result: Result) {
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val display = windowManager.defaultDisplay
        val metrics = DisplayMetrics()

        // Get real display metrics (including status bar, navigation bar)
        display.getRealMetrics(metrics)

        val displayInfo =
            mapOf(
                "widthPixels" to metrics.widthPixels,
                "heightPixels" to metrics.heightPixels,
                "densityDpi" to metrics.densityDpi,
                "density" to metrics.density,
                "scaledDensity" to metrics.scaledDensity,
                "xdpi" to metrics.xdpi,
                "ydpi" to metrics.ydpi,
                "refreshRate" to display.refreshRate,
            )

        logCallback.log(
            "[DISPLAY] Hardware resolution: ${metrics.widthPixels}x${metrics.heightPixels}, " +
                "DPI: ${metrics.densityDpi}, Density: ${metrics.density}, Refresh: ${display.refreshRate}Hz",
        )

        result.success(displayInfo)
    }

    /**
     * Gets current window bounds with system insets.
     *
     * Uses WindowMetrics API (available on API 30+, guaranteed by minSdk 32).
     *
     * Returns a map containing:
     * - width, height: Total window dimensions
     * - left, top, right, bottom: Window position bounds
     * - usableWidth, usableHeight: Window dimensions minus system UI
     * - insetsLeft, insetsTop, insetsRight, insetsBottom: System insets (status bar, nav bar, cutouts)
     */
    private fun handleGetWindowBounds(result: Result) {
        try {
            val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

            // Use WindowMetrics API (minSdk 32 guarantees API 30+ availability)
            val windowMetrics = windowManager.currentWindowMetrics
            val bounds = windowMetrics.bounds
            val windowInsets = windowMetrics.windowInsets

            // Get system bars insets (status bar, navigation bar, etc.)
            val insets =
                windowInsets.getInsetsIgnoringVisibility(
                    android.view.WindowInsets.Type
                        .systemBars() or
                        android.view.WindowInsets.Type
                            .displayCutout(),
                )

            // Calculate usable bounds (window bounds minus system UI)
            val usableWidth = bounds.width() - insets.left - insets.right
            val usableHeight = bounds.height() - insets.top - insets.bottom

            val windowInfo =
                mapOf(
                    "width" to bounds.width(),
                    "height" to bounds.height(),
                    "left" to bounds.left,
                    "top" to bounds.top,
                    "right" to bounds.right,
                    "bottom" to bounds.bottom,
                    "usableWidth" to usableWidth,
                    "usableHeight" to usableHeight,
                    "insetsLeft" to insets.left,
                    "insetsTop" to insets.top,
                    "insetsRight" to insets.right,
                    "insetsBottom" to insets.bottom,
                )

            logCallback.log(
                "[WINDOW] Window bounds: ${bounds.width()}x${bounds.height()}, " +
                    "Usable: ${usableWidth}x$usableHeight, " +
                    "Insets: T:${insets.top} B:${insets.bottom} L:${insets.left} R:${insets.right}",
            )

            result.success(windowInfo)
        } catch (e: Exception) {
            logCallback.log("[WINDOW] Error getting window bounds: ${e.message}")
            result.error("WindowBoundsError", "Failed to get window bounds: ${e.message}", null)
        }
    }
}
