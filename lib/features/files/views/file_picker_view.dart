import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/upload_controller.dart';
import '../models/upload_task.dart';

class FilePickerView extends GetView<UploadController> {
  const FilePickerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(
          '${controller.doneCount}/${controller.totalFiles} uploaded',
        )),
        actions: [
          Obx(() {
            if (controller.completedFileIds.isEmpty) return const SizedBox.shrink();
            return TextButton(
              onPressed: _attachToMessage,
              child: const Text('Attach'),
            );
          }),
        ],
      ),
      body: Column(children: [
        // Overall progress
        Obx(() {
          final total = controller.totalFiles.value;
          final done  = controller.doneCount.value;
          return total > 0
              ? LinearProgressIndicator(value: done / total)
              : const SizedBox.shrink();
        }),
        Expanded(
          child: Obx(() {
            if (controller.queue.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.upload_file, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('No files selected'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: controller.pickFiles,
                      icon: const Icon(Icons.add),
                      label: const Text('Select files'),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              itemCount: controller.queue.length,
              itemBuilder: (ctx, i) {
                final task = controller.queue[i];
                return ListTile(
                  leading: _statusIcon(task.status),
                  title: Text(
                    task.fileName,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  subtitle: task.status == UploadStatus.uploading
                      ? LinearProgressIndicator(value: task.progress)
                      : Text(_statusLabel(task)),
                  trailing: task.status == UploadStatus.failed
                      ? IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () => controller.retryTask(task.id),
                        )
                      : null,
                );
              },
            );
          }),
        ),
      ]),
      floatingActionButton: Obx(() => controller.queue.isEmpty
          ? const SizedBox.shrink()
          : FloatingActionButton.extended(
              onPressed: controller.pickFiles,
              label: const Text('Add more'),
              icon: const Icon(Icons.add),
            )),
    );
  }

  Widget _statusIcon(UploadStatus s) {
    return switch (s) {
      UploadStatus.done       => const Icon(Icons.check_circle, color: Colors.green),
      UploadStatus.failed     => const Icon(Icons.error, color: Colors.red),
      UploadStatus.uploading  => const Icon(Icons.upload, color: Colors.blue),
      UploadStatus.encrypting => const Icon(Icons.lock, color: Colors.orange),
      UploadStatus.paused     => const Icon(Icons.pause_circle, color: Colors.grey),
      UploadStatus.pending    => const Icon(Icons.hourglass_empty, color: Colors.grey),
    };
  }

  String _statusLabel(UploadTask t) {
    return switch (t.status) {
      UploadStatus.done       => 'Uploaded',
      UploadStatus.failed     => t.error ?? 'Failed',
      UploadStatus.encrypting => 'Encrypting...',
      UploadStatus.paused     => 'Paused',
      UploadStatus.pending    => 'Waiting...',
      UploadStatus.uploading  => '${t.chunksUploaded}/${t.chunksTotal} chunks',
    };
  }

  void _attachToMessage() {
    final ids = controller.completedFileIds.toList();
    Get.back(result: ids);
  }
}
