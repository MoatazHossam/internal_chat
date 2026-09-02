import '../models/api_result.dart'; import '../models/file_models.dart';
abstract interface class FileRepository { Future<ApiResult<UploadedFile>> upload(FileSelection file); }
