import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  List<DocumentSnapshot> _matches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _findMatches();
  }

  Future<void> _findMatches() async {
    final user = FirebaseAuth.instance.currentUser!;
    final txs = await FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (txs.docs.isEmpty) return;
    final myTx = txs.docs.first;
    final myType = myTx['type'];
    final myAmount = myTx['amount'];
    final myLoc = myTx['location'];
    final oppType = myType == 'Deposit' ? 'Withdraw' : 'Deposit';

    final candidates = await FirebaseFirestore.instance
        .collection('transactions')
        .where('type', isEqualTo: oppType)
        .where('status', isEqualTo: 'pending')
        .get();

    List<DocumentSnapshot> matches = [];
    for (var doc in candidates.docs) {
      final amt = doc['amount'];
      if ((amt - myAmount).abs() / myAmount <= 0.1) {
        // Distance calculation (simple, not accurate for production)
        final loc = doc['location'];
        final d = _distance(myLoc['lat'], myLoc['lng'], loc['lat'], loc['lng']);
        if (d < 5.0) { // within 5km
          matches.add(doc);
        }
      }
    }
    setState(() {
      _matches = matches;
      _loading = false;
    });
  }

  double _distance(lat1, lon1, lat2, lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p)/2 +
        cos(lat1 * p) * cos(lat2 * p) *
        (1 - cos((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Matches')),
        body: const Center(child: Text('No matches found. Try again later.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Matches')),
      body: ListView.builder(
        itemCount: _matches.length,
        itemBuilder: (ctx, i) {
          final tx = _matches[i];
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(tx['userId']).get(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const ListTile(title: Text('Loading...'));
              final user = snap.data!;
              return Card(
                child: ListTile(
                  title: Text('${user['name']} (${user['gender']})'),
                  subtitle: Text(
                    'Amount: ${tx['amount']} | Distance: ~${_distance(tx['location']['lat'], tx['location']['lng'], tx['location']['lat'], tx['location']['lng']).toStringAsFixed(2)}km | Rating: ${user['rating']}',
                  ),
                  onTap: () {
                    // Save match info and go to agreement
                    Navigator.of(context).pushNamed('/agreement', arguments: {
                      'myTxId': tx.id,
                      'otherUserId': user['userId'],
                    });
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
