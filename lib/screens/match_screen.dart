import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:cashlink/l10n/app_localizations.dart';
import 'package:cashlink/services/voice_service.dart';
import 'dart:async';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  List<DocumentSnapshot> _matches = [];
  List<DocumentSnapshot> _bestChoices = [];
  bool _loading = true;
  String _filterType = "best"; // Default to "best" for best choice algorithm
  Map<String, dynamic>? _myLoc;
  double _myAmount = 0;
  DocumentSnapshot? _myTx;
  int _searchRadius = 50; // Increased default radius to show more users
  bool _lockActive = false;
  DateTime? _lockUntil;
  bool _noCandidates = false;
  bool _canLeave = false;
  bool _showSaveButton = false;
  Timer? _expiryTimer;
  Timer? _refreshTimer;
  Duration _remaining = const Duration(minutes: 30);
  StreamSubscription<DocumentSnapshot>? _myTxListener;

  String? lastType;
  String? lastAmount;
  Map<String, dynamic>? lastLocation;

  String? _requestedTxId; // id of the transaction we've requested (target)

  @override
  void initState() {
    super.initState();
    _findMatches();
    _startExpiryTimer();
    _startAutoRefresh();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupRejectedListener();
    });
  }

  void _setupRejectedListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    _myTxListener?.cancel();
    FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: currentUser.uid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get()
        .then((txs) {
      if (txs.docs.isNotEmpty) {
        final txId = txs.docs.first.id;
        _myTxListener = FirebaseFirestore.instance
            .collection('transactions')
            .doc(txId)
            .snapshots()
            .listen((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null && data['status'] == 'rejected') {
            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/match');
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _refreshTimer?.cancel();
    _myTxListener?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      _findMatches();
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
                if (!mounted) return;
                setState(() {
                  _remaining = Duration.zero;
                });
                if (mounted) {
                  Future.microtask(() {
                    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                  });
                }
              } else {
                if (!mounted) return;
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
    if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _matches = [];
        _bestChoices = [];
        _loading = false;
      });
      return;
    }
    
    _myTx = txs.docs.first;
    _startExpiryTimer();
    final myData = _myTx!.data() as Map<String, dynamic>?;

    if (myData == null || !myData.containsKey('type') || !myData.containsKey('amount') || !myData.containsKey('location')) {
      if (!mounted) return;
      setState(() {
        _matches = [];
        _bestChoices = [];
        _loading = false;
      });
      return;
    }

    final myType = myData['type'];
    _myAmount = myData['amount'];
    _myLoc = myData['location'];
    final oppType = myType == 'Deposit' ? 'Withdraw' : 'Deposit';

    // Get ALL users with reverse transaction type
    final candidatesSnap = await FirebaseFirestore.instance
        .collection('transactions')
        .where('type', isEqualTo: oppType)
        .where('status', whereIn: ['pending', 'requested', 'active'])
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
      if (expiresAt == null || expiresAt.isBefore(now)) continue;

      // IMPORTANT: hide transactions already requested by other users (not targeted to me)
      if (data['status'] == 'requested' && data['partnerTxId'] != _myTx!.id) {
        continue;
      }

      final loc = data['location'];
      double d = 0.0;
      if (_myLoc != null && loc != null && loc['lat'] != null && loc['lng'] != null) {
        d = _distance(_myLoc!['lat'], _myLoc!['lng'], loc['lat'], loc['lng']);
      }
      if (d <= _searchRadius) {
        candidates.add(doc);
      }
    }

    // Find best matches
    List<DocumentSnapshot> matches = _findBestMatches(candidates);
    List<DocumentSnapshot> bestChoices = matches.isNotEmpty ? [matches.first] : [];

    setState(() {
      _matches = matches;
      _bestChoices = bestChoices;
      _loading = false;
      _noCandidates = matches.isEmpty;
    });

   // Reserve shown slots for selected matches so each candidate is exposed to at most 2 requesters.
   // Candidates who already reached two distinct viewers will be removed locally.
   if (_matches.isNotEmpty && _myTx != null) {
     await _reserveShownSlots(_matches);
   }
  }

  // Reserve per-candidate shownTo slot (limit = 2). Removes matches that cannot be reserved.
  Future<void> _reserveShownSlots(List<DocumentSnapshot> matches) async {
    if (_myTx == null) return;
    final String myTxId = _myTx!.id;
    List<String> removeIds = [];

    for (var candidate in matches) {
      final docRef = candidate.reference;
      try {
        await FirebaseFirestore.instance.runTransaction((txn) async {
          final snap = await txn.get(docRef);
          if (!snap.exists) {
            removeIds.add(candidate.id);
            return;
          }
          final data = snap.data() as Map<String, dynamic>? ?? {};
          final shown = (data['shownTo'] as List<dynamic>?)?.cast<String>() ?? [];
          if (shown.contains(myTxId)) {
            // already reserved by me
            return;
          }
          if (shown.length >= 2) {
            // already full for other requesters -> remove locally
            removeIds.add(candidate.id);
            return;
          }
          // add myTxId to shownTo
          txn.update(docRef, {
            'shownTo': FieldValue.arrayUnion([myTxId])
          });
        });
      } catch (_) {
        // On any failure, remove candidate locally to avoid showing it
        removeIds.add(candidate.id);
      }
    }

    if (removeIds.isNotEmpty && mounted) {
      setState(() {
        _matches = _matches.where((m) => !removeIds.contains(m.id)).toList();
        _bestChoices = _bestChoices.where((m) => !removeIds.contains(m.id)).toList();
      });
    }
  }

  // Smart algorithm to find 1-2 best matches
  List<DocumentSnapshot> _findBestMatches(List<DocumentSnapshot> candidates) {
    if (candidates.isEmpty) return [];

    DocumentSnapshot? bestByAmount;
    DocumentSnapshot? bestByDistance;
    double bestAmountDiff = double.infinity;
    double bestDistanceValue = double.infinity;

    // Find best by amount and best by distance
    for (var candidate in candidates) {
      final data = candidate.data() as Map<String, dynamic>;
      
      // Check amount difference
      final amount = data['amount'] ?? 0.0;
      final amountDiff = (amount - _myAmount).abs();
      if (amountDiff < bestAmountDiff) {
        bestAmountDiff = amountDiff;
        bestByAmount = candidate;
      }
      
      // Check distance
      final loc = data['location'];
      if (_myLoc != null && loc != null && loc['lat'] != null && loc['lng'] != null) {
        final distance = _distance(_myLoc!['lat'], _myLoc!['lng'], loc['lat'], loc['lng']);
        if (distance < bestDistanceValue) {
          bestDistanceValue = distance;
          bestByDistance = candidate;
        }
      }
    }

    // Return results
    List<DocumentSnapshot> results = [];
    
    if (bestByAmount != null && bestByDistance != null) {
      if (bestByAmount.id == bestByDistance.id) {
        // Same user is best in both - show only one
        results.add(bestByAmount);
      } else {
        // Different users - show both, best overall first
        DocumentSnapshot overallBest = _getOverallBest(bestByAmount, bestByDistance);
        DocumentSnapshot other = (overallBest.id == bestByAmount.id) ? bestByDistance : bestByAmount;
        results.add(overallBest);
        results.add(other);
      }
    } else if (bestByAmount != null) {
      results.add(bestByAmount);
    } else if (bestByDistance != null) {
      results.add(bestByDistance);
    }

    return results;
  }

  // Determine overall best between two candidates
  DocumentSnapshot _getOverallBest(DocumentSnapshot candidate1, DocumentSnapshot candidate2) {
    final data1 = candidate1.data() as Map<String, dynamic>;
    final data2 = candidate2.data() as Map<String, dynamic>;
    
    double score1 = 0.0;
    double score2 = 0.0;
    
    // Score by amount similarity (max 50 points)
    final amount1 = data1['amount'] ?? 0.0;
    final amount2 = data2['amount'] ?? 0.0;
    final amountDiff1 = (amount1 - _myAmount).abs();
    final amountDiff2 = (amount2 - _myAmount).abs();
    
    if (amountDiff1 == 0) score1 += 50;
    else if (amountDiff1 <= 100) score1 += 40;
    else if (amountDiff1 <= 500) score1 += 30;
    else if (amountDiff1 <= 1000) score1 += 20;
    
    if (amountDiff2 == 0) score2 += 50;
    else if (amountDiff2 <= 100) score2 += 40;
    else if (amountDiff2 <= 500) score2 += 30;
    else if (amountDiff2 <= 1000) score2 += 20;
    
    // Score by distance (max 50 points)
    if (_myLoc != null) {
      final loc1 = data1['location'];
      final loc2 = data2['location'];
      
      if (loc1 != null && loc1['lat'] != null && loc1['lng'] != null) {
        final dist1 = _distance(_myLoc!['lat'], _myLoc!['lng'], loc1['lat'], loc1['lng']);
        if (dist1 <= 1) score1 += 50;
        else if (dist1 <= 5) score1 += 40;
        else if (dist1 <= 10) score1 += 30;
        else if (dist1 <= 20) score1 += 20;
      }
      
      if (loc2 != null && loc2['lat'] != null && loc2['lng'] != null) {
        final dist2 = _distance(_myLoc!['lat'], _myLoc!['lng'], loc2['lat'], loc2['lng']);
        if (dist2 <= 1) score2 += 50;
        else if (dist2 <= 5) score2 += 40;
        else if (dist2 <= 10) score2 += 30;
        else if (dist2 <= 20) score2 += 20;
      }
    }
    
    return score1 >= score2 ? candidate1 : candidate2;
  }

  Future<void> _expandSearch() async {
    if (_searchRadius < 100) {
      if (!mounted) return;
      setState(() {
        _searchRadius += 25;
        _showSaveButton = true;
      });
      await _findMatches();
    }
  }

  double _distance(lat1, lon1, lat2, lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
            (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  double _calculateDistance(DocumentSnapshot otherTx) {
    final otherData = otherTx.data() as Map<String, dynamic>;
    
    if (_myLoc != null && otherData['location'] != null) {
      return _distance(
        _myLoc!['lat'], 
        _myLoc!['lng'], 
        otherData['location']['lat'], 
        otherData['location']['lng']
      );
    }
    return 0.0;
  }

  Future<void> _sendExchangeRequest(DocumentSnapshot otherTx, String otherUserId) async {
    if (_lockActive && _lockUntil != null && DateTime.now().isBefore(_lockUntil!)) return;
    if (_myTx == null) return;
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    setState(() {
      _lockActive = true;
      _lockUntil = DateTime.now().add(const Duration(seconds: 60));
    });

    final myRef = FirebaseFirestore.instance.collection('transactions').doc(_myTx!.id);
    final otherRef = FirebaseFirestore.instance.collection('transactions').doc(otherTx.id);

    // create notification doc first so we can use its id as requestTag
    final notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
    final requestTag = notificationRef.id;

    final batch = FirebaseFirestore.instance.batch();
    // Update only MY transaction to show I sent a request and store requestTag
    batch.update(myRef, {
      'status': 'requested',
      'partnerTxId': otherTx.id,
      'exchangeRequestedBy': currentUserId,
      'lockUntil': Timestamp.fromDate(_lockUntil!),
      'requestTag': requestTag,
    });
    // Update only the SPECIFIC OTHER transaction to show they have a request and store requestTag
    batch.update(otherRef, {
      'status': 'requested',
      'partnerTxId': _myTx!.id,
      'exchangeRequestedBy': currentUserId,
      'lockUntil': Timestamp.fromDate(_lockUntil!),
      'requestTag': requestTag,
    });
    // Create notification only for the specific user and include requestTag
    batch.set(notificationRef, {
      'id': notificationRef.id,
      'requestTag': requestTag,
      'toUserId': otherUserId,
      'fromUserId': currentUserId,
      'myTxId': otherTx.id,
      'otherTxId': _myTx!.id,
      'amount': (_myTx!.data() as Map<String, dynamic>)['amount'],
      'distance': _calculateDistance(otherTx),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': DateTime.now().add(const Duration(seconds: 60)).toIso8601String(),
    });

    await batch.commit();

    // remember requested id for local requester UI (optional)
    if (mounted) {
      setState(() { _requestedTxId = otherTx.id; });
    }

    // Remove myTx id from shownTo arrays of other candidates so they no longer show me (A -> C removes A from B)
    try {
      for (var m in List<DocumentSnapshot>.from(_matches)) {
        if (m.id == otherTx.id) continue;
        await FirebaseFirestore.instance
            .collection('transactions')
            .doc(m.id)
            .update({'shownTo': FieldValue.arrayRemove([_myTx!.id])});
      }
    } catch (_) {
      // ignore errors - not critical
    }

    VoiceService().speakRequestSent();

    if (!mounted) return;
    Navigator.of(context).pushNamed('/agreement', arguments: {
      'myTxId': _myTx!.id,
      'otherTxId': otherTx.id,
    });
  }

  Future<void> _respondToRequest(DocumentSnapshot tx, bool accept) async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    if (accept) {
      final batch = FirebaseFirestore.instance.batch();
      final myRef = FirebaseFirestore.instance.collection('transactions').doc(_myTx!.id);
      final otherRef = FirebaseFirestore.instance.collection('transactions').doc(tx.id);
      
      // Accept the request - update both specific transactions
      batch.update(myRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'requestTag': FieldValue.delete(),
      });
      batch.update(otherRef, {
        'status': 'accepted', 
        'acceptedAt': FieldValue.serverTimestamp(),
        'requestTag': FieldValue.delete(),
      });
      
      await batch.commit();

      final txData = tx.data() as Map<String, dynamic>;
      final requesterUserId = txData['exchangeRequestedBy'];
      if (requesterUserId != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(requesterUserId).get();
        final userName = userDoc.data()?['name'] ?? 'User';
        VoiceService().speakRequestAccepted(userName);
      }
      
      if (!mounted) return;
      // Clear local requested id (we're moving to agreement)
      setState(() { _requestedTxId = null; });
      Navigator.of(context).pushNamed('/agreement', arguments: {
        'myTxId': _myTx!.id,
        'otherTxId': tx.id,
      });
    } else {
      // Reject the request - reset both specific transactions to pending and clear requestTag
      final batch = FirebaseFirestore.instance.batch();
      final myRef = FirebaseFirestore.instance.collection('transactions').doc(_myTx!.id);
      final otherRef = FirebaseFirestore.instance.collection('transactions').doc(tx.id);
      
      batch.update(myRef, {
        'status': 'pending',
        'partnerTxId': FieldValue.delete(),
        'exchangeRequestedBy': FieldValue.delete(),
        'lockUntil': FieldValue.delete(),
        'requestTag': FieldValue.delete(),
      });
      batch.update(otherRef, {
        'status': 'pending',
        'partnerTxId': FieldValue.delete(),
        'exchangeRequestedBy': FieldValue.delete(),
        'lockUntil': FieldValue.delete(),
        'requestTag': FieldValue.delete(),
      });
      
      await batch.commit();

      // Clear local requested id and refresh matches
      if (mounted) {
        setState(() {
          _requestedTxId = null;
          _lockActive = false;
          _lockUntil = null;
        });
        await _findMatches();
      }
    }
  }

  Future<bool> _onWillPop() async {
    return _canLeave;
  }

  Future<void> _saveRequestInRadius() async {
    if (_myTx != null) {
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(_myTx!.id)
          .update({'searchRadius': _searchRadius});
      if (!mounted) return;
      setState(() {
        _canLeave = true;
      });
      Navigator.of(context).pushReplacementNamed('/history');
    }
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
    if (!mounted) return;
    setState(() {
      _canLeave = true;
    });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final myRequestTag = (_myTx?.data() as Map<String, dynamic>?)?['requestTag'] as String?;
    String timerText =
        "${_remaining.inMinutes.remainder(60).toString().padLeft(2, '0')}:${(_remaining.inSeconds.remainder(60)).toString().padLeft(2, '0')}";

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
                    "${loc.expiresIn}: $timerText",
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
                    value: "best",
                    child: Text("🎯 Smart Match"),
                  ),
                  DropdownMenuItem(
                    value: "distance",
                    child: Text("📍 ${loc.distance}"),
                  ),
                  DropdownMenuItem(
                    value: "amount",
                    child: Text("💰 ${loc.amount}"),
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
            if (_matches.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.star, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    Text(
                      _matches.length == 1 ? "Perfect Match Found!" : "Top 2 Best Matches",
                      style: TextStyle(
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (_noCandidates)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      _searchRadius < 100
                          ? "${loc.noUsersFoundIn} $_searchRadius ${loc.km}"
                          : loc.noUsersAvailableRequestSaved ?? "Sorry, no users available at the moment, your request was saved",
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                    if (_searchRadius < 100)
                      ElevatedButton(
                        onPressed: _expandSearch,
                        child: Text(loc.expandSearch),
                      ),
                  ],
                ),
              ),
            if (!_noCandidates)
              Expanded(
                child: ListView.builder(
                  itemCount: _matches.length,
                  itemBuilder: (ctx, i) {
                    final tx = _matches[i];
                    final txData = tx.data() as Map<String, dynamic>?;

                    if (txData == null || !txData.containsKey('userId')) {
                      return ListTile(title: Text(loc.noTransactions));
                    }

                    // First match is always the best (gold highlight)
                    bool isBestMatch = (i == 0);

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

                        Widget statusIcon = Container();
                        if (isBestMatch) {
                          statusIcon = Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.amber.shade300, Colors.amber.shade100],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.amber.shade600, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.shade200,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 16, color: Colors.amber.shade800),
                                const SizedBox(width: 4),
                                Text(
                                  "BEST MATCH",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Receiver: show accept/reject when this transaction was targeted (partnerTxId == myTx.id)
                        if (txData['status'] == 'requested' &&
                            txData['partnerTxId'] != null &&
                            txData['partnerTxId'] == _myTx?.id &&
                            txData['exchangeRequestedBy'] != currentUserId) {
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: isBestMatch 
                                  ? Border.all(color: Colors.amber.shade400, width: 3)
                                  : null,
                              gradient: isBestMatch 
                                  ? LinearGradient(
                                      colors: [Colors.amber.shade50, Colors.white],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              boxShadow: isBestMatch ? [
                                BoxShadow(
                                  color: Colors.amber.shade200,
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ] : null,
                            ),
                            child: Card(
                              elevation: isBestMatch ? 12 : 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    if (isBestMatch) ...[
                                      statusIcon,
                                      const SizedBox(height: 12),
                                    ],
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 32,
                                          backgroundColor: isBestMatch ? Colors.amber.shade100 : Colors.blueGrey.shade50,
                                          child: Icon(
                                            Icons.person, 
                                            color: isBestMatch ? Colors.amber.shade700 : Colors.blueGrey,
                                            size: 32,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${user['name']} (${user['gender'] == 'Male' ? loc.male : loc.female})',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: isBestMatch ? Colors.amber.shade900 : null,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '${loc.amount}: ${txData['amount']}  •  ${loc.distance}: ~${dist.toStringAsFixed(2)} km',
                                                style: TextStyle(
                                                  color: isBestMatch ? Colors.amber.shade700 : Colors.grey[700],
                                                  fontWeight: isBestMatch ? FontWeight.w600 : null,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            ElevatedButton(
                                              onPressed: () => _respondToRequest(tx, true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isBestMatch ? Colors.amber.shade600 : null,
                                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                              ),
                                              child: Text(
                                                loc.accept,
                                                style: TextStyle(
                                                  fontWeight: isBestMatch ? FontWeight.bold : null,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            OutlinedButton(
                                              onPressed: () => _respondToRequest(tx, false),
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(
                                                  color: isBestMatch ? Colors.amber.shade600 : Colors.grey,
                                                ),
                                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                              ),
                                              child: Text(
                                                loc.reject,
                                                style: TextStyle(
                                                  color: isBestMatch ? Colors.amber.shade700 : null,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        // Requester: show disabled request state for the transaction where partnerTxId == myTx.id
                        if (txData['status'] == 'requested' &&
                            txData['partnerTxId'] != null &&
                            txData['partnerTxId'] == _myTx?.id &&
                            txData['exchangeRequestedBy'] == currentUserId) {
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: isBestMatch 
                                  ? Border.all(color: Colors.amber.shade400, width: 3)
                                  : null,
                            ),
                            child: Card(
                              elevation: isBestMatch ? 8 : 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    if (isBestMatch) ...[
                                      statusIcon,
                                      const SizedBox(height: 12),
                                    ],
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 32,
                                          backgroundColor: isBestMatch ? Colors.amber.shade100 : Colors.green.shade50,
                                          child: Icon(
                                            (txData?['type'] as String?) == 'Deposit' ? Icons.monetization_on : Icons.account_balance_wallet,
                                            color: isBestMatch ? Colors.amber.shade700 : Colors.green,
                                            size: 32,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${user['name']} (${user['gender'] == 'Male' ? loc.male : loc.female})', 
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: isBestMatch ? Colors.amber.shade900 : null,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '${loc.amount}: ${txData['amount']}  •  ${loc.distance}: ~${dist.toStringAsFixed(2)} km', 
                                                style: TextStyle(
                                                  color: isBestMatch ? Colors.amber.shade700 : Colors.grey[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            ElevatedButton(
                                              onPressed: null,
                                              child: Text(loc.exchangeRequestFrom),
                                            ),
                                            const SizedBox(height: 8),
                                            OutlinedButton(
                                              onPressed: null,
                                              child: Text(loc.cancel),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: isBestMatch 
                                ? Border.all(color: Colors.amber.shade400, width: 3)
                                : null,
                            gradient: isBestMatch 
                                ? LinearGradient(
                                    colors: [Colors.amber.shade50, Colors.white],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            boxShadow: isBestMatch ? [
                              BoxShadow(
                                color: Colors.amber.shade200,
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ] : null,
                          ),
                          child: Card(
                            elevation: isBestMatch ? 12 : 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  if (isBestMatch) ...[
                                    statusIcon,
                                    const SizedBox(height: 12),
                                  ],
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 32,
                                        backgroundColor: isBestMatch ? Colors.amber.shade100 : Colors.green.shade50,
                                        child: Icon(
                                          (txData?['type'] as String?) == 'Deposit' ? Icons.monetization_on : Icons.account_balance_wallet,
                                          color: isBestMatch ? Colors.amber.shade700 : Colors.green,
                                          size: 32,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${user['name']} (${user['gender'] == 'Male' ? loc.male : loc.female})', 
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: isBestMatch ? Colors.amber.shade900 : null,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${loc.amount}: ${txData['amount']}  •  ${loc.distance}: ~${dist.toStringAsFixed(2)} km', 
                                              style: TextStyle(
                                                color: isBestMatch ? Colors.amber.shade700 : Colors.grey[700],
                                                fontWeight: isBestMatch ? FontWeight.w600 : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        children: [
                                          ElevatedButton(
                                            onPressed: _lockActive && _lockUntil != null && DateTime.now().isBefore(_lockUntil!) ? null : () => _sendExchangeRequest(tx, user.id),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: isBestMatch ? Colors.amber.shade600 : null,
                                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                            ),
                                            child: Text(
                                              _lockActive && _lockUntil != null && DateTime.now().isBefore(_lockUntil!) ? "Locked (${_lockUntil!.difference(DateTime.now()).inSeconds}s)" : loc.exchangeRequestFrom,
                                              style: TextStyle(
                                                fontWeight: isBestMatch ? FontWeight.bold : null,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          OutlinedButton(
                                            onPressed: _lockActive && _lockUntil != null && DateTime.now().isBefore(_lockUntil!) ? null : () {
                                              if (_myTx != null) {
                                                FirebaseFirestore.instance.collection('transactions').doc(_myTx!.id).update({'status': 'cancelled'});
                                                setState(() {
                                                  _lockActive = false;
                                                  _lockUntil = null;
                                                });
                                              }
                                            },
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(
                                                color: isBestMatch ? Colors.amber.shade600 : Colors.grey,
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                            ),
                                            child: Text(
                                              loc.cancel,
                                              style: TextStyle(
                                                color: isBestMatch ? Colors.amber.shade700 : null,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
                      child: Text('${loc.saveRequest} (${_searchRadius}km)'),
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