import 'package:flutter/material.dart';

import '../styles/chat_theme.dart';

/// The app mark: the chat icon on a rounded tile in the brand colour.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    final chat = ChatTheme.of(context);
    final brand = chat.outgoing;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(brand, Colors.white, 0.18)!, brand],
        ),
        boxShadow: [
          BoxShadow(
            color: brand.withValues(alpha: 0.28),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: Icon(
        Icons.forum_rounded,
        size: size * 0.5,
        color: chat.onOutgoing,
      ),
    );
  }
}
