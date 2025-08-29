import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:cashlink/l10n/app_localizations.dart';

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
    final currentUser = FirebaseAuth.instance.currentUser!;
    final txs = await FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: currentUser.uid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (txs.docs.isEmpty) return;
    _myTx = txs.docs.first;
    final myData = _myTx!.data() as Map<String, dynamic>?;

    if (myData == null || !myData.containsKey('type') || !myData.containsKey('amount') || !myData.containsKey('location')) return;

    final myType = myData['type'];
    _myAmount = myData['amount'];
    _myLoc = myData['location'];
    final oppType = myType == 'Deposit' ? 'Withdraw' : 'Deposit';

    final candidates = await FirebaseFirestore.instance
        .collection('transactions')
        .where('type', isEqualTo: oppType)
        .where('status', isEqualTo: 'pending')
        .get();

    List<DocumentSnapshot> matches = [];
    for (var doc in candidates.docs) {
      final data = doc.data() as Map<String, dynamic>?;

      // ✅ تحقق من الحقول
      if (data == null ||
          !data.containsKey('amount') ||
          !data.containsKey('location') ||
          !data.containsKey('userId')) continue;

      // ✅ تجاهل معاملات نفس المستخدم
      if (data['userId'] == currentUser.uid) continue;

      final amt = data['amount'];
      if ((amt - _myAmount).abs() / _myAmount <= 0.1) {
        final loc = data['location'];
        final d = _distance(_myLoc!['lat'], _myLoc!['lng'], loc['lat'], loc['lng']);
        if (d < 50.0) {
          matches.add(doc);
        }
      }
    }

    matches.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      if (_filterType == "distance") {
        final da = _distance(_myLoc!['lat'], _myLoc!['lng'], aData['location']['lat'], aData['location']['lng']);
        final db = _distance(_myLoc!['lat'], _myLoc!['lng'], bData['location']['lat'], bData['location']['lng']);
        return da.compareTo(db);
      } else {
        final da = (aData['amount'] - _myAmount).abs();
        final db = (bData['amount'] - _myAmount).abs();
        return da.compareTo(db);
      }
    });

    if (!mounted) return;
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
    return 12742 * asin(sqrt(a)); // in km
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
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

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
    final loc = AppLocalizations.of(context)!;
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(loc.notifications)), // Use a new key if you want "Matches"
      body: Column(
        children: [
          // Filter
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButtonFormField<String>(
              value: _filterType,
              decoration: InputDecoration(
                labelText: loc.changeLanguage, // Or add a new key for "Filter By"
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: [
                DropdownMenuItem(
                  value: "distance",
                  child: Text(loc.distance), // Or add a new key for "Closest Distance"
                ),
                DropdownMenuItem(
                  value: "amount",
                  child: Text(loc.amount), // Or add a new key for "Closest Amount"
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
                final txData = tx.data() as Map<String, dynamic>?;

                if (txData == null || !txData.containsKey('userId')) {
                  return ListTile(title: Text(loc.noTransactions));
                }

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('users').doc(txData['userId']).get(),
                  builder: (ctx, snap) {
                    if (!snap.hasData) return ListTile(title: Text(loc.waitingForOther));
                    final user = snap.data!;
                    final locData = txData['location'];
                    final dist = _distance(_myLoc!['lat'], _myLoc!['lng'], locData['lat'], locData['lng']);

                    // If there is an exchange request from the other party
                    if (txData['status'] == 'requested' && txData['exchangeRequestedBy'] != FirebaseAuth.instance.currentUser!.uid) {
                      return Card(
                        child: ListTile(
                          title: Text('${user['name']} (${user['gender'] == 'Male' ? loc.male : loc.female})'),
                          subtitle: Text(
                            '${loc.requested}\n'
                            '${loc.amount}: ${txData['amount']} | '
                            '${loc.distance}: ~${dist.toStringAsFixed(2)} km | '
                            'Rating: ${user['rating']}',
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

                    // Normal cards (can send Exchange Request)
                    return Card(
                      child: ListTile(
                        title: Text('${user['name']} (${user['gender'] == 'Male' ? loc.male : loc.female})'),
                        subtitle: Text(
                          '${loc.amount}: ${txData['amount']} | '
                          '${loc.distance}: ~${dist.toStringAsFixed(2)} km | '
                          '${loc.rating}: ${user['rating']}',
                        ),
                        trailing: ElevatedButton(
                          onPressed: () => _sendExchangeRequest(tx, user.id),
                          child: Text(loc.exchangeRequestFrom),
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
