import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:cashlink/l10n/app_localizations.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _selectedIndex = 2; // History tab

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else if (index == 1) {
      Navigator.of(context).pushReplacementNamed('/profile');
    } else if (index == 2) {
      // Already on History
    } else if (index == 3) {
      Navigator.of(context).pushReplacementNamed('/settings');
    }
  }

  Future<Map<String, dynamic>?> _getOtherUserData(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  double _distance(lat1, lon1, lat2, lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) *
            cos(lat2 * p) *
            (1 - cos((lon2 - lon1) * p)) /
            2;
    return 12742 * asin(sqrt(a)); // Distance in km
  }

  Color _cardColorByStatus(String status) {
    switch (status) {
      case 'accepted':
        return Colors.green[100]!;
      case 'pending':
        return Colors.yellow[100]!;
      case 'rejected':
        return Colors.red[100]!;
      case 'canceled':
        return Colors.grey[300]!;
      case 'requested':
        return Colors.orange[100]!;
      case 'completed':
        return Colors.blue[50]!;
      default:
        return Colors.white;
    }
  }

  void _showTransactionDetails(Map<String, dynamic> data) async {
    final loc = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser!;
    final otherUID = data['exchangeRequestedBy'] != null &&
            data['exchangeRequestedBy'] != user.uid
        ? data['exchangeRequestedBy']
        : null;

    Map<String, dynamic>? otherUser;
    if (otherUID != null) {
      otherUser = await _getOtherUserData(otherUID);
    }

    final distance = (data['location'] != null && otherUser != null)
        ? _distance(
            data['location']['lat'],
            data['location']['lng'],
            data['location']['lat'],
            data['location']['lng'])
        : 0.0;

    // If accepted, always show details and history
    if (data['status'] == 'accepted' || data['status'] == 'completed') {
      // Fetch rating if exists
      double? myRating;
      if (data['partnerTxId'] != null) {
        final ratingSnap = await FirebaseFirestore.instance
            .collection('ratings')
            .where('raterId', isEqualTo: user.uid)
            .where('ratedUserId', isEqualTo: otherUID)
            .limit(1)
            .get();
        if (ratingSnap.docs.isNotEmpty) {
          myRating = ratingSnap.docs.first['stars']?.toDouble();
        }
      }

      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.white, Colors.blueGrey],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${_localizedType(data['type'], loc)} ${loc.details}",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 15),
                  if (otherUser != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow(loc.name, otherUser['name']?.split(' ').first ?? 'Unknown'),
                        _divider(),
                        _infoRow(loc.gender, otherUser['gender'] ?? 'Unknown'),
                        _divider(),
                        _infoRow(loc.amount, "\$${(data['amount'] ?? 0.0).toStringAsFixed(2)}"),
                        _divider(),
                        _infoRow(loc.distance, "~${distance.toStringAsFixed(2)} km"),
                        _divider(),
                        if (data['status'] == 'accepted' || data['status'] == 'completed')
                          _infoRow(loc.rating, myRating != null ? myRating.toString() : loc.noTransactions),
                        if (data['status'] == 'accepted' || data['status'] == 'completed')
                          _divider(),
                        if (data['sharedLocation'] != null)
                          _infoRow(loc.locationShared, "Lat: ${data['sharedLocation']['lat']}, Lng: ${data['sharedLocation']['lng']}"),
                      ],
                    ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(loc.close, style: const TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    // ...existing code for other statuses...
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Colors.blueGrey],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "${_localizedType(data['type'], loc)} ${loc.details}",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 15),
              if (otherUser != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(loc.name, otherUser['name']?.split(' ').first ?? 'Unknown'),
                    _divider(),
                    _infoRow(loc.gender, otherUser['gender'] ?? 'Unknown'),
                    _divider(),
                    _infoRow(loc.amount, "\$${(data['amount'] ?? 0.0).toStringAsFixed(2)}"),
                    _divider(),
                    _infoRow(loc.distance, "~${distance.toStringAsFixed(2)} km"),
                    _divider(),
                  ],
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (data['status'] == 'requested' && otherUID != null) ...[
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('transactions')
                            .doc(data['id'])
                            .update({'status': 'accepted'});
                        if (!mounted) return;
                        Navigator.of(context).pop();
                        Navigator.of(context)
                            .pushNamed('/agreement', arguments: {
                          'myTxId': data['id'],
                          'otherTxId': data['partnerTxId'],
                        });
                      },
                      child: Text(loc.accept, style: const TextStyle(fontSize: 16)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('transactions')
                            .doc(data['id'])
                            .update({'status': 'rejected'});
                        if (!mounted) return;
                        Navigator.of(context).pop();
                      },
                      child: Text(loc.reject, style: const TextStyle(fontSize: 16)),
                    ),
                  ] else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(loc.close, style: const TextStyle(fontSize: 16)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "$title:",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return const Divider(color: Colors.black26, thickness: 1, height: 10);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      appBar: AppBar(title: Text(loc.transactionHistory)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('userId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(child: Text(loc.noTransactions));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              data['id'] = doc.id;

              final type = data['type'] ?? '';
              final amount = data['amount'] ?? 0.0;
              final status = data['status'] ?? 'pending';

              final isRequestedByOther = status == 'requested' &&
                  data['exchangeRequestedBy'] != null &&
                  data['exchangeRequestedBy'] != user.uid;

              return Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: status == 'pending'
                      ? () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(loc.cancel),
                              content: Text("${loc.cancel} this pending transaction?"),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(loc.close)),
                                TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(loc.cancel)),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await FirebaseFirestore.instance.collection('transactions').doc(doc.id).update({'status': 'canceled'});
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${loc.canceled}!')));
                          }
                        }
                      : () => _showTransactionDetails(data),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: type == 'Deposit' ? Colors.green.shade600 : Colors.red.shade600,
                          child: Icon(
                            type == 'Deposit' ? Icons.arrow_downward : Icons.arrow_upward,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _localizedType(type, loc),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${loc.amount}: \$${(amount as num).toStringAsFixed(2)} • ${loc.status}: ${_localizedStatus(status, loc)}",
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _cardColorByStatus(status),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                "\$${(amount as num).toStringAsFixed(0)}",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Chip(
                              label: Text(_localizedStatus(status, loc)),
                              backgroundColor: Colors.grey[100],
                              visualDensity: VisualDensity.compact,
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFE53935),
        unselectedItemColor: Colors.grey,
        onTap: _onNavTap,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: loc.home),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: loc.profile),
          BottomNavigationBarItem(icon: const Icon(Icons.history), label: loc.history),
          BottomNavigationBarItem(icon: const Icon(Icons.settings), label: loc.settings),
        ],
      ),
    );
  }

  // Helper to localize transaction type
  String _localizedType(String? type, AppLocalizations loc) {
    switch (type) {
      case 'Deposit':
        return loc.deposit;
      case 'Withdraw':
        return loc.withdraw;
      default:
        return type ?? '';
    }
  }

  // Helper to localize transaction status
  String _localizedStatus(String? status, AppLocalizations loc) {
    switch (status) {
      case 'pending':
        return loc.pending;
      case 'accepted':
        return loc.accepted;
      case 'rejected':
        return loc.rejected;
      case 'canceled':
        return loc.canceled;
      case 'requested':
        return loc.requested;
      default:
        return status ?? '';
    }
  }
}
