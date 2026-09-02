import 'package:get/get.dart';

import '../../repositories/file_repository.dart';
import 'file_controller.dart';

class FileBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => FileController(Get.find<FileRepository>()));
  }
}
