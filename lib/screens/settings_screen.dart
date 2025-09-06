import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cashlink/l10n/app_localizations.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedIndex = 3;

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else if (index == 1) {
      Navigator.of(context).pushReplacementNamed('/profile');
    } else if (index == 2) {
      Navigator.of(context).pushReplacementNamed('/history');
    }
  }

  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushReplacementNamed('/auth');
  }

  void _changeLanguage(String langCode) {
    final state = context.findAncestorStateOfType<MyAppState>();
    if (state != null) {
      state.setLocale(Locale(langCode));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.settings)),
      body: ListView(
        children: [
          // Wallet Section
          Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet, color: Colors.blue),
              title: const Text('My Wallet'),
              subtitle: const Text('Manage your wallet balance and transactions'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.of(context).pushNamed('/wallet');
              },
            ),
          ),
          const SizedBox(height: 16),
          
          // Language Settings
          ExpansionTile(
            leading: const Icon(Icons.language),
            title: Text(loc.changeLanguage),
            children: [
              ListTile(
                title: const Text("العربية"),
                trailing: Icon(
                  Icons.check, 
                  color: Localizations.localeOf(context).languageCode == 'ar' 
                    ? Colors.green 
                    : Colors.transparent
                ),
                onTap: () => _changeLanguage("ar"),
              ),
              ListTile(
                title: const Text("English"),
                trailing: Icon(
                  Icons.check, 
                  color: Localizations.localeOf(context).languageCode == 'en' 
                    ? Colors.green 
                    : Colors.transparent
                ),
                onTap: () => _changeLanguage("en"),
              ),
            ],
          ),
          
          // Other Settings
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              // Add privacy policy navigation
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Privacy Policy - Coming Soon')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.help),
            title: const Text('Help & Support'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              // Add help navigation
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Help & Support - Coming Soon')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('About'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              // Add about navigation
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('About - Coming Soon')),
              );
            },
          ),
          
          const Divider(),
          
          // Logout
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.red),
            title: Text(loc.logout, style: const TextStyle(color: Colors.red)),
            onTap: () => _logout(context),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
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
