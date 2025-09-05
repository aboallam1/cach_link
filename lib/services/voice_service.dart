import 'package:flutter/services.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  bool _isEnabled = true;

  Future<void> initialize() async {
    // No initialization needed for system sounds
  }

  Future<void> _playSystemAlert(SystemSoundType soundType) async {
    if (!_isEnabled) return;
    
    try {
      await SystemSound.play(soundType);
    } catch (e) {
      print('Error playing system alert: $e');
    }
  }

  Future<void> speakExchangeRequest(String userName) async {
    await _playSystemAlert(SystemSoundType.alert);
  }

  Future<void> speakRequestAccepted(String userName) async {
    await _playSystemAlert(SystemSoundType.click);
  }

  Future<void> speakRequestSent() async {
    await _playSystemAlert(SystemSoundType.click);
  }

  Future<void> speakTransactionCompleted() async {
    await _playSystemAlert(SystemSoundType.click);
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  bool get isEnabled => _isEnabled;

  Future<void> stop() async {
    // No need to stop system sounds
  }

  void dispose() {
    // No resources to dispose for system sounds
  }
}
