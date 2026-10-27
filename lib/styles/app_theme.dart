import 'package:flutter/material.dart';

import 'chat_theme.dart';
import 'palette.dart';
import 'status_colors.dart';
import 'tokens.dart';

/// The app's light and dark themes. Every Material component is styled here,
/// so pages use plain widgets and theme colours, never literal colours.
abstract final class AppTheme {
  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Palette.indigo,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFE3E6FF),
    onPrimaryContainer: Color(0xFF1B2382),
    secondary: Palette.inkMuted,
    onSecondary: Colors.white,
    secondaryContainer: Palette.mist200,
    onSecondaryContainer: Palette.ink,
    tertiary: Palette.green,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFD7F3E4),
    onTertiaryContainer: Color(0xFF0B3D27),
    error: Palette.red,
    onError: Colors.white,
    errorContainer: Color(0xFFFDE5E8),
    onErrorContainer: Color(0xFF6A0E1B),
    surface: Palette.paper,
    onSurface: Palette.ink,
    onSurfaceVariant: Palette.inkMuted,
    surfaceDim: Palette.mist200,
    surfaceBright: Palette.paper,
    surfaceContainerLowest: Palette.paper,
    surfaceContainerLow: Palette.mist50,
    surfaceContainer: Palette.mist100,
    surfaceContainerHigh: Palette.mist200,
    surfaceContainerHighest: Palette.mist300,
    outline: Palette.mist400,
    outlineVariant: Palette.mist300,
    shadow: Color(0x1A151824),
    scrim: Color(0x66151824),
    inverseSurface: Palette.ink,
    onInverseSurface: Palette.snow,
    inversePrimary: Palette.indigoLight,
    surfaceTint: Colors.transparent,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Palette.indigoLight,
    onPrimary: Color(0xFF111A6B),
    primaryContainer: Color(0xFF2E39A3),
    onPrimaryContainer: Color(0xFFE0E3FF),
    secondary: Palette.snowMuted,
    onSecondary: Palette.night,
    secondaryContainer: Palette.night300,
    onSecondaryContainer: Palette.snow,
    tertiary: Palette.greenLight,
    onTertiary: Color(0xFF00391F),
    tertiaryContainer: Color(0xFF124D33),
    onTertiaryContainer: Color(0xFFC9F3DD),
    error: Palette.redLight,
    onError: Color(0xFF5A0010),
    errorContainer: Color(0xFF5B1720),
    onErrorContainer: Color(0xFFFFD9DD),
    surface: Palette.night,
    onSurface: Palette.snow,
    onSurfaceVariant: Palette.snowMuted,
    surfaceDim: Palette.night,
    surfaceBright: Palette.night300,
    surfaceContainerLowest: Color(0xFF0A0B10),
    surfaceContainerLow: Palette.night50,
    surfaceContainer: Palette.night100,
    surfaceContainerHigh: Palette.night200,
    surfaceContainerHighest: Palette.night300,
    outline: Palette.night400,
    outlineVariant: Palette.night300,
    shadow: Colors.black,
    scrim: Color(0x99000000),
    inverseSurface: Palette.snow,
    onInverseSurface: Palette.ink,
    inversePrimary: Palette.indigo,
    surfaceTint: Colors.transparent,
  );

  static ThemeData get light =>
      _build(_lightScheme, ChatTheme.light, StatusColors.light);
  static ThemeData get dark =>
      _build(_darkScheme, ChatTheme.dark, StatusColors.dark);

  static ThemeData _build(
    ColorScheme scheme,
    ChatTheme chat,
    StatusColors status,
  ) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
    );
    final text = _textTheme(base.textTheme, scheme);
    final roundedMd = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.md),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      borderSide: BorderSide.none,
    );
    final buttonText = text.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: 15,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: text,
      extensions: [chat, status],
      splashFactory: InkSparkle.splashFactory,
      dividerColor: scheme.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: Insets.lg,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md + 2,
        ),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, Sizes.buttonHeight - 4),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          shape: roundedMd,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, Sizes.buttonHeight - 4),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          shape: roundedMd,
          side: BorderSide(color: scheme.outline),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: roundedMd, textStyle: buttonText),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        extendedTextStyle: buttonText,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        minVerticalPadding: Insets.md,
      ),
      cardTheme: CardThemeData(
        color: scheme.brightness == Brightness.light
            ? scheme.surface
            : scheme.surfaceContainerHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xxl)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
      ),
    );
  }

  /// Platform fonts (SF on iOS, Roboto on Android, both with Arabic), with a
  /// tighter, heavier title scale.
  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    final themed = base.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return themed.copyWith(
      headlineMedium: themed.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: themed.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: themed.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: themed.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: themed.bodyLarge?.copyWith(fontSize: 16, height: 1.35),
      bodyMedium: themed.bodyMedium?.copyWith(fontSize: 14, height: 1.35),
      labelLarge: themed.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: themed.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}
