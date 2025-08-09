import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

void main() {
  tz.initializeTimeZones();
  runApp(BreathingApp());
}

class BreathingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Breath Trainer',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.blue.shade800,
        ),
        cardTheme: CardTheme(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: BreathingHomePage(),
    );
  }
}

class BreathingHomePage extends StatefulWidget {
  @override
  _BreathingHomePageState createState() => _BreathingHomePageState();
}

class _BreathingHomePageState extends State<BreathingHomePage>
    with SingleTickerProviderStateMixin {
  AudioPlayer audioPlayer = AudioPlayer();
  bool isPlaying = true;
  bool isSessionRunning = false;
  String selectedMethod = '4-7-8';
  int inhale = 4, hold = 7, exhale = 8;
  int sessionDuration = 5;
  int secondsElapsed = 0;
  Timer? sessionTimer;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  List<FlSpot> usageHistory = [];
  int dailyStreak = 0;

  late AnimationController _animationController;
  String _currentPhase = 'Ready';
  int _currentPhaseCounter = 0;

  final Map<String, Map<String, dynamic>> breathingMethods = {
    '4-7-8': {
      'name': '4-7-8 Relaxing',
      'description': 'Perfect for sleep and anxiety',
      'inhale': 4,
      'hold': 7,
      'exhale': 8,
      'icon': Icons.bedtime,
      'color': Colors.purple,
    },
    'Box': {
      'name': 'Box Breathing',
      'description': 'Focus and concentration',
      'inhale': 4,
      'hold': 4,
      'exhale': 4,
      'icon': Icons.crop_square,
      'color': Colors.green,
    },
    'Equal': {
      'name': 'Equal Breathing',
      'description': 'Balance and calm',
      'inhale': 5,
      'hold': 5,
      'exhale': 5,
      'icon': Icons.balance,
      'color': Colors.blue,
    },
    'Relax': {
      'name': 'Deep Relax',
      'description': 'Stress relief',
      'inhale': 6,
      'hold': 2,
      'exhale': 7,
      'icon': Icons.spa,
      'color': Colors.teal,
    },
  };

  @override
  void initState() {
    super.initState();
    _initAudio();
    _initNotifications();
    _scheduleDailyReminder();

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: inhale + hold + exhale),
    )..addListener(() {
        setState(() {});
      });

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed && isSessionRunning) {
        _animationController.reset();
        _animationController.forward();
      }
    });
  }

  void _initAudio() async {
    try {
      await audioPlayer.setReleaseMode(ReleaseMode.loop);
      await audioPlayer.play(AssetSource('sounds/ocean.mp3'));
    } catch (e) {
      debugPrint('Audio initialization failed: $e');
    }
  }

  void _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  tz.TZDateTime _nextInstanceOfTenAM() {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 10);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  void _scheduleDailyReminder() async {
    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'Time to Breathe 🌬️',
      'Take a moment to relax and breathe today.',
      _nextInstanceOfTenAM(),
      const NotificationDetails(
        android: AndroidNotificationDetails('daily_reminder', 'Daily Reminder',
            importance: Importance.max, priority: Priority.high),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  void toggleSound() async {
    setState(() => isPlaying = !isPlaying);
    try {
      isPlaying ? await audioPlayer.resume() : await audioPlayer.pause();
    } catch (e) {
      debugPrint('Audio toggle failed: $e');
    }
  }

  void switchMethod(String method) {
    final methodData = breathingMethods[method]!;
    setState(() {
      selectedMethod = method;
      inhale = methodData['inhale'];
      hold = methodData['hold'];
      exhale = methodData['exhale'];
      
      _animationController.duration =
          Duration(seconds: inhale + hold + exhale);
      if (isSessionRunning) {
        _animationController.reset();
        _animationController.forward();
      }
    });
  }

  void startSession() {
    setState(() {
      isSessionRunning = true;
      secondsElapsed = 0;
      _currentPhase = 'Get Ready';
      _currentPhaseCounter = 3;
    });

    // Countdown before starting
    Timer.periodic(const Duration(seconds: 1), (countdownTimer) {
      setState(() {
        _currentPhaseCounter--;
        if (_currentPhaseCounter <= 0) {
          countdownTimer.cancel();
          _currentPhase = 'Inhale';
          _currentPhaseCounter = inhale;
          _animationController.reset();
          _animationController.forward();
          _startMainTimer();
        } else {
          _currentPhase = 'Get Ready';
        }
      });
    });
  }

  void _startMainTimer() {
    sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        secondsElapsed++;
        _currentPhaseCounter--;

        final double animationValue = _animationController.value;
        final int totalDuration = inhale + hold + exhale;
        final int currentAnimationTime =
            (animationValue * totalDuration).round();

        if (currentAnimationTime < inhale) {
          if (_currentPhase != 'Inhale') {
            _currentPhase = 'Inhale';
            _currentPhaseCounter = inhale - currentAnimationTime;
          }
        } else if (currentAnimationTime < inhale + hold) {
          if (_currentPhase != 'Hold') {
            _currentPhase = 'Hold';
            _currentPhaseCounter = hold - (currentAnimationTime - inhale);
          }
        } else {
          if (_currentPhase != 'Exhale') {
            _currentPhase = 'Exhale';
            _currentPhaseCounter = exhale - (currentAnimationTime - inhale - hold);
          }
        }

        if (_currentPhaseCounter <= 0) {
          if (_currentPhase == 'Inhale') {
            _currentPhase = 'Hold';
            _currentPhaseCounter = hold;
          } else if (_currentPhase == 'Hold') {
            _currentPhase = 'Exhale';
            _currentPhaseCounter = exhale;
          } else if (_currentPhase == 'Exhale') {
            _currentPhase = 'Inhale';
            _currentPhaseCounter = inhale;
          }
        }

        if (secondsElapsed >= sessionDuration * 60) {
          timer.cancel();
          isSessionRunning = false;
          dailyStreak++;
          usageHistory.add(
              FlSpot(DateTime.now().day.toDouble(), sessionDuration.toDouble()));
          _animationController.stop();
          _currentPhase = 'Well Done!';
          _currentPhaseCounter = 0;
        }
      });
    });
  }

  void stopSession() {
    sessionTimer?.cancel();
    _animationController.stop();
    setState(() {
      isSessionRunning = false;
      _currentPhase = 'Ready';
      _currentPhaseCounter = 0;
    });
  }

  Widget _buildBreathingCircle() {
    final double animationValue = _animationController.value;
    final int totalDuration = inhale + hold + exhale;

    double size = 120.0;
    double opacity = 0.4;
    Color color = breathingMethods[selectedMethod]!['color'];

    if (isSessionRunning && _currentPhase != 'Get Ready' && _currentPhase != 'Well Done!') {
      if (animationValue < inhale / totalDuration) {
        // Inhale phase
        final progress = animationValue / (inhale / totalDuration);
        size = 120 + (80 * progress);
        opacity = 0.4 + (0.5 * progress);
      } else if (animationValue < (inhale + hold) / totalDuration) {
        // Hold phase
        size = 200.0;
        opacity = 0.9;
      } else {
        // Exhale phase
        final exhaleProgress =
            (animationValue - (inhale + hold) / totalDuration) /
                (exhale / totalDuration);
        size = 200 - (80 * exhaleProgress);
        opacity = 0.9 - (0.5 * exhaleProgress);
      }
    }

    return Container(
      width: 250,
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withOpacity(0.3),
                width: 2,
              ),
            ),
          ),
          // Animated circle
          AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withOpacity(opacity),
                  color.withOpacity(opacity * 0.7),
                  color.withOpacity(opacity * 0.3),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          // Phase text
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _currentPhase,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (_currentPhaseCounter > 0 && _currentPhase != 'Get Ready')
                Text(
                  _currentPhaseCounter.toString(),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              if (_currentPhase == 'Get Ready')
                Text(
                  _currentPhaseCounter.toString(),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Container(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: breathingMethods.length,
        itemBuilder: (context, index) {
          final methodKey = breathingMethods.keys.elementAt(index);
          final method = breathingMethods[methodKey]!;
          final isSelected = selectedMethod == methodKey;

          return GestureDetector(
            onTap: () => switchMethod(methodKey),
            child: Container(
              width: 160,
              margin: EdgeInsets.symmetric(horizontal: 8),
              child: Card(
                elevation: isSelected ? 12 : 4,
                color: isSelected ? method['color'] : Colors.white,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        method['icon'],
                        size: 32,
                        color: isSelected ? Colors.white : method['color'],
                      ),
                      SizedBox(height: 8),
                      Text(
                        method['name'],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 4),
                      Text(
                        method['description'],
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? Colors.white70 : Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionControls() {
    return Card(
      elevation: 8,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(
                      'Duration',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: isSessionRunning ? null : () {
                            if (sessionDuration > 1) {
                              setState(() => sessionDuration--);
                            }
                          },
                          icon: Icon(Icons.remove_circle_outline),
                        ),
                        Text(
                          '$sessionDuration min',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: isSessionRunning ? null : () {
                            if (sessionDuration < 30) {
                              setState(() => sessionDuration++);
                            }
                          },
                          icon: Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      'Progress',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '${(secondsElapsed / 60).floor()}:${(secondsElapsed % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '/ ${sessionDuration}:00',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 20),
            if (isSessionRunning)
              LinearProgressIndicator(
                value: secondsElapsed / (sessionDuration * 60),
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(
                  breathingMethods[selectedMethod]!['color'],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    sessionTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              breathingMethods[selectedMethod]!['color'].withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Pocket Breath Trainer',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(isPlaying ? Icons.volume_up : Icons.volume_off),
                          onPressed: toggleSound,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.blue.shade800,
                          ),
                        ),
                        SizedBox(width: 8),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.local_fire_department, 
                                   color: Colors.orange, size: 20),
                              SizedBox(width: 4),
                              Text(
                                '$dailyStreak',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Main breathing circle
              Expanded(
                flex: 3,
                child: Center(
                  child: _buildBreathingCircle(),
                ),
              ),

              // Method selector
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Text(
                      'Choose Your Technique',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    SizedBox(height: 12),
                    _buildMethodSelector(),
                  ],
                ),
              ),

              // Session controls
              Padding(
                padding: EdgeInsets.all(16),
                child: _buildSessionControls(),
              ),

              // Start/Stop button
              Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isSessionRunning ? stopSession : startSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSessionRunning 
                          ? Colors.red.shade400 
                          : breathingMethods[selectedMethod]!['color'],
                      foregroundColor: Colors.white,
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: Text(
                      isSessionRunning ? 'Stop Session' : 'Start Breathing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.self_improvement),
            label: 'Breathe',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Stats',
          ),
        ],
        selectedItemColor: breathingMethods[selectedMethod]!['color'],
        onTap: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StatsPage(
                  usageHistory: usageHistory,
                  dailyStreak: dailyStreak,
                ),
              ),
            );
          }
        },
      ),
    );
  }
}

class StatsPage extends StatelessWidget {
  final List<FlSpot> usageHistory;
  final int dailyStreak;

  StatsPage({required this.usageHistory, required this.dailyStreak});

  @override
  Widget build(BuildContext context) {
    final totalSessions = usageHistory.length;
    final totalMinutes = usageHistory.fold<double>(0, (sum, spot) => sum + spot.y);
    final avgSession = totalSessions > 0 ? totalMinutes / totalSessions : 0;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue.shade800,
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      'Your Progress',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ],
                ),
              ),

              // Stats cards
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Daily Streak',
                        '$dailyStreak',
                        Icons.local_fire_department,
                        Colors.orange,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'Total Sessions',
                        '$totalSessions',
                        Icons.timeline,
                        Colors.green,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 12),

              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Total Minutes',
                        '${totalMinutes.toInt()}',
                        Icons.timer,
                        Colors.blue,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'Avg Session',
                        '${avgSession.toInt()} min',
                        Icons.trending_up,
                        Colors.purple,
                      ),
                    ),
                  ],
                ),
              ),

              // Chart
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Card(
                    elevation: 8,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Session History',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          SizedBox(height: 16),
                          Expanded(
                            child: usageHistory.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.self_improvement,
                                          size: 64,
                                          color: Colors.grey.shade400,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No sessions yet',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Complete your first breathing session\nto see your progress here!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : LineChart(
                                    LineChartData(
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: usageHistory,
                                          isCurved: true,
                                          barWidth: 4,
                                          color: Colors.blue,
                                          dotData: FlDotData(
                                            show: true,
                                            getDotPainter: (spot, percent, barData, index) {
                                              return FlDotCirclePainter(
                                                radius: 6,
                                                color: Colors.blue,
                                                strokeWidth: 2,
                                                strokeColor: Colors.white,
                                              );
                                            },
                                          ),
                                          belowBarData: BarAreaData(
                                            show: true,
                                            color: Colors.blue.withOpacity(0.1),
                                          ),
                                        )
                                      ],
                                      titlesData: FlTitlesData(
                                        show: true,
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            getTitlesWidget: (value, meta) {
                                              return Padding(
                                                padding: EdgeInsets.only(top: 8),
                                                child: Text(
                                                  'Day ${value.toInt()}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              );
                                            },
                                            interval: 1,
                                          ),
                                        ),
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            getTitlesWidget: (value, meta) {
                                              return Text(
                                                '${value.toInt()}m',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              );
                                            },
                                            interval: 2,
                                          ),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles: SideTitles(showTitles: false),
                                        ),
                                        topTitles: const AxisTitles(
                                          sideTitles: SideTitles(showTitles: false),
                                        ),
                                      ),
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: true,
                                        horizontalInterval: 2,
                                        verticalInterval: 1,
                                        getDrawingHorizontalLine: (value) {
                                          return FlLine(
                                            color: Colors.grey.shade300,
                                            strokeWidth: 1,
                                          );
                                        },
                                        getDrawingVerticalLine: (value) {
                                          return FlLine(
                                            color: Colors.grey.shade300,
                                            strokeWidth: 1,
                                          );
                                        },
                                      ),
                                      borderData: FlBorderData(
                                        show: true,
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                          width: 1,
                                        ),
                                      ),
                                      minX: usageHistory.isNotEmpty ? 
                                            usageHistory.first.x - 0.5 : 0,
                                      maxX: usageHistory.isNotEmpty ? 
                                            usageHistory.last.x + 0.5 : 10,
                                      minY: 0,
                                      maxY: usageHistory.isNotEmpty
                                          ? usageHistory.map((spot) => spot.y).reduce(max) + 2
                                          : 10,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 6,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}