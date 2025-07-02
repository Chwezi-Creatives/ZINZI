import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android Notification Shade',
      debugShowCheckedModeBanner: false, // Remove debug banner
      theme: ThemeData(
        brightness: Brightness.dark, // Dark theme to match the screenshot
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.black.withOpacity(0.5), // Semi-transparent background
        cardColor: const Color(0xFF333333), // Dark card background
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
          labelLarge: TextStyle(color: Colors.white),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
      ),
      home: const NotificationShadeScreen(),
    );
  }
}

class NotificationShadeScreen extends StatelessWidget {
  const NotificationShadeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Background image or gradient could go here
        // For simplicity, we'll use a semi-transparent black
        color: Colors.black.withOpacity(0.5),
        child: Column(
          children: [
            _buildStatusBar(),
            _buildQuickSettings(context),
            _buildDeviceAndMediaControl(context),
            _buildNotificationsSection(context),
            // Adding some space at the bottom to match the screenshot's scrollable feel
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '06:18 Tue, 01 Jul',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
          Row(
            children: [
              const Icon(Icons.wifi, size: 18),
              const SizedBox(width: 4),
              const Icon(Icons.signal_cellular_alt, size: 18),
              const SizedBox(width: 4),
              const Icon(Icons.battery_full, size: 18),
              const Text(
                '36%',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSettings(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _QuickSettingButton(
                icon: Icons.wifi,
                isActivated: true,
                onTap: () {},
              ),
              _QuickSettingButton(
                icon: Icons.bluetooth,
                isActivated: true,
                onTap: () {},
              ),
              _QuickSettingButton(
                icon: Icons.volume_up,
                isActivated: true,
                onTap: () {},
              ),
              _QuickSettingButton(
                icon: Icons.lock_outline,
                isActivated: false,
                onTap: () {},
              ),
              _QuickSettingButton(
                icon: Icons.flight,
                isActivated: false,
                onTap: () {},
              ),
              _QuickSettingButton(
                icon: Icons.lightbulb_outline,
                isActivated: false,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {},
                color: Colors.white70,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceAndMediaControl(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Column(
        children: [
          Material(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16.0),
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(16.0),
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(Icons.devices_other, color: Colors.blueAccent),
                    SizedBox(width: 10),
                    Text(
                      'Device control',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16.0),
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(16.0),
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(Icons.cast, color: Colors.green),
                    SizedBox(width: 10),
                    Text(
                      'Media output',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16), // Space before notifications
        ],
      ),
    );
  }

  Widget _buildNotificationsSection(BuildContext context) {
    return Expanded(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        children: const [
          _NotificationCard(
            icon: Icons.check_circle,
            iconColor: Colors.green,
            title: 'Download paused',
            subtitle: 'One UI 7.0 is available.',
            trailing: Icon(Icons.keyboard_arrow_down, color: Colors.white70),
          ),
          _NotificationCard(
            icon: Icons.image,
            iconColor: Colors.blueAccent,
            title: 'Screenshot saved',
            subtitle: 'Tap here to see your screenshot.',
            trailing: Image(image: AssetImage('assets/images/screenshot_preview.png'), width: 40, height: 40), // Placeholder, replace with actual image asset
            timestamp: '06:18',
          ),
          _NotificationCard(
            icon: Icons.vpn_key, // Placeholder for HA Tunnel Plus icon
            iconColor: Colors.orange,
            title: 'HA Tunnel Plus - Random...',
            subtitle: 'Disconnected',
            trailing: CircleAvatar(
              backgroundColor: Colors.orange,
              child: Text('HA', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
            timestamp: '06:14',
          ),
          _NotificationCard(
            icon: Icons.signal_wifi_off,
            iconColor: Colors.grey,
            title: 'No Internet',
            subtitle: 'You may be out of data from Vodacom-SA. Tap for options.',
            trailing: Icon(Icons.keyboard_arrow_down, color: Colors.white70),
          ),
          _NotificationCard(
            icon: Icons.download,
            iconColor: Colors.green,
            title: 'Blood Strike - FPS for all',
            subtitle: 'Downloading...',
            trailing: Icon(Icons.keyboard_arrow_down, color: Colors.white70),
            timestamp: '06:18',
          ),
          _NotificationCard(
            icon: Icons.vpn_key, // Placeholder for ZA Vodacom 2025 icon
            iconColor: Colors.purple,
            title: 'ZA Vodacom 2025 🔥[V2RAY]',
            subtitle: 'proxy• 0,0 B/s↑ 2,1 MB/s↓\ndirect • 0,0 B/s↑ 0,0 B/s↓',
            trailing: Icon(Icons.keyboard_arrow_down, color: Colors.white70),
          ),
          _NotificationSettingsFooter(),
        ],
      ),
    );
  }
}

class _QuickSettingButton extends StatelessWidget {
  final IconData icon;
  final bool isActivated;
  final VoidCallback onTap;

  const _QuickSettingButton({
    required this.icon,
    required this.isActivated,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActivated ? Colors.blueAccent : const Color(0xFF444444), // Adjusted inactive color
      borderRadius: BorderRadius.circular(12.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Icon(
            icon,
            color: isActivated ? Colors.white : Colors.white70,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final String? timestamp;

  const _NotificationCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16.0),
        child: InkWell(
          onTap: () {}, // Make the card tappable
          borderRadius: BorderRadius.circular(16.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: iconColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (timestamp != null)
                                Text(
                                  timestamp!,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      trailing!,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationSettingsFooter extends StatelessWidget {
  const _NotificationSettingsFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.settings, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                'Notification settings',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          MaterialButton(
            onPressed: () {},
            color: const Color(0xFF444444),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}