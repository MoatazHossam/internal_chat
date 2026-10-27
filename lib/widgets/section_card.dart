import 'package:flutter/material.dart';

import '../styles/tokens.dart';

/// A titled group of rows on a rounded card, for settings-style pages.
/// Rows are separated by hairlines that start after the leading icon.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(indent: 68));
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              0,
              Insets.lg,
              Insets.sm,
            ),
            child: Text(
              title!.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        Card(child: Column(children: rows)),
      ],
    );
  }
}

/// An icon on a soft tinted square, for list rows.
class TileIcon extends StatelessWidget {
  const TileIcon(this.icon, {super.key, this.color});

  final IconData icon;

  /// Defaults to the primary colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Icon(icon, size: 20, color: tint),
    );
  }
}
