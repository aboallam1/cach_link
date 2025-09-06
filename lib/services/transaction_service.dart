import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TransactionService {
  static const double TRANSACTION_FEE_RATE = 0.003;
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Process fee deduction when transaction is accepted with retry logic
  static Future<void> processTransactionAcceptance(String transactionId, String partnerTransactionId) async {
    const maxRetries = 3;
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        await _attemptTransactionProcessing(transactionId, partnerTransactionId);
        print('Successfully processed transaction fees for $transactionId and $partnerTransactionId');
        return; // Success, exit retry loop
      } catch (e) {
        retryCount++;
        print('Attempt $retryCount failed: $e');
        if (retryCount >= maxRetries) {
          throw Exception('Failed to process transaction after $maxRetries attempts: $e');
        }
        // Wait before retrying with exponential backoff
        await Future.delayed(Duration(milliseconds: 100 * (1 << retryCount)));
      }
    }
  }

  static Future<void> _attemptTransactionProcessing(String transactionId, String partnerTransactionId) async {
    final firestore = FirebaseFirestore.instance;
    
    await firestore.runTransaction((transaction) async {
      print('Starting transaction processing for $transactionId and $partnerTransactionId');
      
      // Get both transactions with fresh data
      final txRef = firestore.collection('transactions').doc(transactionId);
      final partnerTxRef = firestore.collection('transactions').doc(partnerTransactionId);
      
      final txDoc = await transaction.get(txRef);
      final partnerTxDoc = await transaction.get(partnerTxRef);
      
      if (!txDoc.exists || !partnerTxDoc.exists) {
        throw Exception('Transaction not found');
      }
      
      final txData = txDoc.data()!;
      final partnerTxData = partnerTxDoc.data()!;
      
      print('Transaction statuses: ${txData['status']}, ${partnerTxData['status']}');
      
      // Calculate fees for both transactions
      final txAmount = (txData['amount'] as num).toDouble();
      final partnerAmount = (partnerTxData['amount'] as num).toDouble();
      final txFee = txAmount * TRANSACTION_FEE_RATE;
      final partnerFee = partnerAmount * TRANSACTION_FEE_RATE;
      
      print('Calculated fees: $txFee for tx, $partnerFee for partner');
      
      final userId = txData['userId'] as String;
      final partnerUserId = partnerTxData['userId'] as String;
      
      // Get wallet references
      final userWalletRef = firestore.collection('wallets').doc(userId);
      final partnerWalletRef = firestore.collection('wallets').doc(partnerUserId);
      
      final userWalletDoc = await transaction.get(userWalletRef);
      final partnerWalletDoc = await transaction.get(partnerWalletRef);
      
      if (!userWalletDoc.exists || !partnerWalletDoc.exists) {
        throw Exception('Wallet not found');
      }
      
      final userBalance = (userWalletDoc.data()!['balance'] as num).toDouble();
      final partnerBalance = (partnerWalletDoc.data()!['balance'] as num).toDouble();
      
      print('Current balances: user=$userBalance, partner=$partnerBalance');
      
      // Check if both users have sufficient balance
      if (userBalance < txFee) {
        throw Exception('Insufficient balance for user: required ${txFee.toStringAsFixed(3)}, available ${userBalance.toStringAsFixed(3)}');
      }
      
      if (partnerBalance < partnerFee) {
        throw Exception('Insufficient balance for partner: required ${partnerFee.toStringAsFixed(3)}, available ${partnerBalance.toStringAsFixed(3)}');
      }
      
      final now = FieldValue.serverTimestamp();
      
      // Update wallets with fee deductions
      transaction.update(userWalletRef, {
        'balance': userBalance - txFee,
        'totalSpent': FieldValue.increment(txFee),
        'lastUpdated': now,
      });
      
      transaction.update(partnerWalletRef, {
        'balance': partnerBalance - partnerFee,
        'totalSpent': FieldValue.increment(partnerFee),
        'lastUpdated': now,
      });
      
      print('Updated wallet balances');
      
      // Update transaction statuses to accepted
      transaction.update(txRef, {
        'status': 'accepted',
        'feeDeducted': true,
        'actualFee': txFee,
        'acceptedAt': now,
        'updatedAt': now,
      });
      
      transaction.update(partnerTxRef, {
        'status': 'accepted',
        'feeDeducted': true,
        'actualFee': partnerFee,
        'acceptedAt': now,
        'updatedAt': now,
      });
      
      print('Updated transaction statuses');
      
      // Create wallet transaction records
      final userWalletTxRef = firestore.collection('wallet_transactions').doc();
      transaction.set(userWalletTxRef, {
        'userId': userId,
        'type': 'fee_deduction',
        'amount': -txFee,
        'description': 'Transaction fee for ${txData['type']} of ${txAmount.toStringAsFixed(2)} EGP',
        'relatedTransactionId': transactionId,
        'balanceBefore': userBalance,
        'balanceAfter': userBalance - txFee,
        'createdAt': now,
      });
      
      final partnerWalletTxRef = firestore.collection('wallet_transactions').doc();
      transaction.set(partnerWalletTxRef, {
        'userId': partnerUserId,
        'type': 'fee_deduction',
        'amount': -partnerFee,
        'description': 'Transaction fee for ${partnerTxData['type']} of ${partnerAmount.toStringAsFixed(2)} EGP',
        'relatedTransactionId': partnerTransactionId,
        'balanceBefore': partnerBalance,
        'balanceAfter': partnerBalance - partnerFee,
        'createdAt': now,
      });
      
      print('Created wallet transaction records');
      
      // Clear any existing notifications related to this transaction
      final notificationsQuery = await firestore
          .collection('notifications')
          .where('myTxId', whereIn: [transactionId, partnerTransactionId])
          .get();
      
      for (final notifDoc in notificationsQuery.docs) {
        transaction.delete(notifDoc.reference);
      }
      
      print('Cleared notifications');
    });
  }

  // Handle transaction request with proper concurrency control
  static Future<String> requestTransaction(String myTxId, String otherTxId, String toUserId) async {
    const maxRetries = 3;
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        return await _attemptTransactionRequest(myTxId, otherTxId, toUserId);
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          throw Exception('Failed to create transaction request after $maxRetries attempts: $e');
        }
        // Wait before retrying
        await Future.delayed(Duration(milliseconds: 100 * (1 << retryCount)));
      }
    }
    throw Exception('Maximum retries exceeded');
  }

  static Future<String> _attemptTransactionRequest(String myTxId, String otherTxId, String toUserId) async {
    final firestore = FirebaseFirestore.instance;
    final requestTag = firestore.collection('temp').doc().id;
    final fromUserId = FirebaseAuth.instance.currentUser!.uid;
    
    return await firestore.runTransaction<String>((transaction) async {
      final myTxRef = firestore.collection('transactions').doc(myTxId);
      final otherTxRef = firestore.collection('transactions').doc(otherTxId);
      
      final myTxDoc = await transaction.get(myTxRef);
      final otherTxDoc = await transaction.get(otherTxRef);
      
      if (!myTxDoc.exists || !otherTxDoc.exists) {
        throw Exception('Transaction not found');
      }
      
      final myTxData = myTxDoc.data()!;
      final otherTxData = otherTxDoc.data()!;
      
      // Check if transactions are still available for pairing
      if (myTxData['status'] != 'pending' || otherTxData['status'] != 'pending') {
        throw Exception('One or both transactions are no longer available');
      }
      
      // Check if transactions are already locked or paired
      if (myTxData.containsKey('lockUntil') && myTxData['lockUntil'] != null) {
        final lockUntil = (myTxData['lockUntil'] as Timestamp).toDate();
        if (DateTime.now().isBefore(lockUntil)) {
          throw Exception('Your transaction is currently locked');
        }
      }
      
      if (otherTxData.containsKey('lockUntil') && otherTxData['lockUntil'] != null) {
        final lockUntil = (otherTxData['lockUntil'] as Timestamp).toDate();
        if (DateTime.now().isBefore(lockUntil)) {
          throw Exception('Target transaction is currently locked');
        }
      }
      
      final lockUntil = Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 1)));
      final now = FieldValue.serverTimestamp();
      
      // Update both transactions to requested status with lock
      transaction.update(myTxRef, {
        'status': 'requested',
        'partnerTxId': otherTxId,
        'exchangeRequestedBy': fromUserId,
        'lockUntil': lockUntil,
        'requestTag': requestTag,
        'updatedAt': now,
      });
      
      transaction.update(otherTxRef, {
        'status': 'requested',
        'partnerTxId': myTxId,
        'exchangeRequestedBy': fromUserId,
        'lockUntil': lockUntil,
        'requestTag': requestTag,
        'updatedAt': now,
      });
      
      // Create notification
      final notificationRef = firestore.collection('notifications').doc(requestTag);
      transaction.set(notificationRef, {
        'id': requestTag,
        'requestTag': requestTag,
        'toUserId': toUserId,
        'fromUserId': fromUserId,
        'myTxId': otherTxId,
        'otherTxId': myTxId,
        'amount': otherTxData['amount'],
        'distance': _calculateDistance(myTxData, otherTxData),
        'status': 'pending',
        'expiresAt': DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        'createdAt': now,
      });
      
      return requestTag;
    });
  }

  static double _calculateDistance(Map<String, dynamic> tx1Data, Map<String, dynamic> tx2Data) {
    // Basic distance calculation - implement your distance formula here
    if (tx1Data['location'] != null && tx2Data['location'] != null) {
      final lat1 = tx1Data['location']['lat'] as double;
      final lng1 = tx1Data['location']['lng'] as double;
      final lat2 = tx2Data['location']['lat'] as double;
      final lng2 = tx2Data['location']['lng'] as double;
      
      // Simple distance calculation (you can use a more accurate formula)
      final deltaLat = lat1 - lat2;
      final deltaLng = lng1 - lng2;
      return (deltaLat * deltaLat + deltaLng * deltaLng) * 111.0; // Rough km conversion
    }
    return 0.0;
  }
}
