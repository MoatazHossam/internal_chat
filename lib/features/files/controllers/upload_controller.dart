import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../models/upload_task.dart';
import '../../../core/services/api_service.dart';

class UploadController extends GetxController {
  final _api = Get.find<ApiService>();

  static const _maxFiles = 1000;

  final queue            = <UploadTask>[].obs;
  final totalFiles       = 0.obs;
  final doneCount        = 0.obs;
  final isUploading      = false.obs;
  final completedFileIds = <String>[].obs;

  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    if (result == null) return;

    final picked = result.files.take(_maxFiles).toList();
    totalFiles.value = picked.length;

    for (final f in picked) {
      if (f.path == null) continue;
      final task = UploadTask(
        id: const Uuid().v4(),
        filePath: f.path!,
        fileName: f.name,
        fileSize: f.size,
        chunksTotal: ((f.size / (5 * 1024 * 1024)).ceil()).clamp(1, 9999),
      );
      queue.add(task);
    }

    if (!isUploading.value) _processQueue();
  }

  Future<void> _processQueue() async {
    isUploading.value = true;
    for (final task in queue.where((t) => t.status == UploadStatus.pending).toList()) {
      await _uploadFile(task);
    }
    isUploading.value = false;
  }

  Future<void> _uploadFile(UploadTask task) async {
    // Simulate encrypt step
    task.status = UploadStatus.encrypting;
    queue.refresh();
    await Future.delayed(const Duration(milliseconds: 400));

    // Simulate upload init
    final initResult = await _api.post(
      '/files/upload/init',
      {
        'file_name': task.fileName,
        'file_size': task.fileSize,
        'chunks_total': task.chunksTotal,
        'mime_type': 'application/octet-stream',
      },
      (j) => j,
    );
    if (initResult is ApiError) {
      _failTask(task, (initResult as ApiError).message);
      return;
    }

    // Simulate chunk uploads
    task.status = UploadStatus.uploading;
    queue.refresh();
    for (int i = 0; i < task.chunksTotal; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      task.chunksUploaded = i + 1;
      task.progress = (i + 1) / task.chunksTotal;
      queue.refresh();
    }

    // Finalize
    final finalResult = await _api.post(
      '/files/upload/complete',
      {'upload_id': 'dummy_upload'},
      (j) => j['file_id'] as String,
    );
    if (finalResult is ApiSuccess<String>) {
      task.status = UploadStatus.done;
      task.serverFileId = finalResult.data;
      completedFileIds.add(finalResult.data);
      doneCount.value++;
    } else if (finalResult is ApiError) {
      _failTask(task, (finalResult as ApiError).message);
    }
    queue.refresh();
  }

  void retryTask(String id) {
    final task = queue.firstWhereOrNull((t) => t.id == id);
    if (task != null) {
      task.status = UploadStatus.pending;
      task.error = null;
      task.chunksUploaded = 0;
      task.progress = 0;
      queue.refresh();
      if (!isUploading.value) _processQueue();
    }
  }

  void _failTask(UploadTask task, String error) {
    task.status = UploadStatus.failed;
    task.error = error;
    queue.refresh();
  }
}

extension UploadIterableExt<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
