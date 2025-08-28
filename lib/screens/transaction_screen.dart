import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';

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
      const SnackBar(content: Text("Location set successfully")),
    );
  }

  Future<void> _submit() async {
    if (_type == null || _amountController.text.isEmpty || _location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
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

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("New Transaction"),
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
              "Create Transaction",
              style: theme.textTheme.headlineSmall!.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Select transaction type, enter amount and set your location to find a match.",
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
                      items: const [
                        DropdownMenuItem(
                          value: 'Deposit',
                          child: Row(
                            children: [
                              Icon(Icons.arrow_downward, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Deposit'),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Withdraw',
                          child: Row(
                            children: [
                              Icon(Icons.arrow_upward, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Withdraw'),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _type = v),
                      decoration: InputDecoration(
                        labelText: "Transaction Type",
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
                        labelText: "Amount",
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
                            ? "Set Location"
                            : "Location Selected",
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
                    label: const Text(
                      "Find Match",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
