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
      'code': 'Code',
      'waitingForOther': 'Waiting for the other party to accept your request...',
      'agreementTitle': 'Agreement',
      'confirmTransaction': 'Confirm Transaction',
      'findMatch': 'Search',
      'notifications': 'Notifications',
      'deposit': 'Deposit',
      'withdraw': 'Withdraw',
      'pending': 'Pending',
      'accepted': 'Accepted',
      'rejected': 'Rejected',
      'requested': 'Requested',
      'transactionHistory': 'Transactions History',
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
      'meetingWarning': 'Meet in a public place. Don’t hand over cash before confirming transfer.',
      'exchangeRequestFrom': 'Exchange',
      'cashReceived': 'Cash Received',
      'instapayTransferred': 'Transferred via Instapay',
      'exchangeCompleted': 'Exchange completed',
      'completed': 'Completed',
      'counterpartyDetails': 'Counterparty Details',
      'locationNotShared': 'Their location is not shared yet',
      'sharing': 'Sharing...',
      'sendMyLocation': 'Send My Location',
      'male': 'Male',
      'female': 'Female',
      'phone': 'Phone',
      'rating': 'Rating',
      'password': 'Password',
      'smsCode': 'SMS Code',
      'enterSmsCode': 'Enter SMS Code',
      'cancelled': 'Cancelled',
      'archived': 'Archived',
      'verify': 'Verify',
      'transactionType': 'Transaction Type',
      'save': 'Save',
      'filterBy': 'Filter By',
      'changeLanguage': 'Change Language',
      'Matches': 'Matches',
      'Create Transaction': 'Create Transaction',
      'New Transaction': 'New Transaction',
      'descriptionOfNewTransaction': 'Create a new transaction.',
      'expiresIn': 'Expires in',
      'activeTransaction': 'You already have a transaction, you cannot create a new one until the time expires or you cancel this transaction.',
      'noUsersFoundIn': 'No users found in',
      'km': 'km',
      'noUsersAvailableRequestSaved': 'Sorry, no users available at the moment, your request was saved',
      'expandSearch': 'Expand Search (+10km)',
      'rateUser': 'Rate User',
      'rateUserTransactionPartner': 'Rate your transaction partner:',
      'commentOptional': 'Comment (optional)',
      'submitRating': 'Submit Rating',
      'confirmCashReceived': 'Confirm Cash Received',
      'confirmInstapayTransfer': 'Confirm Instapay Transfer',
      'confirmTransfer': 'Confirm Transfer',
      'saveRequest': 'Save Request in (km)',
      'locationPermissionDenied': 'Location permission denied.',
      'locationSharedSuccessfully': 'Location shared successfully.',
      'waitingForCashConfirmation': 'Waiting for cash confirmation.',
      'waitingForInstapayConfirmation': 'Waiting for Instapay confirmation.',
      'latitude': 'Latitude',
      'longitude': 'Longitude',
      'openInMaps': 'Open in Maps',
      'transactionDetails': 'Transaction Details',
      'partnerDetails': 'Partner Details',
      'partnerRating': 'Partner Rating',
      'confirmationStatus': 'Confirmation Status',
      'confirmed': 'Confirmed',
      'notConfirmed': 'Not Confirmed',
      'instapayTransfer': 'Instapay Transfer',
      'ratingInformation': 'Rating Information',
      'yourRating': 'Your Rating',
      'theirRating': 'Their Rating',
      'notRatedYet': 'Not rated yet.',
      'transactionTimeline': 'Transaction Timeline',
      'created': 'Created',
      'ratePartner': 'Rate Partner',
    },
    'ar': {
      'appTitle': 'كاش لينك',
      'home': 'الرئيسية',
      'profile': 'الملف الشخصي',
      'history': 'السجل',
      'settings': 'الإعدادات',
      'login': 'تسجيل الدخول',
      'signup': 'ليس لديك حساب! إنشاء حساب',
      'logout': 'تسجيل الخروج',
      'code': 'الرمز',
      'waitingForOther': 'في انتظار الطرف الآخر لقبول طلبك...',
      'agreementTitle': 'الاتفاق',
      'confirmTransaction': 'تأكيد المعاملة',
      'findMatch': 'بحث',
      'notifications': 'الإشعارات',
      'deposit': 'إيداع',
      'withdraw': 'سحب',
      'pending': 'قيد الانتظار',
      'accepted': 'تم القبول',
      'rejected': 'مرفوض',
      'cancelled': 'تم الالغاء',
      'cancel': 'الغاء',
      'requested': 'بانتظار الموافقة',
      'transactionHistory': 'تاريخ المعاملات',
      'noTransactions': 'لا توجد معاملات بعد.',
      'details': 'التفاصيل',
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
      'meetingWarning': 'اجتمع في مكان عام. لا تسلم النقود قبل تأكيد التحويل.',
      'exchangeRequestFrom': 'تبادل ',
      'cashReceived': 'النقود المستلمة',
      'instapayTransferred': 'تم التحويل ',
      'exchangeCompleted': 'تمت عملية التبادل ',
      'completed': 'مكتمل',
      'counterpartyDetails': 'تفاصيل الطرف الآخر',
      'locationNotShared': 'لم يتم مشاركة موقعك ',
      'sharing': 'جارٍ المشاركة...',
      'sendMyLocation': 'أرسل موقعي',
      'male': 'ذكر',
      'female': 'أنثى',
      'phone': 'الهاتف',
      'rating': 'التقييم',
      'password': 'كلمة المرور',
      'smsCode': 'رمز الرسالة',
      'enterSmsCode': 'أدخل رمز التحقق',
      'archived': 'أرشيف',
      'confirm': 'تأكيد',
      'verify': 'تحقق',
      'transactionType': 'نوع المعاملة',
      'save': 'حفظ',
      'filterBy': 'اعطي اولوية ل',
      'changeLanguage': 'غير اللغة',
      'Matches': 'الطلبات المتشابهة',
      'Create Transaction': 'إنشاء معاملة',
      'New Transaction': 'معاملة جديدة',
      'descriptionOfNewTransaction': 'قم بإنشاء معاملة جديدة.',
      'expiresIn': 'ينتهي خلال',
      'activeTransaction': 'لديك معاملة بالفعل، لا يمكنك إنشاء معاملة جديدة حتى ينتهي الوقت أو تلغي هذه المعاملة.',
      'noUsersFoundIn': 'لا يوجد مستخدمون في نطاق',
      'km': 'كم',
      'noUsersAvailableRequestSaved': 'عذراً، لا يوجد مستخدمون حالياً، تم حفظ طلبك',
      'expandSearch': 'توسيع البحث (+10كم)',
      'rateUser': 'قيم المستخدم',
      'rateUserTransactionPartner': 'قيم شريك معاملتك:',
      'commentOptional': 'تعليق (اختياري)',
      'submitRating': 'إرسال التقييم',
      'confirmCashReceived': 'تأكيد استلام النقود',
      'confirmInstapayTransfer': 'تأكيد التحويل ',
      'confirmTransfer': 'تأكيد التحويل',
      'saveRequest': 'حفظ الطلب',
      'locationPermissionDenied': 'تم رفض إذن الموقع.',
      'locationSharedSuccessfully': 'تمت مشاركة الموقع بنجاح.',
      'waitingForCashConfirmation': 'في انتظار تأكيد استلام النقود.',
      'waitingForInstapayConfirmation': 'في انتظار تأكيد التحويل.',
      'latitude': 'خط العرض',
      'longitude': 'خط الطول',
      'openInMaps': 'افتح في الخرائط',
      'transactionDetails': 'تفاصيل المعاملة',
      'partnerDetails': 'تفاصيل الشريك',
      'partnerRating': 'تقييم الشريك',
      'confirmationStatus': 'حالة التأكيد',
      'confirmed': 'مؤكد',
      'notConfirmed': 'غير مؤكد',
      'instapayTransfer': 'تحويل إنستا باي',
      'ratingInformation': 'معلومات التقييم',
      'yourRating': 'تقييمك',
      'theirRating': 'تقييمهم',
      'notRatedYet': 'لم يتم تقييمه بعد.',
      'transactionTimeline': 'جدول زمني المعاملة',
      'created': 'تم الإنشاء',
      'ratePartner': 'قيم الشريك',
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
  String get filterBy => _t('filterBy');
  String get waitingForOther => _t('waitingForOther');
  String get agreementTitle => _t('agreementTitle');
  String get confirmTransaction => _t('confirmTransaction');
  String get findMatch => _t('findMatch');
  String get notifications => _t('notifications');
  String get deposit => _t('deposit');
  String get withdraw => _t('withdraw');
  String get pending => _t('pending');
  String get accepted => _t('accepted');
  String get rejected => _t('rejected');
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
  String get cancel => _t('cancel');
  String get archived => _t('archived');
  String get confirm => _t('confirm');
  String get locationShared => _t('locationShared');
  String get locationSharedMessage => _t('locationSharedMessage');
  String get meetingWarning => _t('meetingWarning');
  String get exchangeRequestFrom => _t('exchangeRequestFrom');
  String get cashReceived => _t('cashReceived');
  String get instapayTransferred => _t('instapayTransferred');
  String get exchangeCompleted => _t('exchangeCompleted');
  String get completed => _t('completed');
  String get counterpartyDetails => _t('counterpartyDetails');
  String get locationNotShared => _t('locationNotShared');
  String get sharing => _t('sharing');
  String get sendMyLocation => _t('sendMyLocation');
  String get male => _t('male');
  String get female => _t('female');
  String get phone => _t('phone');
  String get rating => _t('rating');
  String get code => _t('code');
  String get password => _t('password');
  String get smsCode => _t('smsCode');
  String get enterSmsCode => _t('enterSmsCode');
  String get cancelled => _t('cancelled');
  String get verify => _t('verify');
  String get transactionType => _t('transactionType');
  String get save => _t('save');
  String get changeLanguage => _t('changeLanguage');
  String get Matches => _t('Matches');
  String get CreateTransaction => _t('Create Transaction');
  String get NewTransaction => _t('New Transaction');
  String get descriptionOfNewTransaction => _t('descriptionOfNewTransaction');
  String get expiresIn => _t('expiresIn');
  String get activeTransaction => _t('activeTransaction');
  String get noUsersFoundIn => _t('noUsersFoundIn');
  String get km => _t('km');
  String get noUsersAvailableRequestSaved => _t('noUsersAvailableRequestSaved');
  String get expandSearch => _t('expandSearch');
  String get rateUser => _t('rateUser');
  String get rateUserTransactionPartner => _t('rateUserTransactionPartner');
  String get commentOptional => _t('commentOptional');
  String get submitRating => _t('submitRating');
  String get confirmCashReceived => _t('confirmCashReceived');
  String get confirmInstapayTransfer => _t('confirmInstapayTransfer');
  String get confirmTransfer => _t('confirmTransfer');
  String get saveRequest => _t('saveRequest');

  // Add missing getters for all new localization keys used in the app
  String get locationPermissionDenied => _t('locationPermissionDenied');
  String get locationSharedSuccessfully => _t('locationSharedSuccessfully');
  String get waitingForCashConfirmation => _t('waitingForCashConfirmation');
  String get waitingForInstapayConfirmation => _t('waitingForInstapayConfirmation');
  String get latitude => _t('latitude');
  String get longitude => _t('longitude');
  String get openInMaps => _t('openInMaps');
  String get transactionDetails => _t('transactionDetails');
  String get partnerDetails => _t('partnerDetails');
  String get partnerRating => _t('partnerRating');
  String get confirmationStatus => _t('confirmationStatus');
  String get confirmed => _t('confirmed');
  String get notConfirmed => _t('notConfirmed');
  String get instapayTransfer => _t('instapayTransfer');
  String get ratingInformation => _t('ratingInformation');
  String get yourRating => _t('yourRating');
  String get theirRating => _t('theirRating');
  String get notRatedYet => _t('notRatedYet');
  String get transactionTimeline => _t('transactionTimeline');
  String get created => _t('created');
  String get ratePartner => _t('ratePartner');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
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
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}
