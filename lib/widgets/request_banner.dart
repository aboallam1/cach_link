import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RequestBanner extends StatefulWidget {
  final Widget? child;
  const RequestBanner({Key? key, this.child}) : super(key: key);

  @override
  State<RequestBanner> createState() => _RequestBannerState();
}

class _RequestBannerState extends State<RequestBanner> {
  Stream<DocumentSnapshot>? _requestStream;
  String? _activeRequestId;
  int _remaining = 60;
  String? _userId;
  bool _showBanner = false;
  late final Ticker _ticker;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    // Fix: Only access FirebaseAuth.instance.currentUser if not null
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showBanner = false;
      return;
    }
    _userId = user.uid;
    _listenActiveRequest();
    _ticker = Ticker(_onTick);
  }

  void _onTick(Duration elapsed) {
    if (_expiresAt == null) return;
    final left = _expiresAt!.difference(DateTime.now()).inSeconds;
    if (left != _remaining && mounted) {
      setState(() => _remaining = left.clamp(0, 60));
    }
    if (left <= 0) {
      _ticker.stop();
      setState(() => _showBanner = false);
    }
  }

  void _listenActiveRequest() async {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(_userId).get();
    if (userDoc.data()?['hasActiveRequest'] == true) {
      final reqSnap = await FirebaseFirestore.instance
          .collection('requests')
          .where('ownerId', isEqualTo: _userId)
          .where('status', whereIn: ['pending', 'matched', 'awaiting_confirmation'])
          .limit(1)
          .get();
      if (reqSnap.docs.isNotEmpty) {
        final req = reqSnap.docs.first;
        _activeRequestId = req.id;
        _requestStream = req.reference.snapshots();
        setState(() => _showBanner = true);
        _requestStream!.listen((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return;
          final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
          if (expiresAt != null) {
            _expiresAt = expiresAt;
            _ticker.start();
          }
          if (['cancelled', 'completed', 'expired'].contains(data['status'])) {
            _ticker.stop();
            setState(() => _showBanner = false);
          }
        });
      }
    }
  }

  Future<void> _cancelRequest() async {
    if (_activeRequestId == null) return;
    await FirebaseFirestore.instance.collection('requests').doc(_activeRequestId).update({'status': 'cancelled'});
    setState(() => _showBanner = false);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBanner) return widget.child ?? const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.yellow[800],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.timer, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: _requestStream,
                    builder: (ctx, snap) {
                      final status = snap.data?.get('status') ?? '';
                      String text = "Waiting for response…";
                      if (status == 'matched') text = "Matched with user";
                      if (status == 'awaiting_confirmation') text = "Awaiting confirmation";
                      if (status == 'pending') text = "Waiting for response…";
                      return Text(
                        "$text (${_remaining}s)",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: LinearProgressIndicator(
                    value: _remaining / 60,
                    backgroundColor: Colors.yellow[200],
                    color: Colors.red,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.white),
                  onPressed: _cancelRequest,
                  tooltip: "Cancel",
                ),
              ],
            ),
          ),
        ),
        if (widget.child != null) Expanded(child: widget.child!),
      ],
    );
  }
}

// Helper ticker for countdown
class Ticker {
  final void Function(Duration) onTick;
  Duration _elapsed = Duration.zero;
  bool _running = false;
  Ticker(this.onTick);

  void start() {
    if (_running) return;
    _running = true;
    _tick();
  }

  void stop() {
    _running = false;
  }

  void _tick() async {
    while (_running) {
      await Future.delayed(const Duration(seconds: 1));
      if (_running) {
        _elapsed += const Duration(seconds: 1);
        onTick(_elapsed);
      }
    }
  }

  void dispose() {
    _running = false;
  }
}
