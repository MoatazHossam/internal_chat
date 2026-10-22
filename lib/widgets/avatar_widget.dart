import 'package:flutter/material.dart';

/// Displays an avatar with the first two initials of [name].
/// The background color is deterministically derived from [name].
///
/// There is no online indicator: presence is disabled on the server.
class AvatarWidget extends StatelessWidget {
  const AvatarWidget({super.key, required this.name, this.radius = 24});

  final String name;
  final double radius;

  static const _palette = <Color>[
    Color(0xFFE57373),
    Color(0xFF81C784),
    Color(0xFF64B5F6),
    Color(0xFFFFB74D),
    Color(0xFFBA68C8),
    Color(0xFF4DD0E1),
    Color(0xFFF06292),
    Color(0xFFAED581),
    Color(0xFF4FC3F7),
    Color(0xFFFFD54F),
  ];

  Color _colorFor(String text) {
    final index = text.codeUnits.fold(0, (a, b) => a + b) % _palette.length;
    return _palette[index];
  }

  String _initials(String text) {
    // Matrix IDs ("@name:server") start with a sigil; skip it.
    final cleaned = text.trim().replaceFirst(RegExp(r'^[@!#]'), '');
    final parts = cleaned
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _colorFor(name),
      child: Text(
        _initials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}
