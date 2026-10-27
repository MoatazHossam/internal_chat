import 'package:flutter/material.dart';

import 'palette.dart';

/// Success / warning colours, which the [ColorScheme] does not have. Danger
/// uses the scheme's error colours.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
  });

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;

  static const light = StatusColors(
    success: Palette.green,
    successContainer: Color(0xFFD7F3E4),
    warning: Palette.amber,
    warningContainer: Color(0xFFFFEFD2),
  );

  static const dark = StatusColors(
    success: Palette.greenLight,
    successContainer: Color(0xFF124D33),
    warning: Palette.amberLight,
    warningContainer: Color(0xFF4A3410),
  );

  static StatusColors of(BuildContext context) =>
      Theme.of(context).extension<StatusColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  StatusColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
  }) => StatusColors(
    success: success ?? this.success,
    successContainer: successContainer ?? this.successContainer,
    warning: warning ?? this.warning,
    warningContainer: warningContainer ?? this.warningContainer,
  );

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
    );
  }
}
