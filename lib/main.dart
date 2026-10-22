import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'app_pages.dart';
import 'app_routes.dart';
import 'constants.dart';
import 'l10n/app_localizations.dart';
import 'modules/app_binding.dart';
import 'services/locale_service.dart';
import 'styles/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  runApp(InternalChatApp(configuration: AppConfiguration.fromEnvironment()));
}

class InternalChatApp extends StatelessWidget {
  const InternalChatApp({super.key, required this.configuration});

  final AppConfiguration configuration;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Internal Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      locale: LocaleService.current(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      initialBinding: AppBinding(configuration),
      initialRoute: AppRoutes.splash,
      getPages: AppPages.pages,
    );
  }
}
