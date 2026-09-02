import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/channel_controller.dart';
import '../../../core/models/channel.dart';
import '../../../features/auth/controllers/auth_controller.dart';
import '../../../app/theme/app_theme.dart';

// ─── Hospitality quick options ────────────────────────────────────────────────

const _kHospitalityOptions = [
  (icon: '☕', label: 'قهوة عربية وتمر للضيوف'),
  (icon: '🍵', label: 'شاي وبسكويت'),
  (icon: '💧', label: 'مياه وعصائر'),
  (icon: '🍽️', label: 'ترتيب قاعة الاجتماعات'),
];

class ChannelListView extends GetView<ChannelController> {
  const ChannelListView({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('داخلي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              Obx(() => Text(
                auth.currentUser.value?.name ?? '',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              )),
            ],
          ),
          actions: [
            Obx(() {
              final name = auth.currentUser.value?.name ?? '?';
              return CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.uaeRed,
                child: Text(
                  name.isNotEmpty ? name[0] : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              );
            }),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => _confirmLogout(context, auth),
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppTheme.uaeRed,
            indicatorWeight: 3,
            tabs: [
              Tab(icon: Icon(Icons.tag), text: 'Rooms'),
              Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Direct'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showHospitalitySheet(context),
          backgroundColor: AppTheme.primary,
          icon: const Text('🫖', style: TextStyle(fontSize: 20)),
          label: const Text('طلب ضيافة',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      body: Obx(() {
          if (controller.isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }
          return TabBarView(
            children: [
              _RoomsList(
                channels: controller.rooms,
                onRefresh: controller.loadChannels,
              ),
              _DmsList(
                channels: controller.dms,
                onRefresh: controller.loadChannels,
              ),
            ],
          );
        }),
      ),
    );
  }

  void _showHospitalitySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _HospitalitySheet(controller: controller),
    );
  }

  void _confirmLogout(BuildContext context, AuthController auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.uaeRed),
            onPressed: () {
              Navigator.pop(ctx);
              auth.logout();
            },
            child: const Text('خروج'),
          ),
        ],
      ),
    );
  }
}

class _RoomsList extends StatelessWidget {
  final List<Channel> channels;
  final Future<void> Function() onRefresh;

  const _RoomsList({required this.channels, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Center(child: Text('لا توجد غرف'));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        itemCount: channels.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (ctx, i) => _RoomTile(channel: channels[i]),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final Channel channel;
  const _RoomTile({required this.channel});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.uaeGreen.withValues(alpha: 0.15),
        child: Text(
          '#',
          style: TextStyle(
            color: AppTheme.uaeGreen,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              channel.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (channel.unreadCount > 0) ...[
            const SizedBox(width: 8),
            _UnreadBadge(count: channel.unreadCount),
          ],
        ],
      ),
      subtitle: channel.lastMessage != null
          ? Text(channel.lastMessage!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: channel.lastMessageAt != null
          ? Text(_fmt(channel.lastMessageAt!), style: Theme.of(context).textTheme.bodySmall)
          : null,
      onTap: () => Get.toNamed(
        '/chat/${channel.id}',
        parameters: {'channelId': channel.id, 'channelName': channel.name},
      ),
    );
  }
}

class _DmsList extends StatelessWidget {
  final List<Channel> channels;
  final Future<void> Function() onRefresh;

  const _DmsList({required this.channels, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Center(child: Text('لا توجد محادثات مباشرة'));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        itemCount: channels.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (ctx, i) => _DmTile(channel: channels[i]),
      ),
    );
  }
}

class _DmTile extends StatelessWidget {
  final Channel channel;
  const _DmTile({required this.channel});

  @override
  Widget build(BuildContext context) {
    final name = channel.dmParticipantName ?? channel.name;
    final initials = _initials(name);
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.uaeRed.withValues(alpha: 0.15),
            child: Text(
              initials,
              style: const TextStyle(
                color: AppTheme.uaeRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Online indicator dot
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (channel.unreadCount > 0) ...[
            const SizedBox(width: 8),
            _UnreadBadge(count: channel.unreadCount),
          ],
        ],
      ),
      subtitle: channel.lastMessage != null
          ? Text(channel.lastMessage!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: channel.lastMessageAt != null
          ? Text(_fmt(channel.lastMessageAt!), style: Theme.of(context).textTheme.bodySmall)
          : null,
      onTap: () => Get.toNamed(
        '/chat/${channel.id}',
        parameters: {
          'channelId': channel.id,
          'channelName': name,
          'isDirect': 'true',
        },
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.uaeRed,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

String _fmt(DateTime dt) {
  final now = DateTime.now();
  if (now.difference(dt).inDays == 0) return DateFormat.jm().format(dt);
  if (now.difference(dt).inDays < 7) return DateFormat.E().format(dt);
  return DateFormat.MMMd().format(dt);
}

// ─── Hospitality bottom sheet ─────────────────────────────────────────────────

class _HospitalitySheet extends StatefulWidget {
  final ChannelController controller;
  const _HospitalitySheet({required this.controller});

  @override
  State<_HospitalitySheet> createState() => _HospitalitySheetState();
}

class _HospitalitySheetState extends State<_HospitalitySheet> {
  int?   _selectedIdx;
  final  _textCtrl  = TextEditingController();
  bool   _sending   = false;

  String get _order {
    if (_textCtrl.text.trim().isNotEmpty) return _textCtrl.text.trim();
    if (_selectedIdx != null) return _kHospitalityOptions[_selectedIdx!].label;
    return '';
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_order.isEmpty) return;
    setState(() => _sending = true);
    final ok = await widget.controller.sendHospitalityRequest(_order);
    setState(() => _sending = false);
    if (!mounted) return;
    Navigator.pop(context);
    Get.snackbar(
      ok ? '✅ تم إرسال الطلب' : '❌ فشل الإرسال',
      ok ? 'سيصلك خالد قريباً 🫖' : 'حاول مجدداً',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
      backgroundColor: ok ? AppTheme.primary : Colors.red.shade400,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              border: Border(
                bottom: BorderSide(color: AppTheme.primary.withValues(alpha: 0.15)),
              ),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Text('🫖', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('طلب ضيافة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('سيصلك خالد في أقرب وقت',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ]),
            ]),
          ),
          // Quick options
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('طلبات جاهزة',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(_kHospitalityOptions.length, (i) {
                final opt      = _kHospitalityOptions[i];
                final selected = _selectedIdx == i;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedIdx = selected ? null : i;
                    if (!selected) _textCtrl.clear();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : Colors.grey.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? AppTheme.primary : Colors.grey.shade300,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(opt.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(opt.label,
                          style: TextStyle(
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            color: selected ? AppTheme.primary : null,
                          )),
                    ]),
                  ),
                );
              }),
            ),
          ),
          // Free text
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('أو اكتب طلبك',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: TextField(
              controller: _textCtrl,
              maxLines: 2,
              onChanged: (_) {
                if (_textCtrl.text.trim().isNotEmpty) {
                  setState(() => _selectedIdx = null);
                }
              },
              decoration: InputDecoration(
                hintText: 'مثال: قهوة سادة بدون هيل، كوبان فقط...',
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.07),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
          // Send button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_order.isEmpty || _sending) ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_sending ? 'جارٍ الإرسال...' : 'إرسال الطلب لخالد',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
