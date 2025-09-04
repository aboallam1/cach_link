import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  StreamSubscription? _notificationSubscription;
  final ValueNotifier<Map<String, dynamic>?> currentNotification = ValueNotifier(null);

  void initialize() {
    _listenToNotifications();
  }

  void _listenToNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _notificationSubscription?.cancel();
    _notificationSubscription = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final notificationData = snapshot.docs.first.data();
        notificationData['id'] = snapshot.docs.first.id;
        currentNotification.value = notificationData;
      } else {
        currentNotification.value = null;
      }
    });
  }

  Future<void> handleAccept(Map<String, dynamic> data) async {
    final batch = FirebaseFirestore.instance.batch();
    
    final myTxRef = FirebaseFirestore.instance.collection('transactions').doc(data['myTxId']);
    final otherTxRef = FirebaseFirestore.instance.collection('transactions').doc(data['otherTxId']);
    
    batch.update(myTxRef, {
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
    batch.update(otherTxRef, {
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
    
    final notificationRef = FirebaseFirestore.instance.collection('notifications').doc(data['id']);
    batch.delete(notificationRef);
    
    await batch.commit();
    currentNotification.value = null;
  }

  Future<void> handleReject(Map<String, dynamic> data) async {
    final batch = FirebaseFirestore.instance.batch();
    
    final myTxRef = FirebaseFirestore.instance.collection('transactions').doc(data['myTxId']);
    final otherTxRef = FirebaseFirestore.instance.collection('transactions').doc(data['otherTxId']);
    
    batch.update(myTxRef, {'status': 'rejected'});
    batch.update(otherTxRef, {'status': 'rejected'});
    
    final notificationRef = FirebaseFirestore.instance.collection('notifications').doc(data['id']);
    batch.delete(notificationRef);
    
    await batch.commit();
    currentNotification.value = null;
  }

  Future<void> handleExpired(Map<String, dynamic> data) async {
    final batch = FirebaseFirestore.instance.batch();
    
    final myTxRef = FirebaseFirestore.instance.collection('transactions').doc(data['myTxId']);
    final otherTxRef = FirebaseFirestore.instance.collection('transactions').doc(data['otherTxId']);
    
    batch.update(myTxRef, {'status': 'archived'});
    batch.update(otherTxRef, {'status': 'archived'});
    
    final notificationRef = FirebaseFirestore.instance.collection('notifications').doc(data['id']);
    batch.delete(notificationRef);
    
    await batch.commit();
    currentNotification.value = null;
  }

  void dispose() {
    _notificationSubscription?.cancel();
    currentNotification.dispose();
  }
}
