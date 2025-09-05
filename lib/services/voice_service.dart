import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  bool _isEnabled = true;

  Future<void> initialize() async {
    // No initialization needed
  }

  Future<void> _playAlert(String alertType) async {
    if (!_isEnabled) return;
    
    try {
      if (kIsWeb) {
        // For web, we'll use console output and attempt system sound
        print('🔊 Alert: $alertType');
        // Try to use the browser's notification sound
        await SystemSound.play(SystemSoundType.alert);
      } else {
        // For mobile platforms
        await SystemSound.play(SystemSoundType.alert);
        // Add haptic feedback for mobile
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      print('Error playing alert: $e');
      // Fallback to haptic feedback
      try {
        HapticFeedback.lightImpact();
      } catch (e2) {
        print('Haptic feedback also failed: $e2');
      }
    }
  }

  Future<void> speakExchangeRequest(String userName) async {
    await _playAlert('Exchange Request from $userName');
  }

  Future<void> speakRequestAccepted(String userName) async {
    await _playAlert('Request Accepted by $userName');
  }

  Future<void> speakRequestSent() async {
    await _playAlert('Request Sent');
  }

  Future<void> speakTransactionCompleted() async {
    await _playAlert('Transaction Completed');
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  bool get isEnabled => _isEnabled;

  Future<void> stop() async {
    // No need to stop
  }

  void dispose() {
    // No resources to dispose
  }
}