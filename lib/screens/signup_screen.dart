import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cashlink/l10n/app_localizations.dart';
import 'dart:async';
import 'dart:math';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  String _countryCode = '+20';
  String _phone = '';
  String _password = '';
  String _name = '';
  String? _gender;
  bool _loading = false;
  String? _error;
  final TextEditingController _smsController = TextEditingController();
  String? _verificationId;

  String get _fullPhoneNumber => '$_countryCode${_phone.trim()}';

  Future<void> _startPhoneVerification() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _fullPhoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-retrieval (rarely used)
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

  Future<void> _verifySmsCodeAndSignup() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_verificationId == null || _smsController.text.trim().isEmpty) {
        setState(() {
          _error = 'Verification code is missing. Please try again.';
          _loading = false;
        });
        return;
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _smsController.text.trim(),
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // Create user document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'name': _name.trim(),
        'phone': _fullPhoneNumber,
        'password': _password,
        'gender': _gender,
        'rating': 5.0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Create wallet with 10 EGP default balance
      await FirebaseFirestore.instance
          .collection('wallets')
          .doc(userCredential.user!.uid)
          .set({
        'balance': 10.0,
        'currency': 'EGP',
        'totalDeposited': 10.0,
        'totalSpent': 0.0,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Create initial wallet transaction record
      await FirebaseFirestore.instance
          .collection('wallet_transactions')
          .add({
        'userId': userCredential.user!.uid,
        'type': 'deposit',
        'amount': 10.0,
        'description': 'Welcome bonus - Initial wallet balance',
        'balanceBefore': 0.0,
        'balanceAfter': 10.0,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(loc.signupSuccessful),
          content: Text(loc.accountCreatedWithBonus),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.ok))],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      setState(() {
        _error = 'Invalid code or signup failed. Try again.';
        _loading = false;
      });
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(loc.signupError),
            content: Text(e.toString()),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(loc.ok))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSmsCodeDialog() {
    // reuse the same enhanced OTP dialog pattern used in auth_screen
    List<TextEditingController> otpControllers = List.generate(6, (_) => TextEditingController());
    List<FocusNode> otpFocus = List.generate(6, (_) => FocusNode());
    int remaining = 60;
    Timer? dialogTimer;
    bool resendEnabled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setStateDialog) {
          void startTimer() {
            dialogTimer?.cancel();
            remaining = 60;
            resendEnabled = false;
            dialogTimer = Timer.periodic(const Duration(seconds: 1), (t) {
              if (!mounted) return;
              setStateDialog(() {
                remaining--;
                if (remaining <= 0) {
                  resendEnabled = true;
                  dialogTimer?.cancel();
                }
              });
            });
          }

          if (dialogTimer == null || !dialogTimer!.isActive) startTimer();

          return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              title: Text(loc.enterSmsCode),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: (remaining > 0) ? remaining / 60 : 0.0),
                  const SizedBox(height: 8),
                  Text('Expires in ${remaining}s'),
                  const SizedBox(height: 12),
                  // Responsive OTP fields (avoid overflow on narrow dialogs)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (i) {
                      return Flexible(
                        fit: FlexFit.loose,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 36.0, maxWidth: 56.0, minHeight: 48.0),
                            child: IntrinsicWidth(
                              child: TextField(
                                controller: otpControllers[i],
                                focusNode: otpFocus[i],
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                maxLength: 1,
                                decoration: const InputDecoration(counterText: ''),
                                onChanged: (v) {
                                  if (v.isNotEmpty && i < 5) {
                                    otpFocus[i + 1].requestFocus();
                                  } else if (v.isEmpty && i > 0) {
                                    otpFocus[i - 1].requestFocus();
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: resendEnabled
                        ? () async {
                            try {
                              await _startPhoneVerification();
                              setStateDialog(() {
                                startTimer();
                              });
                            } catch (_) {}
                          }
                        : null,
                    child: Text(resendEnabled ? 'Resend Code' : 'Resend (wait)'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    dialogTimer?.cancel();
                    Navigator.of(ctx).pop();
                    if (mounted) setState(() => _loading = false);
                  },
                  child: Text(loc.cancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    final code = otpControllers.map((c) => c.text.trim()).join();
                    if (code.length != 6) {
                      showDialog(
                        context: ctx,
                        builder: (_) => AlertDialog(
                          title: Text(loc.invalidCode),
                          content: Text(loc.enterFullCode),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(loc.ok))],
                        ),
                      );
                      return;
                    }
                    _smsController.text = code;
                    dialogTimer?.cancel();
                    Navigator.of(ctx).pop();
                    _verifySmsCodeAndSignup();
                  },
                  child: Text(loc.verify),
                ),
              ],
            ),
          );
        });
      },
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
                    Text('${loc.signup} ${loc.appTitle}',
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),
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
                                labelText: loc.code,
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
                            validator: (val) {
                              if (val == null) return loc.noTransactions;
                              final digits = val.trim();
                              final phoneReg = RegExp(r'^[0-9]{6,14}$');
                              if (!phoneReg.hasMatch(digits)) return loc.noTransactions;
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: InputDecoration(labelText: loc.name),
                      onChanged: (val) => _name = val,
                      validator: (val) =>
                          val != null && val.trim().isNotEmpty
                              ? null
                              : loc.noTransactions,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _gender,
                      items: [
                        DropdownMenuItem(value: 'Male', child: Text(loc.male)),
                        DropdownMenuItem(value: 'Female', child: Text(loc.female)),
                      ],
                      onChanged: (v) => setState(() => _gender = v),
                      decoration: InputDecoration(
                        labelText: loc.gender,
                        prefixIcon: const Icon(Icons.wc),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: InputDecoration(labelText: loc.password),
                      obscureText: true,
                      onChanged: (val) => _password = val,
                      validator: (val) =>
                          val != null && val.isNotEmpty && val.length >= 6
                              ? null
                              : loc.noTransactions,
                    ),
                    const SizedBox(height: 24),
                    _loading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: () async {
                              if (_formKey.currentState!.validate()) {
                                // Use phone authentication instead of email/password
                                _startPhoneVerification();
                              }
                            },
                            child: Text(loc.signup),
                          ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacementNamed('/auth');
                      },
                      child: Text(loc.login),
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