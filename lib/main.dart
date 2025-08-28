import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/transaction_screen.dart';
import 'screens/match_screen.dart';
import 'screens/agreement_screen.dart';
import 'screens/rating_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/settings_screen.dart';   // ✅ Add
import 'screens/history_screen.dart';    // ✅ Add
import 'screens/notifications_screen.dart';    // ✅ Add

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CashLink',
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
        '/settings': (_) => const SettingsScreen(),   // ✅ Add
        '/history': (_) => const HistoryScreen(),     // ✅ Add
        '/notifications': (_) => const NotificationsScreen(),     // ✅ Add
      },
    );
  }
}
