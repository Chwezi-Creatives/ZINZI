import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'notification_provider.dart';
import '../services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_feedback_service.dart';
import 'package:vibration/vibration.dart';
import 'dialogs/vibration_duration_dialog.dart';
import 'dialogs/vibration_amplitude_dialog.dart';
import 'dialogs/vibration_pattern_dialog.dart';

// Dialogs for settings
import 'package:flutter/services.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _orderNotifications = true;
  bool _chefNotifications = true;
  bool _producerNotifications = true;
  bool _transporterNotifications = true;
  bool _socialNotifications = true;
  bool _blogNotifications = true;
  bool _systemNotifications = true;
  bool _isSoundEnabled = true;
  bool _isVibrationEnabled = true;
  int _vibrationDuration = 500;
  int _vibrationAmplitude = 255;
  List<int>? _customVibrationPattern;

  late NotificationProvider _notificationProvider;
  late NotificationFeedbackService _feedbackService;
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    _prefs = await SharedPreferences.getInstance();
    _notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
    _feedbackService = NotificationFeedbackService(_prefs);
    await _loadSettings();
  }

  // Helper method to build section headers
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _loadSettings() async {
    // Load settings from the feedback service
    _isSoundEnabled = _feedbackService.isSoundEnabled;
    _isVibrationEnabled = _feedbackService.isVibrationEnabled;
    _vibrationDuration = _feedbackService.vibrationDuration;
    _vibrationAmplitude = _feedbackService.vibrationAmplitude;
    _customVibrationPattern = _feedbackService.customVibrationPattern;
    
    // Load notification types from preferences
    _orderNotifications = _prefs.getBool('notify_orders') ?? true;
    _chefNotifications = _prefs.getBool('notify_chefs') ?? true;
    _producerNotifications = _prefs.getBool('notify_producers') ?? true;
    _transporterNotifications = _prefs.getBool('notify_transporters') ?? true;
    _socialNotifications = _prefs.getBool('notify_social') ?? true;
    _blogNotifications = _prefs.getBool('notify_blog') ?? true;
    _systemNotifications = _prefs.getBool('notify_system') ?? true;
  }

  void _saveSettings() {
    // TODO: Implement saving settings to backend
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while services are initializing
    if (!mounted) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // General Settings
          SwitchListTile(
            title: const Text('Enable Notifications'),
            value: _notificationProvider.notificationsEnabled,
            onChanged: (value) {
              setState(() {
                _notificationProvider.setNotificationsEnabled(value);
              });
            },
          ),
          const Divider(height: 16),
          
          // Sound Settings
          SwitchListTile(
            title: const Text('Play Sound'),
            value: _isSoundEnabled,
            onChanged: (value) async {
              setState(() {
                _isSoundEnabled = value;
              });
              await _feedbackService.setSoundEnabled(value);
            },
          ),
          const Divider(height: 16),
          
          // Vibration Settings
          SwitchListTile(
            title: const Text('Vibrate'),
            value: _isVibrationEnabled,
            onChanged: (value) async {
              setState(() {
                _isVibrationEnabled = value;
              });
              await _feedbackService.setVibrationEnabled(value);
            },
          ),
          const Divider(),
          
          // Vibration Duration
          ListTile(
            title: const Text('Vibration Duration'),
            subtitle: Text('${_vibrationDuration}ms'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () async {
              final duration = await showDialog<int>(
                context: context,
                builder: (context) => VibrationDurationDialog(
                  initialDuration: _vibrationDuration,
                ),
              );
              if (duration != null) {
                setState(() {
                  _vibrationDuration = duration;
                });
                await _feedbackService.setVibrationDuration(duration);
              }
            },
          ),
          const Divider(),

          // Vibration Amplitude
          ListTile(
            title: const Text('Vibration Intensity'),
            subtitle: Text('${_vibrationAmplitude}/255'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () async {
              final amplitude = await showDialog<int>(
                context: context,
                builder: (context) => VibrationAmplitudeDialog(
                  initialAmplitude: _vibrationAmplitude,
                ),
              );
              if (amplitude != null) {
                setState(() {
                  _vibrationAmplitude = amplitude;
                });
                await _feedbackService.setVibrationAmplitude(amplitude);
              }
            },
          ),
          const Divider(),
          
          // Custom Vibration Pattern
          ListTile(
            title: const Text('Custom Vibration Pattern'),
            subtitle: Text(_customVibrationPattern != null 
                ? 'Custom pattern enabled' 
                : 'Default pattern'),
            trailing: _customVibrationPattern != null 
                ? IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      await _feedbackService.clearCustomVibrationPattern();
                      setState(() {
                        _customVibrationPattern = null;
                      });
                    },
                  )
                : const Icon(Icons.arrow_forward_ios),
            onTap: () async {
              final pattern = await showDialog<List<int>>(
                context: context,
                builder: (context) => VibrationPatternDialog(
                  initialPattern: _customVibrationPattern ?? 
                    _feedbackService.customVibrationPattern,
                ),
              );
              if (pattern != null) {
                setState(() {
                  _customVibrationPattern = pattern;
                });
                await _feedbackService.setCustomVibrationPattern(pattern);
              }
            },
          ),
          const Divider(),
          
          // Test Feedback
          ListTile(
            title: const Text('Test Notification Feedback'),
            subtitle: const Text('Test vibration and sound'),
            trailing: const Icon(Icons.play_arrow),
            onTap: () async {
              await _feedbackService.giveFeedback();
            },
          ),
          const Divider(),
          
          // Order Notifications
          _buildSectionHeader('Order Notifications'),
          SwitchListTile(
            title: const Text('Order Updates'),
            value: _orderNotifications,
            onChanged: (value) {
              setState(() {
                _orderNotifications = value;
              });
            },
          ),
          const Divider(),
          
          // Chef Notifications
          _buildSectionHeader('Chef Notifications'),
          SwitchListTile(
            title: const Text('Chef Network Updates'),
            value: _chefNotifications,
            onChanged: (value) {
              setState(() {
                _chefNotifications = value;
              });
            },
          ),
          const Divider(),
          
          // Producer Notifications
          _buildSectionHeader('Producer Notifications'),
          SwitchListTile(
            title: const Text('Producer Network Updates'),
            value: _producerNotifications,
            onChanged: (value) {
              setState(() {
                _producerNotifications = value;
              });
            },
          ),
          const Divider(),
          
          // Transporter Notifications
          _buildSectionHeader('Transporter Notifications'),
          SwitchListTile(
            title: const Text('Transport Updates'),
            value: _transporterNotifications,
            onChanged: (value) {
              setState(() {
                _transporterNotifications = value;
              });
            },
          ),
          const Divider(),
          
          // Social Notifications
          _buildSectionHeader('Social Notifications'),
          SwitchListTile(
            title: const Text('Community Updates'),
            value: _socialNotifications,
            onChanged: (value) {
              setState(() {
                _socialNotifications = value;
              });
            },
          ),

          _buildSectionHeader('Blog Notifications'),
          SwitchListTile(
            title: const Text('New Blog Posts'),
            value: _blogNotifications,
            onChanged: (value) {
              setState(() {
                _blogNotifications = value;
              });
            },
          ),

          _buildSectionHeader('System Notifications'),
          SwitchListTile(
            title: const Text('System Updates'),
            value: _systemNotifications,
            onChanged: (value) {
              setState(() {
                _systemNotifications = value;
              });
            },
          ),

          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saveSettings,
            child: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }
}