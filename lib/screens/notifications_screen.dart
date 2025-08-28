import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  Future<void> _respondToRequest(String txId, String otherUserId, bool accept) async {
    final myId = FirebaseAuth.instance.currentUser!.uid;
    final txRef = FirebaseFirestore.instance.collection('transactions').doc(txId);
    final tx = await txRef.get();

    if (accept) {
      await txRef.update({'status': 'accepted'});
      // الطرفين يروحوا على صفحة Agreement
      // ممكن تعمل Navigator.pushNamed('/agreement', ...)
    } else {
      await txRef.update({'status': 'rejected'});
    }

    // علشان نخفي الإشعار
    final notifs = await FirebaseFirestore.instance
        .collection('notifications')
        .where('txId', isEqualTo: txId)
        .where('toUserId', isEqualTo: myId)
        .get();
    for (var doc in notifs.docs) {
      await doc.reference.update({'seen': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('toUserId', isEqualTo: myId)
            .where('seen', isEqualTo: false)
            .snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (snap.data!.docs.isEmpty) return const Center(child: Text("No notifications"));

          return ListView(
            children: snap.data!.docs.map((notif) {
              final data = notif.data() as Map<String, dynamic>;
              return Card(
                child: ListTile(
                  title: const Text("New Exchange Request"),
                  subtitle: Text("From user: ${data['fromUserId']}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () => _respondToRequest(data['txId'], data['fromUserId'], true),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => _respondToRequest(data['txId'], data['fromUserId'], false),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
