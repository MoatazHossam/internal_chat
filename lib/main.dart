import 'package:flutter/material.dart';import 'package:get/get.dart';import 'app_pages.dart';import 'app_routes.dart';import 'modules/app_binding.dart';import 'styles/app_theme.dart';
void main(){WidgetsFlutterBinding.ensureInitialized();runApp(const InternalChatApp());}
class InternalChatApp extends StatelessWidget{const InternalChatApp({super.key});@override Widget build(BuildContext context)=>GetMaterialApp(title:'Internal Chat',debugShowCheckedModeBanner:false,theme:AppTheme.light,initialBinding:AppBinding(),initialRoute:AppRoutes.login,getPages:AppPages.pages);}
