import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cashlink/l10n/app_localizations.dart';
import 'dart:async';
import 'dart:math';

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
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Login failed'),
            content: const Text('No account is associated with this number.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        return;
      }

      final userDoc = userQuery.docs.first;
      final userData = userDoc.data();
      if (userData['password'] != _password) {
        setState(() {
          _error = 'Incorrect password.';
          _loading = false;
        });
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Authentication failed'),
            content: const Text('The password you entered is incorrect.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        return;
      }

      // Success: show a brief success dialog then navigate
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Login successful'),
          content: const Text('You are now logged in.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('OK'),
            )
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      setState(() {
        _error = 'Login failed. Try again.';
        _loading = false;
      });
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Verification error'),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // SMS input dialog
  void _showSmsCodeDialog() {
    // Enhanced OTP dialog with 6-digit inputs, timer, progress bar and resend behavior.
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

          // start timer when dialog is built
          if (dialogTimer == null || !dialogTimer!.isActive) {
            startTimer();
          }

          double progress = (60 - remaining) / 60;
          return WillPopScope(
            onWillPop: () async => false,
            child: AlertDialog(
              title: const Text('Enter 6‑digit Code'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: (remaining > 0) ? remaining / 60 : 0.0),
                  const SizedBox(height: 8),
                  Text('Expires in ${remaining}s'),
                  const SizedBox(height: 12),
                  // replace the Row of OTP boxes with flexible constrained boxes
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
                                style: const TextStyle(fontWeight: FontWeight.bold),
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
                            // Immediately update dialog UI: disable resend, reset remaining and clear OTP inputs
                            setStateDialog(() {
                              resendEnabled = false;
                              remaining = 60;
                            });
                            // clear OTP inputs
                            for (var c in otpControllers) { c.clear(); }
                            // restart timer
                            dialogTimer?.cancel();
                            startTimer();
                            // call send (async) — keep UI responsive even if send takes time
                            try {
                              await _startPhoneLogin();
                            } catch (_) {
                              // ignore; verification will report errors via _error
                            }
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
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final code = otpControllers.map((c) => c.text.trim()).join();
                    if (code.length != 6) {
                      // show inline error dialog
                      showDialog(
                        context: ctx,
                        builder: (_) => AlertDialog(
                          title: const Text('Invalid code'),
                          content: const Text('Please enter the full 6-digit code.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                        ),
                      );
                      return;
                    }
                    _smsController.text = code;
                    dialogTimer?.cancel();
                    Navigator.of(ctx).pop();
                    _verifySmsCodeAndLogin();
                  },
                  child: const Text('Verify'),
                ),
              ],
            ),
          );
        });
      },
    ).then((_) {
      // cleanup
    });
  }

  @override
  void dispose() {
    _smsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    // Make Auth page visually match Signup: same card layout, country code + phone, password, validators.
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
                    if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),

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
                            decoration: InputDecoration(labelText: loc.phone, border: const OutlineInputBorder()),
                            keyboardType: TextInputType.phone,
                            // style: const TextStyle(fontWeight: FontWeight.bold),
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
                      decoration: InputDecoration(labelText: loc.password),
                      obscureText: true,
                      onChanged: (val) => _password = val,
                      validator: (val) =>
                          val != null && val.isNotEmpty && val.length >= 6 ? null : loc.noTransactions,
                    ),
                    const SizedBox(height: 24),

                    _loading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: _loading
                                ? null
                                : () async {
                                    if (_formKey.currentState!.validate()) {
                                      // start phone verification (OTP) then verify and login
                                      _startPhoneLogin();
                                    }
                                  },
                            child: Text(loc.login),
                          ),

                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacementNamed('/signup');
                      },
                      child: Text(loc.signup),
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