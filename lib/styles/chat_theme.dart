import 'package:flutter/material.dart';

import 'palette.dart';

/// Colours specific to conversations, on top of the [ColorScheme].
@immutable
class ChatTheme extends ThemeExtension<ChatTheme> {
  const ChatTheme({
    required this.background,
    required this.outgoing,
    required this.onOutgoing,
    required this.outgoingMeta,
    required this.incoming,
    required this.onIncoming,
    required this.incomingMeta,
    required this.incomingBorder,
    required this.readReceipt,
    required this.highlight,
    required this.onHighlight,
    required this.identity,
  });

  /// Behind the message list.
  final Color background;

  /// The user's own bubbles.
  final Color outgoing;
  final Color onOutgoing;

  /// Time and ticks inside the user's own bubbles.
  final Color outgoingMeta;

  /// Other people's bubbles.
  final Color incoming;
  final Color onIncoming;
  final Color incomingMeta;
  final Color incomingBorder;

  /// "Read" ticks inside the user's own bubbles.
  final Color readReceipt;

  /// Search matches.
  final Color highlight;
  final Color onHighlight;

  /// Per-person colours for avatars and sender names.
  final List<Color> identity;

  static const light = ChatTheme(
    background: Palette.mist100,
    outgoing: Palette.indigo,
    onOutgoing: Colors.white,
    outgoingMeta: Color(0xCCFFFFFF),
    incoming: Palette.paper,
    onIncoming: Palette.ink,
    incomingMeta: Palette.inkSubtle,
    incomingBorder: Palette.mist300,
    readReceipt: Color(0xFF9BE8FF),
    highlight: Color(0xFFFFE27A),
    onHighlight: Palette.ink,
    identity: Palette.identityLight,
  );

  static const dark = ChatTheme(
    background: Palette.night,
    outgoing: Color(0xFF3E4BC8),
    onOutgoing: Colors.white,
    outgoingMeta: Color(0xB3FFFFFF),
    incoming: Palette.night200,
    onIncoming: Palette.snow,
    incomingMeta: Palette.snowMuted,
    incomingBorder: Palette.night300,
    readReceipt: Color(0xFF9BE8FF),
    highlight: Color(0xFFFFD54F),
    onHighlight: Palette.ink,
    identity: Palette.identityDark,
  );

  /// A stable colour for [key] (a user or conversation ID).
  Color identityFor(String key) {
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return identity[hash % identity.length];
  }

  static ChatTheme of(BuildContext context) =>
      Theme.of(context).extension<ChatTheme>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  ChatTheme copyWith({
    Color? background,
    Color? outgoing,
    Color? onOutgoing,
    Color? outgoingMeta,
    Color? incoming,
    Color? onIncoming,
    Color? incomingMeta,
    Color? incomingBorder,
    Color? readReceipt,
    Color? highlight,
    Color? onHighlight,
    List<Color>? identity,
  }) => ChatTheme(
    background: background ?? this.background,
    outgoing: outgoing ?? this.outgoing,
    onOutgoing: onOutgoing ?? this.onOutgoing,
    outgoingMeta: outgoingMeta ?? this.outgoingMeta,
    incoming: incoming ?? this.incoming,
    onIncoming: onIncoming ?? this.onIncoming,
    incomingMeta: incomingMeta ?? this.incomingMeta,
    incomingBorder: incomingBorder ?? this.incomingBorder,
    readReceipt: readReceipt ?? this.readReceipt,
    highlight: highlight ?? this.highlight,
    onHighlight: onHighlight ?? this.onHighlight,
    identity: identity ?? this.identity,
  );

  @override
  ChatTheme lerp(ChatTheme? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ChatTheme(
      background: mix(background, other.background),
      outgoing: mix(outgoing, other.outgoing),
      onOutgoing: mix(onOutgoing, other.onOutgoing),
      outgoingMeta: mix(outgoingMeta, other.outgoingMeta),
      incoming: mix(incoming, other.incoming),
      onIncoming: mix(onIncoming, other.onIncoming),
      incomingMeta: mix(incomingMeta, other.incomingMeta),
      incomingBorder: mix(incomingBorder, other.incomingBorder),
      readReceipt: mix(readReceipt, other.readReceipt),
      highlight: mix(highlight, other.highlight),
      onHighlight: mix(onHighlight, other.onHighlight),
      identity: t < 0.5 ? identity : other.identity,
    );
  }
}
