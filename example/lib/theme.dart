import 'package:flutter/material.dart';

// Material 3 theme configuration for Carlink automotive app.
//
// Designed for dark-only automotive use with:
// - High contrast for readability in vehicle lighting conditions
// - 72dp touch targets for gloved hands and driving context
// - Proper Material 3 color roles and elevation system
//
class AppTheme {
  // Private constructor to prevent instantiation
  AppTheme._();

  /// Material 3 dark theme optimized for automotive displays
  /// Based on Material Theme Builder with primary color #003E49 (dark teal/cyan)
  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      // Primary colors - Dark teal/cyan based on #003E49
      primary: Color(0xFF5FD5ED), // Light cyan for primary actions
      onPrimary: Color(0xFF003640), // Dark teal text on primary
      primaryContainer: Color(0xFF004E5C), // Medium teal container
      onPrimaryContainer: Color(0xFFB5EEFF), // Light cyan text on container

      // Secondary colors - Complementary cool tones
      secondary: Color(0xFFB0CBCE), // Light blue-gray
      onSecondary: Color(0xFF1B3438), // Dark blue-gray
      secondaryContainer: Color(0xFF324B4F), // Medium blue-gray container
      onSecondaryContainer: Color(0xFFCCE7EA), // Very light blue-gray

      // Tertiary colors - Warm accent (yellow-orange for warnings)
      tertiary: Color(0xFFFFB951), // Warm yellow-orange
      onTertiary: Color(0xFF432C00), // Dark brown
      tertiaryContainer: Color(0xFF604000), // Medium brown container
      onTertiaryContainer: Color(0xFFFFDDB0), // Light cream

      // Error colors - Bright red for destructive actions (tone 20)
      error: Color(0xFFBA1A1A), // Deep vibrant red (tone 20)
      onError: Color(0xFFFFFFFF), // White text on red
      errorContainer: Color(0xFF93000A), // Dark red container
      onErrorContainer: Color(0xFFFFDAD6), // Light pink text

      // Surface colors - Dark backgrounds with proper elevation
      surface: Color(0xFF0E1415), // Deep dark teal-gray
      onSurface: Color(0xFFDDE4E5), // Light gray text
      surfaceContainerHighest: Color(0xFF30393A), // Elevated surfaces (cards)
      surfaceContainerHigh: Color(0xFF252E2F),
      surfaceContainer: Color(0xFF1A2324),
      surfaceContainerLow: Color(0xFF171D1E),
      surfaceContainerLowest: Color(0xFF090F10),

      // Outline colors - Borders and dividers
      outline: Color(0xFF889394),
      outlineVariant: Color(0xFF3F484A),

      // Scrim - Modal overlays
      scrim: Color(0xFF000000),

      // Shadow - Elevation shadows
      shadow: Color(0xFF000000),

      // Inverse colors - Contrasting elements
      inverseSurface: Color(0xFFDDE4E5),
      onInverseSurface: Color(0xFF2B3132),
      inversePrimary: Color(0xFF006780),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,

      // Typography - Material 3 type scale
      textTheme: _buildTextTheme(colorScheme),

      // App Bar
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),

      // Cards
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),

      // Elevated Button (automotive 72dp height)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(88, 72), // 72dp height for automotive
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
      ),

      // Filled Button (automotive 72dp height)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(88, 72),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // Outlined Button (automotive 72dp height)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(88, 72),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),

      // Text Button (automotive 72dp height)
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(88, 72),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Navigation Rail (used in settings)
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        selectedIconTheme: IconThemeData(
          color: colorScheme.onSecondaryContainer,
          size: 28,
        ),
        unselectedIconTheme: IconThemeData(
          color: colorScheme.onSurfaceVariant,
          size: 28,
        ),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 16,
        ),
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
        minWidth: 80,
        minExtendedWidth: 220,
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return colorScheme.outline;
        }),
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),

      // Icon
      iconTheme: IconThemeData(
        color: colorScheme.onSurface,
        size: 24,
      ),

      // Scaffold
      scaffoldBackgroundColor: colorScheme.surface,
    );
  }

  /// Build Material 3 text theme with proper type scale
  static TextTheme _buildTextTheme(ColorScheme colorScheme) {
    return TextTheme(
      // Display - Largest text (reserved for short, important text)
      displayLarge: TextStyle(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
        color: colorScheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurface,
      ),
      displaySmall: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurface,
      ),

      // Headline - High emphasis text
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurface,
      ),

      // Title - Medium emphasis text
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
        color: colorScheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: colorScheme.onSurface,
      ),

      // Body - Default text
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: colorScheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: colorScheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        color: colorScheme.onSurfaceVariant,
      ),

      // Label - Text for components
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: colorScheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: colorScheme.onSurface,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
