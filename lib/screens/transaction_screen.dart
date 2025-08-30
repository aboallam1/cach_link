import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class TransactionScreen extends StatefulWidget {
  const TransactionScreen({super.key});

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  String? _type;
  final _amountController = TextEditingController();
  LocationData? _location;
  bool _loading = false;
  bool _hasActiveRequest = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['transactionType'] is String) {
      _type = args['transactionType'];
    }
  }

  @override
  void initState() {
    super.initState();
    _checkActiveRequest();
  }

  Future<void> _checkActiveRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    setState(() {
      _hasActiveRequest = userDoc.data()?['hasActiveRequest'] == true;
    });
  }

  Future<void> _submit() async {
    final loc = AppLocalizations.of(context)!;
    if (_type == null || _amountController.text.isEmpty || _location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.noTransactions)),
      );
      return;
    }
    if (_hasActiveRequest) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You already have an active request. Cancel it first.")),
      );
      return;
    }

    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser!;

    // Instead of direct Firestore write, call a Cloud Function (not shown here)
    // Example:
    // await FirebaseFunctions.instance.httpsCallable('createRequest').call({...});

    setState(() => _loading = false);
    Navigator.of(context).pushReplacementNamed('/match');
  }

  // Add this method to fix the _getLocation error
  Future<void> _getLocation() async {
    final loc = Location();
    final data = await loc.getLocation();
    setState(() => _location = data);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.locationSharedMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(loc.NewTransaction),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text(
              loc.CreateTransaction,
              style: theme.textTheme.headlineSmall!.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.descriptionOfNewTransaction,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            // Card container
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _type,
                      items: [
                        DropdownMenuItem(
                          value: 'Deposit',
                          child: Row(
                            children: [
                              Icon(Icons.arrow_downward, color: Colors.green),
                              const SizedBox(width: 8),
                              Text(loc.deposit),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Withdraw',
                          child: Row(
                            children: [
                              Icon(Icons.arrow_upward, color: Colors.red),
                              const SizedBox(width: 8),
                              Text(loc.withdraw),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _type = v),
                      decoration: InputDecoration(
                        labelText: loc.transactionType,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.swap_horiz),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: loc.amount,
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _getLocation,
                      icon: const Icon(Icons.location_on),
                      label: Text(
                        _location == null
                            ? (loc.locationShared ?? "Set Location")
                            : (loc.locationSharedMessage ?? "Location Selected"),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            if (_hasActiveRequest)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  "You already have an active request. Cancel it before creating a new one.",
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _hasActiveRequest ? null : _submit,
                      style: ButtonStyle(
                        shape: MaterialStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search),
                          const SizedBox(width: 8),
                          Text(
                            loc.findMatch,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
