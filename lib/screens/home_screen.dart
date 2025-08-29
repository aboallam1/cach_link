import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  bool _profileComplete = false;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.of(context).pushReplacementNamed('/auth');
      return;
    }
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    if (doc.exists && doc['name'] != null && doc['gender'] != null ) {
      setState(() {
        _profileComplete = true;
        _loading = false;
      });
    } else {
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 220,
              height: 100,
              child: Card(
                color: const Color(0xFFE53935),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 6,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).pushNamed(
                    '/transaction',
                    arguments: {'transactionType': 'Deposit'},
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children:  [
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
                  onTap: () => Navigator.of(context).pushNamed(
                    '/transaction',
                    arguments: {'transactionType': 'Withdraw'},
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children:  [
                        const Icon(Icons.attach_money, color: Colors.white, size: 32),
                        const SizedBox(width: 16),
                        Text(loc.withdraw, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFE53935),
        unselectedItemColor: Colors.grey,
        onTap: _onNavTap,
        items:  [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: loc.home),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: loc.profile),
          BottomNavigationBarItem(icon: const Icon(Icons.history), label: loc.history),
          BottomNavigationBarItem(icon: const Icon(Icons.settings), label: loc.settings),
        ],
      ),
    );
  }
}
