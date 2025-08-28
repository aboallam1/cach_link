import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';

class AgreementScreen extends StatefulWidget {
  const AgreementScreen({super.key});

  @override
  State<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends State<AgreementScreen> {
  bool _busy = false;
  bool _sharingLocation = false;

  Future<void> _setBothTxFields({
    required String myTxId,
    required String otherTxId,
    required Map<String, dynamic> data,
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    final myRef = FirebaseFirestore.instance.collection('transactions').doc(myTxId);
    final otherRef = FirebaseFirestore.instance.collection('transactions').doc(otherTxId);
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
    // ترجيع الحالتين لـ pending ومسح ربط الشريك إن وجد
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
    Navigator.pop(context); // ارجع لقائمة الماتشات
  }

  Future<void> _shareMyLocation(String myTxId) async {
    setState(() => _sharingLocation = true);
    final loc = Location();
    final permission = await loc.requestPermission();
    if (permission == PermissionStatus.denied || permission == PermissionStatus.deniedForever) {
      if (!mounted) return;
      setState(() => _sharingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied')),
      );
      return;
    }
    final data = await loc.getLocation();
    await FirebaseFirestore.instance.collection('transactions').doc(myTxId).update({
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

    // نحدد أي علم (flag) هنفعّله بناءً على نوعي أنا
    // لو أنا Deposit → أؤكد instapay
    // لو أنا Withdraw → أؤكد cash
    final myFlag = iAmDeposit ? 'instapayConfirmed' : 'cashConfirmed';

    // أولاً فعّل العلم على معاملتي
    await FirebaseFirestore.instance.collection('transactions').doc(myTxId).update({
      myFlag: true,
    });

    // اقرأ معاملات الطرفين عشان نتحقق هل الاتنين اتأكدوا
    final mySnap = await FirebaseFirestore.instance.collection('transactions').doc(myTxId).get();
    final otherSnap = await FirebaseFirestore.instance.collection('transactions').doc(otherTxId).get();

    final myData = mySnap.data() as Map<String, dynamic>;
    final otherData = otherSnap.data() as Map<String, dynamic>;

    final instapayConfirmed = (myData['instapayConfirmed'] == true) || (otherData['instapayConfirmed'] == true);
    final cashConfirmed = (myData['cashConfirmed'] == true) || (otherData['cashConfirmed'] == true);

    if (instapayConfirmed && cashConfirmed) {
      // كمّل العملية
      await _setBothTxFields(
        myTxId: myTxId,
        otherTxId: otherTxId,
        data: {'status': 'completed', 'completedAt': FieldValue.serverTimestamp()},
      );

      final otherUserId = otherData['userId'];
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/rating', arguments: {
        'otherUserId': otherUserId,
      });
    } else {
      // لسه ناقص خطوة الطرف الآخر
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
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    final myTxId = args?['myTxId'] as String?;
    final otherTxIdArg = args?['otherTxId'] as String?;

    if (myTxId == null) {
      return const Scaffold(body: Center(child: Text('Missing myTxId in arguments')));
    }

    final myTxStream = FirebaseFirestore.instance.collection('transactions').doc(myTxId).snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: myTxStream,
      builder: (context, mySnap) {
        if (!mySnap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final myDoc = mySnap.data!;
        if (!myDoc.exists) {
          return const Scaffold(body: Center(child: Text('Transaction not found')));
        }
        final myData = myDoc.data() as Map<String, dynamic>;
        final currentUserId = FirebaseAuth.instance.currentUser!.uid;

        // حاول استنتاج otherTxId لو مش جاي في args
        final otherTxId = otherTxIdArg ?? (myData['partnerTxId'] as String?);
        if (otherTxId == null) {
          return const Scaffold(body: Center(child: Text('Missing otherTxId (pass it in arguments or set partnerTxId)')));
        }

        final iAmRequester = (myData['exchangeRequestedBy'] == currentUserId);
        final myType = (myData['type'] as String?) ?? '';
        final iAmDeposit = myType == 'Deposit';
        final status = (myData['status'] as String?) ?? 'pending';

        // اقرأ معاملة الطرف الآخر + بياناته
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('transactions').doc(otherTxId).snapshots(),
          builder: (context, otherTxSnap) {
            if (!otherTxSnap.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final otherTxDoc = otherTxSnap.data!;
            final otherTxData = otherTxDoc.data() as Map<String, dynamic>?;

            if (otherTxData == null) {
              return const Scaffold(body: Center(child: Text('Other transaction not found')));
            }

            final otherUserId = otherTxData['userId'] as String;
            final otherSharedLocation = otherTxData['sharedLocation'] as Map<String, dynamic>?;

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
              builder: (context, otherUserSnap) {
                if (!otherUserSnap.hasData) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }
                final otherUserDoc = otherUserSnap.data!;
                final otherUser = otherUserDoc.data() as Map<String, dynamic>? ?? {};

                return Scaffold(
                  appBar: AppBar(title: const Text('Agreement')),
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚠️ Meet in a public place. Don’t hand over cash before confirming transfer.',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),

                        // حالة الطلب
                        if (status == 'requested' && iAmRequester) ...[
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.hourglass_top),
                              title: const Text('Waiting for the other party to accept your exchange request'),
                              subtitle: Text('Other user: ${otherUser['name'] ?? 'Unknown'}'),
                            ),
                          ),
                        ] else if (status == 'requested' && !iAmRequester) ...[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Exchange request from: ${otherUser['name'] ?? 'Unknown'}'),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _busy ? null : () => _declineRequest(myTxId, otherTxId),
                                          icon: const Icon(Icons.close),
                                          label: const Text('Decline'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: _busy ? null : () => _acceptRequest(myTxId, otherTxId),
                                          icon: const Icon(Icons.check),
                                          label: const Text('Accept'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // بعد القبول: عرض بيانات الطرف الآخر + مشاركة الموقع + زر التأكيد المناسب
                        if (status == 'accepted' || status == 'completed') ...[
                          Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Counterparty Details', style: TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text('Name: ${otherUser['name'] ?? '-'}'),
                                  Text('Gender: ${otherUser['gender'] ?? '-'}'),
                                  Text('Phone: ${otherUser['phone'] ?? '-'}'),
                                  Text('Rating: ${otherUser['rating'] ?? '-'}'),
                                  const SizedBox(height: 8),
                                  // موقع الطرف الآخر إن شاركه
                                  if (otherSharedLocation != null)
                                    Text('Their location shared ✓ (Lat: ${otherSharedLocation['lat']}, Lng: ${otherSharedLocation['lng']})')
                                  else
                                    const Text('Their location is not shared yet'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _sharingLocation ? null : () => _shareMyLocation(myTxId),
                                  icon: const Icon(Icons.location_on),
                                  label: _sharingLocation
                                      ? const Text('Sharing...')
                                      : const Text('Send My Location'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (status != 'completed')
                            ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _confirmStep(
                                        myTxId: myTxId,
                                        otherTxId: otherTxId,
                                        iAmDeposit: iAmDeposit,
                                      ),
                              child: Text(iAmDeposit ? 'Transferred via Instapay' : 'It was received'),
                            ),
                          if (status == 'completed') ...[
                            const SizedBox(height: 12),
                            const Center(child: Text('Exchange completed ✅')),
                          ],
                        ],

                        const Spacer(),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
