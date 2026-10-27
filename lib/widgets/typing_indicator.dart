import 'package:flutter/material.dart';

import '../styles/chat_theme.dart';
import '../styles/tokens.dart';

/// Animated three dots in an incoming-message bubble.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(3, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
    });

    _animations = _controllers.map((c) {
      return Tween<double>(
        begin: 0,
        end: -6,
      ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut));
    }).toList();

    _startAnimation();
  }

  void _startAnimation() async {
    while (mounted) {
      for (int i = 0; i < _controllers.length; i++) {
        if (!mounted) return;
        _controllers[i].forward();
        await Future.delayed(const Duration(milliseconds: 120));
      }
      await Future.delayed(const Duration(milliseconds: 200));
      for (final c in _controllers) {
        c.reverse();
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ChatTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md + 2,
        vertical: Insets.md,
      ),
      decoration: BoxDecoration(
        color: chat.incoming,
        border: Border.all(color: chat.incomingBorder, width: 0.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(Radii.bubble),
          topRight: Radius.circular(Radii.bubble),
          bottomRight: Radius.circular(Radii.bubble),
          bottomLeft: Radius.circular(Radii.bubbleJoined),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (context, _) {
              return Transform.translate(
                offset: Offset(0, _animations[i].value),
                child: Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: chat.incomingMeta,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
