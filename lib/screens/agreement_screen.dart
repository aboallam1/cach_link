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
  late final AgreementTicker _ticker; // Use the renamed ticker class
  bool _canLeave = false;
  bool _showCancel = true;
  bool _navigatedToRating = false; // prevent duplicate navigation

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _ticker = AgreementTicker(_onTick)..start(); // Use renamed ticker
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

    // set this user's confirmation flag
    await FirebaseFirestore.instance
        .collection('transactions')
        .doc(myTxId)
        .update({myFlag: true});

    // fetch fresh snapshots once
    final mySnap = await FirebaseFirestore.instance.collection('transactions').doc(myTxId).get();
    final otherSnap = await FirebaseFirestore.instance.collection('transactions').doc(otherTxId).get();

    final myData = mySnap.data() as Map<String, dynamic>? ?? {};
    final otherData = otherSnap.data() as Map<String, dynamic>? ?? {};

    final instapayConfirmed =
        (myData['instapayConfirmed'] == true) &&
        (otherData['instapayConfirmed'] == true);
    final cashConfirmed =
        (myData['cashConfirmed'] == true) &&
        (otherData['cashConfirmed'] == true);

    if (instapayConfirmed && cashConfirmed) {
      // both sides confirmed -> mark completed for both tx docs
      await _setBothTxFields(
        myTxId: myTxId,
        otherTxId: otherTxId,
        data: {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp()
        },
      );

      // navigate current user immediately to rating
      final otherUserId = otherData['userId'] as String?;
      if (mounted) {
        _navigatedToRating = true;
        if (otherUserId != null) {
          Navigator.of(context).pushReplacementNamed('/rating', arguments: {
            'otherUserId': otherUserId,
          });
        } else {
          // fallback: try to read partner tx userId
          final partnerSnap = await FirebaseFirestore.instance.collection('transactions').doc(otherTxId).get();
          final partnerUserId = (partnerSnap.data() as Map<String, dynamic>?)?['userId'] as String?;
          if (partnerUserId != null) {
            Navigator.of(context).pushReplacementNamed('/rating', arguments: {
              'otherUserId': partnerUserId,
            });
          }
        }
      }
    } else {
      // keep the button disabled for this user until other confirms
      if (mounted) setState(() => _busy = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(iAmDeposit
                ? 'Waiting for cash confirmation from the other party.'
                : 'Waiting for Instapay confirmation from the other party.'),
          ),
        );
      }
    }
    // do not re-enable _busy here; navigation or stream update will change UI
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
          // If transaction already completed, navigate to rating once
          if (myData['status'] == 'completed' && !_navigatedToRating) {
            // set guard early to avoid duplicate navigations
            _navigatedToRating = true;
            Future.microtask(() async {
              String? partnerTxId;
              try {
                partnerTxId = (myData['partnerTxId'] != null && myData['partnerTxId'] is String)
                    ? myData['partnerTxId'] as String
                    : null;
              } catch (_) {
                partnerTxId = null;
              }

              String? otherUserId;
              if (partnerTxId != null && partnerTxId.isNotEmpty) {
                try {
                  final partnerSnap = await FirebaseFirestore.instance
                      .collection('transactions')
                      .doc(partnerTxId)
                      .get();
                  otherUserId = (partnerSnap.data() as Map<String, dynamic>?)?['userId'] as String?;
                } catch (_) {
                  otherUserId = null;
                }
              }

              // fallback: try argument otherTxIdArg
              if (otherUserId == null && otherTxIdArg != null && otherTxIdArg is String) {
                try {
                  final otherSnap = await FirebaseFirestore.instance
                      .collection('transactions')
                      .doc(otherTxIdArg)
                      .get();
                  otherUserId = (otherSnap.data() as Map<String, dynamic>?)?['userId'] as String?;
                } catch (_) {
                  otherUserId = null;
                }
              }

              if (otherUserId != null && mounted) {
                Navigator.of(context).pushReplacementNamed('/rating', arguments: {'otherUserId': otherUserId});
              } else {
                // If we couldn't resolve partner user id, still pop to matches to avoid blocking UI
                if (mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  Navigator.of(context).pushReplacementNamed('/match');
                }
              }
            });
          }
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

          // Listen to changes in the other transaction to update details live
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
              final otherTxData = otherTxDoc.data() as Map<String, dynamic>?;

              // Define otherStatus here so it's in scope for the UI logic below
              final otherStatus = (otherTxData?['status'] as String?) ?? 'pending';
              final otherUserId = otherTxData?['userId'] as String?;
              final otherSharedLocation = otherTxData?['sharedLocation'] as Map<String, dynamic>?;

              // Stop timer for both users when either transaction is accepted or completed
              if ((status == 'accepted' || status == 'completed' ||
                   otherStatus == 'accepted' || otherStatus == 'completed') && _ticker._running) {
                _ticker.stop();
              }

              // Fetch receiver details live
              return StreamBuilder<DocumentSnapshot>(
                stream: otherUserId != null
                    ? FirebaseFirestore.instance.collection('users').doc(otherUserId).snapshots()
                    : null,
                builder: (context, otherUserSnap) {
                  if (!otherUserSnap.hasData) {
                    return const Scaffold(
                        body: Center(child: CircularProgressIndicator()));
                  }
                  final otherUserDoc = otherUserSnap.data!;
                  final otherUser = otherUserDoc.data() as Map<String, dynamic>? ?? {};

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
                            // Show timer bar only for requester
                            if (iAmRequester)
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
                            if (iAmRequester)
                              const SizedBox(height: 12),
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

                            // Show details if accepted or completed
                            if ((status == 'accepted' || status == 'completed' ||
                                 otherStatus == 'accepted' || otherStatus == 'completed') && otherUser.isNotEmpty)
                              ...[
                                _detailsCard(otherUser, otherSharedLocation, loc),
                                if (iAmRequester)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: Icon(
                                          iAmDeposit ? Icons.send : Icons.attach_money,
                                          color: Colors.white,
                                        ),
                                        label: Text(
                                          iAmDeposit
                                              ? loc.confirmCashReceived
                                              : loc.confirmInstapayTransfer,
                                              
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green[700],
                                          minimumSize: const Size.fromHeight(48),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        onPressed: _busy
                                            ? null
                                            : () => _confirmStep(
                                                  myTxId: myTxId,
                                                  otherTxId: otherTxId,
                                                  iAmDeposit: iAmDeposit,
                                                ),
                                      ),
                                    ),
                                  ),
                              ],

                            // Accept / Decline flow
                            if (status == 'requested' && otherStatus != 'accepted' && iAmRequester) ...[
                              _infoCard(
                                icon: Icons.hourglass_top,
                                title: loc.waitingForOther,
                                subtitle:
                                    '${loc.name}: ${otherUser['name'] ?? 'Unknown'}',
                              ),
                              const Spacer(),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.cancel, color: Colors.red),
                                    label: Text(loc.cancel),
                                    onPressed: _busy
                                        ? null
                                        : () => _cancelTransaction(myTxId, otherTxId),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      minimumSize: const Size.fromHeight(48),
                                      side: const BorderSide(color: Colors.red),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            // Confirmation buttons for receiver (not requester)
                            if ((status == 'accepted' || status == 'completed') && !iAmRequester) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: Icon(
                                      otherTxData?['type'] == 'Deposit'
                                          ? Icons.send
                                          : Icons.attach_money,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      otherTxData?['type'] == 'Deposit'
                                          ? loc.confirmTransfer
                                          : loc.confirmCashReceived,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green[700],
                                      minimumSize: const Size.fromHeight(48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => _confirmStep(
                                              myTxId: myTxId,
                                              otherTxId: otherTxId,
                                              iAmDeposit: otherTxData?['type'] == 'Deposit',
                                            ),
                                  ),
                                ),
                              ),
                            ],

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

  Widget _detailsCard(Map<String, dynamic> otherUser, Map<String, dynamic>? otherLocation, AppLocalizations loc) {
    String? googleMapsUrl;
    if (otherLocation != null &&
        otherLocation['lat'] != null &&
        otherLocation['lng'] != null) {
      final lat = otherLocation['lat'];
      final lng = otherLocation['lng'];
      if (lat != null && lng != null) {
        googleMapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      }
    }
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (otherLocation['lat'] != null && otherLocation['lng'] != null)
                        ? '${loc.locationShared} (Lat: ${otherLocation['lat']}, Lng: ${otherLocation['lng']})'
                        : loc.locationNotShared
                    ),
                  ),
                  if (googleMapsUrl != null)
                    IconButton(
                      icon: const Icon(Icons.map, color: Colors.blue),
                      tooltip: 'Open in Maps',
                      onPressed: () {
                        if (googleMapsUrl != null && googleMapsUrl.isNotEmpty) {
                          print('Open maps: $googleMapsUrl');
                        }
                      },
                    ),
                ],
              )
              
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

  Future<bool> _onWillPop() async {
    return _canLeave;
  }

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

class AgreementTicker {
  final void Function(Duration) onTick;
  bool _running = false;

  AgreementTicker(this.onTick);

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