import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int _stars = 5;
  bool _loading = false;
  final TextEditingController _commentController = TextEditingController();

  Future<void> _submit(String otherUserId) async {
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection('ratings').add({
      'raterId': user.uid,
      'ratedUserId': otherUserId,
      'stars': _stars,
      'comment': _commentController.text.trim(),
    });
    // Update average rating
    final ratings = await FirebaseFirestore.instance
        .collection('ratings')
        .where('ratedUserId', isEqualTo: otherUserId)
        .get();
    double avg = ratings.docs.fold<num>(0, (sum, doc) => sum + doc['stars']) / ratings.docs.length;
    await FirebaseFirestore.instance.collection('users').doc(otherUserId).update({'rating': avg});
    setState(() => _loading = false);
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    final otherUserId = args?['otherUserId'];
    return Scaffold(
      appBar: AppBar(title: Text(loc.rateUser)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(loc.rateUserTransactionPartner ?? 'Rate your transaction partner:'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => IconButton(
                icon: Icon(
                  i < _stars ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                onPressed: () => setState(() => _stars = i + 1),
              )),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              decoration: InputDecoration(
                labelText: loc.commentOptional ?? 'Comment (optional)',
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: () => _submit(otherUserId),
                    child: Text(loc.submitRating ?? 'Submit Rating'),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
}
