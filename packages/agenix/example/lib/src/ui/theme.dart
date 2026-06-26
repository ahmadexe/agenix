import 'package:flutter/material.dart';

class SciTheme {
  static const bg = Color(0xFF05070F);
  static const panel = Color(0xFF0A0F1E);
  static const grid = Color(0xFF13203B);
  static const cyan = Color(0xFF35E1FF);
  static const magenta = Color(0xFFFF3DCB);
  static const lime = Color(0xFF8AFF80);
  static const amber = Color(0xFFFFC857);
  static const danger = Color(0xFFFF5C5C);
  static const fg = Color(0xFFE7F0FF);
  static const dim = Color(0xFF6E7F9E);

  static ThemeData build() {
    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        primary: cyan,
        secondary: magenta,
        surface: panel,
      ),
      textTheme: base.textTheme
          .apply(bodyColor: fg, displayColor: fg, fontFamily: 'monospace')
          .copyWith(
            bodySmall: const TextStyle(
              fontFamily: 'monospace',
              color: dim,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
    );
  }
}
