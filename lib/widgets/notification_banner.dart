import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cashlink/l10n/app_localizations.dart';
import 'package:cashlink/services/notification_service.dart';
import 'package:cashlink/services/voice_service.dart';
import 'dart:async';

class NotificationBanner extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onNavigateToAgreement;

  const NotificationBanner({
    super.key,
    required this.data,
    required this.onNavigateToAgreement,
  });

  @override
  State<NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<NotificationBanner>
    with SingleTickerProviderStateMixin {
  late Timer _timer;
  int _remainingSeconds = 60;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: const Offset(0.0, 0.0),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    _animationController.forward();
    _startTimer();

    // Play voice notification when banner is shown
    _playVoiceNotification();
  }

  void _playVoiceNotification() async {
    // Get the sender's name from the notification data
    final fromUserId = widget.data['fromUserId'];
    if (fromUserId != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(fromUserId).get();
        final userName = userDoc.data()?['name'] ?? 'User';
        VoiceService().speakExchangeRequest(userName);
      } catch (e) {
        VoiceService().speakExchangeRequest('User');
      }
    } else {
      VoiceService().speakExchangeRequest('User');
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        NotificationService().handleExpired(widget.data);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    
    return SlideTransition(
      position: _slideAnimation,
      child: Material(
        elevation: 8,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border(
              bottom: BorderSide(color: Colors.blue.shade200, width: 2),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with timer
                Row(
                  children: [
                    Icon(Icons.notifications_active, 
                         color: Colors.blue.shade700, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'New Exchange Request',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _remainingSeconds > 10 ? Colors.green.shade100 : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _remainingSeconds > 10 ? Colors.green : Colors.red,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${_remainingSeconds}s',
                        style: TextStyle(
                          color: _remainingSeconds > 10 ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _remainingSeconds / 60,
                    minHeight: 6,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _remainingSeconds > 10 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Request details
                FutureBuilder<Map<String, dynamic>?>(
                  future: _getUserDetails(widget.data['fromUserId']),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    final user = snapshot.data!;
                    return Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(Icons.person, 
                                   color: Colors.blue.shade700, size: 30),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user['name']?.split(' ').first ?? 'Unknown',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${user['gender'] ?? 'Unknown'} • \$${widget.data['amount']?.toStringAsFixed(0) ?? '0'}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                              if (widget.data['distance'] != null)
                                Text(
                                  '~${widget.data['distance'].toStringAsFixed(1)} km away',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                
                const SizedBox(height: 20),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await NotificationService().handleAccept(widget.data);
                          widget.onNavigateToAgreement();
                        },
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: Text(
                          loc.accept,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => NotificationService().handleReject(widget.data),
                        icon: const Icon(Icons.close, color: Colors.red),
                        label: Text(
                          loc.reject,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _getUserDetails(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    return doc.exists ? doc.data() : null;
  }
}
