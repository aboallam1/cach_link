import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:cashlink/l10n/app_localizations.dart';
import 'package:flutter/services.dart';

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
  int _searchRadius = 10; // km
  bool _lockActive = false;
  DateTime? _lockUntil;
  bool _noCandidates = false;
  bool _showSaveBanner = false;
  bool _requestExpired = false;
  bool _saveOrCancelRequired = false;

  // Replace all _type, _amountController, _location with public fields or pass them as arguments.
  // Add these fields at the top of your _MatchScreenState if you want to access the last transaction request:
  String? lastType;
  String? lastAmount;
  Map<String, dynamic>? lastLocation;

  @override
  void initState() {
    super.initState();
    _findMatches();
    _checkRequestExpiry();
    // Use WillPopScope in build to control back navigation.
  }

  @override
  void dispose() {
    // nothing to remove here; WillPopScope manages onWillPop
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    // Prevent back navigation if Save-or-Cancel required
    return !_saveOrCancelRequired;
  }

  Future<void> _checkRequestExpiry() async {
    final user = FirebaseAuth.instance.currentUser!;
    final txSnap = await FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (txSnap.docs.isNotEmpty) {
      final tx = txSnap.docs.first;
      final data = tx.data() as Map<String, dynamic>;
      final expiresAt = DateTime.tryParse(data['expiresAt'] ?? '');
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        await tx.reference.update({'status': 'archived'});
        setState(() {
          _requestExpired = true;
        });
      }
    }
  }

  Future<void> _findMatches() async {
    setState(() {
      _loading = true;
      _noCandidates = false;
      _saveOrCancelRequired = false;
    });
    final currentUser = FirebaseAuth.instance.currentUser!;
    final txs = await FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: currentUser.uid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (txs.docs.isEmpty) {
      setState(() {
        _matches = [];
        _loading = false;
        _saveOrCancelRequired = true;
      });
      return;
    }
    _myTx = txs.docs.first;
    final myData = _myTx!.data() as Map<String, dynamic>?;

    // Check expiry
    final expiresAt = myData?['expiresAt'];
    if (expiresAt != null) {
      final exp = DateTime.tryParse(expiresAt);
      if (exp != null && DateTime.now().isAfter(exp)) {
        await _myTx!.reference.update({'status': 'archived'});
        setState(() {
          _matches = [];
          _loading = false;
          _requestExpired = true;
        });
        return;
      }
    }

    if (myData == null || !myData.containsKey('type') || !myData.containsKey('amount') || !myData.containsKey('location')) {
      setState(() {
        _matches = [];
        _loading = false;
        _saveOrCancelRequired = true;
      });
      return;
    }

    final myType = myData['type'];
    _myAmount = myData['amount'];
    _myLoc = myData['location'];
    final oppType = myType == 'Deposit' ? 'Withdraw' : 'Deposit';

    final nowIso = DateTime.now().toIso8601String();
    final candidatesSnap = await FirebaseFirestore.instance
        .collection('transactions')
        .where('type', isEqualTo: oppType)
        .where('status', isEqualTo: 'pending')
        .where('expiresAt', isGreaterThan: nowIso)
        .get();

    List<DocumentSnapshot> candidates = [];
    for (var doc in candidatesSnap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null ||
          !data.containsKey('amount') ||
          !data.containsKey('location') ||
          !data.containsKey('userId')) continue;
      if (data['userId'] == currentUser.uid) continue;

      final loc = data['location'];
      final d = _distance(_myLoc!['lat'], _myLoc!['lng'], loc['lat'], loc['lng']);
      if (d <= _searchRadius) {
        candidates.add(doc);
      }
    }

    // Find closest by GPS
    DocumentSnapshot? closestByGps;
    double minDist = double.infinity;
    for (var doc in candidates) {
      final data = doc.data() as Map<String, dynamic>;
      final loc = data['location'];
      final d = _distance(_myLoc!['lat'], _myLoc!['lng'], loc['lat'], loc['lng']);
      if (d < minDist) {
        minDist = d;
        closestByGps = doc;
      }
    }

    // Find closest by amount
    DocumentSnapshot? closestByAmount;
    double minAmountDiff = double.infinity;
    for (var doc in candidates) {
      final data = doc.data() as Map<String, dynamic>;
      final amt = data['amount'];
      final diff = (amt - _myAmount).abs();
      if (diff < minAmountDiff) {
        minAmountDiff = diff;
        closestByAmount = doc;
      }
    }

    // If both are the same, suggest only one
    List<DocumentSnapshot> matches = [];
    if (closestByGps != null && closestByGps.id == closestByAmount?.id) {
      matches = [closestByGps];
    } else {
      if (closestByGps != null) matches.add(closestByGps);
      if (closestByAmount != null && closestByAmount.id != closestByGps?.id) matches.add(closestByAmount);
    }

    setState(() {
      _matches = matches;
      _loading = false;
      _noCandidates = matches.isEmpty;
      _saveOrCancelRequired = matches.isEmpty;
    });
  }

  Future<void> _expandSearch() async {
    if (_searchRadius < 50) {
      setState(() {
        _searchRadius += 10;
      });
      await _findMatches();
    }
  }

  double _distance(lat1, lon1, lat2, lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
            (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // in km
  }

  Future<void> _sendExchangeRequest(DocumentSnapshot otherTx, String otherUserId) async {
    if (_lockActive && _lockUntil != null && DateTime.now().isBefore(_lockUntil!)) return;
    if (_myTx == null) return;
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    // Lock sender for 60s
    setState(() {
      _lockActive = true;
      _lockUntil = DateTime.now().add(const Duration(seconds: 60));
    });

    final myRef = FirebaseFirestore.instance.collection('transactions').doc(_myTx!.id);
    final otherRef = FirebaseFirestore.instance.collection('transactions').doc(otherTx.id);

    final batch = FirebaseFirestore.instance.batch();
    batch.update(myRef, {
      'status': 'requested',
      'partnerTxId': otherTx.id,
      'exchangeRequestedBy': currentUserId,
      'lockUntil': Timestamp.fromDate(_lockUntil!),
    });
    batch.update(otherRef, {
      'status': 'requested',
      'partnerTxId': _myTx!.id,
      'exchangeRequestedBy': currentUserId,
      'lockUntil': Timestamp.fromDate(_lockUntil!),
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
      // Unlock sender immediately
      setState(() {
        _lockActive = false;
        _lockUntil = null;
      });
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

    // Expiry notification
    if (_requestExpired) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.Matches)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Your request has expired, you can create a new one.", style: const TextStyle(color: Colors.red)),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacementNamed('/dashboard');
                },
                child: const Text("Go to Home"),
              ),
            ],
          ),
        ),
      );
    }

    // Show Save/Cancel buttons at all times, block back navigation until pressed
    return Scaffold(
      appBar: AppBar(title: Text(loc.Matches)),
      body: WillPopScope(
        onWillPop: _onWillPop,
        child: Stack(
          children: [
            Column(
              children: [
                if (_showSaveBanner)
                  MaterialBanner(
                    content: Text("Your request is saved at $_searchRadius km radius, we will notify you when someone is available."),
                    actions: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _showSaveBanner = false;
                          });
                        },
                        child: const Text("Dismiss"),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: DropdownButtonFormField<String>(
                    value: _filterType,
                    decoration: InputDecoration(
                      labelText: loc.filterBy,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: "distance",
                        child: Text(loc.distance),
                      ),
                      DropdownMenuItem(
                        value: "amount",
                        child: Text(loc.amount),
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

                if (_noCandidates)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          _searchRadius < 50
                              ? "No users found in $_searchRadius km."
                              : "Sorry, no users available at the moment, your request was saved",
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                        if (_searchRadius < 50)
                          ElevatedButton(
                            onPressed: _expandSearch,
                            child: Text("Expand Search (+10km)"),
                          ),
                        // Save-or-Cancel buttons
                        if (_saveOrCancelRequired)
                          Padding(
                            padding: const EdgeInsets.only(top: 32),
                            child: Column(
                              children: [
                                ElevatedButton(
                                  onPressed: _saveRequestInRadius,
                                  child: Text("Save Request in this Radius"),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _cancelRequestAndExit,
                                  child: const Text("Cancel"),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                if (!_noCandidates)
                  Expanded(
                    child: ListView.builder(
                      itemCount: _matches.length > 2 ? 2 : _matches.length,
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

                            return Card(
                              child: ListTile(
                                title: Text('${user['name']} (${user['gender'] == 'Male' ? loc.male : loc.female})'),
                                subtitle: Text(
                                  '${loc.amount}: ${txData['amount']} | '
                                  '${loc.distance}: ~${dist.toStringAsFixed(2)} km | '
                                  '${loc.rating}: ${user['rating']}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton(
                                      onPressed: _lockActive &&
                                              _lockUntil != null &&
                                              DateTime.now().isBefore(_lockUntil!)
                                          ? null
                                          : () => _sendExchangeRequest(tx, user.id),
                                      child: Text(_lockActive &&
                                              _lockUntil != null &&
                                              DateTime.now().isBefore(_lockUntil!)
                                          ? "Locked (${_lockUntil!.difference(DateTime.now()).inSeconds}s)"
                                          : "Send Request"),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: _lockActive &&
                                              _lockUntil != null &&
                                              DateTime.now().isBefore(_lockUntil!)
                                          ? null
                                          : () {
                                              if (_myTx != null) {
                                                FirebaseFirestore.instance
                                                    .collection('transactions')
                                                    .doc(_myTx!.id)
                                                    .update({'status': 'cancelled'});
                                                setState(() {
                                                  _lockActive = false;
                                                  _lockUntil = null;
                                                });
                                              }
                                            },
                                      child: const Text("Cancel Request"),
                                    ),
                                  ],
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
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveRequestInRadius,
                  child: Text("Save Request in this Radius (${_searchRadius}km)"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelRequestAndExit,
                  child: const Text("Cancel"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Update _savePendingRequestIfNeeded to use these fields:
  Future<void> _savePendingRequestIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser!;
    final txSnap = await FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (txSnap.docs.isEmpty && lastType != null && lastAmount != null && lastLocation != null) {
      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'type': lastType,
        'amount': double.parse(lastAmount!),
        'location': {
          'lat': lastLocation!['lat'],
          'lng': lastLocation!['lng'],
        },
        'status': 'pending',
        'exchangeRequestedBy': null,
        'instapayConfirmed': false,
        'cashConfirmed': false,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
        'searchRadius': _searchRadius,
      });
    }
  }

  Future<void> _saveRequestInRadius() async {
    final user = FirebaseAuth.instance.currentUser!;
    if (_myTx != null) {
      // Update existing transaction doc to pending with radius and expiry
      await FirebaseFirestore.instance.collection('transactions').doc(_myTx!.id).update({
        'status': 'pending',
        'searchRadius': _searchRadius,
        'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
      });
    } else {
      // Fallback: create a pending transaction if last fields available
      await _savePendingRequestIfNeeded();
    }

    setState(() {
      _showSaveBanner = true;
      _saveOrCancelRequired = false;
      _noCandidates = false;
    });
  }

  Future<void> _cancelRequestAndExit() async {
    final user = FirebaseAuth.instance.currentUser!;
    final txSnap = await FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    for (var doc in txSnap.docs) {
      await doc.reference.delete();
    }
    setState(() {
      _saveOrCancelRequired = false;
    });
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/dashboard');
    }
  }
}
