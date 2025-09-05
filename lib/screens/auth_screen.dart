import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  String _countryCode = '+20'; // Default country code (Egypt)
  String _phone = '';
  String _password = '';
  bool _loading = false;
  String? _error;
  String? _verificationId;
  final TextEditingController _smsController = TextEditingController();

  String get _fullPhoneNumber => '$_countryCode${_phone.trim()}';

  // Start phone verification
  Future<void> _startPhoneLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _fullPhoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Rarely used: auto-retrieval
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _error = 'Phone verification failed: ${e.message}';
            _loading = false;
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _loading = false;
          });
          _showSmsCodeDialog();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          setState(() {
            _verificationId = verificationId;
            _loading = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _error = 'Failed to send SMS: $e';
        _loading = false;
      });
    }
  }

  // Verify OTP and login
  Future<void> _verifySmsCodeAndLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Verify OTP with Firebase Auth
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _smsController.text.trim(),
      );
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // Search user in Firestore by full phone number
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: _fullPhoneNumber)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        setState(() {
          _error = 'No user found with this phone.';
          _loading = false;
        });
        return;
      }

      final userDoc = userQuery.docs.first;
      final userData = userDoc.data();

      // Check password
      if (userData['password'] != _password) {
        setState(() {
          _error = 'Incorrect password.';
          _loading = false;
        });
        return;
      }

      // Navigate to home
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      setState(() {
        _error = 'Login failed. Try again.';
        _loading = false;
      });
    }
  }

  // SMS input dialog
  void _showSmsCodeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter SMS Code'),
        content: TextField(
          controller: _smsController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'SMS Code'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _loading = false);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _verifySmsCodeAndLogin();
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _smsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(loc.login + ' ${loc.appTitle}',
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),

                    // Phone with country code
                    Row(
                      children: [
                        Flexible(
                          flex: 2,
                          child: SizedBox(
                            height: 55,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _countryCode,
                              items: const [
                                DropdownMenuItem(value: '+20', child: Text('+20 🇪🇬')),
                                DropdownMenuItem(value: '+966', child: Text('+966 🇸🇦')),
                                DropdownMenuItem(value: '+971', child: Text('+971 🇦🇪')),
                                DropdownMenuItem(value: '+1', child: Text('+1 🇺🇸')),
                              ],
                              onChanged: (val) => setState(() => _countryCode = val ?? '+20'),
                              decoration: InputDecoration(
                                labelText: loc.code, // Not ideal, but you can add a new key for "Code"
                                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          flex: 5,
                          child: TextFormField(
                            decoration: InputDecoration(
                              labelText: loc.phone,
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                            onChanged: (val) => _phone = val.trim(),
                            validator: (val) =>
                                val != null && val.trim().isNotEmpty && val.length >= 8
                                    ? null
                                    : loc.noTransactions, // Add a new key for "Enter valid number"
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextFormField(
                      decoration: InputDecoration(labelText: loc.password), // Add a new key for "Password"
                      obscureText: true,
                      onChanged: (val) => _password = val,
                      validator: (val) =>
                          val != null && val.isNotEmpty && val.length >= 6
                              ? null
                              : loc.noTransactions, // Add a new key for "Password min 6 chars"
                    ),
                    const SizedBox(height: 24),

                    // Login button
                    _loading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: _loading ? null : () async {
                              if (_formKey.currentState!.validate()) {
                                // Use phone authentication instead of email/password
                                _startPhoneLogin();
                              }
                            },
                            child: Text(loc.login),
                          ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacementNamed('/signup');
                      },
                      child: Text("${loc.signup}"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}