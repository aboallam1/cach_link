import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'package:cashlink/l10n/app_localizations.dart';
import 'dart:math'; // Ensure this is present

class TransactionScreen extends StatefulWidget {
  const TransactionScreen({super.key});

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  String? _type;
  final _amountController = TextEditingController();
  LocationData? _location;
  bool _loading = false;

  bool hasActiveRequest = false;
  int searchRadius = 10;
  bool searching = false;
  bool noCandidates = false;
  List<DocumentSnapshot> candidates = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['transactionType'] is String) {
      _type = args['transactionType'];
    }
  }

  Future<void> _getLocation() async {
    final loc = Location();
    final data = await loc.getLocation();
    setState(() => _location = data);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.locationSharedMessage)),
    );
  }

  Future<void> _checkActiveRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    setState(() {
      hasActiveRequest = userDoc.data()?['hasActiveRequest'] == true;
    });
  }

  double _distance(lat1, lon1, lat2, lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
            (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742.0 * asin(sqrt(a));
  }

  Future<List<DocumentSnapshot>> _findCandidates() async {
    final user = FirebaseAuth.instance.currentUser!;
    final oppType = _type == 'Deposit' ? 'Withdraw' : 'Deposit';
    final txSnap = await FirebaseFirestore.instance
        .collection('transactions')
        .where('type', isEqualTo: oppType)
        .where('status', isEqualTo: 'pending')
        .get();

    List<DocumentSnapshot> found = [];
    for (var doc in txSnap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null ||
          !data.containsKey('amount') ||
          !data.containsKey('location') ||
          !data.containsKey('userId')) continue;
      if (data['userId'] == user.uid) continue;
      final loc = data['location'];
      final d = _distance(_location!.latitude, _location!.longitude, loc['lat'], loc['lng']);
      if (d <= searchRadius) {
        found.add(doc);
      }
    }
    return found;
  }

  @override
  void dispose() {
    // Clean up controllers and prevent setState after dispose
    _amountController.dispose();
    super.dispose();
  }

  Future<void> searchAndShowCandidates() async {
    final user = FirebaseAuth.instance.currentUser!;
    final amount = double.parse(_amountController.text);

    List<DocumentSnapshot> found = await _findCandidates();

    // Find closest by GPS
    DocumentSnapshot? closestByGps;
    double minDist = double.infinity;
    for (var doc in found) {
      final data = doc.data() as Map<String, dynamic>;
      final loc = data['location'];
      final d = _distance(_location!.latitude, _location!.longitude, loc['lat'], loc['lng']);
      if (d < minDist) {
        minDist = d;
        closestByGps = doc;
      }
    }

    // Find closest by amount
    DocumentSnapshot? closestByAmount;
    double minAmountDiff = double.infinity;
    for (var doc in found) {
      final data = doc.data() as Map<String, dynamic>;
      final amt = data['amount'];
      final diff = (amt - amount).abs();
      if (diff < minAmountDiff) {
        minAmountDiff = diff;
        closestByAmount = doc;
      }
    }

    // If both are the same, suggest only one
    List<DocumentSnapshot> matches = [];
    if (closestByGps != null && closestByGps.id == closestByAmount?.id) {
      matches = [closestByGps];
    } else {
      if (closestByGps != null) matches.add(closestByGps);
      if (closestByAmount != null && closestByAmount.id != closestByGps?.id) matches.add(closestByAmount);
    }

    if (!mounted) return;
    setState(() {
      candidates = matches;
      _loading = false;
      searching = false;
      noCandidates = matches.isEmpty;
    });

    if (matches.isNotEmpty) {
      if (!mounted) return;
      Navigator.of(context).pushNamed('/match', arguments: {
        'type': _type,
        'amount': _amountController.text,
        'location': {
          'lat': _location!.latitude,
          'lng': _location!.longitude,
        },
      });
    } else {
      if (searchRadius >= 50) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.findMatch),
            content: const Text("Sorry, no users available at the moment."),
            actions: [
              TextButton(
                onPressed: () {
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  Navigator.of(context).pushReplacementNamed('/home');
                },
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  final user = FirebaseAuth.instance.currentUser!;
                  await FirebaseFirestore.instance.collection('transactions').add({
                    'userId': user.uid,
                    'type': _type,
                    'amount': amount,
                    'location': {
                      'lat': _location!.latitude,
                      'lng': _location!.longitude,
                    },
                    'status': 'pending',
                    'exchangeRequestedBy': null,
                    'instapayConfirmed': false,
                    'cashConfirmed': false,
                    'createdAt': FieldValue.serverTimestamp(),
                    'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
                  });
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Your request was saved and will appear in your history.")),
                  );
                  Navigator.of(context).pushReplacementNamed('/history');
                },
                child: const Text("Save Transaction"),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _submit() async {
    final loc = AppLocalizations.of(context)!;
    if (_type == null || _amountController.text.isEmpty || _location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.locationNotShared)),
      );
      return;
    }
    if (hasActiveRequest) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You already have an active request. Cancel it first.")),
      );
      return;
    }

    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser!;

    // Record transaction in Firestore with radius 10km
    await FirebaseFirestore.instance.collection('transactions').add({
      'userId': user.uid,
      'type': _type,
      'amount': double.parse(_amountController.text),
      'location': {
        'lat': _location!.latitude,
        'lng': _location!.longitude,
      },
      'status': 'pending',
      'exchangeRequestedBy': null,
      'instapayConfirmed': false,
      'cashConfirmed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
      'searchRadius': 10,
    });

    setState(() => _loading = false);
    Navigator.of(context).pushReplacementNamed('/match', arguments: {
      'type': _type,
      'amount': _amountController.text,
      'location': {
        'lat': _location!.latitude,
        'lng': _location!.longitude,
      },
    });
  }

  Future<void> expandSearch() async {
    if (searchRadius < 50) {
      setState(() {
        searchRadius += 10;
        _loading = true;
        searching = true;
      });
      await searchAndShowCandidates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(loc.NewTransaction), // Use getter, not property with space
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text(
              loc.CreateTransaction, // Use getter, not property with space
              style: theme.textTheme.headlineSmall!.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.descriptionOfNewTransaction,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            // Card container
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _type,
                      items: [
                        DropdownMenuItem(
                          value: 'Deposit',
                          child: Row(
                            children: [
                              Icon(Icons.arrow_downward, color: Colors.green),
                              const SizedBox(width: 8),
                              Text(loc.deposit),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Withdraw',
                          child: Row(
                            children: [
                              Icon(Icons.arrow_upward, color: Colors.red),
                              const SizedBox(width: 8),
                              Text(loc.withdraw),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _type = v),
                      decoration: InputDecoration(
                        labelText: loc.transactionType, // Or add a new key for "Transaction Type"
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.swap_horiz),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: loc.amount,
                        prefixIcon: const Icon(Icons.attach_money),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _getLocation,
                      icon: const Icon(Icons.location_on),
                      label: Text(
                        _location == null
                            ? (loc.locationShared ?? "Set Location")
                            : (loc.locationSharedMessage ?? "Location Selected"),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Submit button
            _loading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.search),
                    label: Text(
                      loc.findMatch, // Or add a new key for "Find Match"
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
