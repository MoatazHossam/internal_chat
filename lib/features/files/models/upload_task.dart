enum UploadStatus { pending, encrypting, uploading, paused, done, failed }

class UploadTask {
  final String id;
  final String filePath;
  final String fileName;
  final int fileSize;
  UploadStatus status;
  double progress;
  int chunksTotal;
  int chunksUploaded;
  String? serverFileId;
  String? error;

  UploadTask({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
    this.chunksTotal = 0,
    this.chunksUploaded = 0,
  });
}
