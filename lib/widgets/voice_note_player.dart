import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../utilities/temporary_media.dart';

/// Voice-note playback: a play/pause button, a progress bar and an
/// elapsed/total time label, coloured to match the bubble it sits in.
///
/// The audio is downloaded and decrypted on first play. On mobile it is
/// written to a temporary file for the platform player and deleted when this
/// widget goes away.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    super.key,
    required this.loadBytes,
    required this.totalDuration,
    required this.accentColor,
    this.onAccentColor = Colors.white,
    this.mimeType,
  });

  final Future<Uint8List> Function() loadBytes;
  final Duration totalDuration;
  final Color accentColor;

  /// The play icon on [accentColor].
  final Color onAccentColor;
  final String? mimeType;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration? _duration;
  Source? _source;
  File? _tempFile;
  bool _loading = false;
  bool _failed = false;

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
    if (_loading) return;
    try {
      final source = _source ??= await _prepareSource();
      await _player.play(source, position: _position);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<Source> _prepareSource() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final bytes = await widget.loadBytes();
      if (kIsWeb) return BytesSource(bytes, mimeType: widget.mimeType);
      final directory = await temporaryMediaDirectory();
      final name = 'vn-${Random.secure().nextInt(1 << 32)}${_extension()}';
      final file = File('${directory.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      _tempFile = file;
      return DeviceFileSource(file.path, mimeType: widget.mimeType);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The platform players pick the decoder from the file extension.
  String _extension() => switch (widget.mimeType) {
    'audio/ogg' || 'audio/opus' => '.ogg',
    'audio/mpeg' => '.mp3',
    'audio/wav' || 'audio/x-wav' => '.wav',
    _ => '.m4a',
  };

  @override
  void dispose() {
    _player.dispose();
    final file = _tempFile;
    if (file != null) {
      file.delete().then<void>((_) {}, onError: (Object _) {});
    }
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
        Material(
          color: widget.accentColor,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggle,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Center(
                child: _loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.onAccentColor,
                        ),
                      )
                    : Icon(
                        _failed
                            ? Icons.error_outline_rounded
                            : isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 24,
                        color: widget.onAccentColor,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: widget.accentColor.withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation(widget.accentColor),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _format(showElapsed ? _position : duration),
                style: const TextStyle(
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
