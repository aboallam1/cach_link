import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class RequestNotificationOverlay extends StatefulWidget {
  const RequestNotificationOverlay({super.key});

  @override
  State<RequestNotificationOverlay> createState() => _RequestNotificationOverlayState();
}

class _RequestNotificationOverlayState extends State<RequestNotificationOverlay> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, Timer> _timers = {};
  final Map<String, int> _remaining = {};
  final Set<String> _localHidden = {}; // locally dismissed (reject or timeout)

  @override
  void dispose() {
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    super.dispose();
  }

  void _startTimer(String txId, {int from = 60}) {
    if (_timers.containsKey(txId)) return;
    _remaining[txId] = from;
    _timers[txId] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = (_remaining[txId] ?? 0) - 1;
      setState(() => _remaining[txId] = left);
      if (left <= 0) {
        timer.cancel();
        _timers.remove(txId);
        _remaining.remove(txId);
        _localHidden.add(txId);
        try {
          await _db.collection('transactions').doc(txId).update({'status': 'archived'});
          debugPrint('Overlay: auto-archived $txId');
        } catch (e) {
          debugPrint('Overlay: archive failed $txId -> $e');
        }
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _accept(String txId, Map<String, dynamic> data) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      await _db.collection('transactions').doc(txId).update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedBy': me.uid,
      });
      debugPrint('Overlay: accepted $txId by ${me.uid}');
    } catch (e) {
      debugPrint('Overlay: accept failed $txId -> $e');
    }
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    _localHidden.add(txId);
    if (!mounted) return;
    Navigator.of(context).pushNamed('/agreement', arguments: {'otherTxId': txId});
  }

  Future<void> _reject(String txId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      await _db.collection('transactions').doc(txId).update({
        'rejectedBy': FieldValue.arrayUnion([me.uid])
      });
      debugPrint('Overlay: rejected $txId by ${me.uid}');
    } catch (e) {
      debugPrint('Overlay: reject failed $txId -> $e');
    }
    _localHidden.add(txId);
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    if (mounted) setState(() {});
  }

  Widget _banner(BuildContext ctx, DocumentSnapshot doc) {
    final loc = AppLocalizations.of(ctx);
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final txId = doc.id;
    final requester = (data['requesterName'] as String?) ?? (data['userId'] as String?) ?? 'Requester';
    final amount = data['amount'] != null ? "\$${data['amount'].toString()}" : '-';
    final locMap = data['location'] as Map<String, dynamic>?;
    final distanceText = locMap != null && locMap.containsKey('approxDistance') ? "${locMap['approxDistance']} km" : '-';
    final remaining = _remaining[txId] ?? 60;
    final progress = (remaining / 60).clamp(0.0, 1.0);

    if (!_timers.containsKey(txId) && !_localHidden.contains(txId)) {
      _startTimer(txId, from: remaining);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        elevation: 14,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: Colors.blueGrey.shade50, child: const Icon(Icons.person, color: Colors.blueGrey)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(requester, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text("${loc?.amount ?? 'Amount'}: $amount", style: TextStyle(color: Colors.grey[700])),
                    const SizedBox(width: 12),
                    Text("${loc?.distance ?? 'Distance'}: $distanceText", style: TextStyle(color: Colors.grey[700])),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(value: progress, strokeWidth: 4, color: progress > 0.2 ? Colors.green : Colors.red[700], backgroundColor: Colors.grey[200]),
                    ),
                    Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], minimumSize: const Size(80, 36)), onPressed: () => _accept(txId, data), child: Text(loc?.accept ?? 'Accept')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => _reject(txId), child: Text(loc?.reject ?? 'Reject')),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth changes so overlay appears once user logs in
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        if (user == null) {
          // not signed in yet
          return const SizedBox.shrink();
        }
        final myUid = user.uid;

        final txStream = _db.collection('transactions').where('status', isEqualTo: 'requested').snapshots();

        return StreamBuilder<QuerySnapshot>(
          stream: txStream,
          builder: (context, snap) {
            if (!snap.hasData) {
              debugPrint('Overlay: tx snapshot no data');
              return const SizedBox.shrink();
            }
            final docs = snap.data!.docs;
            debugPrint('Overlay: tx snapshot count=${docs.length}');
            final visible = docs.where((d) {
              final data = d.data() as Map<String, dynamic>? ?? {};
              // hide own requests
              if ((data['userId'] ?? data['ownerId'] ?? '') == myUid) return false;
              // hide if explicitly rejected by this user already
              final rejected = (data['rejectedBy'] as List<dynamic>?)?.cast<String>() ?? [];
              if (rejected.contains(myUid)) return false;
              if (_localHidden.contains(d.id)) return false;
              return true;
            }).toList();

            debugPrint('Overlay: visible count=${visible.length}');
            if (visible.isEmpty) return const SizedBox.shrink();

            final banners = visible.take(3).map((d) => _banner(context, d)).toList();

            return Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: banners),
              ),
            );
          },
        );
      },
    );
  }
}
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class RequestNotificationOverlay extends StatefulWidget {
  const RequestNotificationOverlay({super.key});

  @override
  State<RequestNotificationOverlay> createState() => _RequestNotificationOverlayState();
}

class _RequestNotificationOverlayState extends State<RequestNotificationOverlay> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, Timer> _timers = {};
  final Map<String, int> _remaining = {};
  final Set<String> _localHidden = {}; // locally dismissed (reject or timeout)

  @override
  void dispose() {
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    super.dispose();
  }

  void _startTimerFor(String txId, {int startFrom = 60}) {
    if (_timers.containsKey(txId)) return;
    _remaining[txId] = startFrom;
    _timers[txId] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = (_remaining[txId] ?? 0) - 1;
      setState(() => _remaining[txId] = left);
      if (left <= 0) {
        timer.cancel();
        _timers.remove(txId);
        _remaining.remove(txId);
        _localHidden.add(txId);
        try {
          await _db.collection('transactions').doc(txId).update({'status': 'archived'});
        } catch (_) {}
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _acceptRequest(String txId, Map<String, dynamic> data) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      await _db.collection('transactions').doc(txId).update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedBy': me.uid,
      });
    } catch (_) {}
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    _localHidden.add(txId);
    if (!mounted) return;
    // navigate to agreement page; you may want to pass partner ids depending on your flow
    Navigator.of(context).pushNamed('/agreement', arguments: {'otherTxId': txId});
    setState(() {});
  }

  Future<void> _rejectForMe(String txId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      await _db.collection('transactions').doc(txId).update({
        'rejectedBy': FieldValue.arrayUnion([me.uid])
      });
    } catch (_) {}
    _localHidden.add(txId);
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    if (mounted) setState(() {});
  }

  Widget _buildBanner(BuildContext ctx, DocumentSnapshot doc) {
    final loc = AppLocalizations.of(ctx);
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final txId = doc.id;
    final requesterName = (data['requesterName'] as String?) ?? (data['userId'] as String?) ?? 'Requester';
    final amount = data['amount'] != null ? "\$${data['amount'].toString()}" : '-';
    final locMap = data['location'] as Map<String, dynamic>?;
    final distanceText = locMap != null && locMap.containsKey('approxDistance')
        ? "${locMap['approxDistance']} km"
        : (locMap != null && locMap['lat'] != null && locMap['lng'] != null ? "-" : '-');

    final remaining = _remaining[txId] ?? 60;
    final progress = (remaining / 60).clamp(0.0, 1.0);

    if (!_timers.containsKey(txId) && !_localHidden.contains(txId)) {
      _startTimerFor(txId, startFrom: remaining);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        elevation: 14,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: Colors.blueGrey.shade50, child: const Icon(Icons.person, color: Colors.blueGrey)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(requesterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text("${loc?.amount ?? 'Amount'}: $amount", style: TextStyle(color: Colors.grey[700])),
                    const SizedBox(width: 12),
                    Text("${loc?.distance ?? 'Distance'}: $distanceText", style: TextStyle(color: Colors.grey[700])),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        color: progress > 0.2 ? Colors.green : Colors.red[700],
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], minimumSize: const Size(80, 36)),
                    onPressed: () => _acceptRequest(txId, data),
                    child: Text(loc?.accept ?? 'Accept'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _rejectForMe(txId),
                    child: Text(loc?.reject ?? 'Reject'),
                  ),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final myUid = user.uid;

    final stream = _db.collection('transactions').where('status', isEqualTo: 'requested').snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();

        final docs = snap.data!.docs;
        final visible = docs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          // hide requester own requests
          if ((data['userId'] ?? data['ownerId'] ?? '') == myUid) return false;
          // hide if user already rejected this tx
          final rejected = (data['rejectedBy'] as List<dynamic>?)?.cast<String>() ?? [];
          if (rejected.contains(myUid)) return false;
          // hide if locally dismissed (timeout or reject)
          if (_localHidden.contains(d.id)) return false;
          return true;
        }).toList();

        if (visible.isEmpty) return const SizedBox.shrink();

        final banners = visible.take(3).map((d) => _buildBanner(context, d)).toList();

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: banners,
            ),
          ),
        );
      },
    );
  }
}
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class RequestNotificationOverlay extends StatefulWidget {
  const RequestNotificationOverlay({super.key});

  @override
  State<RequestNotificationOverlay> createState() => _RequestNotificationOverlayState();
}

class _RequestNotificationOverlayState extends State<RequestNotificationOverlay> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';
  final Map<String, Timer> _timers = {};
  final Map<String, int> _remaining = {};
  final Set<String> _localHidden = {};

  @override
  void dispose() {
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    super.dispose();
  }

  void _startTimer(String txId, {int from = 60}) {
    if (_timers.containsKey(txId)) return;
    _remaining[txId] = from;
    _timers[txId] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = (_remaining[txId] ?? 0) - 1;
      setState(() => _remaining[txId] = left);
      if (left <= 0) {
        timer.cancel();
        _timers.remove(txId);
        _remaining.remove(txId);
        _localHidden.add(txId);
        try {
          await _db.collection('transactions').doc(txId).update({'status': 'archived'});
        } catch (_) {}
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _accept(String txId, Map<String, dynamic> data) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      final batch = _db.batch();
      final reqRef = _db.collection('transactions').doc(txId);
      batch.update(reqRef, {'status': 'accepted', 'acceptedAt': FieldValue.serverTimestamp()});
      final partnerId = (data['partnerTxId'] as String?) ?? null;
      if (partnerId != null && partnerId.isNotEmpty) {
        final partnerRef = _db.collection('transactions').doc(partnerId);
        batch.update(partnerRef, {'status': 'accepted', 'partnerTxId': txId, 'acceptedAt': FieldValue.serverTimestamp()});
      } else {
        batch.update(reqRef, {'exchangeRequestedBy': me.uid});
      }
      await batch.commit();
    } catch (_) {}
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    _localHidden.add(txId);
    if (!mounted) return;
    final partnerId = (data['partnerTxId'] as String?) ?? null;
    if (partnerId != null && partnerId.isNotEmpty) {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': partnerId, 'otherTxId': txId});
    } else {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': txId, 'otherTxId': null});
    }
  }

  Future<void> _rejectForMe(String txId) async {
    try {
      await _db.collection('transactions').doc(txId).update({'rejectedBy': FieldValue.arrayUnion([_me])});
    } catch (_) {}
    _localHidden.add(txId);
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    if (mounted) setState(() {});
  }

  Widget _buildBanner(BuildContext context, DocumentSnapshot doc) {
    final loc = AppLocalizations.of(context);
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final txId = doc.id;
    final requesterName = (data['requesterName'] as String?) ?? (data['userId'] as String?) ?? 'Requester';
    final amount = data['amount'] != null ? "\$${data['amount'].toString()}" : '-';
    final locMap = data['location'] as Map<String, dynamic>?;
    final distanceText = locMap != null && locMap.containsKey('approxDistance') ? "${locMap['approxDistance']} km" : '-';
    final remaining = _remaining[txId] ?? 60;
    final progress = (remaining / 60).clamp(0.0, 1.0);

    if (!_timers.containsKey(txId) && !_localHidden.contains(txId)) _startTimer(txId, from: remaining);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: Colors.blueGrey.shade50, child: const Icon(Icons.person, color: Colors.blueGrey)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(requesterName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text("${loc?.amount ?? 'Amount'}: $amount", style: TextStyle(color: Colors.grey[700])),
                    const SizedBox(width: 12),
                    Text("${loc?.distance ?? 'Distance'}: $distanceText", style: TextStyle(color: Colors.grey[700])),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        color: progress > 0.2 ? Colors.green : Colors.red[700],
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], minimumSize: const Size(80, 36)),
                    onPressed: () => _accept(txId, data),
                    child: Text(loc?.accept ?? 'Accept'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _rejectForMe(txId),
                    child: Text(loc?.reject ?? 'Reject'),
                  ),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_me.isEmpty) return const SizedBox.shrink();
    final stream = _db.collection('transactions').where('status', isEqualTo: 'requested').snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        final visible = docs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          if ((data['userId'] ?? data['ownerId'] ?? '') == _me) return false;
          final rejected = (data['rejectedBy'] as List<dynamic>?)?.cast<String>() ?? [];
          if (rejected.contains(_me)) return false;
          if (_localHidden.contains(d.id)) return false;
          return true;
        }).toList();

        if (visible.isEmpty) return const SizedBox.shrink();
        final banners = visible.take(3).map((d) => _buildBanner(context, d)).toList();

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: banners)),
        );
      },
    );
  }
}
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class RequestNotificationOverlay extends StatefulWidget {
  const RequestNotificationOverlay({super.key});

  @override
  State<RequestNotificationOverlay> createState() => _RequestNotificationOverlayState();
}

class _RequestNotificationOverlayState extends State<RequestNotificationOverlay> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';
  final Map<String, Timer> _timers = {};
  final Map<String, int> _remaining = {};
  final Set<String> _localDismissed = {};

  @override
  void dispose() {
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    super.dispose();
  }

  void _startTimer(String txId, {int from = 60}) {
    if (_timers.containsKey(txId)) return;
    _remaining[txId] = from;
    _timers[txId] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = (_remaining[txId] ?? 0) - 1;
      setState(() => _remaining[txId] = left);
      if (left <= 0) {
        timer.cancel();
        _timers.remove(txId);
        _remaining.remove(txId);
        _localDismissed.add(txId);
        try {
          await _db.collection('transactions').doc(txId).update({'status': 'archived'});
        } catch (_) {}
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _accept(String txId, Map<String, dynamic> data) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      final batch = _db.batch();
      final reqRef = _db.collection('transactions').doc(txId);
      batch.update(reqRef, {'status': 'accepted', 'acceptedAt': FieldValue.serverTimestamp()});
      final partner = data['partnerTxId'] as String?;
      if (partner != null && partner.isNotEmpty) {
        final pRef = _db.collection('transactions').doc(partner);
        batch.update(pRef, {'status': 'accepted', 'partnerTxId': txId, 'acceptedAt': FieldValue.serverTimestamp()});
      } else {
        batch.update(reqRef, {'exchangeRequestedBy': me.uid});
      }
      await batch.commit();
    } catch (_) {}
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    _localDismissed.add(txId);
    if (!mounted) return;
    final partner = (data['partnerTxId'] as String?) ?? null;
    if (partner != null && partner.isNotEmpty) {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': partner, 'otherTxId': txId});
    } else {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': txId, 'otherTxId': null});
    }
  }

  Future<void> _reject(String txId) async {
    try {
      await _db.collection('transactions').doc(txId).update({'rejectedBy': FieldValue.arrayUnion([_me])});
    } catch (_) {}
    _localDismissed.add(txId);
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    if (mounted) setState(() {});
  }

  Widget _buildBanner(BuildContext ctx, DocumentSnapshot doc) {
    final loc = AppLocalizations.of(ctx);
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final txId = doc.id;
    final requester = (data['requesterName'] as String?) ?? (data['userId'] as String?) ?? 'Requester';
    final amount = data['amount'] != null ? "\$${data['amount'].toString()}" : '-';
    final locMap = data['location'] as Map<String, dynamic>?;
    final distanceText = locMap != null && locMap.containsKey('approxDistance')
        ? "${locMap['approxDistance']} km"
        : '-';
    final remaining = _remaining[txId] ?? 60;
    final progress = (remaining / 60).clamp(0.0, 1.0);

    if (!_timers.containsKey(txId) && !_localDismissed.contains(txId)) {
      _startTimer(txId, from: remaining);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white, border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: Colors.blueGrey.shade50, child: const Icon(Icons.person, color: Colors.blueGrey)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(requester, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text("${loc?.amount ?? 'Amount'}: $amount", style: TextStyle(color: Colors.grey[700])),
                    const SizedBox(width: 12),
                    Text("${loc?.distance ?? 'Distance'}: $distanceText", style: TextStyle(color: Colors.grey[700])),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        color: progress > 0.2 ? Colors.green : Colors.red[700],
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], minimumSize: const Size(80, 36)), onPressed: () => _accept(txId, data), child: Text(loc?.accept ?? 'Accept')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => _reject(txId), child: Text(loc?.reject ?? 'Reject')),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_me.isEmpty) return const SizedBox.shrink();
    final stream = _db.collection('transactions').where('status', isEqualTo: 'requested').snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();

        final docs = snap.data!.docs;
        final visible = docs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          if ((data['userId'] ?? data['ownerId'] ?? '') == _me) return false;
          final rejected = (data['rejectedBy'] as List<dynamic>?)?.cast<String>() ?? [];
          if (rejected.contains(_me)) return false;
          if (_localDismissed.contains(d.id)) return false;
          return true;
        }).toList();

        if (visible.isEmpty) return const SizedBox.shrink();
        final banners = visible.take(3).map((d) => _buildBanner(context, d)).toList();

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: banners)),
        );
      },
    );
  }
}
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class RequestNotificationOverlay extends StatefulWidget {
  const RequestNotificationOverlay({super.key});

  @override
  State<RequestNotificationOverlay> createState() => _RequestNotificationOverlayState();
}

class _RequestNotificationOverlayState extends State<RequestNotificationOverlay> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';
  final Map<String, Timer> _timers = {};
  final Map<String, int> _remaining = {};
  final Set<String> _localDismissed = {};

  @override
  void dispose() {
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    super.dispose();
  }

  void _startTimer(String txId, {int from = 60}) {
    if (_timers.containsKey(txId)) return;
    _remaining[txId] = from;
    _timers[txId] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = (_remaining[txId] ?? 0) - 1;
      setState(() => _remaining[txId] = left);
      if (left <= 0) {
        timer.cancel();
        _timers.remove(txId);
        _remaining.remove(txId);
        _localDismissed.add(txId);
        try {
          await _db.collection('transactions').doc(txId).update({'status': 'archived'});
        } catch (_) {}
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _accept(String txId, Map<String, dynamic> data) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      final batch = _db.batch();
      final reqRef = _db.collection('transactions').doc(txId);
      batch.update(reqRef, {'status': 'accepted', 'acceptedAt': FieldValue.serverTimestamp()});
      final partner = data['partnerTxId'] as String?;
      if (partner != null && partner.isNotEmpty) {
        final pRef = _db.collection('transactions').doc(partner);
        batch.update(pRef, {'status': 'accepted', 'partnerTxId': txId, 'acceptedAt': FieldValue.serverTimestamp()});
      } else {
        batch.update(reqRef, {'exchangeRequestedBy': me.uid});
      }
      await batch.commit();
    } catch (_) {}
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    _localDismissed.add(txId);
    if (!mounted) return;
    final partner = (data['partnerTxId'] as String?) ?? null;
    if (partner != null && partner.isNotEmpty) {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': partner, 'otherTxId': txId});
    } else {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': txId, 'otherTxId': null});
    }
  }

  Future<void> _reject(String txId) async {
    try {
      await _db.collection('transactions').doc(txId).update({'rejectedBy': FieldValue.arrayUnion([_me])});
    } catch (_) {}
    _localDismissed.add(txId);
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    if (mounted) setState(() {});
  }

  double _distanceKm(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return -1.0;
    final num? la = a['lat'] as num?;
    final num? lo = a['lng'] as num?;
    final num? lb = b['lat'] as num?;
    final num? lb2 = b['lng'] as num?;
    if (la == null || lo == null || lb == null || lb2 == null) return -1.0;
    final lat1 = la.toDouble(), lon1 = lo.toDouble(), lat2 = lb.toDouble(), lon2 = lb2.toDouble();
    const p = 0.017453292519943295;
    final x = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(x));
  }

  Widget _banner(BuildContext ctx, DocumentSnapshot doc) {
    final loc = AppLocalizations.of(ctx);
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final txId = doc.id;
    final requester = (data['requesterName'] as String?) ?? (data['userId'] as String?) ?? 'Requester';
    final amount = data['amount'] != null ? "\$${data['amount'].toString()}" : '-';
    final locMap = data['location'] as Map<String, dynamic>?;
    final distanceText = locMap != null && locMap.containsKey('approxDistance') ? "${locMap['approxDistance']} km" : '-';

    final remaining = _remaining[txId] ?? 60;
    final progress = (remaining / 60).clamp(0.0, 1.0);

    if (!_timers.containsKey(txId) && !_localDismissed.contains(txId)) {
      _startTimer(txId, from: remaining);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white, border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: Colors.blueGrey.shade50, child: const Icon(Icons.person, color: Colors.blueGrey)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(requester, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text("${loc?.amount ?? 'Amount'}: $amount", style: TextStyle(color: Colors.grey[700])),
                    const SizedBox(width: 12),
                    Text("${loc?.distance ?? 'Distance'}: $distanceText", style: TextStyle(color: Colors.grey[700])),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(value: progress, strokeWidth: 4, color: progress > 0.2 ? Colors.green : Colors.red[700], backgroundColor: Colors.grey[200]),
                    ),
                    Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], minimumSize: const Size(80, 36)), onPressed: () => _accept(txId, data), child: Text(loc?.accept ?? 'Accept')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => _reject(txId), child: Text(loc?.reject ?? 'Reject')),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_me.isEmpty) return const SizedBox.shrink();
    final stream = _db.collection('transactions').where('status', isEqualTo: 'requested').snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        final visible = docs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          if ((data['userId'] ?? data['ownerId'] ?? '') == _me) return false;
          final rejected = (data['rejectedBy'] as List<dynamic>?)?.cast<String>() ?? [];
          if (rejected.contains(_me)) return false;
          if (_localDismissed.contains(d.id)) return false;
          return true;
        }).toList();

        if (visible.isEmpty) return const SizedBox.shrink();
        final banners = visible.take(3).map((d) => _banner(context, d)).toList();

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: banners),
          ),
        );
      },
    );
  }
}
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class RequestNotificationOverlay extends StatefulWidget {
  const RequestNotificationOverlay({super.key});

  @override
  State<RequestNotificationOverlay> createState() => _RequestNotificationOverlayState();
}

class _RequestNotificationOverlayState extends State<RequestNotificationOverlay> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';
  final Map<String, Timer> _timers = {};
  final Map<String, int> _remaining = {};
  final Set<String> _localDismissed = {};

  @override
  void dispose() {
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    super.dispose();
  }

  void _startTimer(String txId, {int startFrom = 60}) {
    if (_timers.containsKey(txId)) return;
    _remaining[txId] = startFrom;
    _timers[txId] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final left = (_remaining[txId] ?? 0) - 1;
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining[txId] = left);
      if (left <= 0) {
        timer.cancel();
        _timers.remove(txId);
        _remaining.remove(txId);
        _localDismissed.add(txId);
        try {
          await _db.collection('transactions').doc(txId).update({'status': 'archived'});
        } catch (_) {}
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _acceptRequest(String txId, Map<String, dynamic> txData) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      final batch = _db.batch();
      final reqRef = _db.collection('transactions').doc(txId);
      batch.update(reqRef, {'status': 'accepted', 'acceptedAt': FieldValue.serverTimestamp()});

      final partnerId = (txData['partnerTxId'] as String?) ?? txData['partnerTxId'];
      if (partnerId is String && partnerId.isNotEmpty) {
        final partnerRef = _db.collection('transactions').doc(partnerId);
        batch.update(partnerRef, {'status': 'accepted', 'partnerTxId': txId, 'acceptedAt': FieldValue.serverTimestamp()});
      } else {
        batch.update(reqRef, {'exchangeRequestedBy': me.uid});
      }

      await batch.commit();
    } catch (_) {}

    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    _localDismissed.add(txId);

    if (!mounted) return;
    final partnerId = (txData['partnerTxId'] as String?) ?? null;
    if (partnerId != null && partnerId.isNotEmpty) {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': partnerId, 'otherTxId': txId});
    } else {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': txId, 'otherTxId': null});
    }
    setState(() {});
  }

  Future<void> _rejectForMe(String txId) async {
    try {
      await _db.collection('transactions').doc(txId).update({'rejectedBy': FieldValue.arrayUnion([_me])});
    } catch (_) {}
    _localDismissed.add(txId);
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    if (mounted) setState(() {});
  }

  double _distanceKm(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return -1.0;
    final num? lat1n = a['lat'] as num?;
    final num? lon1n = a['lng'] as num?;
    final num? lat2n = b['lat'] as num?;
    final num? lon2n = b['lng'] as num?;
    if (lat1n == null || lon1n == null || lat2n == null || lon2n == null) return -1.0;
    final lat1 = lat1n.toDouble(), lon1 = lon1n.toDouble(), lat2 = lat2n.toDouble(), lon2 = lon2n.toDouble();
    const p = 0.017453292519943295;
    final aVal = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(aVal));
  }

  Widget _buildBanner(BuildContext context, DocumentSnapshot doc) {
    final loc = AppLocalizations.of(context);
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final txId = doc.id;
    final requesterName = (data['requesterName'] as String?) ?? (data['userId'] as String?) ?? 'Requester';
    final amount = data['amount'] != null ? "\$${data['amount'].toString()}" : '-';
    final requesterLoc = data['location'] as Map<String, dynamic>?;
    final distanceText = requesterLoc != null && requesterLoc.containsKey('approxDistance')
        ? "${requesterLoc['approxDistance']} km"
        : (requesterLoc != null ? "${_distanceKm(requesterLoc, requesterLoc).toStringAsFixed(1)} km" : '-');

    final remaining = _remaining[txId] ?? 60;
    final progress = (remaining / 60).clamp(0.0, 1.0);

    if (!_timers.containsKey(txId) && !_localDismissed.contains(txId)) _startTimer(txId, startFrom: remaining);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.white, border: Border.all(color: Colors.grey.shade200)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: Colors.blueGrey.shade50, child: const Icon(Icons.person, color: Colors.blueGrey)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(requesterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text("${loc?.amount ?? 'Amount'}: $amount", style: TextStyle(color: Colors.grey[700])),
                    const SizedBox(width: 12),
                    Text("${loc?.distance ?? 'Distance'}: $distanceText", style: TextStyle(color: Colors.grey[700])),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        color: progress > 0.2 ? Colors.green : Colors.red[700],
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], minimumSize: const Size(80, 36)),
                    onPressed: () => _acceptRequest(txId, data),
                    child: Text(loc?.accept ?? 'Accept'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => _rejectForMe(txId), child: Text(loc?.reject ?? 'Reject')),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_me.isEmpty) return const SizedBox.shrink();
    final stream = _db.collection('transactions').where('status', isEqualTo: 'requested').snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        final visible = docs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          if ((data['userId'] ?? data['ownerId'] ?? '') == _me) return false;
          final rejected = (data['rejectedBy'] as List<dynamic>?)?.cast<String>() ?? [];
          if (rejected.contains(_me)) return false;
          if (_localDismissed.contains(d.id)) return false;
          return true;
        }).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        final banners = visible.take(3).map((d) => _buildBanner(context, d)).toList();

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: banners),
          ),
        );
      },
    );
  }
}
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class RequestNotificationOverlay extends StatefulWidget {
  const RequestNotificationOverlay({super.key});

  @override
  State<RequestNotificationOverlay> createState() => _RequestNotificationOverlayState();
}

class _RequestNotificationOverlayState extends State<RequestNotificationOverlay> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';
  final Map<String, Timer> _timers = {};
  final Map<String, int> _remaining = {};
  final Set<String> _localDismissed = {};

  @override
  void dispose() {
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    super.dispose();
  }

  void _startTimer(String txId, {int startFrom = 60}) {
    if (_timers.containsKey(txId)) return;
    _remaining[txId] = startFrom;
    _timers[txId] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final left = (_remaining[txId] ?? 0) - 1;
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining[txId] = left);
      if (left <= 0) {
        timer.cancel();
        _timers.remove(txId);
        _remaining.remove(txId);
        _localDismissed.add(txId);
        try {
          await _db.collection('transactions').doc(txId).update({'status': 'archived'});
        } catch (_) {}
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _acceptRequest(String txId, Map<String, dynamic> txData) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      final batch = _db.batch();
      final reqRef = _db.collection('transactions').doc(txId);
      batch.update(reqRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      final partnerId = txData['partnerTxId'] as String?;
      if (partnerId != null) {
        final partnerRef = _db.collection('transactions').doc(partnerId);
        batch.update(partnerRef, {
          'status': 'accepted',
          'partnerTxId': txId,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      } else {
        batch.update(reqRef, {'exchangeRequestedBy': me.uid});
      }

      await batch.commit();
    } catch (_) {}

    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    _localDismissed.add(txId);
    if (!mounted) return;

    final partnerId = txData['partnerTxId'] as String?;
    if (partnerId != null) {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': partnerId, 'otherTxId': txId});
    } else {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': txId, 'otherTxId': null});
    }
    setState(() {});
  }

  Future<void> _rejectForMe(String txId) async {
    try {
      await _db.collection('transactions').doc(txId).update({
        'rejectedBy': FieldValue.arrayUnion([_me])
      });
    } catch (_) {}
    _localDismissed.add(txId);
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    if (mounted) setState(() {});
  }

  double _distanceKm(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return -1.0;
    final num? lat1n = a['lat'] as num?;
    final num? lon1n = a['lng'] as num?;
    final num? lat2n = b['lat'] as num?;
    final num? lon2n = b['lng'] as num?;
    if (lat1n == null || lon1n == null || lat2n == null || lon2n == null) return -1.0;
    final lat1 = lat1n.toDouble();
    final lon1 = lon1n.toDouble();
    final lat2 = lat2n.toDouble();
    final lon2 = lon2n.toDouble();
    const p = 0.017453292519943295;
    final aVal = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(aVal));
  }

  Widget _buildBanner(BuildContext context, DocumentSnapshot doc) {
    final loc = AppLocalizations.of(context);
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final txId = doc.id;
    final requesterName = (data['requesterName'] as String?) ?? (data['userId'] as String?) ?? 'Requester';
    final amount = data['amount'] != null ? "\$${data['amount'].toString()}" : '-';
    final requesterLoc = data['location'] as Map<String, dynamic>?;
    final distanceText = requesterLoc != null && requesterLoc.containsKey('approxDistance')
        ? "${requesterLoc['approxDistance']} km"
        : '-';
    final remaining = _remaining[txId] ?? 60;
    final progress = (remaining / 60).clamp(0.0, 1.0);

    if (!_timers.containsKey(txId) && !_localDismissed.contains(txId)) {
      _startTimer(txId, startFrom: remaining);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blueGrey.shade50,
                child: const Icon(Icons.person, color: Colors.blueGrey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(requesterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text("${loc?.amount ?? 'Amount'}: $amount", style: TextStyle(color: Colors.grey[700])),
                    const SizedBox(width: 12),
                    Text("${loc?.distance ?? 'Distance'}: $distanceText", style: TextStyle(color: Colors.grey[700])),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        color: progress > 0.2 ? Colors.green : Colors.red[700],
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], minimumSize: const Size(80, 36)),
                    onPressed: () => _acceptRequest(txId, data),
                    child: Text(loc?.accept ?? 'Accept'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _rejectForMe(txId),
                    child: Text(loc?.reject ?? 'Reject'),
                  ),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_me.isEmpty) return const SizedBox.shrink();

    final stream = _db.collection('transactions').where('status', isEqualTo: 'requested').snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();

        final docs = snap.data!.docs;
        final visible = docs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          if ((data['userId'] ?? data['ownerId'] ?? '') == _me) return false;
          final rejected = (data['rejectedBy'] as List<dynamic>?)?.cast<String>() ?? [];
          if (rejected.contains(_me)) return false;
          if (_localDismissed.contains(d.id)) return false;
          return true;
        }).toList();

        if (visible.isEmpty) return const SizedBox.shrink();

        final banners = visible.take(3).map((d) => _buildBanner(context, d)).toList();

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: banners),
          ),
        );
      },
    );
  }
}
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class RequestNotificationOverlay extends StatefulWidget {
  const RequestNotificationOverlay({super.key});

  @override
  State<RequestNotificationOverlay> createState() => _RequestNotificationOverlayState();
}

class _RequestNotificationOverlayState extends State<RequestNotificationOverlay> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';
  final Map<String, Timer> _timers = {};
  final Map<String, int> _remaining = {};
  final Set<String> _localDismissed = {};

  @override
  void dispose() {
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    super.dispose();
  }

  void _startTimer(String txId, {int startFrom = 60}) {
    if (_timers.containsKey(txId)) return;
    _remaining[txId] = startFrom;
    _timers[txId] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final left = (_remaining[txId] ?? 0) - 1;
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining[txId] = left);
      if (left <= 0) {
        timer.cancel();
        _timers.remove(txId);
        _remaining.remove(txId);
        _localDismissed.add(txId);
        try {
          await _db.collection('transactions').doc(txId).update({'status': 'archived'});
        } catch (_) {}
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _acceptRequest(String txId, Map<String, dynamic> txData) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      final batch = _db.batch();
      final reqRef = _db.collection('transactions').doc(txId);
      batch.update(reqRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      final partnerId = txData['partnerTxId'] as String?;
      if (partnerId != null) {
        final partnerRef = _db.collection('transactions').doc(partnerId);
        batch.update(partnerRef, {
          'status': 'accepted',
          'partnerTxId': txId,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      } else {
        batch.update(reqRef, {'exchangeRequestedBy': me.uid});
      }

      await batch.commit();
    } catch (_) {}

    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    _localDismissed.add(txId);
    if (!mounted) return;

    final partnerId = txData['partnerTxId'] as String?;
    if (partnerId != null) {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': partnerId, 'otherTxId': txId});
    } else {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': txId, 'otherTxId': null});
    }
    setState(() {});
  }

  Future<void> _rejectForMe(String txId) async {
    try {
      await _db.collection('transactions').doc(txId).update({
        'rejectedBy': FieldValue.arrayUnion([_me])
      });
    } catch (_) {}
    _localDismissed.add(txId);
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    if (mounted) setState(() {});
  }

  double _distanceKm(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return -1.0;
    final num? lat1n = a['lat'] as num?;
    final num? lon1n = a['lng'] as num?;
    final num? lat2n = b['lat'] as num?;
    final num? lon2n = b['lng'] as num?;
    if (lat1n == null || lon1n == null || lat2n == null || lon2n == null) return -1.0;
    final lat1 = lat1n.toDouble();
    final lon1 = lon1n.toDouble();
    final lat2 = lat2n.toDouble();
    final lon2 = lon2n.toDouble();
    const p = 0.017453292519943295;
    final aVal = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(aVal));
  }

  Widget _buildBanner(BuildContext context, DocumentSnapshot doc) {
    final loc = AppLocalizations.of(context);
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final txId = doc.id;
    final requesterName = (data['requesterName'] as String?) ?? (data['userId'] as String?) ?? 'Requester';
    final amount = data['amount'] != null ? "\$${data['amount'].toString()}" : '-';
    final requesterLoc = data['location'] as Map<String, dynamic>?;
    final distanceText = requesterLoc != null && requesterLoc.containsKey('approxDistance')
        ? "${requesterLoc['approxDistance']} km"
        : '-';
    final remaining = _remaining[txId] ?? 60;
    final progress = (remaining / 60).clamp(0.0, 1.0);

    if (!_timers.containsKey(txId) && !_localDismissed.contains(txId)) {
      _startTimer(txId, startFrom: remaining);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blueGrey.shade50,
                child: const Icon(Icons.person, color: Colors.blueGrey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(requesterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text("${loc?.amount ?? 'Amount'}: $amount", style: TextStyle(color: Colors.grey[700])),
                    const SizedBox(width: 12),
                    Text("${loc?.distance ?? 'Distance'}: $distanceText", style: TextStyle(color: Colors.grey[700])),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        color: progress > 0.2 ? Colors.green : Colors.red[700],
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], minimumSize: const Size(80, 36)),
                    onPressed: () => _acceptRequest(txId, data),
                    child: Text(loc?.accept ?? 'Accept'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _rejectForMe(txId),
                    child: Text(loc?.reject ?? 'Reject'),
                  ),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_me.isEmpty) return const SizedBox.shrink();

    final stream = _db.collection('transactions').where('status', isEqualTo: 'requested').snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();

        final docs = snap.data!.docs;
        final visible = docs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          if ((data['userId'] ?? data['ownerId'] ?? '') == _me) return false;
          final rejected = (data['rejectedBy'] as List<dynamic>?)?.cast<String>() ?? [];
          if (rejected.contains(_me)) return false;
          if (_localDismissed.contains(d.id)) return false;
          return true;
        }).toList();

        if (visible.isEmpty) return const SizedBox.shrink();

        final banners = visible.take(3).map((d) => _buildBanner(context, d)).toList();

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: banners),
          ),
        );
      },
    );
  }
}
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class RequestNotificationOverlay extends StatefulWidget {
  const RequestNotificationOverlay({super.key});

  @override
  State<RequestNotificationOverlay> createState() => _RequestNotificationOverlayState();
}

class _RequestNotificationOverlayState extends State<RequestNotificationOverlay> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';
  // per-tx timers and remaining seconds
  final Map<String, Timer> _timers = {};
  final Map<String, int> _remaining = {};
  final Set<String> _localDismissed = {}; // user-specific rejects/hidden

  @override
  void dispose() {
    for (final t in _timers.values) t.cancel();
    _timers.clear();
    super.dispose();
  }

  void _startTimer(String txId, {int startFrom = 60}) {
    if (_timers.containsKey(txId)) return;
    _remaining[txId] = startFrom;
    _timers[txId] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final left = (_remaining[txId] ?? 0) - 1;
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining[txId] = left);
      if (left <= 0) {
        timer.cancel();
        _timers.remove(txId);
        _remaining.remove(txId);
        _localDismissed.add(txId);
        try {
          // archive globally
          await _db.collection('transactions').doc(txId).update({'status': 'archived'});
        } catch (_) {}
        if (mounted) setState(() {}); // refresh UI
      }
    });
  }

  Future<void> _acceptRequest(String txId, Map<String, dynamic> txData) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final otherTxId = txData['partnerTxId'] ?? txId; // partnerTxId may be provided by requester
    // We update the request document to accepted. The "other" transaction update logic (pairing) is app-specific.
    try {
      final batch = _db.batch();
      final reqRef = _db.collection('transactions').doc(txId);
      batch.update(reqRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      // if requester set partnerTxId to point to a matching transaction, update both side if exists
      if (txData['partnerTxId'] != null) {
        final partnerRef = _db.collection('transactions').doc(txData['partnerTxId']);
        batch.update(partnerRef, {
          'status': 'accepted',
          'partnerTxId': txId,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // mark partnerTxId with this user's id as exchangeRequestedBy (optional)
        batch.update(reqRef, {
          'exchangeRequestedBy': me.uid,
        });
      }

      await batch.commit();
    } catch (e) {
      // ignore or show error
    }

    // stop local timer and remove
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    _localDismissed.add(txId);

    if (!mounted) return;

    // navigate to agreement page with tx id pair if available
    final partnerTxId = txData['partnerTxId'] as String?;
    if (partnerTxId != null) {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': partnerTxId, 'otherTxId': txId});
    } else {
      // fallback: open agreement with this tx as myTx (app may handle)
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': txId, 'otherTxId': null});
    }

    setState(() {});
  }

  Future<void> _rejectForMe(String txId) async {
    try {
      await _db.collection('transactions').doc(txId).update({
        'rejectedBy': FieldValue.arrayUnion([_me])
      });
    } catch (_) {}
    // hide locally
    _localDismissed.add(txId);
    // stop timer
    _timers[txId]?.cancel();
    _timers.remove(txId);
    _remaining.remove(txId);
    if (mounted) setState(() {});
  }

  double _distanceKm(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null || b == null) return -1.0;
    final lat1 = a['lat']?.toDouble();
    final lon1 = a['lng']?.toDouble();
    final lat2 = b['lat']?.toDouble();
    final lon2 = b['lng']?.toDouble();
    if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return -1.0;
    const p = 0.017453292519943295;
    final aVal = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(aVal));
  }

  Widget _buildBanner(BuildContext context, DocumentSnapshot doc) {
    final loc = AppLocalizations.of(context);
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final txId = doc.id;
    final requesterName = (data['requesterName'] as String?) ?? (data['userId'] as String?) ?? (data['ownerName'] as String?) ?? 'Requester';
    final amount = data['amount'] != null ? "\$${(data['amount']).toString()}" : '-';
    final requesterLoc = data['location'] as Map<String, dynamic>?;
    // compute approximate distance to current user if user's location saved in profile
    // we fetch current user's saved location once (non-blocking)
    final currentUserDocRef = _db.collection('users').doc(_me);
    // We avoid awaiting here; try to get distance from requester's 'distanceText' or show '-' fallback
    final distanceText = requesterLoc != null ? "${requesterLoc['approxDistance'] ?? '-'} km" : '-';
    final remaining = _remaining[txId] ?? 60;
    final progress = (remaining / 60).clamp(0.0, 1.0);

    // start timer if not started
    if (!_timers.containsKey(txId) && !_localDismissed.contains(txId)) {
      _startTimer(txId, startFrom: remaining);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blueGrey.shade50,
                child: const Icon(Icons.person, color: Colors.blueGrey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(requesterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text("${loc?.amount ?? 'Amount'}: $amount", style: TextStyle(color: Colors.grey[700])),
                    const SizedBox(width: 12),
                    Text("${loc?.distance ?? 'Distance'}: $distanceText", style: TextStyle(color: Colors.grey[700])),
                  ]),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        color: progress > 0.2 ? Colors.green : Colors.red[700],
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                    Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], minimumSize: const Size(80, 36)),
                    onPressed: () => _acceptRequest(txId, data),
                    child: Text(loc?.accept ?? 'Accept'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _rejectForMe(txId),
                    child: Text(loc?.reject ?? 'Reject'),
                  ),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_me.isEmpty) return const SizedBox.shrink();

    // Stream: transactions with status 'requested' and not archived
    final stream = _db.collection('transactions').where('status', isEqualTo: 'requested').snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();

        final docs = snap.data!.docs;
        // filter: exclude requests originated by current user and those we've locally dismissed or explicitly rejected
        final visible = docs.where((d) {
          final data = d.data() as Map<String, dynamic>? ?? {};
          if ((data['userId'] ?? data['ownerId'] ?? '') == _me) return false;
          final rejected = (data['rejectedBy'] as List<dynamic>?)?.cast<String>() ?? [];
          if (rejected.contains(_me)) return false;
          if (_localDismissed.contains(d.id)) return false;
          return true;
        }).toList();

        if (visible.isEmpty) return const SizedBox.shrink();

        // render up to 3 stacked banners (top)
        final banners = visible.take(3).map((d) => _buildBanner(context, d)).toList();

        return Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: banners,
            ),
          ),
        );
      },
    );
  }
}
import 'package:flutter/material.dart';

class RequestNotificationOverlay extends StatelessWidget {
  const RequestNotificationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.shrink();
  }
}