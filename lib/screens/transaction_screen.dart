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
  }

  Future<void> _submit() async {
    if (_type == null || _amountController.text.isEmpty || _location == null) return;
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
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() => _loading = false);
    Navigator.of(context).pushReplacementNamed('/match');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Transaction')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'Deposit', child: Text('Deposit')),
                DropdownMenuItem(value: 'Withdraw', child: Text('Withdraw')),
              ],
              onChanged: (v) => setState(() => _type = v),
              decoration: const InputDecoration(labelText: 'Transaction Type'),
            ),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _getLocation,
              child: Text(_location == null ? 'Get Location' : 'Location Set'),
            ),
            const SizedBox(height: 16),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Find Match'),
                  ),
          ],
        ),
      ),
    );
  }
}
