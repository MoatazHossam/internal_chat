import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Minimal WhatsApp-style voice-note playback control: a play/pause button,
/// a progress bar, and an elapsed/total time label.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    super.key,
    required this.source,
    required this.totalDuration,
    required this.accentColor,
  });

  /// Local file path (native platforms) or blob URL (web).
  final String source;
  final Duration totalDuration;
  final Color accentColor;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _duration = widget.totalDuration;
    _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
    });
    _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _state = PlayerState.stopped;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    final source =
        kIsWeb ? UrlSource(widget.source) : DeviceFileSource(widget.source);
    await _player.play(source, position: _position);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final duration = _duration ?? widget.totalDuration;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final isPlaying = _state == PlayerState.playing;
    final showElapsed = isPlaying || _position > Duration.zero;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _toggle,
          child: CircleAvatar(
            radius: 15,
            backgroundColor: widget.accentColor,
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              size: 17,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: widget.accentColor.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(widget.accentColor),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _format(showElapsed ? _position : duration),
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
