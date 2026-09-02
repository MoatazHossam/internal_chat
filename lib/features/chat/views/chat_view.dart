import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/chat_controller.dart';
import '../../../core/models/message.dart';
import '../../../core/services/socket_service.dart';
import '../../../features/auth/controllers/auth_controller.dart';
import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_theme.dart';

// ─── Chat screen ─────────────────────────────────────────────────────────────

class ChatView extends GetView<ChatController> {
  ChatView({super.key});

  final _textCtrl   = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  Widget build(BuildContext context) {
    final channelName = Get.parameters['channelName'] ?? '';
    final isDirect    = Get.parameters['isDirect'] == 'true';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isDirect ? channelName : '#$channelName'),
            Obx(() => controller.isConnected.value
                ? const Text('متصل',
                    style: TextStyle(fontSize: 11, color: Colors.greenAccent))
                : const Text('جارٍ الاتصال...',
                    style: TextStyle(fontSize: 11, color: Colors.orangeAccent))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: () => Get.toNamed(
              AppRoutes.files.replaceFirst(':channelId', controller.channelId),
              parameters: {'channelId': controller.channelId},
            ),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Obx(() => ListView.builder(
            controller: _scrollCtrl,
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: controller.messages.length,
            itemBuilder: (ctx, i) {
              if (i == controller.messages.length - 1) {
                controller.loadMoreMessages();
              }
              return _MessageBubble(
                message: controller.messages[i],
                onViewOnce: controller.markViewedAndScheduleDelete,
              );
            },
          )),
        ),
        Obx(() {
          if (controller.typingUsers.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('${controller.typingUsers.length} يكتب...',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          );
        }),
        _MessageInputArea(
          textCtrl: _textCtrl,
          onSend: (text, type, media) {
            controller.sendMessage(text, type: type, media: media);
            _textCtrl.clear();
          },
          onTyping: () =>
              Get.find<SocketService>().sendTyping(controller.channelId),
        ),
      ]),
    );
  }
}

// ─── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Message           message;
  final void Function(String) onViewOnce;

  const _MessageBubble({required this.message, required this.onViewOnce});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final isMe = message.senderId == auth.currentUser.value?.id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _Avatar(name: message.senderName),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(message.senderName,
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
                _buildContent(context, isMe),
                _Timestamp(message: message, isMe: isMe),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isMe) {
    // Media messages take priority over type switches
    if (message.media != null) {
      return _MediaBubble(message: message, isMe: isMe);
    }
    return switch (message.type) {
      MessageType.viewOnce  =>
        _ViewOnceBubble(message: message, isMe: isMe, onView: onViewOnce),
      MessageType.otpLocked =>
        _OtpLockedBubble(message: message, isMe: isMe),
      MessageType.normal    =>
        _NormalBubble(message: message, isMe: isMe),
    };
  }
}

// ─── Normal bubble ────────────────────────────────────────────────────────────

class _NormalBubble extends StatelessWidget {
  final Message message;
  final bool    isMe;
  const _NormalBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: _bubbleDecoration(context, isMe),
        child: Text(
          message.text,
          style: TextStyle(
            color: isMe
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
}

// ─── Media bubble ─────────────────────────────────────────────────────────────

class _MediaBubble extends StatelessWidget {
  final Message message;
  final bool    isMe;
  const _MediaBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final media = message.media!;
    return switch (media.type) {
      MediaType.voice => _VoiceContent(media: media, isMe: isMe),
      MediaType.image => _ImageContent(media: media, isMe: isMe, caption: message.text),
      MediaType.video => _VideoContent(media: media, isMe: isMe, caption: message.text),
    };
  }
}

// ── Voice ────────────────────────────────────────────────────────────────────

class _VoiceContent extends StatefulWidget {
  final MediaAttachment media;
  final bool            isMe;
  const _VoiceContent({required this.media, required this.isMe});

  @override
  State<_VoiceContent> createState() => _VoiceContentState();
}

class _VoiceContentState extends State<_VoiceContent>
    with SingleTickerProviderStateMixin {
  bool   _playing  = false;
  int    _elapsed  = 0;
  Timer? _timer;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_playing) {
      _timer?.cancel();
      _pulse.stop();
      setState(() => _playing = false);
    } else {
      _elapsed = 0;
      _pulse.repeat(reverse: true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _elapsed++;
          if (_elapsed >= widget.media.durationSeconds) {
            _elapsed = widget.media.durationSeconds;
            _timer?.cancel();
            _pulse.stop();
            _playing = false;
          }
        });
      });
      setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color    = widget.isMe ? Colors.white : AppTheme.uaeGreen;
    final bgColor  = widget.isMe
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final dur      = widget.media.durationSeconds;
    final progress = dur > 0 ? _elapsed / dur : 0.0;

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        GestureDetector(
          onTap: _toggle,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: _playing ? 0.9 - _pulse.value * 0.2 : 0.2),
              ),
              child: Icon(
                _playing ? Icons.pause : Icons.play_arrow,
                color: widget.isMe ? Theme.of(context).colorScheme.primary : color,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Waveform bars
              _WaveformBars(progress: progress, color: color, seed: widget.media.durationSeconds),
              const SizedBox(height: 4),
              Text(
                _fmt(_playing ? _elapsed : dur),
                style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

class _WaveformBars extends StatelessWidget {
  final double progress;
  final Color  color;
  final int    seed;
  const _WaveformBars({required this.progress, required this.color, required this.seed});

  @override
  Widget build(BuildContext context) {
    final rng    = Random(seed);
    final count  = 24;
    final played = (count * progress).round();
    return Row(
      children: List.generate(count, (i) {
        final h = 4.0 + rng.nextDouble() * 14;
        return Expanded(
          child: Container(
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: i < played
                  ? color
                  : color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

// ── Image ────────────────────────────────────────────────────────────────────

class _ImageContent extends StatelessWidget {
  final MediaAttachment media;
  final bool            isMe;
  final String          caption;
  const _ImageContent({required this.media, required this.isMe, required this.caption});

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (media.localPath != null && File(media.localPath!).existsSync()) {
      imageWidget = Image.file(
        File(media.localPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    } else {
      imageWidget = _placeholder(context);
    }

    return GestureDetector(
      onTap: () => _showFullscreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              height: 180,
              child: imageWidget,
            ),
            if (caption.isNotEmpty)
              Container(
                color: isMe
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(caption,
                    style: TextStyle(
                      color: isMe
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                      fontSize: 13,
                    )),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
        width: 220,
        height: 180,
        color: Colors.grey.shade300,
        child: const Icon(Icons.image, size: 48, color: Colors.grey),
      );

  void _showFullscreen(BuildContext context) {
    if (media.localPath == null || !File(media.localPath!).existsSync()) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: Image.file(File(media.localPath!)),
          ),
        ),
      ),
    );
  }
}

// ── Video ────────────────────────────────────────────────────────────────────

class _VideoContent extends StatelessWidget {
  final MediaAttachment media;
  final bool            isMe;
  final String          caption;
  const _VideoContent({required this.media, required this.isMe, required this.caption});

  @override
  Widget build(BuildContext context) {
    final name = media.localPath != null
        ? media.localPath!.split('/').last
        : 'video.mp4';
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 220,
            height: 140,
            color: Colors.black87,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, size: 40, color: Colors.white54),
                    const SizedBox(height: 4),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30),
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
          if (caption.isNotEmpty)
            Container(
              color: isMe
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(caption,
                  style: TextStyle(
                    color: isMe
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface,
                    fontSize: 13,
                  )),
            ),
        ],
      ),
    );
  }
}

// ─── View-once bubble ────────────────────────────────────────────────────────

class _ViewOnceBubble extends StatelessWidget {
  final Message           message;
  final bool              isMe;
  final void Function(String) onView;
  const _ViewOnceBubble({required this.message, required this.isMe, required this.onView});

  @override
  Widget build(BuildContext context) {
    if (isMe) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: _bubbleDecoration(context, isMe),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.local_fire_department, size: 16, color: Colors.orangeAccent),
          const SizedBox(width: 6),
          Flexible(child: Text(message.text,
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary))),
        ]),
      );
    }
    if (!message.viewed) {
      return GestureDetector(
        onTap: () => onView(message.id),
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.local_fire_department, size: 20, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('اضغط للعرض',
                  style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
              Text('تختفي بعد المشاهدة',
                  style: TextStyle(color: Colors.deepPurple.withValues(alpha: 0.7), fontSize: 11)),
            ]),
          ]),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(message.text, style: const TextStyle(color: Colors.deepPurple)),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.local_fire_department, size: 12, color: Colors.deepPurple),
          const SizedBox(width: 4),
          Text('تختفي الآن...',
              style: TextStyle(fontSize: 10, color: Colors.deepPurple.withValues(alpha: 0.7))),
        ]),
      ]),
    );
  }
}

// ─── OTP-locked bubble ───────────────────────────────────────────────────────

class _OtpLockedBubble extends StatelessWidget {
  final Message message;
  final bool    isMe;
  const _OtpLockedBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    if (isMe) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.uaeGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.uaeGreen.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock, size: 14, color: AppTheme.uaeGreen),
          const SizedBox(width: 6),
          Flexible(child: Text(message.text,
              style: const TextStyle(color: AppTheme.uaeGreen))),
        ]),
      );
    }
    if (message.unlocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
            children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_open, size: 12, color: Colors.teal),
            const SizedBox(width: 4),
            Text('تم فتح الرسالة',
                style: TextStyle(fontSize: 10, color: Colors.teal.shade700)),
          ]),
          const SizedBox(height: 4),
          Text(message.text, style: TextStyle(color: Colors.teal.shade900)),
        ]),
      );
    }
    return GestureDetector(
      onTap: () => _showOtpDialog(context),
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.uaeRed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_outline, color: AppTheme.uaeRed, size: 20),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('رسالة محمية',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Text('اضغط لفتحها برمز OTP',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ]),
        ]),
      ),
    );
  }

  void _showOtpDialog(BuildContext context) {
    final ctrl     = Get.find<ChatController>();
    ctrl.requestOtpForMessage(message.id);
    final otpCtrl  = TextEditingController();
    final hasError = false.obs;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.lock_outline, color: AppTheme.uaeRed),
          SizedBox(width: 8),
          Text('أدخل رمز التحقق'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('تم إرسال رمز OTP إلى هاتفك عبر SMS.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          Obx(() => TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  hintStyle: const TextStyle(letterSpacing: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: hasError.value ? Colors.red : Colors.grey),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: hasError.value ? Colors.red : Colors.grey.shade300),
                  ),
                  errorText: hasError.value ? 'رمز غير صحيح، حاول مجدداً' : null,
                ),
                onChanged: (_) => hasError.value = false,
              )),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.uaeGreen),
            onPressed: () {
              final ok = ctrl.verifyAndUnlock(message.id, otpCtrl.text);
              if (ok) {
                Navigator.pop(ctx);
              } else {
                hasError.value = true;
              }
            },
            child: const Text('تحقق'),
          ),
        ],
      ),
    );
  }
}

// ─── Timestamp ────────────────────────────────────────────────────────────────

class _Timestamp extends StatelessWidget {
  final Message message;
  final bool    isMe;
  const _Timestamp({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(DateFormat.jm().format(message.createdAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
          if (isMe) ...[
            const SizedBox(width: 4),
            Icon(
              message.status == MessageStatus.sending ? Icons.access_time : Icons.done,
              size: 12,
              color: Colors.grey,
            ),
          ],
        ]),
      );
}

// ─── Avatar ───────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 14,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Text(
          name.isNotEmpty ? name[0] : '?',
          style: TextStyle(fontSize: 12,
              color: Theme.of(context).colorScheme.onSecondaryContainer),
        ),
      );
}

// ─── Input area (normal + recording modes) ────────────────────────────────────

class _MessageInputArea extends StatefulWidget {
  final TextEditingController textCtrl;
  final void Function(String text, MessageType type, MediaAttachment? media) onSend;
  final VoidCallback onTyping;

  const _MessageInputArea({
    required this.textCtrl,
    required this.onSend,
    required this.onTyping,
  });

  @override
  State<_MessageInputArea> createState() => _MessageInputAreaState();
}

class _MessageInputAreaState extends State<_MessageInputArea> {
  MessageType _mode       = MessageType.normal;
  bool        _recording  = false;
  int         _recSeconds = 0;
  Timer?      _recTimer;

  void _toggleMode(MessageType t) =>
      setState(() => _mode = (_mode == t) ? MessageType.normal : t);

  void _send() {
    final text = widget.textCtrl.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text, _mode, null);
    setState(() => _mode = MessageType.normal);
  }

  // ── Voice recording ──────────────────────────────────────────────────────

  void _startRecording() {
    setState(() {
      _recording  = true;
      _recSeconds = 0;
    });
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recSeconds++);
    });
  }

  void _cancelRecording() {
    _recTimer?.cancel();
    setState(() { _recording = false; _recSeconds = 0; });
  }

  void _sendVoice() {
    _recTimer?.cancel();
    final dur = _recSeconds;
    setState(() { _recording = false; _recSeconds = 0; });
    if (dur < 1) return;
    widget.onSend('', MessageType.normal,
        MediaAttachment(type: MediaType.voice, durationSeconds: dur));
  }

  // ── Media picking ─────────────────────────────────────────────────────────

  void _showAttachSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _SheetOption(
              icon: Icons.mic,
              label: 'تسجيل صوتي',
              color: Colors.deepOrange,
              onTap: () {
                Navigator.pop(context);
                _startRecording();
              },
            ),
            _SheetOption(
              icon: Icons.image,
              label: 'صورة',
              color: AppTheme.uaeGreen,
              onTap: () async {
                Navigator.pop(context);
                await _pickMedia(FileType.image);
              },
            ),
            _SheetOption(
              icon: Icons.videocam,
              label: 'فيديو',
              color: AppTheme.uaeRed,
              onTap: () async {
                Navigator.pop(context);
                await _pickMedia(FileType.video);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMedia(FileType fileType) async {
    final result = await FilePicker.platform.pickFiles(
      type: fileType,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    final mediaType = fileType == FileType.image ? MediaType.image : MediaType.video;
    widget.onSend('', MessageType.normal,
        MediaAttachment(type: mediaType, localPath: file.path));
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recording) return _buildRecordingBar(context);
    return _buildNormalBar(context);
  }

  // ── Recording bar ─────────────────────────────────────────────────────────

  Widget _buildRecordingBar(BuildContext context) {
    final mins = _recSeconds ~/ 60;
    final secs = _recSeconds % 60;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Row(children: [
        // Cancel
        IconButton(
          onPressed: _cancelRecording,
          icon: const Icon(Icons.delete_outline, color: Colors.grey),
        ),
        // Waveform + timer
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const _PulsingDot(),
              const SizedBox(width: 8),
              Text(
                '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.red, fontSize: 15),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('جارٍ التسجيل...',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        // Send
        IconButton.filled(
          style: IconButton.styleFrom(backgroundColor: AppTheme.uaeGreen),
          onPressed: _sendVoice,
          icon: const Icon(Icons.send),
        ),
      ]),
    );
  }

  // ── Normal input bar ──────────────────────────────────────────────────────

  Widget _buildNormalBar(BuildContext context) {
    final isViewOnce  = _mode == MessageType.viewOnce;
    final isOtpLocked = _mode == MessageType.otpLocked;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_mode != MessageType.normal)
        Container(
          width: double.infinity,
          color: isViewOnce
              ? Colors.deepPurple.withValues(alpha: 0.08)
              : AppTheme.uaeRed.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            Icon(
              isViewOnce ? Icons.local_fire_department : Icons.lock_outline,
              size: 14,
              color: isViewOnce ? Colors.deepPurple : AppTheme.uaeRed,
            ),
            const SizedBox(width: 6),
            Text(
              isViewOnce
                  ? 'رسالة تختفي بعد المشاهدة مرة واحدة'
                  : 'رسالة محمية — يحتاج المستلم رمز OTP للفتح',
              style: TextStyle(
                fontSize: 12,
                color: isViewOnce ? Colors.deepPurple : AppTheme.uaeRed,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _mode = MessageType.normal),
              child: const Icon(Icons.close, size: 14, color: Colors.grey),
            ),
          ]),
        ),
      Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, -2),
            )
          ],
        ),
        child: Row(children: [
          // Attach (image / video / voice)
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showAttachSheet(context),
            color: Colors.grey.shade600,
          ),
          // View-once toggle
          _ModeToggle(
            icon: Icons.local_fire_department,
            active: isViewOnce,
            activeColor: Colors.deepPurple,
            tooltip: 'View once',
            onTap: () => _toggleMode(MessageType.viewOnce),
          ),
          // OTP-locked toggle
          _ModeToggle(
            icon: Icons.lock_outline,
            active: isOtpLocked,
            activeColor: AppTheme.uaeRed,
            tooltip: 'OTP Protected',
            onTap: () => _toggleMode(MessageType.otpLocked),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: widget.textCtrl,
              onChanged: (_) => widget.onTyping(),
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: isOtpLocked
                    ? 'رسالة محمية...'
                    : isViewOnce
                        ? 'رسالة مؤقتة...'
                        : 'رسالة...',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: isViewOnce
                  ? Colors.deepPurple
                  : isOtpLocked
                      ? AppTheme.uaeRed
                      : AppTheme.uaeGreen,
            ),
            onPressed: _send,
            icon: Icon(isOtpLocked ? Icons.lock : Icons.send),
          ),
        ]),
      ),
    ]);
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  const _SheetOption({
    required this.icon, required this.label,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final IconData icon;
  final bool     active;
  final Color    activeColor;
  final String   tooltip;
  final VoidCallback onTap;
  const _ModeToggle({
    required this.icon, required this.active,
    required this.activeColor, required this.tooltip, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: IconButton(
          icon: Icon(icon, color: active ? activeColor : Colors.grey, size: 22),
          onPressed: onTap,
          style: active
              ? IconButton.styleFrom(
                  backgroundColor: activeColor.withValues(alpha: 0.12))
              : null,
        ),
      );
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withValues(alpha: 0.4 + _ctrl.value * 0.6),
          ),
        ),
      );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

BoxDecoration _bubbleDecoration(BuildContext context, bool isMe) => BoxDecoration(
      color: isMe
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: Radius.circular(isMe ? 16 : 4),
        bottomRight: Radius.circular(isMe ? 4 : 16),
      ),
    );
