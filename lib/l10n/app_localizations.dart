import 'dart:async';
import 'package:flutter/widgets.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ar'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'appTitle': 'CashLink',
      'home': 'Home',
      'profile': 'Profile',
      'history': 'History',
      'settings': 'Settings',
      'login': 'Login',
      'signup': 'Sign Up',
      'logout': 'Logout',
      'changeLanguage': 'Change Language',
      'waitingForOther': 'Waiting for the other party to accept your request...',
      'agreementTitle': 'Agreement',
      'confirmTransaction': 'Confirm Transaction',
      'rateUser': 'Rate User',
      'notifications': 'Notifications',
      'deposit': 'Deposit',
      'withdraw': 'Withdraw',
    },
    'ar': {
      'appTitle': 'كاش لينك',
      'home': 'الرئيسية',
      'profile': 'الملف الشخصي',
      'history': 'السجل',
      'settings': 'الإعدادات',
      'login': 'تسجيل الدخول',
      'signup': 'إنشاء حساب',
      'logout': 'تسجيل الخروج',
      'changeLanguage': 'تغيير اللغة',
      'waitingForOther': 'في انتظار الطرف الآخر لقبول طلبك...',
      'agreementTitle': 'الاتفاق',
      'confirmTransaction': 'تأكيد المعاملة',
      'rateUser': 'تقييم المستخدم',
      'notifications': 'الإشعارات',
      'deposit': 'إيداع',
      'withdraw': 'سحب',
    },
  };

  String _t(String key) {
    final lang = locale.languageCode;
    return _localizedValues[lang]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }

  // Common getters used in the app
  String get appTitle => _t('appTitle');
  String get home => _t('home');
  String get profile => _t('profile');
  String get history => _t('history');
  String get settings => _t('settings');
  String get login => _t('login');
  String get signup => _t('signup');
  String get logout => _t('logout');
  String get changeLanguage => _t('changeLanguage');
  String get waitingForOther => _t('waitingForOther');
  String get agreementTitle => _t('agreementTitle');
  String get confirmTransaction => _t('confirmTransaction');
  String get rateUser => _t('rateUser');
  String get notifications => _t('notifications');
  String get deposit => _t('deposit');
  String get withdraw => _t('withdraw');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales
          .any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) {
    // Synchronous in-memory loading without SynchronousFuture
    return Future.value(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
