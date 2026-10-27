import 'package:flutter/material.dart';

import '../styles/chat_theme.dart';

/// Initials on a soft tint of the person's (or conversation's) identity
/// colour. People are circles; groups are rounded squares, so the two read
/// differently at a glance.
///
/// There is no online indicator: presence is disabled on the server.
class AvatarWidget extends StatelessWidget {
  const AvatarWidget({
    super.key,
    required this.name,
    this.radius = 24,
    this.isGroup = false,
    this.colorKey,
  });

  final String name;
  final double radius;
  final bool isGroup;

  /// What the colour is derived from; defaults to [name]. Pass a stable ID
  /// so the colour does not change when a display name does.
  final String? colorKey;

  static String initials(String text) {
    // Matrix IDs ("@name:server") start with a sigil; skip it.
    final cleaned = text
        .trim()
        .replaceFirst(RegExp(r'^[@!#]'), '')
        .split(':')
        .first;
    final parts = cleaned
        .split(RegExp(r'[\s._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ChatTheme.of(context).identityFor(colorKey ?? name);
    final dark = theme.brightness == Brightness.dark;
    final background = Color.alphaBlend(
      color.withValues(alpha: dark ? 0.22 : 0.14),
      theme.colorScheme.surface,
    );
    final size = radius * 2;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: isGroup ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isGroup ? BorderRadius.circular(radius * 0.6) : null,
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.72,
          height: 1,
        ),
      ),
    );
  }
}
