import 'package:flutter/widgets.dart';
import 'package:get_storage/get_storage.dart';

/// Persists the user's chosen display language across launches.
///
/// This is a UI display preference, not sensitive data, so `GetStorage`
/// is appropriate here (unlike tokens, which must never use it).
abstract final class LocaleService {
  static const _key = 'locale_code';

  static const supportedLocales = [Locale('en'), Locale('ar')];

  static Locale current() {
    final code = GetStorage().read<String>(_key);
    return supportedLocales.firstWhere(
      (locale) => locale.languageCode == code,
      orElse: () => supportedLocales.first,
    );
  }

  static Future<void> set(Locale locale) => GetStorage().write(
        _key,
        locale.languageCode,
      );
}
