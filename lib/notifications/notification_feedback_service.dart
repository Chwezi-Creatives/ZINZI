import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert' as convert;

class NotificationFeedbackService {
  static const String _soundPath = 'assets/notification_sound.mp3';
  static const List<int> _defaultVibrationPattern = [0, 500, 200, 500]; // Pattern: delay, duration, delay, duration
  static const int _defaultVibrationDuration = 500; // 500ms
  static const int _defaultVibrationAmplitude = 255; // Maximum amplitude

  final SharedPreferences _prefs;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isVibrationEnabled = true;
  bool _isSoundEnabled = true;
  List<int>? _customVibrationPattern = _defaultVibrationPattern;
  int _vibrationDuration = _defaultVibrationDuration;
  int _vibrationAmplitude = _defaultVibrationAmplitude;

  NotificationFeedbackService(this._prefs) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    _isVibrationEnabled = _prefs.getBool('notification_vibration_enabled') ?? true;
    _isSoundEnabled = _prefs.getBool('notification_sound_enabled') ?? true;
    _vibrationDuration = _prefs.getInt('notification_vibration_duration') ?? _defaultVibrationDuration;
    _vibrationAmplitude = _prefs.getInt('notification_vibration_amplitude') ?? _defaultVibrationAmplitude;
    
    // Load custom vibration pattern if exists
    final patternString = _prefs.getString('notification_vibration_pattern');
    if (patternString != null) {
      try {
        _customVibrationPattern = List<int>.from(convert.json.decode(patternString));
      } catch (e) {
        debugPrint('Error loading custom vibration pattern: $e');
      }
    }
  }

  Future<void> giveFeedback() async {
    if (_isVibrationEnabled) {
      await _vibrate();
    }
    if (_isSoundEnabled) {
      await _playSound();
    }
  }

  Future<void> _vibrate() async {
    if (await Vibration.hasVibrator() == true) {
      if (_customVibrationPattern != null) {
        final pattern = _customVibrationPattern;
        if (pattern?.isNotEmpty ?? false) {
          await Vibration.vibrate(pattern: pattern!);
        } else {
          await Vibration.vibrate(
            duration: _vibrationDuration,
            amplitude: _vibrationAmplitude,
          );
        }
      } else {
        await Vibration.vibrate(
          duration: _vibrationDuration,
          amplitude: _vibrationAmplitude,
        );
      }
    }
  }

  Future<void> _playSound() async {
    try {
      await _audioPlayer.play(AssetSource(_soundPath));
    } catch (e) {
      print('Error playing sound: $e');
    }
  }

  Future<void> setVibrationEnabled(bool enabled) async {
    _isVibrationEnabled = enabled;
    await _prefs.setBool('notification_vibration_enabled', enabled);
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _isSoundEnabled = enabled;
    await _prefs.setBool('notification_sound_enabled', enabled);
  }

  Future<void> setVibrationDuration(int duration) async {
    _vibrationDuration = duration;
    await _prefs.setInt('notification_vibration_duration', duration);
  }

  Future<void> setVibrationAmplitude(int amplitude) async {
    _vibrationAmplitude = amplitude;
    await _prefs.setInt('notification_vibration_amplitude', amplitude);
  }

  Future<void> setCustomVibrationPattern(List<int> pattern) async {
    _customVibrationPattern = pattern;
    await _prefs.setString('notification_vibration_pattern', convert.json.encode(pattern));
  }

  Future<void> clearCustomVibrationPattern() async {
    _customVibrationPattern = null;
    await _prefs.remove('notification_vibration_pattern');
  }

  bool get isVibrationEnabled => _isVibrationEnabled;
  bool get isSoundEnabled => _isSoundEnabled;
  int get vibrationDuration => _vibrationDuration;
  int get vibrationAmplitude => _vibrationAmplitude;
  List<int>? get customVibrationPattern => _customVibrationPattern;
  
  // Add dispose method to clean up resources
  Future<void> dispose() async {
    await _audioPlayer.dispose();
  }
}
