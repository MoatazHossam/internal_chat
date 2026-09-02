import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/models/message.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';

class ChatController extends GetxController {
  final _api    = Get.find<ApiService>();
  final _socket = Get.find<SocketService>();

  final messages      = <Message>[].obs;
  final isConnected   = false.obs;
  final isLoadingMore = false.obs;
  final typingUsers   = <String>[].obs;

  late final String channelId;
  StreamSubscription? _msgSub;
  StreamSubscription? _connSub;

  @override
  void onInit() {
    super.onInit();
    channelId = Get.parameters['channelId']!;
    _loadHistory();
    _subscribeSocket();
  }

  Future<void> _loadHistory() async {
    final result = await _api.get(
      '/channels/$channelId/messages?limit=50',
      (j) => (j['messages'] as List)
          .map((m) => Message.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
    if (result is ApiSuccess<List<Message>>) {
      // API returns newest-first; index 0 = bottom with ListView reverse:true
      messages.assignAll(result.data);
    }
  }

  void _subscribeSocket() {
    _connSub = _socket.connectionState.listen(
      (s) => isConnected.value = s == SocketState.connected,
    );
    _msgSub = _socket.messagesFor(channelId).listen((event) {
      switch (event.type) {
        case 'new_message':
          final msg = Message.fromJson(event.data);
          if (!messages.any((m) => m.id == msg.id)) {
            messages.insert(0, msg);
          }
        case 'typing':
          _updateTyping(event.data['userId'] as String);
        case 'message_deleted':
          messages.removeWhere((m) => m.id == event.data['id']);
      }
    });
  }

  Future<void> sendMessage(
    String text, {
    List<String> attachmentIds = const [],
    MessageType type = MessageType.normal,
    MediaAttachment? media,
  }) async {
    if (text.isEmpty && attachmentIds.isEmpty && media == null) return;

    final otpCode = type == MessageType.otpLocked ? _generateOtp() : null;

    final optimistic = Message.optimistic(
      text:      text,
      channelId: channelId,
      type:      type,
      otpCode:   otpCode,
      media:     media,
    );
    messages.insert(0, optimistic);

    final result = await _api.post(
      '/channels/$channelId/messages',
      {
        'text':           text,
        'attachment_ids': attachmentIds,
        'type':           optimistic.typeString,
        if (otpCode != null) 'otp_code': otpCode,
        if (media != null) 'media': media.toJson(),
      },
      Message.fromJson,
    );

    if (result is ApiSuccess<Message>) {
      final idx = messages.indexWhere((m) => m.id == optimistic.id);
      if (idx != -1) messages[idx] = result.data;
    } else {
      messages.removeWhere((m) => m.id == optimistic.id);
      Get.snackbar('خطأ', 'فشل إرسال الرسالة',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ── View-once ────────────────────────────────────────────────────────────

  void markViewedAndScheduleDelete(
    String messageId, {
    Duration revealDuration = const Duration(seconds: 5),
  }) {
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    messages[idx] = messages[idx].copyWith(viewed: true);
    Future.delayed(revealDuration, () {
      messages.removeWhere((m) => m.id == messageId);
    });
  }

  // ── OTP-locked ───────────────────────────────────────────────────────────

  /// Simulates sending an SMS with the OTP.
  /// Returns the OTP so the UI can show a snackbar simulating SMS receipt.
  String requestOtpForMessage(String messageId) {
    final msg = messages.firstWhereOrNull((m) => m.id == messageId);
    final code = msg?.otpCode ?? '000000';
    // Simulate SMS delivery with a short delay
    Future.delayed(const Duration(seconds: 2), () {
      Get.snackbar(
        '📱 رسالة SMS',
        'رمز التحقق الخاص بك: $code',
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 6),
        backgroundColor: const Color(0xFF1A1A2E),
        colorText: const Color(0xFFFFFFFF),
        icon: const Icon(Icons.sms, color: Colors.greenAccent),
      );
    });
    return code;
  }

  /// Returns true if the OTP matches and unlocks the message.
  bool verifyAndUnlock(String messageId, String enteredOtp) {
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return false;
    final msg = messages[idx];
    if (msg.otpCode == null || msg.otpCode != enteredOtp.trim()) return false;
    messages[idx] = msg.copyWith(unlocked: true);
    return true;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _updateTyping(String userId) {
    if (!typingUsers.contains(userId)) typingUsers.add(userId);
    Future.delayed(
      const Duration(seconds: 3), () => typingUsers.remove(userId));
  }

  Future<void> loadMoreMessages() async {
    if (isLoadingMore.value || messages.isEmpty) return;
    isLoadingMore.value = true;
    await Future.delayed(const Duration(milliseconds: 500));
    isLoadingMore.value = false;
  }

  String _generateOtp() =>
      (100000 + Random.secure().nextInt(900000)).toString();

  @override
  void onClose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    super.onClose();
  }
}

