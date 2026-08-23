import 'package:flutter/material.dart';

/// WildBit's two shipped looks. More variants (Game Boy, Topographic, ...)
/// are anticipated by the brief but not built yet — appended here, never
/// reordered or removed, since [AppThemeId.index] is persisted.
enum AppThemeId { light, dark }

extension AppThemeIdExt on AppThemeId {
  bool get isDark => this == AppThemeId.dark;

  static AppThemeId fromIndex(int i) => AppThemeId.values[i.clamp(0, AppThemeId.values.length - 1)];
}

/// Static palette values usable without a [BuildContext] (e.g. in
/// [CustomPainter]s that only render the light look for now).
abstract final class WildBitColors {
  static const forestGreen = Color(0xFF2F5233);
  static const oliveGreen = Color(0xFF6B7A3A);
  static const cream = Color(0xFFF5EFDD);
  static const brown = Color(0xFF6B4A2F);
  static const ochre = Color(0xFFC98A3B);
  static const naturalBlue = Color(0xFF3E7C8A);
  static const nightForest = Color(0xFF1B2A1E);
}

/// Theme-aware semantic colours, mirroring each other between the light and
/// dark look so widgets never branch on [Brightness] directly.
class WildBitColorsExt extends ThemeExtension<WildBitColorsExt> {
  const WildBitColorsExt({
    required this.isDark,
    required this.accent,
    required this.surface1,
    required this.surface2,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.terrainTint,
  });

  final bool isDark;
  final Color accent;
  final Color surface1;
  final Color surface2;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  /// Multiplied over the pixel-art terrain's base fill so the map itself
  /// dims at night instead of only the chrome around it.
  final Color terrainTint;

  @override
  WildBitColorsExt copyWith({
    bool? isDark,
    Color? accent,
    Color? surface1,
    Color? surface2,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? terrainTint,
  }) {
    return WildBitColorsExt(
      isDark: isDark ?? this.isDark,
      accent: accent ?? this.accent,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      terrainTint: terrainTint ?? this.terrainTint,
    );
  }

  @override
  WildBitColorsExt lerp(WildBitColorsExt? other, double t) {
    if (other == null) return this;
    return WildBitColorsExt(
      isDark: t < 0.5 ? isDark : other.isDark,
      accent: Color.lerp(accent, other.accent, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      terrainTint: Color.lerp(terrainTint, other.terrainTint, t)!,
    );
  }

  static WildBitColorsExt of(BuildContext context) => Theme.of(context).extension<WildBitColorsExt>()!;
}

class WildBitTheme {
  static ThemeData build(AppThemeId id) {
    return id.isDark ? _dark() : _light();
  }

  static ThemeData _light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: WildBitColors.forestGreen,
      brightness: Brightness.light,
      primary: WildBitColors.forestGreen,
      secondary: WildBitColors.ochre,
      surface: WildBitColors.cream,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: WildBitColors.cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: WildBitColors.forestGreen,
        foregroundColor: WildBitColors.cream,
        elevation: 0,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: WildBitColors.cream,
        indicatorColor: WildBitColors.oliveGreen.withValues(alpha: 0.35),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: WildBitColors.ochre,
        foregroundColor: WildBitColors.nightForest,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: WildBitColors.forestGreen,
          foregroundColor: WildBitColors.cream,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? WildBitColors.forestGreen : const Color(0xFFBDBDBD),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? WildBitColors.forestGreen.withValues(alpha: 0.4)
              : const Color(0xFFE0E0E0),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.9),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      extensions: const [
        WildBitColorsExt(
          isDark: false,
          accent: WildBitColors.forestGreen,
          surface1: WildBitColors.cream,
          surface2: Colors.white,
          border: Color(0xFFE3DDC8),
          textPrimary: WildBitColors.nightForest,
          textSecondary: Color(0xFF6B6B5C),
          terrainTint: Colors.white,
        ),
      ],
    );
  }

  static ThemeData _dark() {
    const accent = WildBitColors.oliveGreen;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      primary: accent,
      secondary: WildBitColors.ochre,
      surface: const Color(0xFF14170F),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0D0F0A),
      cardColor: const Color(0xFF1B1F14),
      dividerColor: const Color(0xFF2A2F1F),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF14170F),
        foregroundColor: Color(0xFFE8E6D8),
        elevation: 0,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF14170F),
        indicatorColor: accent.withValues(alpha: 0.35),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: WildBitColors.ochre,
        foregroundColor: Color(0xFF14170F),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF0D0F0A),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? WildBitColors.ochre : const Color(0xFF555045),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? WildBitColors.ochre.withValues(alpha: 0.4)
              : const Color(0xFF2A2F1F),
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1B1F14),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      extensions: const [
        WildBitColorsExt(
          isDark: true,
          accent: WildBitColors.ochre,
          surface1: Color(0xFF0D0F0A),
          surface2: Color(0xFF1B1F14),
          border: Color(0xFF2A2F1F),
          textPrimary: Color(0xFFE8E6D8),
          textSecondary: Color(0xFF9A9A86),
          terrainTint: Color(0xFF9AA08A),
        ),
      ],
    );
  }
}
