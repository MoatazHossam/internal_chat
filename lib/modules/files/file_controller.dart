import 'package:get/get.dart';

import '../../models/api_result.dart';
import '../../models/file_models.dart';
import '../../repositories/file_repository.dart';

class FileController extends GetxController {
  FileController(this._repository);

  final FileRepository _repository;

  final uploads = <UploadedFile>[].obs;
  final error = RxnString();

  Future<void> upload(FileSelection file) async {
    final result = await _repository.upload(file);
    switch (result) {
      case ApiSuccess(value: final value):
        uploads.add(value);
      case ApiFailure(error: final e):
        error.value = e.message;
    }
  }
}
