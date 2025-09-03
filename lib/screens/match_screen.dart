import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:cashlink/l10n/app_localizations.dart';
import 'dart:async';

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
  bool _canLeave = false; // Add this flag
  bool _showSaveButton = false; // Add this flag
  Timer? _expiryTimer;
  Timer? _refreshTimer;
  Duration _remaining = const Duration(minutes: 30);

  // Replace all _type, _amountController, _location with public fields or pass them as arguments.
  // Add these fields at the top of your _MatchScreenState if you want to access the last transaction request:
  String? lastType;
  String? lastAmount;
  Map<String, dynamic>? lastLocation;

  @override
  void initState() {
    super.initState();
    _findMatches();
    _startExpiryTimer();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _findMatches();
      }
    });
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    if (_myTx != null) {
      final data = _myTx!.data() as Map<String, dynamic>?;
      if (data != null && data['expiresAt'] != null) {
        final expiresAt = DateTime.tryParse(data['expiresAt']);
        if (expiresAt != null) {
          final now = DateTime.now();
          final diff = expiresAt.difference(now);
          if (diff.isNegative) {
            _archiveTransaction();
            _remaining = Duration.zero;
            // Navigate to home page when expired
            if (mounted) {
              Future.microtask(() {
                Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
              });
            }
          } else {
            _remaining = diff;
            _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
              final left = expiresAt.difference(DateTime.now());
              if (left.isNegative) {
                timer.cancel();
                _archiveTransaction();
                setState(() {
                  _remaining = Duration.zero;
                });
                // Navigate to home page when expired
                if (mounted) {
                  Future.microtask(() {
                    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                  });
                }
              } else {
                setState(() {
                  _remaining = left;
                });
              }
            });
          }
        }
      }
    }
  }

  Future<void> _archiveTransaction() async {
    if (_myTx != null) {
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(_myTx!.id)
          .update({'status': 'archived'});
    }
  }

  Future<void> _findMatches() async {
    setState(() {
      _loading = true;
      _noCandidates = false;
    });
    final currentUser = FirebaseAuth.instance.currentUser!;
    final now = DateTime.now();
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
      });
      return;
    }
    _myTx = txs.docs.first;
    _startExpiryTimer(); // Restart timer when transaction changes
    final myData = _myTx!.data() as Map<String, dynamic>?;

    if (myData == null || !myData.containsKey('type') || !myData.containsKey('amount') || !myData.containsKey('location')) {
      setState(() {
        _matches = [];
        _loading = false;
      });
      return;
    }

    final myType = myData['type'];
    _myAmount = myData['amount'];
    _myLoc = myData['location'];
    final oppType = myType == 'Deposit' ? 'Withdraw' : 'Deposit';

    // Only show transactions that are pending and not expired
    final candidatesSnap = await FirebaseFirestore.instance
        .collection('transactions')
        .where('type', isEqualTo: oppType)
        .where('status', isEqualTo: 'pending')
        .get();

    List<DocumentSnapshot> candidates = [];
    for (var doc in candidatesSnap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null ||
          !data.containsKey('amount') ||
          !data.containsKey('location') ||
          !data.containsKey('userId') ||
          !data.containsKey('expiresAt')) continue;
      if (data['userId'] == currentUser.uid) continue;

      final expiresAt = DateTime.tryParse(data['expiresAt']);
      if (expiresAt == null || expiresAt.isBefore(now)) continue; // skip expired

      final loc = data['location'];
      double d = 0.0;
      if (_myLoc != null && loc != null && loc['lat'] != null && loc['lng'] != null) {
        d = _distance(_myLoc!['lat'], _myLoc!['lng'], loc['lat'], loc['lng']);
      }
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
      double d = double.infinity;
      if (_myLoc != null && loc != null && loc['lat'] != null && loc['lng'] != null) {
        d = _distance(_myLoc!['lat'], _myLoc!['lng'], loc['lat'], loc['lng']);
      }
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
    });
  }

  Future<void> _expandSearch() async {
    if (_searchRadius < 50) {
      setState(() {
        _searchRadius += 10;
        _showSaveButton = true; // Show save button after expanding search
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

  Future<bool> _onWillPop() async {
    // Prevent back navigation until Save or Cancel is pressed
    return _canLeave;
  }

  Future<void> _saveRequestInRadius() async {
    final user = FirebaseAuth.instance.currentUser!;
    // Always create a new transaction with status "pending" and current search radius
    await FirebaseFirestore.instance.collection('transactions').add({
      'userId': user.uid,
      'type': lastType ?? 'Deposit',
      'amount': lastAmount != null ? double.parse(lastAmount!) : 0.0,
      'location': lastLocation ?? {},
      'status': 'pending',
      'exchangeRequestedBy': null,
      'instapayConfirmed': false,
      'cashConfirmed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
      'searchRadius': _searchRadius,
    });
    setState(() {
      _canLeave = true;
    });
    Navigator.of(context).pushReplacementNamed('/history'); // Go to history after saving
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
      _canLeave = true;
    });
    Navigator.of(context).pop(); // Allow leaving after cancel
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    String timerText =
        "${_remaining.inMinutes.remainder(60).toString().padLeft(2, '0')}:${(_remaining.inSeconds.remainder(60)).toString().padLeft(2, '0')}";

    // Calculate progress for the timer line (1.0 = full, 0.0 = expired)
    double timerProgress = _remaining.inSeconds / (30 * 60);

    Color timerColor;
    if (timerProgress > 0.5) {
      timerColor = Colors.green;
    } else if (timerProgress > 0.2) {
      timerColor = Colors.orange;
    } else {
      timerColor = Colors.red;
    }

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(title: Text(loc.Matches)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text(
                    "Expires in: $timerText",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: timerColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: timerProgress.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                    ),
                  ),
                ],
              ),
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
                        double dist = 0.0;
                        if (_myLoc != null && locData != null && locData['lat'] != null && locData['lng'] != null) {
                          dist = _distance(_myLoc!['lat'], _myLoc!['lng'], locData['lat'], locData['lng']);
                        }

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
                                          // Cancel logic: set status to cancelled
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
        bottomNavigationBar: SafeArea(
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (_noCandidates && _showSaveButton)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveRequestInRadius,
                      child: Text("Save Request in (${_searchRadius}km)"),
                    ),
                  ),
                if (_noCandidates && _showSaveButton)
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
      });
    }
  }
}