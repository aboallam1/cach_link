import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _countryCode = '+20';
  String _phone = '';
  String _password = '';
  String _gender = 'Male';
  bool _loading = false;
  String? _error;
  String? _verificationId;
  final TextEditingController _smsController = TextEditingController();

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
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _smsController.text.trim(),
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // إنشاء المستخدم في Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'name': _name.trim(),
        'phone': _fullPhoneNumber,
        'password': _password,
        'gender': _gender,
        'rating': 5.0,
      });

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      setState(() {
        _error = 'Invalid code or signup failed. Try again.';
        _loading = false;
      });
    }
  }

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
              _verifySmsCodeAndSignup();
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
                    Text('Create Account',
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Text(_error!, style: const TextStyle(color: Colors.red)),

                    // Name
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Full Name'),
                      onChanged: (val) => _name = val.trim(),
                      validator: (val) =>
                          val != null && val.trim().length >= 3 ? null : 'Enter your name',
                    ),
                    const SizedBox(height: 16),

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
                              decoration: const InputDecoration(
                                labelText: 'Code',
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          flex: 5,
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Phone Number',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                            onChanged: (val) => _phone = val.trim(),
                            validator: (val) =>
                                val != null && val.trim().isNotEmpty && val.length >= 8
                                    ? null
                                    : 'Enter valid number',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      onChanged: (val) => _password = val,
                      validator: (val) =>
                          val != null && val.length >= 6 ? null : 'Password min 6 chars',
                    ),
                    const SizedBox(height: 16),

                    // Gender
                    DropdownButtonFormField<String>(
                      value: _gender,
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(value: 'Female', child: Text('Female')),
                      ],
                      onChanged: (val) => setState(() => _gender = val ?? 'Male'),
                      decoration: const InputDecoration(labelText: 'Gender'),
                    ),
                    const SizedBox(height: 24),

                    // Signup button
                    _loading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                _startPhoneVerification();
                              }
                            },
                            child: const Text('Sign Up'),
                          ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacementNamed('/auth');
                      },
                      child: const Text("Already have an account? Login"),
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
