import 'package:flutter/material.dart';

import '../../domain/ids.dart';
import '../../l10n/app_localizations.dart';
import 'chat_controller.dart';
import 'chat_navigation.dart';

Future<void> showNewConversationSheet(
  BuildContext context,
  ChatController controller,
) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: Text(l10n.newChat),
            onTap: () {
              Navigator.pop(sheetContext);
              showNewChatDialog(context, controller);
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: Text(l10n.newGroup),
            onTap: () {
              Navigator.pop(sheetContext);
              showNewGroupDialog(context, controller);
            },
          ),
        ],
      ),
    ),
  );
}

/// Asks for one user ID. The server's user directory only lists people who
/// already share a conversation, so a first chat needs the full ID.
Future<void> showNewChatDialog(
  BuildContext context,
  ChatController controller,
) async {
  final l10n = AppLocalizations.of(context)!;
  final server = controller.defaultServer;
  final input = TextEditingController();
  String? error;
  var busy = false;

  final id = await showDialog<ConversationId>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> submit() async {
          final userId = parseUserId(input.text, defaultServer: server);
          if (userId == null) {
            setState(() => error = l10n.errorInvalidUserId(_example(server)));
            return;
          }
          setState(() {
            busy = true;
            error = null;
          });
          final created = await controller.startDirectChat(userId);
          if (!dialogContext.mounted) return;
          if (created == null) {
            setState(() => busy = false);
            return;
          }
          Navigator.pop(dialogContext, created);
        }

        return AlertDialog(
          title: Text(l10n.newChat),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.newChatBody),
              const SizedBox(height: 16),
              TextField(
                controller: input,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: l10n.userIdLabel,
                  hintText: _example(server),
                  errorText: error,
                ),
                onSubmitted: (_) => submit(),
              ),
              if (busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(l10n.start),
            ),
          ],
        );
      },
    ),
  );
  if (id != null) openConversationPage(controller, id);
}

Future<void> showNewGroupDialog(
  BuildContext context,
  ChatController controller,
) async {
  final l10n = AppLocalizations.of(context)!;
  final server = controller.defaultServer;
  final name = TextEditingController();
  final members = TextEditingController();
  String? nameError;
  String? membersError;
  var busy = false;

  final id = await showDialog<ConversationId>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> submit() async {
          final ids = <UserId>[];
          String? invalid;
          for (final part in members.text.split(RegExp(r'[\s,;]+'))) {
            if (part.isEmpty) continue;
            final userId = parseUserId(part, defaultServer: server);
            if (userId == null) {
              invalid = part;
              break;
            }
            if (!ids.contains(userId)) ids.add(userId);
          }
          setState(() {
            nameError = name.text.trim().isEmpty
                ? l10n.groupNameRequired
                : null;
            membersError = invalid == null
                ? null
                : l10n.errorInvalidUserId(_example(server));
          });
          if (nameError != null || membersError != null) return;

          setState(() => busy = true);
          final created = await controller.createGroup(name.text, ids);
          if (!dialogContext.mounted) return;
          if (created == null) {
            setState(() => busy = false);
            return;
          }
          Navigator.pop(dialogContext, created);
        }

        return AlertDialog(
          title: Text(l10n.newGroup),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: l10n.groupNameLabel,
                    helperText: l10n.groupNameServerVisible,
                    helperMaxLines: 3,
                    errorText: nameError,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: members,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !busy,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.membersLabel,
                    hintText: _example(server),
                    helperText: l10n.membersHint,
                    errorText: membersError,
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(l10n.create),
            ),
          ],
        );
      },
    ),
  );
  if (id != null) openConversationPage(controller, id);
}

String _example(String server) => '@name:${server.isEmpty ? 'server' : server}';
