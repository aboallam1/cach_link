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
      if (partnerId != null && partnerId.isNotEmpty) {
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
    if (partnerId != null && partnerId.isNotEmpty) {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': partnerId, 'otherTxId': txId});
    } else {
      Navigator.of(context).pushNamed('/agreement', arguments: {'myTxId': txId, 'otherTxId': null});
    }
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
    _localDismissed.add(txId);
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
          if ((data['userId'] ?? data['ownerId'] ?? '') == myUid) return false;
          final rejected = (data['rejectedBy'] as List<dynamic>?)?.cast<String>() ?? [];
          if (rejected.contains(myUid)) return false;
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