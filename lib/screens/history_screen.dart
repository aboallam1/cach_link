import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  void _showTransactionDetails(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser!;
    final otherUID = data['fromUID'] == user.uid ? data['toUID'] : data['fromUID'];
    Map<String, dynamic>? otherUser;
    if (otherUID != null) {
      otherUser = await _getOtherUserData(otherUID);
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("${data['type']} Details"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Amount: \$${(data['amount'] ?? 0.0).toStringAsFixed(2)}"),
            Text("Status: ${data['status'] ?? 'pending'}"),
            if (otherUser != null) ...[
              const SizedBox(height: 8),
              Text("Other User: ${otherUser['name'] ?? 'Unknown'}"),
              Text("Phone: ${otherUser['phone'] ?? ''}"),
              Text("Gender: ${otherUser['gender'] ?? ''}"),
              if (data['feedback'] != null)
                Text("Feedback: ${data['feedback']}"),
            ],
            if (data['location'] != null)
              Text(
                  "Location: (${data['location']['lat']}, ${data['location']['lng']})"),
            if (data['createdAt'] != null)
              Text(
                  "Date: ${(data['createdAt'] as Timestamp).toDate()}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Close"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      appBar: AppBar(title: const Text("Transaction History")),
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
            return const Center(child: Text("No transactions yet."));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final type = data['type'] ?? '';
              final amount = data['amount'] ?? 0.0;
              final status = data['status'] ?? 'pending';

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        type == 'Deposit' ? Colors.green : Colors.red,
                    child: Icon(
                      type == 'Deposit'
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    "$type - \$${amount.toStringAsFixed(2)}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text("Status: $status"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showTransactionDetails(data),
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
