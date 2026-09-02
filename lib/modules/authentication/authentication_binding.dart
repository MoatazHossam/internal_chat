import 'package:get/get.dart'; import '../../repositories/authentication_repository.dart'; import 'authentication_controller.dart';
class AuthenticationBinding extends Bindings { @override void dependencies()=>Get.lazyPut(()=>AuthenticationController(Get.find<AuthenticationRepository>())); }
