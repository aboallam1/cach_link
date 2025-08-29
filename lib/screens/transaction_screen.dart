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

  Future<void> _getLocation() async {
    final loc = Location();
    final data = await loc.getLocation();
    setState(() => _location = data);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.locationSharedMessage)),
    );
  }

  Future<void> _submit() async {
    final loc = AppLocalizations.of(context)!;
    if (_type == null || _amountController.text.isEmpty || _location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.noTransactions)), // Or add a new key for "Please fill all fields"
      );
      return;
    }

    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser!;

    await FirebaseFirestore.instance.collection('transactions').add({
      'userId': user.uid,
      'type': _type,
      'amount': double.parse(_amountController.text),
      'location': {
        'lat': _location!.latitude,
        'lng': _location!.longitude,
      },
      'status': 'pending',
      'exchangeRequestedBy': null, // لحد ما يطلب ماتش
      'instapayConfirmed': false,
      'cashConfirmed': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    setState(() => _loading = false);
    Navigator.of(context).pushReplacementNamed('/match');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(loc.confirmTransaction), // Or add a new key for "New Transaction"
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
              loc.confirmTransaction, // Or add a new key for "Create Transaction"
              style: theme.textTheme.headlineSmall!.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.waitingForOther, // Or add a new key for the description
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
                        labelText: loc.status, // Or add a new key for "Transaction Type"
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

            // Submit button
            _loading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.search),
                    label: Text(
                      loc.rateUser, // Or add a new key for "Find Match"
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
