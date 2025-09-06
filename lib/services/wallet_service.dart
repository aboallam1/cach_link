import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WalletService {
  static const double TRANSACTION_FEE = 0.003;
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get user wallet balance stream
  Stream<double> getWalletBalanceStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0.0);

    return _firestore
        .collection('wallets')
        .doc(user.uid)
        .snapshots()
        .map((doc) => doc.exists ? (doc.data()?['balance'] ?? 0.0).toDouble() : 0.0);
  }

  // Get current wallet balance
  Future<double> getCurrentBalance() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0.0;

    final doc = await _firestore.collection('wallets').doc(user.uid).get();
    return doc.exists ? (doc.data()?['balance'] ?? 0.0).toDouble() : 0.0;
  }

  // Check if user has sufficient balance for fee
  Future<bool> hasSufficientBalance() async {
    final balance = await getCurrentBalance();
    return balance >= TRANSACTION_FEE;
  }

  // Get wallet transaction history
  Stream<List<WalletTransaction>> getWalletTransactionsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('wallet_transactions')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => WalletTransaction.fromFirestore(doc))
            .toList());
  }

  // Process wallet deposit (simulate payment gateway success)
  Future<bool> processDeposit({
    required double amount,
    required String paymentReference,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      await _firestore.runTransaction((transaction) async {
        final walletRef = _firestore.collection('wallets').doc(user.uid);
        final walletDoc = await transaction.get(walletRef);
        
        final currentBalance = walletDoc.exists 
            ? (walletDoc.data()?['balance'] ?? 0.0).toDouble() 
            : 0.0;
        
        final newBalance = currentBalance + amount;

        // Update wallet
        transaction.set(walletRef, {
          'balance': newBalance,
          'currency': 'EGP',
          'totalDeposited': FieldValue.increment(amount),
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Create transaction record with more details
        transaction.set(_firestore.collection('wallet_transactions').doc(), {
          'userId': user.uid,
          'type': 'deposit',
          'amount': amount,
          'description': 'Wallet recharge via payment gateway - ${amount.toStringAsFixed(2)} EGP',
          'paymentReference': paymentReference,
          'balanceBefore': currentBalance,
          'balanceAfter': newBalance,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'completed',
        });
      });

      return true;
    } catch (e) {
      print('Error processing deposit: $e');
      return false;
    }
  }

  // Process fee deduction with detailed transaction record
  Future<bool> deductFee({
    required double amount,
    required double feeRate,
    required String transactionId,
    required String description,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final fee = amount * feeRate;

    try {
      await _firestore.runTransaction((transaction) async {
        final walletRef = _firestore.collection('wallets').doc(user.uid);
        final walletDoc = await transaction.get(walletRef);
        
        if (!walletDoc.exists) {
          throw Exception('Wallet not found');
        }

        final currentBalance = (walletDoc.data()!['balance'] as num).toDouble();
        
        if (currentBalance < fee) {
          throw Exception('Insufficient balance for fee');
        }

        final newBalance = currentBalance - fee;

        // Update wallet
        transaction.update(walletRef, {
          'balance': newBalance,
          'totalSpent': FieldValue.increment(fee),
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        // Create detailed transaction record
        transaction.set(_firestore.collection('wallet_transactions').doc(), {
          'userId': user.uid,
          'type': 'fee_deduction',
          'amount': -fee,
          'description': description,
          'relatedTransactionId': transactionId,
          'balanceBefore': currentBalance,
          'balanceAfter': newBalance,
          'feeRate': feeRate,
          'originalAmount': amount,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'completed',
        });
      });

      return true;
    } catch (e) {
      print('Error deducting fee: $e');
      return false;
    }
  }
}

class WalletTransaction {
  final String id;
  final String userId;
  final String type;
  final double amount;
  final String description;
  final String? relatedTransactionId;
  final String? paymentReference;
  final double balanceBefore;
  final double balanceAfter;
  final DateTime createdAt;

  WalletTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.description,
    this.relatedTransactionId,
    this.paymentReference,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.createdAt,
  });

  factory WalletTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WalletTransaction(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: data['type'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      description: data['description'] ?? '',
      relatedTransactionId: data['relatedTransactionId'],
      paymentReference: data['paymentReference'],
      balanceBefore: (data['balanceBefore'] ?? 0.0).toDouble(),
      balanceAfter: (data['balanceAfter'] ?? 0.0).toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
