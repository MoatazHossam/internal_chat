import 'package:get/get.dart';
import '../controllers/upload_controller.dart';

class FilesBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => UploadController());
  }
}
