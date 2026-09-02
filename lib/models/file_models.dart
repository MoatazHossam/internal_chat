class FileSelection { const FileSelection({required this.name, required this.size, this.localPath}); final String name; final int size; final String? localPath; }
class UploadedFile { const UploadedFile({required this.id, required this.name}); final String id; final String name; }
