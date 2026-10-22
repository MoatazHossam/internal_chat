import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../domain/chat_backend.dart';
import '../../domain/chat_failure.dart';
import '../../domain/ids.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/failure_listener.dart';
import 'chat_controller.dart';

class ConversationInfoController extends GetxController {
  ConversationInfoController(this._conversations, this.conversationId);

  final Conversations _conversations;
  final ConversationId conversationId;

  final members = <Member>[].obs;
  final canInvite = false.obs;
  final loading = true.obs;
  final failure = Rxn<ChatFailure>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    await _guard(() async {
      final result = await _conversations.members(conversationId);
      members.assignAll(result.members);
      canInvite.value = result.canInvite;
    });
    loading.value = false;
  }

  Future<void> invite(UserId user) async {
    await _guard(() => _conversations.invite(conversationId, user));
    await load();
  }

  Future<void> remove(Member member) async {
    await _guard(() => _conversations.remove(conversationId, member.id));
    await load();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ChatFailure catch (error) {
      failure.value = error;
      failure.refresh();
    }
  }
}

class ConversationInfoBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => ConversationInfoController(
        Get.find<Conversations>(),
        Get.arguments as ConversationId,
      ),
    );
  }
}

class ConversationInfoPage extends GetView<ConversationInfoController> {
  const ConversationInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chat = Get.find<ChatController>();
    final conversation = chat.conversations
        .where((c) => c.id == controller.conversationId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.conversationInfo)),
      floatingActionButton: Obx(
        () => controller.canInvite.value
            ? FloatingActionButton.extended(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(l10n.addMember),
                onPressed: () => _addMember(context, l10n, chat.defaultServer),
              )
            : const SizedBox.shrink(),
      ),
      body: FailureListener(
        failure: controller.failure,
        child: Obx(() {
          if (controller.loading.value && controller.members.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              if (conversation != null)
                ListTile(
                  leading: Icon(
                    conversation.isEncrypted
                        ? Icons.lock_outline
                        : Icons.no_encryption_outlined,
                  ),
                  title: Text(
                    conversation.isEncrypted
                        ? l10n.encryptionInfo
                        : l10n.notEncryptedComposer,
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  l10n.membersTitle(controller.members.length),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final member in controller.members)
                ListTile(
                  leading: AvatarWidget(name: member.displayName, radius: 20),
                  title: Text(member.displayName),
                  subtitle: Text(member.id.value),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (member.isInvited)
                        _RoleChip(label: l10n.invited)
                      else if (member.role == MemberRole.admin)
                        _RoleChip(label: l10n.roleAdmin)
                      else if (member.role == MemberRole.moderator)
                        _RoleChip(label: l10n.roleModerator),
                      if (member.canRemove)
                        IconButton(
                          tooltip: l10n.removeMember,
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () =>
                              _confirmRemove(context, l10n, member),
                        ),
                    ],
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _addMember(
    BuildContext context,
    AppLocalizations l10n,
    String server,
  ) async {
    final input = TextEditingController();
    String? error;
    final user = await showDialog<UserId>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          void submit() {
            final id = parseUserId(input.text, defaultServer: server);
            if (id == null) {
              setState(
                () => error = l10n.errorInvalidUserId(
                  '@name:${server.isEmpty ? 'server' : server}',
                ),
              );
              return;
            }
            Navigator.pop(dialogContext, id);
          }

          return AlertDialog(
            title: Text(l10n.addMember),
            content: TextField(
              controller: input,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.userIdLabel,
                errorText: error,
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancel),
              ),
              FilledButton(onPressed: submit, child: Text(l10n.addMember)),
            ],
          );
        },
      ),
    );
    if (user != null) await controller.invite(user);
  }

  Future<void> _confirmRemove(
    BuildContext context,
    AppLocalizations l10n,
    Member member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removeMember),
        content: Text(l10n.removeMemberConfirm(member.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.removeMember),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.remove(member);
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: scheme.onSecondaryContainer),
      ),
    );
  }
}
