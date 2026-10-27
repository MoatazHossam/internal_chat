import 'package:flutter/animation.dart';

/// Spacing scale. Use these instead of literal paddings so screens share one
/// rhythm.
abstract final class Insets {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Corner radii.
abstract final class Radii {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double xxl = 28;

  /// Message bubbles: round, with a tighter corner on the sender's side
  /// where consecutive messages from one person meet.
  static const double bubble = 20;
  static const double bubbleJoined = 6;
}

/// Motion.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Curve curve = Curves.easeOutCubic;
}

/// Fixed component sizes.
abstract final class Sizes {
  static const double avatar = 48;
  static const double avatarSmall = 32;
  static const double buttonHeight = 52;
  static const double composerButton = 44;
  static const double maxContentWidth = 440;
}
