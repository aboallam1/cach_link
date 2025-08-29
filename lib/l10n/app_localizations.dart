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
      'pending': 'Pending',
      'accepted': 'Accepted',
      'rejected': 'Rejected',
      'canceled': 'Canceled',
      'requested': 'Requested',
      'transactionHistory': 'Transaction History',
      'noTransactions': 'No transactions yet.',
      'details': 'Details',
      'name': 'Name',
      'gender': 'Gender',
      'amount': 'Amount',
      'distance': 'Distance',
      'status': 'Status',
      'accept': 'Accept',
      'reject': 'Reject',
      'close': 'Close',
      'locationShared': 'Set Location',
      'locationSharedMessage': 'Location Selected',
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
      'pending': 'قيد الانتظار',
      'accepted': 'تم القبول',
      'rejected': 'مرفوض',
      'canceled': 'ملغي',
      'requested': 'بانتظار الموافقة',
      'transactionHistory': 'تاريخ المعاملات',
      'noTransactions': 'لا توجد معاملات بعد.',
      'details': 'تفاصيل',
      'name': 'الاسم',
      'gender': 'الجنس',
      'amount': 'المبلغ',
      'distance': 'المسافة',
      'status': 'الحالة',
      'accept': 'قبول',
      'reject': 'رفض',
      'close': 'إغلاق',
      'locationShared': 'تحديد الموقع',
      'locationSharedMessage': 'تم اختيار الموقع',
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
  String get pending => _t('pending');
  String get accepted => _t('accepted');
  String get rejected => _t('rejected');
  String get canceled => _t('canceled');
  String get requested => _t('requested');
  String get transactionHistory => _t('transactionHistory');
  String get noTransactions => _t('noTransactions');
  String get details => _t('details');
  String get name => _t('name');
  String get gender => _t('gender');
  String get amount => _t('amount');
  String get distance => _t('distance');
  String get status => _t('status');
  String get accept => _t('accept');
  String get reject => _t('reject');
  String get close => _t('close');
  String get locationShared => _t('locationShared');
  String get locationSharedMessage => _t('locationSharedMessage');
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
