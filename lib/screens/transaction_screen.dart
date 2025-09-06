import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'package:cashlink/l10n/app_localizations.dart';
import 'dart:math'; // Ensure this is present
import 'package:flutter/services.dart';

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

  // Transaction fee constant
  static const double TRANSACTION_FEE = 0.003;

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

  // Check wallet balance with calculated fee
  Future<bool> _checkWalletBalance() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      // Calculate the actual fee based on amount
      final amountText = _amountController.text.trim();
      if (amountText.isEmpty) return false;
      
      final amount = double.tryParse(amountText);
      if (amount == null || amount <= 0) return false;
      
      final requiredFee = amount * TRANSACTION_FEE; // fee = amount * 0.003

      final walletDoc = await FirebaseFirestore.instance
          .collection('wallets')
          .doc(user.uid)
          .get();

      final double balance = walletDoc.exists ? 
          (walletDoc.data()?['balance'] ?? 0.0).toDouble() : 0.0;

      return balance >= requiredFee;
    } catch (e) {
      print('Error checking wallet balance: $e');
      return false;
    }
  }

  void _showInsufficientBalanceDialog() {
    final loc = AppLocalizations.of(context)!;
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText) ?? 0.0;
    final requiredFee = amount * TRANSACTION_FEE;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 8),
            Text(loc.insufficientBalance),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You need at least ${requiredFee.toStringAsFixed(3)} EGP in your wallet for this ${amount.toStringAsFixed(2)} EGP transaction.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Text(
              'Transaction fee: 0.3% of ${amount.toStringAsFixed(2)} EGP = ${requiredFee.toStringAsFixed(3)} EGP',
              style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              loc.feeDeductedWhenCompleted,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(loc.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/wallet');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: Text(loc.goToWallet),
          ),
        ],
      ),
    );
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
        const SnackBar(content: Text("You already have an active request. Cancel it first.")),
      );
      return;
    }

    // Check wallet balance before proceeding
    setState(() => _loading = true);
    
    final hasSufficientBalance = await _checkWalletBalance();
    if (!hasSufficientBalance) {
      setState(() => _loading = false);
      _showInsufficientBalanceDialog();
      return;
    }

    final user = FirebaseAuth.instance.currentUser!;
    final amount = double.parse(_amountController.text);
    final fee = amount * TRANSACTION_FEE; // Calculate fee as amount * 0.003

    // Record transaction in Firestore with calculated fee
    await FirebaseFirestore.instance.collection('transactions').add({
      'userId': user.uid,
      'type': _type,
      'amount': amount,
      'fee': fee, // Store the calculated fee
      'location': {
        'lat': _location!.latitude,
        'lng': _location!.longitude,
      },
      'status': 'pending',
      'exchangeRequestedBy': null,
      'instapayConfirmed': false,
      'cashConfirmed': false,
      'feeDeducted': false,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () => Navigator.of(context).pushNamed('/wallet'),
            tooltip: 'Wallet',
          ),
        ],
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
            
            // Fee information
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Transaction fee: 0.3% of transaction amount will be deducted from your wallet when both parties accept.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
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
