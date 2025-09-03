import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cashlink/l10n/app_localizations.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  bool _profileComplete = false;
  int _selectedIndex = 0;

  // Add these for timer
  Duration? _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.of(context).pushReplacementNamed('/auth');
      return;
    }
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final kycVerified = doc.data()?['KYC_verified'] ?? false;
    final hasIdImage = doc.data()?['idImageUrl'] != null && (doc.data()?['idImageUrl'] as String).isNotEmpty;
    if (doc.exists && doc['name'] != null && doc['gender'] != null && kycVerified && hasIdImage) {
      setState(() {
        _profileComplete = true;
        _loading = false;
      });
    } else {
      // If missing ID image, redirect to profile page to upload
      Navigator.of(context).pushReplacementNamed('/profile');
    }
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Navigation logic for other pages
    if (index == 1) {
      Navigator.of(context).pushNamed('/profile');
    } else if (index == 2) {
      Navigator.of(context).pushNamed('/history');
    } else if (index == 3) {
      Navigator.of(context).pushNamed('/settings');
    }
  }

  void _startTimer(DateTime expiresAt) {
    _timer?.cancel();
    _remaining = expiresAt.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remaining = expiresAt.difference(DateTime.now());
        if (_remaining != null && _remaining!.isNegative) {
          _remaining = Duration.zero;
          timer.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.appTitle, style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Center(
        child: FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('transactions')
              .where('userId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
              .where('status', whereIn: ['pending', 'requested', 'accepted'])
              .limit(1)
              .get(),
          builder: (context, snapshot) {
            final hasActiveTx = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
            DateTime? expiresAt;
            if (hasActiveTx) {
              final txData = snapshot.data!.docs.first.data() as Map<String, dynamic>;
              if (txData['expiresAt'] != null) {
                expiresAt = DateTime.tryParse(txData['expiresAt']);
                if (expiresAt != null) {
                  // Start or update timer
                  _startTimer(expiresAt);
                }
              }
            }
            Duration remaining = _remaining ?? Duration.zero;
            double timerProgress = remaining.inSeconds / (30 * 60);
            Color timerColor;
            if (timerProgress > 0.5) {
              timerColor = Colors.red;
            } else if (timerProgress > 0.2) {
              timerColor = Colors.orange;
            } else {
              timerColor = Colors.green;
            }
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Program name and logo above timer
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 125),
                  child: Column(
                    children: [
                      Text(
                        loc.appTitle, // Use localized app name
                        style: const TextStyle(
                          fontSize: 35,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasActiveTx && expiresAt != null && remaining.inSeconds > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      children: [
                        Text(
                          "${loc.expiresIn}: ${remaining.inMinutes.remainder(60).toString().padLeft(2, '0')}:${(remaining.inSeconds.remainder(60)).toString().padLeft(2, '0')}",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: timerColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: timerProgress.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: 220,
                  height: 100,
                  child: Card(
                    color: const Color(0xFFE53935),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 6,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      // Allow new transaction if no activeTx or timer ended
                      onTap: (!hasActiveTx || (remaining.inSeconds <= 0))
                          ? () async {
                              Navigator.of(context).pushNamed(
                                '/transaction',
                                arguments: {'transactionType': 'Deposit'},
                              );
                            }
                          : null,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.credit_card, color: Colors.white, size: 32),
                            const SizedBox(width: 16),
                            Text(loc.deposit, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 220,
                  height: 100,
                  child: Card(
                    color: const Color(0xFFE53935),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 6,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      // Allow new transaction if no activeTx or timer ended
                      onTap: (!hasActiveTx || (remaining.inSeconds <= 0))
                          ? () async {
                              Navigator.of(context).pushNamed(
                                '/transaction',
                                arguments: {'transactionType': 'Withdraw'},
                              );
                            }
                          : null,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.attach_money, color: Colors.white, size: 32),
                            const SizedBox(width: 16),
                            Text(loc.withdraw, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasActiveTx && remaining.inSeconds > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(
                      loc.activeTransaction,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFE53935),
        unselectedItemColor: Colors.grey,
        onTap: _onNavTap,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: loc.home),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: loc.profile),
          BottomNavigationBarItem(icon: const Icon(Icons.history), label: loc.history),
          BottomNavigationBarItem(icon: const Icon(Icons.settings), label: loc.settings),
        ],
      ),
    );
  }
}
