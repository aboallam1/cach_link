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
  String _filterType = "distance";
  Map<String, dynamic>? _myLoc;
  double _myAmount = 0;
  DocumentSnapshot? _myTx;

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
    _myTx = txs.docs.first;
    final myType = _myTx!['type'];
    _myAmount = _myTx!['amount'];
    _myLoc = _myTx!['location'];
    final oppType = myType == 'Deposit' ? 'Withdraw' : 'Deposit';

    final candidates = await FirebaseFirestore.instance
        .collection('transactions')
        .where('type', isEqualTo: oppType)
        .where('status', isEqualTo: 'pending')
        .get();

    List<DocumentSnapshot> matches = [];
    for (var doc in candidates.docs) {
      final amt = doc['amount'];
      if ((amt - _myAmount).abs() / _myAmount <= 0.1) {
        final loc = doc['location'];
        final d = _distance(_myLoc!['lat'], _myLoc!['lng'], loc['lat'], loc['lng']);
        if (d < 50.0) {
          matches.add(doc);
        }
      }
    }

    matches.sort((a, b) {
      if (_filterType == "distance") {
        final da = _distance(_myLoc!['lat'], _myLoc!['lng'], a['location']['lat'], a['location']['lng']);
        final db = _distance(_myLoc!['lat'], _myLoc!['lng'], b['location']['lat'], b['location']['lng']);
        return da.compareTo(db);
      } else {
        final da = (a['amount'] - _myAmount).abs();
        final db = (b['amount'] - _myAmount).abs();
        return da.compareTo(db);
      }
    });

    setState(() {
      _matches = matches;
      _loading = false;
    });
  }

  double _distance(lat1, lon1, lat2, lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
            (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Future<void> _sendExchangeRequest(DocumentSnapshot otherTx, String otherUserId) async {
    if (_myTx == null) return;
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    final myRef = FirebaseFirestore.instance.collection('transactions').doc(_myTx!.id);
    final otherRef = FirebaseFirestore.instance.collection('transactions').doc(otherTx.id);

    final batch = FirebaseFirestore.instance.batch();
    batch.update(myRef, {
      'status': 'requested',
      'partnerTxId': otherTx.id,
      'exchangeRequestedBy': currentUserId,
    });
    batch.update(otherRef, {
      'status': 'requested',
      'partnerTxId': _myTx!.id,
      'exchangeRequestedBy': currentUserId,
    });

    await batch.commit();

    if (!mounted) return;
    Navigator.of(context).pushNamed('/agreement', arguments: {
      'myTxId': _myTx!.id,
      'otherTxId': otherTx.id,
    });
  }

  Future<void> _respondToRequest(DocumentSnapshot tx, bool accept) async {
    final txRef = FirebaseFirestore.instance.collection('transactions').doc(tx.id);

    if (accept) {
      await txRef.update({'status': 'accepted'});
      if (!mounted) return;
      Navigator.of(context).pushNamed('/agreement', arguments: {
        'myTxId': _myTx!.id,
        'otherTxId': tx.id,
      });
    } else {
      await txRef.update({'status': 'rejected'});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Matches')),
      body: Column(
        children: [
          // فلتر
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButtonFormField<String>(
              value: _filterType,
              decoration: InputDecoration(
                labelText: "Filter By",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: const [
                DropdownMenuItem(
                  value: "distance",
                  child: Text("Closest Distance"),
                ),
                DropdownMenuItem(
                  value: "amount",
                  child: Text("Closest Amount"),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _filterType = val!;
                  _findMatches();
                });
              },
            ),
          ),

          Expanded(
            child: ListView.builder(
              itemCount: _matches.length,
              itemBuilder: (ctx, i) {
                final tx = _matches[i];
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('users').doc(tx['userId']).get(),
                  builder: (ctx, snap) {
                    if (!snap.hasData) return const ListTile(title: Text('Loading...'));
                    final user = snap.data!;
                    final dist = _distance(_myLoc!['lat'], _myLoc!['lng'],
                        tx['location']['lat'], tx['location']['lng']);

                    // ✅ لو جالي Exchange request من الطرف التاني
                    if (tx['status'] == 'requested' && tx['exchangeRequestedBy'] != FirebaseAuth.instance.currentUser!.uid) {
                      return Card(
                        child: ListTile(
                          title: Text('${user['name']} (${user['gender']})'),
                          subtitle: Text(
                            'Exchange Request received!\nAmount: ${tx['amount']} | Distance: ~${dist.toStringAsFixed(2)} km | Rating: ${user['rating']}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                onPressed: () => _respondToRequest(tx, true),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () => _respondToRequest(tx, false),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // ✅ الكروت العادية (لسه ممكن أعمل لهم Exchange request)
                    return Card(
                      child: ListTile(
                        title: Text('${user['name']} (${user['gender']})'),
                        subtitle: Text(
                          'Amount: ${tx['amount']} | Distance: ~${dist.toStringAsFixed(2)} km | Rating: ${user['rating']}',
                        ),
                        trailing: ElevatedButton(
                          onPressed: () => _sendExchangeRequest(tx, user.id),
                          child: const Text('Exchange Request'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
