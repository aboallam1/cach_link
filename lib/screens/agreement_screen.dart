import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AgreementScreen extends StatefulWidget {
  const AgreementScreen({super.key});

  @override
  State<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends State<AgreementScreen> {
  bool _instapayConfirmed = false;
  bool _cashConfirmed = false;
  bool _loading = false;

  Future<void> _confirm(String type, String txId) async {
    setState(() => _loading = true);
    final txRef = FirebaseFirestore.instance.collection('transactions').doc(txId);
    await txRef.update({type: true});
    final tx = await txRef.get();
    if (tx['instapayConfirmed'] == true && tx['cashConfirmed'] == true) {
      await txRef.update({'status': 'completed'});
      Navigator.of(context).pushReplacementNamed('/rating', arguments: {
        'otherUserId': tx['userId'],
      });
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    final txId = args?['myTxId'];
    final otherUserId = args?['otherUserId'];
    return Scaffold(
      appBar: AppBar(title: const Text('Agreement')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Meet in a public place. Don’t hand over cash before confirming transfer.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : () => _confirm('instapayConfirmed', txId),
              child: const Text('Confirm Instapay Transfer'),
            ),
            ElevatedButton(
              onPressed: _loading ? null : () => _confirm('cashConfirmed', txId),
              child: const Text('Confirm Cash Received'),
            ),
          ],
        ),
      ),
    );
  }
}
