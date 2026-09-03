import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../l10n/app_localizations.dart';
import 'file_controller.dart';

class FilePage extends GetView<FileController> {
  const FilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.attachmentsTitle)),
      body: Obx(
        () => controller.uploads.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.attach_file,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.noAttachmentsYet,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: controller.uploads.length,
                itemBuilder: (context, index) {
                  final file = controller.uploads[index];
                  return ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(file.name),
                    subtitle: Text(file.id),
                  );
                },
              ),
      ),
    );
  }
}
