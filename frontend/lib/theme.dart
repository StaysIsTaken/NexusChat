/// NexusChat Design-System.
///
/// Indigo/Violett-Akzent auf tiefem Anthrazit (Dark) bzw. zartem Violett-Weiß
/// (Light). Premium-Look à la Claude/Linear: weiche Flächen, abgerundete Kanten,
/// dezente Ränder statt harter Schatten, Verläufe auf Akzentelementen.

import 'package:flutter/material.dart';

class NexusColors {
  NexusColors._();

  /// Primärer Akzent (Indigo-Violett).
  static const seed = Color(0xFF6D5DF6);

  /// Verlauf für Akzentelemente (User-Bubble, Avatare, Senden-Button).
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6E5DF6), Color(0xFF9B6DFF)],
  );

  // ── Dark: tiefes Anthrazit mit leichtem Violett-Schimmer ────────────────
  static const _darkSurface = Color(0xFF0D0D12);
  static const _darkSurfaceLowest = Color(0xFF09090D);
  static const _darkSurfaceLow = Color(0xFF131319);
  static const _darkSurfaceContainer = Color(0xFF181820);
  static const _darkSurfaceHigh = Color(0xFF1F1F29);
  static const _darkSurfaceHighest = Color(0xFF262633);
  static const _darkOnSurface = Color(0xFFE9E9F0);
  static const _darkOnSurfaceVariant = Color(0xFF9D9DB0);
  static const _darkOutline = Color(0xFF3A3A48);
  static const _darkOutlineVariant = Color(0xFF26262F);

  // ── Light: zartes Violett-Weiß ──────────────────────────────────────────
  static const _lightSurface = Color(0xFFFBFAFF);
  static const _lightSurfaceLowest = Color(0xFFFFFFFF);
  static const _lightSurfaceLow = Color(0xFFF6F4FF);
  static const _lightSurfaceContainer = Color(0xFFF1EEFB);
  static const _lightSurfaceHigh = Color(0xFFECE8F8);
  static const _lightSurfaceHighest = Color(0xFFE5E1F3);
  static const _lightOnSurface = Color(0xFF1A1924);
  static const _lightOnSurfaceVariant = Color(0xFF625E73);
  static const _lightOutline = Color(0xFFC9C4DC);
  static const _lightOutlineVariant = Color(0xFFE6E2F1);
}

ThemeData buildNexusTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  var scheme = ColorScheme.fromSeed(
    seedColor: NexusColors.seed,
    brightness: brightness,
  );

  // Flächen & Konturen für den Premium-Look feinjustieren
  scheme = isDark
      ? scheme.copyWith(
          surface: NexusColors._darkSurface,
          surfaceContainerLowest: NexusColors._darkSurfaceLowest,
          surfaceContainerLow: NexusColors._darkSurfaceLow,
          surfaceContainer: NexusColors._darkSurfaceContainer,
          surfaceContainerHigh: NexusColors._darkSurfaceHigh,
          surfaceContainerHighest: NexusColors._darkSurfaceHighest,
          onSurface: NexusColors._darkOnSurface,
          onSurfaceVariant: NexusColors._darkOnSurfaceVariant,
          outline: NexusColors._darkOutline,
          outlineVariant: NexusColors._darkOutlineVariant,
        )
      : scheme.copyWith(
          surface: NexusColors._lightSurface,
          surfaceContainerLowest: NexusColors._lightSurfaceLowest,
          surfaceContainerLow: NexusColors._lightSurfaceLow,
          surfaceContainer: NexusColors._lightSurfaceContainer,
          surfaceContainerHigh: NexusColors._lightSurfaceHigh,
          surfaceContainerHighest: NexusColors._lightSurfaceHighest,
          onSurface: NexusColors._lightOnSurface,
          onSurfaceVariant: NexusColors._lightOnSurfaceVariant,
          outline: NexusColors._lightOutline,
          outlineVariant: NexusColors._lightOutlineVariant,
        );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
  );

  final radius = BorderRadius.circular(14);

  return base.copyWith(
    // Typografie etwas straffer & moderner
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ).copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
    ),

    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      selectedIconTheme: IconThemeData(color: scheme.primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          )),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: scheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),

    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
