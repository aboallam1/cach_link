import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class AgreementScreen extends StatefulWidget {
  const AgreementScreen({super.key});

  @override
  State<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends State<AgreementScreen> {
  bool _busy = false;
  bool _sharingLocation = false;
  int _remainingSeconds = 60;
  late final Stopwatch _stopwatch;
  late final Ticker _ticker;
  bool _canLeave = false;
  bool _showCancel = true;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _ticker = Ticker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    setState(() {
      _remainingSeconds = 60 - elapsed.inSeconds;
      if (_remainingSeconds <= 0) {
        _remainingSeconds = 0;
        _showCancel = false;
        _canLeave = true;
        _ticker.stop();
        // On timeout: leave to match page
        Future.microtask(() {
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            Navigator.of(context).pushReplacementNamed('/match');
          }
        });
      }
    });
  }
  
  Future<void> _setBothTxFields({
    required String myTxId,
    required String otherTxId,
    required Map<String, dynamic> data,
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    final myRef =
        FirebaseFirestore.instance.collection('transactions').doc(myTxId);
    final otherRef =
        FirebaseFirestore.instance.collection('transactions').doc(otherTxId);
    batch.update(myRef, data);
    batch.update(otherRef, data);
    await batch.commit();
  }

  Future<void> _acceptRequest(String myTxId, String otherTxId) async {
    setState(() => _busy = true);
    await _setBothTxFields(
      myTxId: myTxId,
      otherTxId: otherTxId,
      data: {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      },
    );
    setState(() => _busy = false);
  }

  Future<void> _declineRequest(String myTxId, String otherTxId) async {
    setState(() => _busy = true);
    await _setBothTxFields(
      myTxId: myTxId,
      otherTxId: otherTxId,
      data: {
        'status': 'pending',
        'partnerTxId': FieldValue.delete(),
        'exchangeRequestedBy': FieldValue.delete(),
        'acceptedAt': FieldValue.delete(),
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(context);
  }

  Future<void> _shareMyLocation(String myTxId) async {
    setState(() => _sharingLocation = true);
    final loc = Location();
    final permission = await loc.requestPermission();
    if (permission == PermissionStatus.denied ||
        permission == PermissionStatus.deniedForever) {
      if (!mounted) return;
      setState(() => _sharingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied')),
      );
      return;
    }
    final data = await loc.getLocation();
    await FirebaseFirestore.instance
        .collection('transactions')
        .doc(myTxId)
        .update({
      'sharedLocation': {
        'lat': data.latitude,
        'lng': data.longitude,
      },
      'sharedLocationAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    setState(() => _sharingLocation = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Location shared')),
    );
  }

  Future<void> _confirmStep({
    required String myTxId,
    required String otherTxId,
    required bool iAmDeposit,
  }) async {
    setState(() => _busy = true);

    final myFlag = iAmDeposit ? 'instapayConfirmed' : 'cashConfirmed';

    await FirebaseFirestore.instance
        .collection('transactions')
        .doc(myTxId)
        .update({myFlag: true});

    final mySnap = await FirebaseFirestore.instance
        .collection('transactions')
        .doc(myTxId)
        .get();
    final otherSnap = await FirebaseFirestore.instance
        .collection('transactions')
        .doc(otherTxId)
        .get();

    final myData = mySnap.data() as Map<String, dynamic>;
    final otherData = otherSnap.data() as Map<String, dynamic>;

    final instapayConfirmed =
        (myData['instapayConfirmed'] == true) ||
            (otherData['instapayConfirmed'] == true);
    final cashConfirmed = (myData['cashConfirmed'] == true) ||
        (otherData['cashConfirmed'] == true);

    if (instapayConfirmed && cashConfirmed) {
      await _setBothTxFields(
        myTxId: myTxId,
        otherTxId: otherTxId,
        data: {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp()
        },
      );

      final otherUserId = otherData['userId'];
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/rating', arguments: {
        'otherUserId': otherUserId,
      });
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(iAmDeposit
              ? 'Waiting for cash confirmation from the other party.'
              : 'Waiting for Instapay confirmation from the other party.'),
        ),
      );
    }

    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    final myTxId = args?['myTxId'] as String?;
    final otherTxIdArg = args?['otherTxId'] as String?;

    if (myTxId == null) {
      return Scaffold(
          body: Center(child: Text(loc.noTransactions)));
    }

    final myTxStream = FirebaseFirestore.instance
        .collection('transactions')
        .doc(myTxId)
        .snapshots();

    return WillPopScope(
      onWillPop: _onWillPop,
      child: StreamBuilder<DocumentSnapshot>(
        stream: myTxStream,
        builder: (context, mySnap) {
          if (!mySnap.hasData) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final myDoc = mySnap.data!;
          if (!myDoc.exists) {
            return Scaffold(
                body: Center(child: Text(loc.noTransactions)));
          }
          final myData = myDoc.data() as Map<String, dynamic>;
          final currentUserId = FirebaseAuth.instance.currentUser!.uid;

          final otherTxId = otherTxIdArg ?? (myData['partnerTxId'] as String?);
          if (otherTxId == null) {
            return Scaffold(
                body: Center(child: Text(loc.noTransactions)));
          }

          final iAmRequester = (myData['exchangeRequestedBy'] == currentUserId);
          final myType = (myData['type'] as String?) ?? '';
          final iAmDeposit = myType == 'Deposit';
          final status = (myData['status'] as String?) ?? 'pending';

          // If accepted, allow leaving and show details
          if (status == 'accepted' || status == 'completed') {
            _canLeave = true;
            _ticker.stop();
          }

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('transactions')
                .doc(otherTxId)
                .snapshots(),
            builder: (context, otherTxSnap) {
              if (!otherTxSnap.hasData) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              final otherTxDoc = otherTxSnap.data!;
              final otherTxData =
                  otherTxDoc.data() as Map<String, dynamic>?;

              if (otherTxData == null) {
                return Scaffold(
                    body: Center(child: Text(loc.noTransactions)));
              }

              final otherUserId = otherTxData['userId'] as String;
              final otherSharedLocation =
                  otherTxData['sharedLocation'] as Map<String, dynamic>?;

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherUserId)
                    .get(),
                builder: (context, otherUserSnap) {
                  if (!otherUserSnap.hasData) {
                    return const Scaffold(
                        body: Center(child: CircularProgressIndicator()));
                  }
                  final otherUserDoc = otherUserSnap.data!;
                  final otherUser =
                      otherUserDoc.data() as Map<String, dynamic>? ?? {};

                  return Scaffold(
                    appBar: AppBar(
                      title: Text(loc.agreementTitle),
                      backgroundColor: Colors.blueGrey[800],
                      automaticallyImplyLeading: false,
                    ),
                    body: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blueGrey.shade50, Colors.white],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Professional timer bar
                            Row(
                              children: [
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: _remainingSeconds / 60,
                                    backgroundColor: Colors.grey[300],
                                    color: _remainingSeconds > 10 ? Colors.green : Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  "${_remainingSeconds}s",
                                  style: TextStyle(
                                    color: _remainingSeconds > 10 ? Colors.black : Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const SizedBox(height: 16),
                            Card(
                              color: Colors.red[50],
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning,
                                        color: Colors.red, size: 28),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        loc.meetingWarning,
                                        style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Show details if accepted (for receiver)
                            if (status == 'accepted' || status == 'completed')
                              _detailsCard(otherUser, otherSharedLocation, loc),

                            // Show waiting/accept/reject UI if not accepted
                            if (status == 'requested' && iAmRequester) ...[
                              _infoCard(
                                icon: Icons.hourglass_top,
                                title: loc.waitingForOther,
                                subtitle:
                                    '${loc.name}: ${otherUser['name'] ?? 'Unknown'}',
                              ),
                            ] else if (status == 'requested' &&
                                !iAmRequester) ...[
                              _actionCard(
                                name: otherUser['name'] ?? 'Unknown',
                                onAccept: () =>
                                    _acceptRequest(myTxId, otherTxId),
                                onDecline: () =>
                                    _declineRequest(myTxId, otherTxId),
                                busy: _busy,
                                loc: loc,
                              ),
                            ],

                            const Spacer(),
                            // Add cancel button at the bottom always
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.cancel),
                                  label: const Text("Cancel Request"),
                                  onPressed: _busy
                                      ? null
                                      : () => _cancelTransaction(myTxId, otherTxId),
                                ),
                              ),
                            ),
                            if (status == 'accepted')
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: Colors.green[700],
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.check_circle),
                                onPressed: _busy
                                    ? null
                                    : () => _confirmStep(
                                          myTxId: myTxId,
                                          otherTxId: otherTxId,
                                          iAmDeposit: iAmDeposit,
                                        ),
                                label: Text(iAmDeposit
                                    ? loc.instapayTransferred
                                    : loc.cashReceived),
                              ),
                            if (status == 'completed')
                              Center(
                                child: Text(
                                  loc.exchangeCompleted,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green),
                                ),
                              )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _infoCard({required IconData icon, required String title, String? subtitle}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.blueGrey, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null ? Text(subtitle) : null,
      ),
    );
  }

  Widget _actionCard({
    required String name,
    required VoidCallback onAccept,
    required VoidCallback onDecline,
    required bool busy,
    required AppLocalizations loc,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${loc.exchangeRequestFrom} $name',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onDecline,
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: Text(loc.reject),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                    ),
                    onPressed: busy ? null : onAccept,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: Text(loc.accept),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _detailsCard(Map<String, dynamic> otherUser, Map<String, dynamic>? otherLocation, AppLocalizations loc) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.counterpartyDetails,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blueGrey)),
            const SizedBox(height: 8),
            Text('${loc.name}: ${otherUser['name'] ?? '-'}'),
            Text('${loc.gender}: ${otherUser['gender'] ?? '-'}'),
            Text('${loc.phone}: ${otherUser['phone'] ?? '-'}'),
            Text('${loc.rating}: ${otherUser['rating'] ?? '-'}'),
            const Divider(),
            if (otherLocation != null)
              Text('${loc.locationShared} (Lat: ${otherLocation['lat']}, Lng: ${otherLocation['lng']})')
            else
              Text(loc.locationNotShared),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _sharingLocation ? null : () => _shareMyLocation(otherUser['id']),
              icon: const Icon(Icons.location_on, color: Colors.blueGrey),
              label: _sharingLocation
                  ? Text(loc.sharing)
                  : Text(loc.sendMyLocation),
            )
          ],
        ),
      ),
    );
  }

  // Add this method to fix the error
  Future<bool> _onWillPop() async {
    // Prevent leaving unless cancelled, accepted, or timeout
    return _canLeave;
  }

  // Define the cancel transaction method
  Future<void> _cancelTransaction(String myTxId, String otherTxId) async {
    setState(() => _busy = true);
    await _setBothTxFields(
      myTxId: myTxId,
      otherTxId: otherTxId,
      data: {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      },
    );
    setState(() => _busy = false);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

// Helper ticker for countdown
class Ticker {
  final void Function(Duration) onTick;
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
    Duration elapsed = Duration.zero;
    while (_running && elapsed.inSeconds < 61) {
      await Future.delayed(const Duration(seconds: 1));
      if (_running) {
        elapsed += const Duration(seconds: 1);
        onTick(elapsed);
      }
    }
  }

  void dispose() {
    _running = false;
  }
}
