import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cashlink/l10n/app_localizations.dart';

import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/transaction_screen.dart';
import 'screens/match_screen.dart';
import 'screens/agreement_screen.dart';
import 'screens/rating_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/history_screen.dart';
import 'screens/notifications_screen.dart';
import 'widgets/request_banner.dart';
import 'widgets/request_notification_overlay.dart';
import 'services/notification_service.dart';
import 'services/voice_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize audio service for alert tones
  await VoiceService().initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  Locale _locale = const Locale('en');

  void setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          RequestBanner(
            child: MaterialApp(
              title: 'CashLink',
              debugShowCheckedModeBanner: false,
              locale: _locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(
                scaffoldBackgroundColor: Colors.white,
                primaryColor: Colors.white,
                colorScheme: ColorScheme.fromSwatch(
                  primarySwatch: Colors.grey,
                ).copyWith(
                  secondary: Colors.red,
                ),
                fontFamily: 'SansSerif',
                textTheme: const TextTheme(
                  headlineLarge: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontFamily: 'SansSerif',
                  ),
                  titleMedium: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    fontFamily: 'SansSerif',
                  ),
                  bodyMedium: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontFamily: 'SansSerif',
                  ),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'SansSerif',
                    ),
                  ),
                ),
                inputDecorationTheme: const InputDecorationTheme(
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.red),
                  ),
                ),
              ),
              initialRoute: '/',
              routes: {
                '/': (_) => const SplashScreen(),
                '/auth': (_) => const AuthScreen(),
                '/signup': (_) => const SignupScreen(),
                '/profile': (_) => const ProfileScreen(),
                '/home': (_) => const HomeScreen(),
                '/transaction': (_) => const TransactionScreen(),
                '/match': (_) => const MatchScreen(),
                '/agreement': (_) => const AgreementScreen(),
                '/rating': (_) => const RatingScreen(),
                '/settings': (_) => const SettingsScreen(),
                '/history': (_) => const HistoryScreen(),
                '/notifications': (_) => const NotificationsScreen(),
              },
            ),
          ),
          const RequestNotificationOverlay(),
        ],
      ),
    );
  }
}
