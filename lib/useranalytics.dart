import 'dart:async';
import 'dart:convert';
import 'dart:math'; // For max(), min()
import 'package:collection/collection.dart'; // For firstWhereOrNull

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // For .env
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http; // For API calls
import 'package:shared_preferences/shared_preferences.dart'; // For user_id
import 'package:visibility_detector/visibility_detector.dart';
import 'package:zinzi2/app_drawer_unified.dart'; // <<<< YOUR ACTUAL DRAWER

// --- Constants from OLD code (Primary Source of Truth for this file's UI) ---
const Duration kAnimationDuration = Duration(milliseconds: 1200);
const Curve kAnimationCurve = Curves.easeOutCubic;

const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorPrimaryLighter = Color(0xFFB2DFDB);
const Color kColorPrimaryLightest = Color(0xFFE0F2F1);
const Color kColorBackground = Color(0xFFF8F8F8); // Scaffold background
const Color kColorSurface = Colors.white;         // Card backgrounds, etc.
const Color kColorTextPrimary = kColorPrimaryDark;
const Color kColorTextSecondary = Color(0xFF546E7A);
const Color kColorTextOnPrimary = Colors.white;     // Text on kColorPrimary/kColorPrimaryDark
const Color kColorTextOnSurface = kColorTextPrimary;// Text on kColorSurface
const Color kColorBorder = kColorPrimaryLighter;
const Color kColorDivider = Color(0xFFE0E0E0);
const Color kColorWarningHigh = Color(0xFFFFA000);
const Color kColorWarningLow = Color(0xFF00B0FF);
const Color kColorNegative = Color(0xFFFF5252);
const Color kColorPositiveOrTarget = Color(0xFF00E676);

// Chart specific colors from OLD code
const Color kChartLineColor = kColorPrimaryLight;
const Color kChartLineGradientStart = Color(0x554DB6AC);
const Color kChartLineGradientEnd = Color(0x004DB6AC);
const Color kChartGuideLineColor = kColorTextSecondary;
const Color kChartBarColor = kColorPrimary;
const Color kChartTooltipBg = Color(0xEE333333);
const Color kChartTooltipText = Colors.white;

// --- API Constants (from NEW code) ---
// Ensure .env is loaded by the main application
final String apiBaseUrl = dotenv.env['API_BASE_URL'] ?? 'https://your.default.api.url/if/not/loaded';
const String kEndpointPath = '/rr/users/';
const String kCombinedMetricsEndpoint = 'combined_metrics';
const int kDefaultLimit = 30;

// --- Data Models (from NEW code) ---
class CombinedMetrics {
  final int userId;
  final Map<String, dynamic> preferences;
  final Map<String, dynamic> metrics;
  final List<Map<String, dynamic>> caloriesHistory;
  final List<Map<String, dynamic>> weightHistory;
  final String lastUpdated;

  CombinedMetrics({
    required this.userId,
    required this.preferences,
    required this.metrics,
    required this.caloriesHistory,
    required this.weightHistory,
    required this.lastUpdated,
  });

  factory CombinedMetrics.fromJson(Map<String, dynamic> json) {
    return CombinedMetrics(
      userId: json['user_id'] as int? ?? 0,
      preferences: json['preferences'] as Map<String, dynamic>? ?? {},
      metrics: json['metrics'] as Map<String, dynamic>? ?? {},
      caloriesHistory: List<Map<String, dynamic>>.from(json['calories_history'] as List<dynamic>? ?? []),
      weightHistory: List<Map<String, dynamic>>.from(json['weight_history'] as List<dynamic>? ?? []),
      lastUpdated: json['last_updated'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}

// --- Main Dashboard Widget ---
class UserAnalyticsDashboard extends StatefulWidget {
  const UserAnalyticsDashboard({super.key});
  @override
  _UserAnalyticsDashboardState createState() => _UserAnalyticsDashboardState();
}

class _UserAnalyticsDashboardState extends State<UserAnalyticsDashboard> with TickerProviderStateMixin {
  late AnimationController _metricsController;
  late Animation<double> _mealsAnimation;
  late Animation<double> _caloriesAnimation;
  late Animation<double> _weightAnimation;

  String _selectedCalorieView = 'D';
  String _selectedWeightView = 'W';
  final List<String> _views = ['D', 'W', 'M', '6M'];

  Timer? _summaryTimer;
  int _currentDayIndex = 0;
  String _calorieSummaryMessage = '';

  CombinedMetrics? _metricsData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setupMetricsAnimations(mealsLogged: 17, avgCalories: 2122, weightChange: -2.0); // Corrected parameter name
    _fetchMetricsData().then((_) {
      if (_metricsData != null && mounted) {
        _startOrUpdateSummaryTimer();
      }
    });
  }

  @override
  void dispose() {
    _metricsController.dispose();
    _summaryTimer?.cancel();
    super.dispose();
  }

  void _setupMetricsAnimations({required double mealsLogged, required double avgCalories, required double weightChange}) {
    _metricsController = AnimationController(duration: kAnimationDuration, vsync: this);
    final curvedMetricsAnimation = CurvedAnimation(parent: _metricsController, curve: kAnimationCurve);
    _mealsAnimation = Tween<double>(begin: 0, end: mealsLogged).animate(curvedMetricsAnimation);
    _caloriesAnimation = Tween<double>(begin: 0, end: avgCalories).animate(curvedMetricsAnimation);
    _weightAnimation = Tween<double>(begin: 0, end: weightChange).animate(curvedMetricsAnimation);
    _metricsController.forward();
  }

  void _updateAnimationsWithApiData() {
    if (_metricsData == null || !mounted) return;
    
    if (_metricsController.isAnimating || _metricsController.isCompleted || _metricsController.isDismissed) {
      _metricsController.dispose();
    }

    // Calculate weekly meals logged by summing daily counts over the last 7 days
    final List<double> dailyMealCounts = _aggregateDataByPeriod(
      _metricsData!.caloriesHistory,
      'logged_at',
      'calories', // The key doesn't matter here, we just need the count of entries
      null,
      7, // Last 7 days
      const Duration(days: 1),
      average: false, // We want the sum, not the average
      countEntries: true, // Count entries instead of summing values
    );
    final double weeklyMealsLogged = dailyMealCounts.fold(0.0, (sum, count) => sum + count);

    // Calculate average calories over the last 7 days
    final double averageWeeklyCalories = _getAverageCaloriesOverDuration(
      _metricsData!.caloriesHistory,
      const Duration(days: 7),
    );

    _setupMetricsAnimations(
      mealsLogged: weeklyMealsLogged, // Use the calculated weekly total
      avgCalories: averageWeeklyCalories, // Use the calculated average weekly calories
      weightChange: (_metricsData!.metrics['weight_change'] as num? ?? 0).toDouble(),
    );
  }

  Future<void> _fetchMetricsData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '1';
      final int userIdInt = int.tryParse(userId) ?? 1;

      if (userIdInt <= 0) {
        throw Exception('Invalid user_id: $userId');
      }
      
      final url = Uri.parse('$apiBaseUrl$kEndpointPath$userIdInt/$kCombinedMetricsEndpoint?limit=$kDefaultLimit');
      
      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        setState(() {
          _metricsData = CombinedMetrics.fromJson(data);
          _isLoading = false;
          _error = null;
          _updateAnimationsWithApiData();
          _startOrUpdateSummaryTimer();
        });
      } else {
        setState(() {
          _error = 'Failed to fetch metrics (Status: ${response.statusCode}). Check API.';
          _isLoading = false;
        });
      }
    } catch (e, s) {
      print('Error fetching metrics: $e\n$s');
      if (!mounted) return;
      setState(() {
        _error = 'Error fetching metrics. Check connection/config.';
        _isLoading = false;
      });
    }
  }

  List<double> _getTypedHistoryValues(List<Map<String, dynamic>> history, String valueKey, [String? nestedKey]) {
    return history.map((item) {
      dynamic value = item[valueKey]; 
      if (nestedKey != null && value is Map) {
        value = value[nestedKey]; 
      }
      return (value as num?)?.toDouble() ?? 0.0;
    }).toList();
  }

  List<double> _aggregateDataByPeriod(List<Map<String, dynamic>> historyData, String dateKey, String valueKey, String? nestedValueKey, int numPeriods, Duration periodDuration, {bool average = false, bool countEntries = false}) {
    if (historyData.isEmpty) return List.filled(numPeriods, 0.0);

    List<double> aggregatedValues = List.filled(numPeriods, 0.0);
    final nowUtc = DateTime.now().toUtc(); // Use UTC for consistent comparison

    for (int i = 0; i < numPeriods; i++) {
      DateTime periodEndUtc;
      DateTime periodStartUtc;

      if (periodDuration.inDays == 1) {
        // Calculate period start and end in UTC
        periodStartUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day - i);
        periodEndUtc = periodStartUtc.add(const Duration(days: 1));
      } else if (periodDuration.inDays == 7) {
        // Calculate the start of the current week in UTC, then subtract weeks
        int daysToSubtract = nowUtc.weekday - 1 + (i * 7);
        periodStartUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day - daysToSubtract);
        periodEndUtc = periodStartUtc.add(const Duration(days: 7));
      } else {
        // Calculate the start of the current month in UTC, then subtract months
        periodEndUtc = DateTime.utc(nowUtc.year, nowUtc.month - i + 1, 1);
        periodStartUtc = DateTime.utc(nowUtc.year, nowUtc.month - i, 1);
      }
      
      final entriesForPeriod = historyData.where((entry) {
        try {
          // Parse entry date as UTC
          final entryDateUtc = DateTime.parse(entry[dateKey] as String).toUtc();
          // Compare in UTC
          return entryDateUtc.isAtSameMomentAs(periodStartUtc) || (entryDateUtc.isAfter(periodStartUtc) && entryDateUtc.isBefore(periodEndUtc));
        } catch (e) {
          return false;
        }
      }).toList();

      if (entriesForPeriod.isNotEmpty) {
        if (countEntries) { // If countEntries is true, just count the entries
          aggregatedValues[i] = entriesForPeriod.length.toDouble();
        } else { // Otherwise, aggregate values as before
          final values = _getTypedHistoryValues(entriesForPeriod, valueKey, nestedValueKey);
          double sum = values.fold(0.0, (prev, element) => prev + element);
          if (average && values.isNotEmpty) {
            aggregatedValues[i] = sum / values.length;
          } else {
            aggregatedValues[i] = sum;
          }
        }
      }
    }
    return aggregatedValues.reversed.toList(); 
  }


  List<double> _getCaloriesData(String view) {
    if (_metricsData == null || _metricsData!.caloriesHistory.isEmpty) {
      return view == 'D' ? List.filled(7,0.0) :
             view == 'W' ? List.filled(4,0.0) :
             view == 'M' ? List.filled(4,0.0) : 
             List.filled(6,0.0);
    }
    const String outerCaloriesKey = "calories";
    const String innerCaloriesKey = "calories";

    switch (view) {
      case 'D': 
        return _aggregateDataByPeriod(_metricsData!.caloriesHistory, 'logged_at', outerCaloriesKey, innerCaloriesKey, 7, const Duration(days: 1));
      case 'W': 
        return _aggregateDataByPeriod(_metricsData!.caloriesHistory, 'logged_at', outerCaloriesKey, innerCaloriesKey, 4, const Duration(days: 7));
      case 'M': 
        return _aggregateDataByPeriod(_metricsData!.caloriesHistory, 'logged_at', outerCaloriesKey, innerCaloriesKey, 4, const Duration(days: 7)); 
      case '6M': 
        return _aggregateDataByPeriod(_metricsData!.caloriesHistory, 'logged_at', outerCaloriesKey, innerCaloriesKey, 6, const Duration(days: 30));
      default:
        return List.filled(7, 0.0);
    }
  }

  List<double> _getWeightData(String view) {
     if (_metricsData == null || _metricsData!.weightHistory.isEmpty) {
      return view == 'D' ? List.filled(7,0.0) :
             view == 'W' ? List.filled(4,0.0) :
             view == 'M' ? List.filled(4,0.0) :
             List.filled(6,0.0);
    }
    const String weightKey = "weight";

    switch (view) {
      case 'D':
        return _aggregateDataByPeriod(_metricsData!.weightHistory, 'logged_at', weightKey, null, 7, const Duration(days: 1), average: true);
      case 'W':
        return _aggregateDataByPeriod(_metricsData!.weightHistory, 'logged_at', weightKey, null, 4, const Duration(days: 7), average: true);
      case 'M':
         return _aggregateDataByPeriod(_metricsData!.weightHistory, 'logged_at', weightKey, null, 4, const Duration(days: 7), average: true);
      case '6M':
        return _aggregateDataByPeriod(_metricsData!.weightHistory, 'logged_at', weightKey, null, 6, const Duration(days: 30), average: true);
      default:
        return List.filled(7, 0.0);
    }
  }

  // Helper function to calculate average calories over a specific duration
  double _getAverageCaloriesOverDuration(List<Map<String, dynamic>> historyData, Duration duration) {
    if (historyData.isEmpty) return 0.0;

    final now = DateTime.now();
    final periodStart = now.subtract(duration);

    final entriesInPeriod = historyData.where((entry) {
      try {
        final entryDate = DateTime.parse(entry['logged_at'] as String);
        return entryDate.isAfter(periodStart) && entryDate.isBefore(now);
      } catch (e) {
        return false;
      }
    }).toList();

    if (entriesInPeriod.isEmpty) return 0.0;

    final totalCalories = entriesInPeriod.fold(0.0, (sum, entry) {
      final calories = entry['calories'] as Map<String, dynamic>?;
      return sum + ((calories?['calories'] as num?)?.toDouble() ?? 0.0);
    });

    return totalCalories / entriesInPeriod.length;
  }
  
  final Map<String, List<double>> recommendedCaloriesData = {
    'D': List.filled(7, 1500.0),
    'W': List.filled(4, 1500.0 * 7),
    'M': List.filled(4, 1550.0 * 7),
    '6M': List.filled(6, 1600.0 * 30),
  };
  
  final Map<String, List<double>> recommendedWeightData = {
    'D': List.filled(7, 76.0),
    'W': List.filled(4, 76.0),
    'M': List.filled(4, 75.0),
    '6M': List.filled(6, 74.0),
  };
  
  final Map<String, double> macroData = {'Protein': 30, 'Carbs': 50, 'Fats': 20};
  final Map<String, double> cuisineData = {'Continental': 45, 'Asian': 35, 'Other': 20};

  // Function to get daily meal counts from calories history
  List<double> _getDailyMealCounts() {
    if (_metricsData == null || _metricsData!.caloriesHistory.isEmpty) {
      return List.filled(7, 0.0); // Return 7 zeros for the last 7 days if no data
    }
    return _aggregateDataByPeriod(
      _metricsData!.caloriesHistory,
      'logged_at',
      'calories', // Value key doesn't matter when counting entries
      null,
      7, // Last 7 days
      const Duration(days: 1),
      countEntries: true, // Count entries instead of summing values
    );
  }


  List<double> get currentActualCalories => _getCaloriesData(_selectedCalorieView);
  List<double> get currentRecommendedCalories => recommendedCaloriesData[_selectedCalorieView] ?? recommendedCaloriesData['D']!;
  List<double> get currentActualWeight => _getWeightData(_selectedWeightView);
  List<double> get currentRecommendedWeight => recommendedWeightData[_selectedWeightView] ?? recommendedWeightData['D']!;
  
  List<FlSpot> get currentCalorieIntakeSpots => _generateSpots(currentActualCalories);
  List<String> get currentCalorieLabels => _getLabelsForView(_selectedCalorieView, currentActualCalories.length);
  List<FlSpot> get currentWeightProgressSpots => _generateSpots(currentActualWeight);
  List<String> get currentWeightLabels => _getLabelsForView(_selectedWeightView, currentActualWeight.length);
  List<FlSpot> get currentRecommendedCalorieSpots => _generateSpots(currentRecommendedCalories);
  List<FlSpot> get currentRecommendedWeightSpots => _generateSpots(currentRecommendedWeight);


  void _startOrUpdateSummaryTimer() {
    _summaryTimer?.cancel();
    _updateCalorieSummary(); 

    if ((_selectedCalorieView == 'D' || _selectedCalorieView == 'W') && currentActualCalories.isNotEmpty) {
      _summaryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted && currentActualCalories.isNotEmpty) { 
          setState(() {
            _currentDayIndex = (_currentDayIndex + 1) % currentActualCalories.length;
            _calorieSummaryMessage = _getCalorieSummaryMessage(_currentDayIndex);
          });
        } else {
          timer.cancel();
        }
      });
    }
  }

  void _updateCalorieSummary() {
     _currentDayIndex = 0;
     if (!mounted) return;
     setState(() {
        if (currentActualCalories.isEmpty && currentRecommendedCalories.isEmpty) {
            _calorieSummaryMessage = "Summary data unavailable.";
        } else if (_selectedCalorieView == 'D' || _selectedCalorieView == 'W') {
            _calorieSummaryMessage = _getCalorieSummaryMessage(_currentDayIndex);
        } else {
            _calorieSummaryMessage = _getAggregateSummaryMessage(_selectedCalorieView);
        }
     });
  }

  String _getCalorieSummaryMessage(int dayIndex) {
    final labels = _getLabelsForView(_selectedCalorieView, currentActualCalories.length);

    if (currentActualCalories.isEmpty || currentRecommendedCalories.isEmpty || labels.isEmpty || 
        dayIndex < 0 || dayIndex >= currentActualCalories.length || 
        dayIndex >= currentRecommendedCalories.length || dayIndex >= labels.length) {
        return "Summary unavailable for this period.";
    }
    double actual = currentActualCalories[dayIndex];
    double recommended = currentRecommendedCalories[dayIndex];
    double calorieDiff = actual - recommended;
    String label = labels[dayIndex];

    if (calorieDiff == 0) { return 'You hit your calorie target on $label! 🎉'; }
    else if (calorieDiff > 0) { return 'Consumed ${calorieDiff.toStringAsFixed(0)} kcal more than recommended on $label.'; }
    else { return 'Consumed ${(-calorieDiff).toStringAsFixed(0)} kcal less than recommended on $label.'; }
  }

  String _getAggregateSummaryMessage(String view) {
      if (currentActualCalories.isEmpty || currentRecommendedCalories.isEmpty) return "Summary unavailable.";
      
      double sumActual = currentActualCalories.fold(0.0, (a,b) => a+b);
      double sumRecommended = currentRecommendedCalories.fold(0.0, (a,b) => a+b);

      if (currentActualCalories.isEmpty) return "Average actual calories unavailable.";
      if (currentRecommendedCalories.isEmpty) return "Average recommended calories unavailable.";
      
      double avgActual = sumActual / currentActualCalories.length;
      double avgRecommended = sumRecommended / currentRecommendedCalories.length;
      double avgDiff = avgActual - avgRecommended; 
      
      String period;
      switch (view) {
        case 'M': period = 'the last month (avg weekly)'; break;
        case '6M': period = 'the last 6 months (avg monthly)'; break;
        default: period = 'the selected period';
      }

      if(avgDiff.abs() < (avgRecommended * 0.05)) return 'Your average intake was close to recommended over $period.';
      else if (avgDiff > 0) return 'On average, you consumed ${avgDiff.toStringAsFixed(0)} kcal more than recommended over $period.';
      else return 'On average, you consumed ${(-avgDiff).toStringAsFixed(0)} kcal less than recommended over $period.';
  }

  List<String> _getLabelsForView(String view, int dataLength) {
    if (dataLength == 0) return [];
    final now = DateTime.now();
    const monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const dayNamesShort = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

    switch (view) {
      case 'D':
        return List.generate(dataLength, (i) {
          final day = now.subtract(Duration(days: dataLength - 1 - i));
          return dayNamesShort[day.weekday - 1];
        }).toList();
      case 'W': 
      case 'M': 
        return List.generate(dataLength, (i) => 'W${i+1}' ).toList(); 
      case '6M': 
        return List.generate(dataLength, (i) {
          final month = DateTime(now.year, now.month - (dataLength - 1 - i), 1);
          return monthNames[month.month-1];
        }).toList();
      default:
        return List.generate(dataLength, (i) => 'P${i+1}');
    }
  }
  
  List<FlSpot> _generateSpots(List<double> data) {
       if (data.isEmpty) return []; 
       return data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
  }

  void _handleViewChange(String? value, bool isCalorieChart) {
       if (value != null) {
            if (isCalorieChart && value != _selectedCalorieView) {
                setState(() { _selectedCalorieView = value; });
                _startOrUpdateSummaryTimer();
            } else if (!isCalorieChart && value != _selectedWeightView) {
                 setState(() { _selectedWeightView = value; });
            }
       }
  }

  @override
  Widget build(BuildContext context) {
    final smallLabelStyle = GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 11);
    final mediumLabelStyle = GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 12, fontWeight: FontWeight.w500);
    final titleStyle = GoogleFonts.poppins(color: kColorPrimary, fontSize: 18, fontWeight: FontWeight.w600);
    final cardTitleStyle = GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 16, fontWeight: FontWeight.w500);
    final metricValueStyle = GoogleFonts.poppins(color: kColorPrimaryDark, fontSize: 14, fontWeight: FontWeight.bold);
    final appBarTitleStyle = GoogleFonts.poppins(color: kColorTextOnPrimary, fontSize: 20, fontWeight: FontWeight.w600);
    final chartLegendLabelStyle = GoogleFonts.poppins(fontSize: 11, color: kColorTextPrimary);


    if (_isLoading) {
      return Scaffold(
        backgroundColor: kColorBackground,
        appBar: AppBar(
            title: Text('Analytics Dashboard', style: appBarTitleStyle), 
            backgroundColor: kColorPrimaryDark, 
            foregroundColor: kColorTextOnPrimary, 
            iconTheme: const IconThemeData(color: kColorTextOnPrimary),
            centerTitle: true),
        drawer: const AppDrawer(),
        body: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(kColorPrimary))),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: kColorBackground,
        appBar: AppBar(
            title: Text('Analytics Dashboard', style: appBarTitleStyle), 
            backgroundColor: kColorPrimaryDark, 
            foregroundColor: kColorTextOnPrimary, 
            iconTheme: const IconThemeData(color: kColorTextOnPrimary),
            centerTitle: true),
        drawer: const AppDrawer(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: $_error', style: GoogleFonts.poppins(color: kColorNegative, fontSize: 16), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, color: kColorTextOnPrimary),
                  label: Text('Retry', style: GoogleFonts.poppins(color: kColorTextOnPrimary)),
                  onPressed: _fetchMetricsData,
                  style: ElevatedButton.styleFrom(backgroundColor: kColorPrimary),
                )
              ],
            ),
          ),
        ),
      );
    }
    
    if (_metricsData == null && !_isLoading && _error == null) {
         return Scaffold(
            backgroundColor: kColorBackground,
            appBar: AppBar(
                title: Text('Analytics Dashboard', style: appBarTitleStyle), 
                backgroundColor: kColorPrimaryDark, 
                foregroundColor: kColorTextOnPrimary, 
                iconTheme: const IconThemeData(color: kColorTextOnPrimary),
                centerTitle: true),
            drawer: const AppDrawer(),
            body: Center(
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Text('No data available. Please try again later.', style: GoogleFonts.poppins(fontSize: 16, color: kColorTextPrimary), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                    icon: const Icon(Icons.refresh, color: kColorTextOnPrimary),
                    label: Text('Fetch Data', style: GoogleFonts.poppins(color: kColorTextOnPrimary)),
                    onPressed: _fetchMetricsData,
                    style: ElevatedButton.styleFrom(backgroundColor: kColorPrimary),
                    )
                ],
                ),
            ),
            ),
        );
    }


    return Scaffold(
      backgroundColor: kColorBackground,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text('Analytics Dashboard', style: appBarTitleStyle),
        centerTitle: true,
        backgroundColor: kColorPrimaryDark,
        foregroundColor: kColorTextOnPrimary,
        iconTheme: const IconThemeData(color: kColorTextOnPrimary),
        elevation: 1.0,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchMetricsData,
        color: kColorPrimary,
        backgroundColor: kColorSurface,
        child: Container( 
          color: kColorBackground, 
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
            children: [
              _buildSectionTitle('Weekly Summary', titleStyle),
              _buildMetricsSection(mediumLabelStyle, metricValueStyle),
              const SizedBox(height: 24.0),

              _buildSectionTitle('Calorie Intake', titleStyle),
              _AnimatedChartSection(
                  key: const ValueKey('calorie_chart'),
                  chartType: _ChartType.line,
                  title: "Calorie Intake vs Recommended",
                  cardTitleStyle: cardTitleStyle,
                  axisLabelStyle: smallLabelStyle,
                  lineChartData: currentCalorieIntakeSpots,
                  lineRecommendedData: currentRecommendedCalorieSpots,
                  lineLabels: currentCalorieLabels,
                  isWeightChart: false,
                  viewSelector: _buildViewToggle(selectedValue: _selectedCalorieView, onChanged: (v) => _handleViewChange(v, true)),
                  summaryContent: _buildSummaryContainer(_calorieSummaryMessage, Icons.info_outline),
              ),
              const SizedBox(height: 24.0),

              _buildSectionTitle('Meal Trends', titleStyle),
              _AnimatedChartSection(
                  key: const ValueKey('meal_trend_chart'),
                  chartType: _ChartType.bar,
                  title: "Weekly Meal Logging",
                  cardTitleStyle: cardTitleStyle,
                  axisLabelStyle: smallLabelStyle,
                  barChartData: _getDailyMealCounts().map((e) => e.toInt()).toList(), // Use daily meal counts
                  summaryContent: _buildSummaryContainer("Maintain consistent meal times for better insights.", Icons.check_circle_outline),
              ),
              const SizedBox(height: 24.0),

              _buildSectionTitle('Weight Progress', titleStyle),
              _AnimatedChartSection(
                  key: const ValueKey('weight_chart'),
                  chartType: _ChartType.line,
                  title: "Weight Progress vs Target",
                  cardTitleStyle: cardTitleStyle,
                  axisLabelStyle: smallLabelStyle,
                  lineChartData: currentWeightProgressSpots,
                  lineRecommendedData: currentRecommendedWeightSpots,
                  lineLabels: currentWeightLabels,
                  isWeightChart: true,
                  viewSelector: _buildViewToggle(selectedValue: _selectedWeightView, onChanged: (v) => _handleViewChange(v, false)),
              ),
              const SizedBox(height: 16.0),

              _buildSectionTitle('Nutrition Overview', titleStyle),
              _AnimatedChartSection(
                   key: const ValueKey('macro_chart'),
                   chartType: _ChartType.pie,
                   axisLabelStyle: smallLabelStyle,
                   title: "Macronutrient Balance",
                   cardTitleStyle: cardTitleStyle,
                   pieChartData: macroData,
                   legendLabelStyle: chartLegendLabelStyle,
                   summaryContent: _buildSummaryContainer("Consider balancing carbs with more protein for your goals.", Icons.pie_chart_outline),
              ),
              const SizedBox(height: 16.0),
              _AnimatedChartSection(
                   key: const ValueKey('cuisine_chart'),
                   chartType: _ChartType.pie,
                   axisLabelStyle: smallLabelStyle,
                   title: "Popular Cuisines",
                   cardTitleStyle: cardTitleStyle,
                   pieChartData: cuisineData,
                   legendLabelStyle: chartLegendLabelStyle,
                   summaryContent: _buildSummaryContainer("Continental and Asian cuisines are your top choices.", Icons.restaurant),
              ),
              const SizedBox(height: 24.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, TextStyle style) {
     return Padding(
       padding: const EdgeInsets.only(bottom: 12.0, top: 8.0), 
       child: Text(title, style: style),
     );
  }

  Widget _buildMetricsSection(TextStyle labelStyle, TextStyle valueStyle) {
      return Card(
        elevation: 2,
        shadowColor: kColorPrimaryLighter.withOpacity(0.4),
        margin: const EdgeInsets.only(bottom: 16.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: kColorSurface,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 32 - 16 - 16) / 3,
                  height: 110,
                  child: MetricCard(
                    title: 'Meals Logged',
                    icon: Icons.restaurant_menu,
                    color: kColorPrimary,
                    labelStyle: labelStyle,
                    child: AnimatedBuilder(
                      animation: _mealsAnimation,
                      builder: (c, ch) => Text('${_mealsAnimation.value.toInt()}', style: valueStyle),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 32 - 16 - 16) / 3,
                  height: 110,
                  child: MetricCard(
                    title: 'Avg Calories',
                    icon: Icons.local_fire_department,
                    color: kColorWarningHigh,
                    labelStyle: labelStyle,
                    child: AnimatedBuilder(
                      animation: _caloriesAnimation,
                      builder: (c, ch) => Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${_caloriesAnimation.value.toInt()} kcal', style: valueStyle, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 32 - 16 - 16) / 3,
                  height: 110,
                  child: MetricCard(
                    title: 'Weight Change',
                    icon: Icons.monitor_weight,
                    color: kColorPrimaryLight,
                    labelStyle: labelStyle,
                    child: AnimatedBuilder(
                      animation: _weightAnimation,
                      builder: (c, ch) {
                        final wv = _weightAnimation.value;
                        Color wc = (wv == 0) ? kColorTextPrimary : ((wv > 0) ? kColorPositiveOrTarget : kColorNegative);
                        return Text('${wv.toStringAsFixed(1)} kg', style: valueStyle.copyWith(color: wc), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildSummaryContainer(String message, IconData icon) {
     return Container(
       decoration: BoxDecoration(
         color: kColorPrimaryLightest,
         borderRadius: BorderRadius.circular(8),
         border: Border.all(color: kColorPrimaryLighter.withOpacity(0.8)),
       ),
       padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
       child: Row(
         children: [
           Icon(icon, size: 18, color: kColorPrimary),
           const SizedBox(width: 8),
           Expanded(
             child: Text(
               message,
               style: GoogleFonts.poppins(
                 color: kColorPrimaryDark,
                 fontWeight: FontWeight.w500,
                 fontSize: 13,
               ),
             ),
           ),
         ],
       ),
     );
  }

  Widget _buildViewToggle({required String selectedValue, required ValueChanged<String?> onChanged}) {
    final isSelected = _views.map((v) => v == selectedValue).toList();
    final tts = GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12);

    return LayoutBuilder(
      builder: (context, constraints) {
        double availableWidthForButtons = constraints.maxWidth;
        double buttonMinWidth = (availableWidthForButtons / _views.length) - 16.0 - (_views.length > 1 ? 1.0 : 0.0);
        buttonMinWidth = max(40.0, buttonMinWidth); 
        
        return Container(
          alignment: Alignment.center,
          child: ToggleButtons(
            isSelected: isSelected,
            onPressed: (i) => onChanged(_views[i]),
            borderRadius: BorderRadius.circular(8.0),
            selectedBorderColor: kColorPrimary,
            selectedColor: kColorTextOnPrimary,
            fillColor: kColorPrimary,        
            color: kColorPrimary,            
            borderColor: kColorPrimaryLighter,
            splashColor: kColorPrimaryLight.withOpacity(0.2),
            constraints: BoxConstraints(
              minHeight: 36.0,
              minWidth: buttonMinWidth, 
            ),
            children: _views
                .map(
                  (v) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(v, style: tts),
                  ),
                )
                .toList(),
          ),
        );
      }
    );
  }
}

enum _ChartType { line, bar, pie }

class _AnimatedChartSection extends StatefulWidget {
  final _ChartType chartType;
  final TextStyle axisLabelStyle;
  final String? title;
  final TextStyle? cardTitleStyle;
  final TextStyle? legendLabelStyle;
  final Widget? viewSelector;
  final Widget? summaryContent;

  final List<FlSpot>? lineChartData;
  final List<FlSpot>? lineRecommendedData;
  final List<String>? lineLabels;
  final bool? isWeightChart;
  final List<int>? barChartData;
  final Map<String, double>? pieChartData;

  const _AnimatedChartSection({
    required super.key,
    required this.chartType,
    required this.axisLabelStyle,
    this.title,
    this.cardTitleStyle,
    this.legendLabelStyle,
    this.viewSelector,
    this.summaryContent,
    this.lineChartData,
    this.lineRecommendedData,
    this.lineLabels,
    this.isWeightChart,
    this.barChartData,
    this.pieChartData,
  });

  @override
  _AnimatedChartSectionState createState() => _AnimatedChartSectionState();
}

class _AnimatedChartSectionState extends State<_AnimatedChartSection> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: kAnimationDuration, vsync: this);
    _animation = CurvedAnimation(parent: _controller, curve: kAnimationCurve);
  }

  @override
  void didUpdateWidget(covariant _AnimatedChartSection oldWidget) {
     super.didUpdateWidget(oldWidget);
     bool dataChanged = false;
     if (widget.chartType == _ChartType.line) {
         dataChanged = oldWidget.lineChartData?.toString() != widget.lineChartData?.toString() ||
                       oldWidget.lineLabels?.join(',') != widget.lineLabels?.join(',');
     } else if (widget.chartType == _ChartType.bar) {
         dataChanged = oldWidget.barChartData?.toString() != widget.barChartData?.toString();
     } else if (widget.chartType == _ChartType.pie) {
         dataChanged = oldWidget.pieChartData?.toString() != widget.pieChartData?.toString();
     }

     if (dataChanged && _hasData()) { 
         _controller.reset();
         _hasAnimated = false; 
         if (mounted && _controller.status != AnimationStatus.forward && _controller.status != AnimationStatus.completed) {
            Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted) _startAnimation();
            });
         }
     }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _hasData() {
    switch(widget.chartType) {
      case _ChartType.line: return widget.lineChartData?.isNotEmpty ?? false;
      case _ChartType.bar: return widget.barChartData?.isNotEmpty ?? false;
      case _ChartType.pie: return widget.pieChartData?.isNotEmpty ?? false;
    }
  }

  void _startAnimation() {
    if (!_hasAnimated && mounted && _controller.status != AnimationStatus.forward && _controller.status != AnimationStatus.completed) {
      _controller.forward();
      setState(() { _hasAnimated = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: widget.key!,
      onVisibilityChanged: (visibilityInfo) {
        if (visibilityInfo.visibleFraction > 0.2 && !_hasAnimated && _hasData()) {
           Future.delayed(const Duration(milliseconds: 150), _startAnimation);
        }
      },
      child: Card(
        elevation: 1.5, 
        shadowColor: kColorPrimaryLighter.withOpacity(0.3),
        margin: const EdgeInsets.only(bottom: 16.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: kColorBorder.withOpacity(0.7), width: 1)
        ),
        color: kColorSurface,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if(widget.title != null && widget.cardTitleStyle != null)
                 Padding(
                   padding: const EdgeInsets.only(bottom: 15.0), 
                   child: Text(widget.title!, style: widget.cardTitleStyle!),
                 ),
              if (widget.summaryContent != null) ...[
                widget.summaryContent!,
                const SizedBox(height: 15),
              ],
              if (widget.viewSelector != null) ...[
                widget.viewSelector!, 
                const SizedBox(height: 20),
              ],
              if (!_hasData())
                SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      "No data available for this chart.",
                      style: widget.axisLabelStyle.copyWith(color: kColorTextSecondary),
                    ),
                  ),
                )
              else
                AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    switch(widget.chartType) {
                        case _ChartType.line:
                          assert(widget.lineChartData != null);
                          assert(widget.lineRecommendedData != null);
                          assert(widget.lineLabels != null);
                          assert(widget.isWeightChart != null);
                          
                          List<FlSpot> animatedData = widget.lineChartData!
                              .map((spot) => FlSpot(spot.x, spot.y * _animation.value))
                              .toList();
                          List<FlSpot> animatedRecommendedData = widget.lineRecommendedData!
                              .map((spot) => FlSpot(spot.x, spot.y * _animation.value))
                              .toList();
                          
                          if (_animation.value < 0.01) {
                               animatedData = widget.lineChartData!.map((s) => FlSpot(s.x, 0)).toList();
                               animatedRecommendedData = widget.lineRecommendedData!.map((s) => FlSpot(s.x, 0)).toList();
                          }

                          final double maxX = (widget.lineLabels!.isNotEmpty ? widget.lineLabels!.length - 1 : 0).toDouble();
                          
                          return _buildLineChartWidget(
                            data: animatedData,
                            recommendedData: animatedRecommendedData,
                            labels: widget.lineLabels!,
                            isWeightChart: widget.isWeightChart!,
                            axisLabelStyle: widget.axisLabelStyle,
                            maxX: maxX,
                            animationValue: _animation.value,
                          );
                        case _ChartType.bar:
                          assert(widget.barChartData != null);
                          return WeeklyMealTrendChart(
                              mealsPerDay: widget.barChartData!,
                              animationProgress: _animation.value,
                              axisLabelStyle: widget.axisLabelStyle,
                          );
                        case _ChartType.pie:
                          assert(widget.pieChartData != null);
                          Widget chartWidget;
                          if (widget.title == "Macronutrient Balance") {
                            chartWidget = MacronutrientBreakdownChart(
                                      data: widget.pieChartData!,
                                      animationProgress: _animation.value,
                                    );
                          } else { 
                              chartWidget = PopularCuisinesChart(
                                      data: widget.pieChartData!,
                                      animationProgress: _animation.value,
                                    );
                          }
                          return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Center(
                                    child: SizedBox(
                                      height: 220,
                                      width: 220,
                                      child: chartWidget,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: _buildLegendWidget(widget.pieChartData!, widget.legendLabelStyle ?? widget.axisLabelStyle),
                                  ),
                                ),
                              ],
                            );
                    }
                  }
                ),
              if (widget.summaryContent != null || (widget.chartType == _ChartType.pie && widget.pieChartData != null))
                  const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLineChartWidget({
     required List<FlSpot> data, 
     required List<FlSpot> recommendedData,
     required List<String> labels, 
     required bool isWeightChart,
     required TextStyle axisLabelStyle,
     required double maxX,
     required double animationValue,
   }) {
    if (data.isEmpty && labels.isEmpty) {
      return SizedBox(height: 250, child: Center(child: Text("No data for chart", style: axisLabelStyle)));
    }
    
    List<FlSpot> originalActualData = widget.lineChartData ?? [];
    List<FlSpot> originalRecommendedData = widget.lineRecommendedData ?? [];

    double minY = double.infinity; 
    double maxY = double.negativeInfinity; 

    List<FlSpot> allOriginalSpots = [...originalActualData, ...originalRecommendedData];

    if (allOriginalSpots.isEmpty) { 
      minY = isWeightChart ? 60 : 0; 
      maxY = isWeightChart ? 90 : 2500; 
    } else { 
      for (var spot in allOriginalSpots) { 
        minY = min(minY, spot.y); 
        maxY = max(maxY, spot.y); 
      }
      if (minY == maxY) {
        minY = minY - (minY * 0.1).abs(); 
        maxY = maxY + (maxY * 0.1).abs();
        if (minY == 0 && maxY == 0) {
            maxY = isWeightChart ? 10 : 500; 
        }
      }
      double paddingY = (maxY - minY) * 0.15; 
      minY = (minY - paddingY); 
      maxY = (maxY + paddingY); 
      if (!isWeightChart) minY = max(0, minY); else minY = max(0, minY);
      if (minY.isInfinite || minY.isNaN) minY = 0;
      if (maxY.isInfinite || maxY.isNaN) maxY = isWeightChart ? 90 : 2500;
    } 
    
    double yInterval = ((maxY - minY) / 5).clamp(isWeightChart ? 1.0 : 50.0, double.infinity);
    if (yInterval <= 0) yInterval = isWeightChart ? 5 : 250;

    final tooltipTextStyle = GoogleFonts.poppins(color: kChartTooltipText, fontSize: 11, fontWeight: FontWeight.normal); 
    final tooltipBoldTextStyle = tooltipTextStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 12);
    final tooltipLabelStyle = tooltipTextStyle.copyWith(fontWeight: FontWeight.w600);
    
    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.all(),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            getTouchedSpotIndicator: (barData, spotIndexes) {
              return spotIndexes.map((index) {
                return TouchedSpotIndicatorData(
                  FlLine(color: kChartLineColor.withOpacity(0.5), strokeWidth: 2),
                  FlDotData(
                    getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                      radius: 6,
                      color: kChartLineColor,
                      strokeWidth: 2,
                      strokeColor: kColorSurface,
                    ),
                  ),
                );
              }).toList();
            },
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => kChartTooltipBg,
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((LineBarSpot touchedSpot) {
                  // For the primary data line (barIndex == 0), show detailed tooltip.
                  // For other lines (e.g., recommended line), show a minimal tooltip.
                  if (touchedSpot.barIndex == 0) {
                    final int spotIndex = touchedSpot.x.toInt();

                    if (spotIndex < 0 || spotIndex >= labels.length || spotIndex >= originalActualData.length) {
                      return LineTooltipItem('not enough data. please continue buying our meals', tooltipTextStyle); // Minimal tooltip for invalid index
                    }

                    final String label = labels[spotIndex];
                    final double actualValue = originalActualData[spotIndex].y;
                    // Find the corresponding spot on the recommended line for the same x-value
                    final LineBarSpot? recommendedSpot = touchedSpots.firstWhereOrNull(
                      (spot) => spot.x == touchedSpot.x && spot.barIndex != 0,
                      // Provide a default value or handle the case where no corresponding spot is found
                      // For this scenario, we assume the recommended line is always present if the actual is.
                      // If not, a default recommendedValue of 0.0 is used below.
                    );
                    final double recommendedValue = (recommendedSpot != null && spotIndex < originalRecommendedData.length)
                                                  ? originalRecommendedData[spotIndex].y
                                                  : 0.0;
                    final double difference = actualValue - recommendedValue;

                    String actualValueStr = isWeightChart ? '${actualValue.toStringAsFixed(1)} kg' : '${actualValue.toStringAsFixed(0)} kcal';
                    String recommendedValueStr = isWeightChart ? '${recommendedValue.toStringAsFixed(1)} kg' : '${recommendedValue.toStringAsFixed(0)} kcal';
                    
                    String diffStr;
                    Color diffColor;
                    double tolerance = isWeightChart ? 0.2 : 50.0;

                    if (difference.abs() <= tolerance) {
                      diffStr = 'On Target';
                      diffColor = kColorPositiveOrTarget;
                    } else if (difference > 0) {
                      diffStr = '+${isWeightChart ? difference.toStringAsFixed(1) : difference.toStringAsFixed(0)} ${isWeightChart ? "kg" : "kcal"}';
                      diffColor = kColorWarningHigh;
                    } else {
                      diffStr = '${isWeightChart ? difference.toStringAsFixed(1) : difference.toStringAsFixed(0)} ${isWeightChart ? "kg" : "kcal"}';
                      diffColor = kColorWarningLow;
                    }

                    return LineTooltipItem(
                      '$label\n',
                      tooltipBoldTextStyle,
                      children: <TextSpan>[
                        TextSpan(text: 'Actual: ', style: tooltipLabelStyle),
                        TextSpan(text: '$actualValueStr\n', style: tooltipTextStyle),
                        TextSpan(text: 'Target: ', style: tooltipLabelStyle),
                        TextSpan(text: '$recommendedValueStr\n', style: tooltipTextStyle),
                        TextSpan(
                          text: diffStr,
                          style: tooltipTextStyle.copyWith(color: diffColor, fontWeight: FontWeight.bold)
                        ),
                      ],
                      textAlign: TextAlign.left,
                    );
                  } else {
                    // For other bars (e.g., recommended line), return a minimal tooltip
                    return LineTooltipItem('', tooltipTextStyle);
                  }
                }).toList(); // Return the list directly without filtering nulls
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: yInterval > 0 ? yInterval : null,
            verticalInterval: 1,
            getDrawingHorizontalLine: (v) => FlLine(color: kColorDivider, strokeWidth: 0.5),
            getDrawingVerticalLine: (v) => FlLine(color: kColorDivider, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= labels.length) return const SizedBox();
                  if (labels.length > 10 && index % 2 != 0 && index != labels.length -1 && index != 0) return const SizedBox();
                  
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(labels[index], style: axisLabelStyle),
                    space: 8.0,
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                interval: yInterval > 0 ? yInterval : null,
                getTitlesWidget: (double value, TitleMeta meta) {
                  return Text(
                    value.toStringAsFixed(isWeightChart ? 1 : 0),
                    style: axisLabelStyle,
                    textAlign: TextAlign.left,
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: true, border: Border.all(color: kColorBorder)),
          lineBarsData: [
            LineChartBarData(
              spots: data,
              isCurved: true,
              curveSmoothness: 0.4,
              color: kChartLineColor,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: data.length <= 15,
                getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                  radius: 3,
                  color: kChartLineColor,
                  strokeWidth: 1,
                  strokeColor: kColorSurface
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                      kChartLineGradientStart.withOpacity(kChartLineGradientStart.opacity * animationValue),
                      kChartLineGradientEnd.withOpacity(kChartLineGradientEnd.opacity * animationValue)
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              shadow: Shadow(
                color: kChartLineColor.withOpacity(0.3 * animationValue),
                blurRadius: 8,
                offset: const Offset(0, 4)
              ),
            ),
            if (recommendedData.isNotEmpty)
              LineChartBarData(
                spots: recommendedData,
                isCurved: true,
                curveSmoothness: 0.4,
                color: kChartGuideLineColor.withOpacity(0.8),
                barWidth: 1.5,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                dashArray: [5, 5],
                belowBarData: BarAreaData(show: false),
              ),
          ],
        ),
      ),
    );
   }

   Widget _buildLegendWidget(Map<String, double> data, TextStyle legendLabelStyle) {
      final List<Color> macroColors = [kColorWarningHigh, kColorPositiveOrTarget, kColorPrimaryLight];
      final List<Color> cuisineColors = [kColorPrimary, kColorPrimaryLight, kColorTextSecondary, kColorPrimaryLighter];
      
      bool isMacro = data.keys.any((k) => k.toLowerCase().contains('protein') || k.toLowerCase().contains('carb') || k.toLowerCase().contains('fat'));
      final List<Color> colorsToUse = isMacro ? macroColors : cuisineColors;

      int ci = 0; 
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: data.entries.map((e) {
          final lc = colorsToUse[ci++ % colorsToUse.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: lc, shape: BoxShape.circle),
                  margin: const EdgeInsets.only(right: 8),
                ),
                Flexible(
                  child: Text(
                    '${e.key} (${e.value.toStringAsFixed(0)}%)',
                    style: legendLabelStyle,
                    overflow: TextOverflow.ellipsis
                  )
                ),
              ],
            ),
          );
        }).toList(),
      );
   }
}

class WeeklyMealTrendChart extends StatelessWidget {
  final List<int> mealsPerDay;
  final double animationProgress;
  final TextStyle axisLabelStyle;

  const WeeklyMealTrendChart({
    super.key,
    required this.mealsPerDay,
    required this.animationProgress,
    required this.axisLabelStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (mealsPerDay.isEmpty) {
      return SizedBox(height: 200, child: Center(child: Text("No meal data", style: axisLabelStyle)));
    }
    final barColor = kChartBarColor;
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].sublist(0, mealsPerDay.length);
    final maxValue = mealsPerDay.isEmpty ? 1.0 : (mealsPerDay.reduce(max) + 1).toDouble();
    
    final tooltipTextStyle = GoogleFonts.poppins(color: kChartTooltipText, fontSize: 11);
    final tooltipBoldTextStyle = tooltipTextStyle.copyWith(fontWeight: FontWeight.bold);

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => kChartTooltipBg,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (group.x.toInt() >= days.length) return null;
                final day = days[group.x.toInt()];
                final value = mealsPerDay[group.x.toInt()];
                return BarTooltipItem(
                  '$day\n',
                  tooltipBoldTextStyle,
                  children: [TextSpan(text: '$value Meal${value==1 ? "" : "s"}', style: tooltipTextStyle)],
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response != null && response.spot != null) {
                final dayIndex = response.spot!.touchedBarGroupIndex;
                if (dayIndex >= mealsPerDay.length) return;
                final meals = mealsPerDay[dayIndex];
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('You logged $meals meal${meals==1 ? "" : "s"} on ${days[dayIndex]}',
                        style: GoogleFonts.poppins(color: kColorTextPrimary, fontSize: 12)),
                    duration: const Duration(seconds: 2),
                    backgroundColor: kColorSurface,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                );
              }
            },
          ),
          barGroups: mealsPerDay.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.toDouble() * animationProgress,
                  color: barColor,
                  width: 22,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(6),
                    topRight: Radius.circular(6)
                  ),
                  borderSide: entry.value == 0 && animationProgress == 1.0 // Add border only when value is 0 and animation is complete
                      ? BorderSide(color: kColorPrimaryLight, width: 1.0)
                      : BorderSide.none,
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxValue,
                    color: kColorBackground.withOpacity(0.5),
                  ),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= days.length) return const SizedBox();
                  return SideTitleWidget(
                    meta: meta,
                    space: 4.0,
                    child: Text(days[index], style: axisLabelStyle),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: max(1.0, (maxValue / 5).floorToDouble()),
            getDrawingHorizontalLine: (value) => FlLine(color: kColorDivider.withOpacity(0.5), strokeWidth: 1),
          ),
        ),
      ),
    );
  }
}

abstract class BasePieChart extends StatelessWidget {
  final Map<String, double> data;
  final double animationProgress;
  const BasePieChart({
    super.key,
    required this.data,
    required this.animationProgress,
  });
  List<Color> get chartColors;
  
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(child: Text("No data", style: GoogleFonts.poppins(fontSize: 12, color: kColorTextSecondary)));
    }
    int ci = 0;
    final labelStyle = GoogleFonts.poppins(
      fontSize: 10,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      shadows: [const Shadow(color: Colors.black54, blurRadius: 2)],
    );

    final totalValue = data.values.fold(0.0, (sum, item) => sum + item);
    if (totalValue == 0 && data.isNotEmpty) return Center(child: Text("Data sum is zero", style: labelStyle.copyWith(color: kColorTextSecondary)));


    return SizedBox(
      height: 200,
      width: 200,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: animationProgress > 0.5 ? 40 - (20 * (1-animationProgress)) : (40 * animationProgress),
          startDegreeOffset: -90,
          sections: data.entries.map((entry) {
            final sc = chartColors[ci++ % chartColors.length];
            final percentage = totalValue == 0 ? 0 : (entry.value / totalValue) * 100 * animationProgress;
            return PieChartSectionData(
              value: entry.value * animationProgress,
              title: percentage > 5 ? '${percentage.toStringAsFixed(0)}%' : '',
              color: sc,
              radius: 90 - (20 * (1-animationProgress)),
              titleStyle: labelStyle,
              borderSide: BorderSide(color: Colors.white.withOpacity(0.5), width: 0.5),
            );
          }).toList(),
        ),
        swapAnimationDuration: const Duration(milliseconds: 250),
        swapAnimationCurve: Curves.easeInOutCubic,
      ),
    );
  }
}

class PopularCuisinesChart extends BasePieChart {
  const PopularCuisinesChart({
    super.key, 
    required Map<String, double> data, 
    required double animationProgress
  }) : super(data: data, animationProgress: animationProgress);
  
  @override
  List<Color> get chartColors => [
    kColorPrimary, 
    kColorPrimaryLight, 
    kColorTextSecondary,
    kColorPrimaryLighter
  ];
}

class MacronutrientBreakdownChart extends BasePieChart {
  const MacronutrientBreakdownChart({
    super.key,
    required Map<String, double> data,
    required double animationProgress
  }) : super(data: data, animationProgress: animationProgress);

  @override
  List<Color> get chartColors => [
    kColorWarningHigh,
    kColorPositiveOrTarget,
    kColorPrimaryLight,
  ];
}

class MetricCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color color;
  final TextStyle labelStyle;
  
  const MetricCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    required this.color,
    required this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: kColorSurface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: kColorPrimaryLighter.withOpacity(0.2),
            blurRadius: 5,
            offset: const Offset(0, 2),
          )
        ],
        border: Border.all(color: kColorBorder.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            title,
            style: labelStyle,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: child,
          ),
        ],
      ),
    );
  }
}
