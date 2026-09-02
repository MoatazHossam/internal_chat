import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../features/auth/controllers/auth_controller.dart';
import '../routes/app_routes.dart';

class AuthMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    final auth = Get.find<AuthController>();
    if (auth.currentUser.value == null) {
      return const RouteSettings(name: AppRoutes.login);
    }
    return null;
  }
}
