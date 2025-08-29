// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CashLink';

  @override
  String get home => 'Home';

  @override
  String get profile => 'Profile';

  @override
  String get history => 'History';

  @override
  String get settings => 'Settings';

  @override
  String get login => 'Login';

  @override
  String get signup => 'Sign Up';

  @override
  String get logout => 'Logout';

  @override
  String get changeLanguage => 'Change Language';

  @override
  String get waitingForOther => 'Waiting for the other party to accept your request...';

  @override
  String get agreementTitle => 'Agreement';

  @override
  String get confirmTransaction => 'Confirm Transaction';

  @override
  String get rateUser => 'Rate User';

  @override
  String get notifications => 'Notifications';

  @override
  String get deposit => 'Deposit';

  @override
  String get withdraw => 'Withdraw';
}
