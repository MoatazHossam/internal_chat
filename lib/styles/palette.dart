import 'package:flutter/material.dart';

/// Raw brand and neutral colours. Widgets never use these directly: they
/// read the [ColorScheme] and [ChatTheme] built from them in `app_theme.dart`.
abstract final class Palette {
  // Brand: a calm indigo. Changing these two re-colours the app.
  static const indigo = Color(0xFF4351D6);
  static const indigoLight = Color(0xFFAAB3FF);

  // Light neutrals (cool grey).
  static const ink = Color(0xFF151824);
  static const inkMuted = Color(0xFF5D6378);
  static const inkSubtle = Color(0xFF8A90A4);
  static const paper = Color(0xFFFFFFFF);
  static const mist50 = Color(0xFFF7F8FB);
  static const mist100 = Color(0xFFF2F3F8);
  static const mist200 = Color(0xFFEBEDF3);
  static const mist300 = Color(0xFFE2E5EC);
  static const mist400 = Color(0xFFC9CDD9);

  // Dark neutrals.
  static const night = Color(0xFF0E1016);
  static const night50 = Color(0xFF13161E);
  static const night100 = Color(0xFF181B25);
  static const night200 = Color(0xFF1F2330);
  static const night300 = Color(0xFF282C3B);
  static const night400 = Color(0xFF434859);
  static const snow = Color(0xFFE7E9F1);
  static const snowMuted = Color(0xFFA3A8BB);

  // Status.
  static const green = Color(0xFF1C8A5A);
  static const greenLight = Color(0xFF6FD6A3);
  static const red = Color(0xFFD23A4C);
  static const redLight = Color(0xFFFF8E99);
  static const amber = Color(0xFFB86A00);
  static const amberLight = Color(0xFFFFC46B);

  /// Identity colours for avatars and sender names, readable on light
  /// surfaces...
  static const identityLight = <Color>[
    Color(0xFF4351D6),
    Color(0xFF0E7C74),
    Color(0xFFB4501B),
    Color(0xFF8A3FD1),
    Color(0xFFC0306E),
    Color(0xFF2F7D32),
    Color(0xFF9A6A00),
    Color(0xFF1F6FB8),
  ];

  /// ...and on dark ones (same order).
  static const identityDark = <Color>[
    Color(0xFFAAB3FF),
    Color(0xFF6ED8CC),
    Color(0xFFFFAD7D),
    Color(0xFFD3AEFF),
    Color(0xFFFF9CC3),
    Color(0xFF94DB97),
    Color(0xFFF2CB6B),
    Color(0xFF8CC4FF),
  ];
}
