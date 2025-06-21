import 'dart:async';
import 'dart:convert';
import 'dart:math'; // For max(), min()
import 'package:collection/collection.dart'; // For firstWhereOrNull, whereNotNull

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // For .env
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http; // For API calls
import 'package:shared_preferences/shared_preferences.dart'; // For user_id
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter/widgets.dart'; // For RouteAware, RouteObserver
import 'package:zinzi/app_drawer_unified.dart'; // Unified app drawer for navigation

// Create a RouteObserver instance at the top level
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// --- Constants ---
const Duration kAnimationDuration = Duration(milliseconds: 1200);
const Curve kAnimationCurve = Curves.easeOutCubic;

const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorPrimaryLighter = Color(0xFFB2DFDB);
const Color kColorPrimaryLightest = Color(0xFFE0F2F1);
const Color kColorBackground = Color(0xFFF8F8F8); // Scaffold background
const Color kColorSurface = Colors.white; // Card backgrounds, etc.
const Color kColorTextPrimary = kColorPrimaryDark;
const Color kColorTextSecondary = Color(0xFF546E7A);
const Color kColorTextOnPrimary =
    Colors.white; // Text on kColorPrimary/kColorPrimaryDark
const Color kColorTextOnSurface = kColorTextPrimary; // Text on kColorSurface
const Color kColorBorder = kColorPrimaryLighter;
const Color kColorDivider = Color(0xFFE0E0E0);
const Color kColorWarningHigh = Color(0xFFFFA000);
const Color kColorWarningLow = Color(0xFF00B0FF);
const Color kColorNegative = Color(0xFFFF5252);
const Color kColorPositiveOrTarget = Color(0xFF00E676);

// Chart specific colors
const Color kChartLineColor = kColorPrimaryLight;
const Color kChartLineGradientStart = Color(0x554DB6AC);
const Color kChartLineGradientEnd = Color(0x004DB6AC);
const Color kChartGuideLineColor = kColorTextSecondary;
const Color kChartBarColor = kColorPrimary;
const Color kChartTooltipBg = Color(0xEE333333);
const Color kColorTooltipText = Colors.white;

// --- API Constants ---
final String apiBaseUrl =
    dotenv.env['API_BASE_URL'] ?? 'https://your.default.api.url/if/not/loaded';
const String kEndpointPath = '/rr/users/';
const String kCombinedMetricsEndpoint = 'combined_metrics';
const int kDefaultLimit = 30;

// --- Data Models ---
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
      caloriesHistory: List<Map<String, dynamic>>.from(
          json['calories_history'] as List<dynamic>? ?? []),
      weightHistory: List<Map<String, dynamic>>.from(
          json['weight_history'] as List<dynamic>? ?? []),
      lastUpdated:
          json['last_updated'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}

// --- Main Dashboard Widget ---
class UserAnalyticsDashboard extends StatefulWidget {
  const UserAnalyticsDashboard({super.key});
  @override
  _UserAnalyticsDashboardState createState() => _UserAnalyticsDashboardState();
}

class _UserAnalyticsDashboardState extends State<UserAnalyticsDashboard>
    with TickerProviderStateMixin, RouteAware {
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
  bool _isLoading = true; // <<< CHANGE: For initial full-screen load
  bool _isRefreshing = false; // <<< CHANGE: For the "Refreshing..." banner
  String? _error;

  // Weight update dialog controllers
  final TextEditingController _weightController = TextEditingController();
  String _weightUnit = 'kg'; // Default to kg
  double _weightKg = 0.0;
  bool _isUpdatingWeight = false;

  // Macros tracking state
  Map<String, double> macroData = {
    'Protein': 0,
    'Carbs': 0,
    'Fats': 0,
  };
  final Map<String, double> macroGoals = {
    'Protein': 0,
    'Carbs': 0,
    'Fats': 0,
  };
  Map<String, double> aggregatedMacroGrams = {
    'Protein': 0,
    'Carbs': 0,
    'Fats': 0,
  };
  String _selectedMacroPeriod = 'D';
  late DateTimeRange _macroDateRange;

  // Static data for demonstration
  final Map<String, double> cuisineData = {'African': 99, 'Chinese': 1};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _macroDateRange = DateTimeRange(
      start: today,
      end: today.add(const Duration(days: 1)),
    );

    // Initialize weight controller
    _weightController.addListener(_parseAndUpdateWeight);

    // Initial animations with placeholder data
    _setupMetricsAnimations(mealsLogged: 0, avgCalories: 0, weightChange: 0.0);

    // Trigger the initial data fetch
    _fetchData(isInitialLoad: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes when the widget is mounted
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    // <<< CHANGE: Called when returning to this page. Fetches fresh data.
    _fetchData();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _metricsController.dispose();
    _summaryTimer?.cancel();
    _weightController.removeListener(_parseAndUpdateWeight);
    _weightController.dispose();
    super.dispose();
  }

  // <<< CHANGE: Unified method to fetch data and manage loading/refreshing states.
  Future<void> _fetchData({bool isInitialLoad = false}) async {
    // Prevent multiple concurrent fetches.
    if (!mounted || _isRefreshing) return;

    setState(() {
      // Use the full-screen loader only on the first load or if there's no data.
      if (isInitialLoad || _metricsData == null) {
        _isLoading = true;
      } else {
        // Otherwise, show the non-blocking "refreshing" banner.
        _isRefreshing = true;
      }
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '1';
      final int userIdInt = int.tryParse(userId) ?? 1;

      if (userIdInt <= 0) {
        throw Exception('Invalid user_id: $userId');
      }

      final url = Uri.parse(
          '$apiBaseUrl$kEndpointPath$userIdInt/$kCombinedMetricsEndpoint?limit=$kDefaultLimit');
      final response = await http.get(url);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        setState(() {
          _metricsData = CombinedMetrics.fromJson(data);
          // With new data, update all dependent UI components.
          _updateAnimationsWithApiData();
          _calculateMacroGoals();
          _aggregateMacronutrients(_metricsData!.caloriesHistory);
          _startOrUpdateSummaryTimer();
        });
      } else {
        throw Exception(
            'Failed to fetch metrics (Status: ${response.statusCode})');
      }
    } catch (e, s) {
      print('Error fetching data: $e\n$s');
      if (mounted) {
        setState(() {
          _error = 'Error fetching data. Check connection/config.';
        });
      }
    } finally {
      // No matter the outcome, always turn off loading indicators.
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  // --- Macronutrient and Meal Logic ---
  void _aggregateMacronutrients(List<Map<String, dynamic>>? caloriesHistory) {
    if (caloriesHistory == null) return;

    double totalProteinGrams = 0;
    double totalCarbsGrams = 0;
    double totalFatsGrams = 0;

    for (final entry in caloriesHistory) {
      final String? dateString = entry['logged_at'] as String?;
      if (dateString == null) continue;

      final DateTime? entryDateUtc = DateTime.tryParse(dateString);
      if (entryDateUtc == null) continue;

      final DateTime entryDateLocal = entryDateUtc.toLocal();

      if (_isDateInRange(entryDateLocal, _macroDateRange)) {
        final caloriesData = entry['calories'] as Map<String, dynamic>?;
        if (caloriesData == null) continue;

        final nutritionalInfo =
            caloriesData['nutritional_info'] as Map<String, dynamic>?;
        if (nutritionalInfo == null) continue;

        totalProteinGrams +=
            (nutritionalInfo['proteins'] as num?)?.toDouble() ?? 0.0;
        totalCarbsGrams +=
            (nutritionalInfo['carbohydrates'] as num?)?.toDouble() ?? 0.0;
        totalFatsGrams += (nutritionalInfo['fats'] as num?)?.toDouble() ?? 0.0;
      }
    }

    // Calculate percentages for the pie chart based on calories
    final double totalProteinCalories = totalProteinGrams * 4;
    final double totalCarbsCalories = totalCarbsGrams * 4;
    final double totalFatsCalories = totalFatsGrams * 9;
    final double totalCalories =
        totalProteinCalories + totalCarbsCalories + totalFatsCalories;

    double proteinPercent = 0.0;
    double carbsPercent = 0.0;
    double fatsPercent = 0.0;

    if (totalCalories > 0) {
      proteinPercent = (totalProteinCalories / totalCalories) * 100;
      carbsPercent = (totalCarbsCalories / totalCalories) * 100;
      fatsPercent = (totalFatsCalories / totalCalories) * 100;
    }

    if (mounted) {
      setState(() {
        // Store the raw grams for comparison
        aggregatedMacroGrams = {
          'Protein': totalProteinGrams,
          'Carbs': totalCarbsGrams,
          'Fats': totalFatsGrams,
        };
        // Store percentages for the pie chart
        macroData = {
          'Protein': proteinPercent,
          'Carbs': carbsPercent,
          'Fats': fatsPercent,
        };
      });
    }
  }

  bool _isDateInRange(DateTime date, DateTimeRange range) {
    return !date.isBefore(range.start) && date.isBefore(range.end);
  }

  void _calculateMacroGoals() {
    if (_metricsData == null) return;

    final dailyCalories =
        (_metricsData!.metrics['daily_calories'] as num?)?.toDouble() ?? 2000.0;
    final goal = _metricsData!.preferences['goal'] as String? ?? 'Maintenance';

    double proteinRatio;
    double carbsRatio;
    double fatsRatio;

    switch (goal) {
      case 'Weight Loss':
        proteinRatio = 0.40; // 40%
        carbsRatio = 0.30; // 30%
        fatsRatio = 0.30; // 30%
        break;
      case 'Muscle Gain':
        proteinRatio = 0.30; // 30%
        carbsRatio = 0.50; // 50%
        fatsRatio = 0.20; // 20%
        break;
      case 'Maintenance':
      default:
        proteinRatio = 0.30; // 30%
        carbsRatio = 0.40; // 40%
        fatsRatio = 0.30; // 30%
        break;
    }

    final proteinCalories = dailyCalories * proteinRatio;
    final carbsCalories = dailyCalories * carbsRatio;
    final fatsCalories = dailyCalories * fatsRatio;

    if (mounted) {
      setState(() {
        macroGoals['Protein'] = proteinCalories / 4; // 4 calories per gram
        macroGoals['Carbs'] = carbsCalories / 4; // 4 calories per gram
        macroGoals['Fats'] = fatsCalories / 9; // 9 calories per gram
      });
    }
  }

  String _getMacroSummaryMessage() {
    final goal = _metricsData?.preferences['goal'] as String? ?? 'Maintenance';
    final String goalPrefix = 'Your goal is to **$goal**. ';

    if (aggregatedMacroGrams.values.every((v) => v == 0)) {
      return '${goalPrefix}Log your meals to see your macronutrient breakdown.';
    }

    final numDaysInPeriod = _macroDateRange.duration.inDays;
    if (numDaysInPeriod < 1) {
      return '${goalPrefix}An error occurred calculating your daily average.';
    }

    // Get average daily consumption in grams
    final avgProteinGrams = aggregatedMacroGrams['Protein']! / numDaysInPeriod;
    final avgCarbsGrams = aggregatedMacroGrams['Carbs']! / numDaysInPeriod;
    final avgFatsGrams = aggregatedMacroGrams['Fats']! / numDaysInPeriod;

    // Compare average daily grams to daily goal grams
    final proteinRatio = macroGoals['Protein']! > 0
        ? avgProteinGrams / macroGoals['Protein']!
        : 0;
    final carbsRatio =
        macroGoals['Carbs']! > 0 ? avgCarbsGrams / macroGoals['Carbs']! : 0;
    final fatsRatio =
        macroGoals['Fats']! > 0 ? avgFatsGrams / macroGoals['Fats']! : 0;

    String baseMessage;

    // Thresholds for advice
    const double lowThreshold = 0.85;
    const double highThreshold = 1.15;

    switch (goal) {
      case 'Weight Loss':
        if (proteinRatio < lowThreshold) {
          baseMessage =
              'To support weight loss, try increasing your protein. It helps preserve muscle and keeps you feeling full.';
        } else if (carbsRatio > highThreshold) {
          baseMessage =
              'For effective weight loss, consider reducing carbohydrate intake and focusing on high-fiber sources.';
        } else if (fatsRatio > highThreshold) {
          baseMessage =
              'Healthy fats are important, but keeping them in check can help with your calorie deficit for weight loss.';
        } else {
          baseMessage =
              'Your macronutrient balance is well-aligned with your weight loss goal. Great job!';
        }
        break;

      case 'Muscle Gain':
        if (proteinRatio < lowThreshold) {
          baseMessage =
              'To build muscle effectively, boosting your protein intake is essential. Aim for your daily protein goal.';
        } else if (carbsRatio < lowThreshold) {
          baseMessage =
              'Carbohydrates are crucial for energy during workouts. Increasing complex carbs will help fuel your muscle-building sessions.';
        } else if (proteinRatio > highThreshold && carbsRatio > highThreshold) {
          baseMessage =
              'You\'re eating plenty for muscle gain! Ensure your workouts are intense enough to utilize the extra energy.';
        } else {
          baseMessage =
              'Your macros look good for muscle gain. Keep fueling your body and training hard!';
        }
        break;

      case 'Maintenance':
      default:
        if (proteinRatio < lowThreshold) {
          baseMessage =
              'Your protein seems a bit low. A balanced intake helps with overall body function and repair.';
        } else if (carbsRatio > highThreshold || fatsRatio > highThreshold) {
          baseMessage =
              'Your intake seems a bit high in carbs or fats. A balanced diet is key for long-term health maintenance.';
        } else {
          baseMessage =
              'Your macronutrient balance looks great for maintaining your physique. Keep up the good work!';
        }
        break;
    }

    return goalPrefix + baseMessage;
  }

  // Helper to build the rich text for the summary container
  Widget _buildRichTextSummary(String message, IconData icon) {
    List<String> parts = message.split('**');
    final normalStyle = GoogleFonts.poppins(
        color: kColorPrimaryDark, fontWeight: FontWeight.w500, fontSize: 13.0);
    final boldStyle = normalStyle.copyWith(fontWeight: FontWeight.bold);

    return Container(
      decoration: BoxDecoration(
          color: kColorPrimaryLightest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kColorPrimaryLighter.withOpacity(0.8))),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Row(
        children: [
          Icon(icon, size: 18.0, color: kColorPrimary),
          const SizedBox(width: 8.0),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: normalStyle,
                children: [
                  for (int i = 0; i < parts.length; i++)
                    TextSpan(
                      text: parts[i],
                      style: i % 2 == 1 ? boldStyle : normalStyle,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI and Charting Logic ---

  void _setupMetricsAnimations(
      {required double mealsLogged,
      required double avgCalories,
      required double weightChange}) {
    _metricsController =
        AnimationController(duration: kAnimationDuration, vsync: this);
    final curvedMetricsAnimation =
        CurvedAnimation(parent: _metricsController, curve: kAnimationCurve);
    _mealsAnimation = Tween<double>(begin: 0, end: mealsLogged)
        .animate(curvedMetricsAnimation);
    _caloriesAnimation = Tween<double>(begin: 0, end: avgCalories)
        .animate(curvedMetricsAnimation);
    _weightAnimation = Tween<double>(begin: 0, end: weightChange)
        .animate(curvedMetricsAnimation);
    _metricsController.forward();
  }

  double _calculateWeightChange(List<Map<String, dynamic>> weightHistory) {
    if (weightHistory.length < 2) return 0.0;
    var sortedHistory = List<Map<String, dynamic>>.from(weightHistory);
    sortedHistory.sort((a, b) => DateTime.parse(b['logged_at'] as String)
        .compareTo(DateTime.parse(a['logged_at'] as String)));
    final latestWeight = (sortedHistory[0]['weight'] as num?)?.toDouble();
    final previousWeight = (sortedHistory[1]['weight'] as num?)?.toDouble();
    if (latestWeight != null && previousWeight != null) {
      return latestWeight - previousWeight;
    }
    return 0.0;
  }

  void _updateAnimationsWithApiData() {
    if (_metricsData == null || !mounted) return;
    if (_metricsController.isAnimating ||
        _metricsController.isCompleted ||
        _metricsController.isDismissed) {
      _metricsController.dispose();
    }
    final dailyMealCounts = _aggregateDataByPeriod(
        _metricsData!.caloriesHistory,
        'logged_at',
        'calories',
        null,
        7,
        const Duration(days: 1),
        average: false,
        countEntries: true);
    final double weeklyMealsLogged =
        dailyMealCounts.fold(0.0, (sum, count) => sum + count);
    final double averageWeeklyCalories = _getAverageCaloriesOverDuration(
        _metricsData!.caloriesHistory, const Duration(days: 7));
    final double calculatedWeightChange =
        _calculateWeightChange(_metricsData!.weightHistory);
    _setupMetricsAnimations(
        mealsLogged: weeklyMealsLogged,
        avgCalories: averageWeeklyCalories,
        weightChange: calculatedWeightChange);
  }

  List<double> _getTypedHistoryValues(
      List<Map<String, dynamic>> history, String valueKey,
      [String? nestedKey]) {
    return history.map((item) {
      dynamic value = item[valueKey];
      if (nestedKey != null && value is Map) {
        value = value[nestedKey];
      }
      return (value as num?)?.toDouble() ?? 0.0;
    }).toList();
  }

  List<double> _aggregateDataByPeriod(
      List<Map<String, dynamic>> historyData,
      String dateKey,
      String valueKey,
      String? nestedValueKey,
      int numPeriods,
      Duration periodDuration,
      {bool average = false,
      bool countEntries = false}) {
    if (historyData.isEmpty) return List.filled(numPeriods, 0.0);
    List<double> aggregatedValues = List.filled(numPeriods, 0.0);
    final now = DateTime.now().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    for (int i = 0; i < numPeriods; i++) {
      DateTime periodStart;
      DateTime periodEnd;
      if (periodDuration.inDays == 1) {
        periodStart = today.subtract(Duration(days: numPeriods - 1 - i));
        periodEnd = periodStart.add(const Duration(days: 1));
      } else if (periodDuration.inDays == 7) {
        periodStart = today.subtract(Duration(days: numPeriods - 1 - i));
        periodEnd = periodStart.add(const Duration(days: 1));
      } else if (periodDuration.inDays >= 28) {
        periodStart = DateTime(now.year, now.month - (numPeriods - 1 - i), 1);
        periodEnd = DateTime(periodStart.year, periodStart.month + 1, 1);
      } else {
        periodStart = today.subtract(Duration(days: (numPeriods - 1 - i) * 7));
        periodEnd = periodStart.add(const Duration(days: 7));
      }
      final periodStartUtc = periodStart.toUtc();
      final periodEndUtc = periodEnd.toUtc();
      final entriesForPeriod = historyData.where((entry) {
        try {
          final entryDateUtc = DateTime.parse(entry[dateKey] as String).toUtc();
          return !entryDateUtc.isBefore(periodStartUtc) &&
              entryDateUtc.isBefore(periodEndUtc);
        } catch (e) {
          return false;
        }
      }).toList();
      if (entriesForPeriod.isNotEmpty) {
        if (countEntries) {
          aggregatedValues[i] = entriesForPeriod.length.toDouble();
        } else {
          final values = _getTypedHistoryValues(
              entriesForPeriod, valueKey, nestedValueKey);
          if (values.isNotEmpty) {
            final sum = values.fold(0.0, (prev, element) => prev + element);
            aggregatedValues[i] = average ? sum / values.length : sum;
          }
        }
      }
    }
    return aggregatedValues;
  }

  List<double> _aggregateLastWeightByPeriod(
      List<Map<String, dynamic>> historyData,
      String dateKey,
      String valueKey,
      int numPeriods,
      Duration periodDuration) {
    if (historyData.isEmpty) return List.filled(numPeriods, 0.0);
    var sortedHistory = List<Map<String, dynamic>>.from(historyData);
    sortedHistory.sort((a, b) => DateTime.parse(a[dateKey] as String)
        .compareTo(DateTime.parse(b[dateKey] as String)));
    List<double?> aggregatedValues = List.filled(numPeriods, null);
    final now = DateTime.now().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    DateTime firstPeriodStartForView = now;
    for (int i = 0; i < numPeriods; i++) {
      DateTime periodStart;
      DateTime periodEnd;
      if (periodDuration.inDays == 1) {
        periodStart = today.subtract(Duration(days: numPeriods - 1 - i));
        periodEnd = periodStart.add(const Duration(days: 1));
      } else if (periodDuration.inDays >= 28) {
        periodStart = DateTime(now.year, now.month - (numPeriods - 1 - i), 1);
        periodEnd = DateTime(periodStart.year, periodStart.month + 1, 1);
      } else {
        periodStart = today.subtract(
            Duration(days: (numPeriods - 1 - i) * periodDuration.inDays));
        periodEnd = periodStart.add(periodDuration);
      }
      if (i == 0) firstPeriodStartForView = periodStart;
      final lastEntryForPeriod = sortedHistory.lastWhereOrNull((entry) {
        final entryDate = DateTime.parse(entry[dateKey] as String).toLocal();
        return !entryDate.isBefore(periodStart) &&
            entryDate.isBefore(periodEnd);
      });
      if (lastEntryForPeriod != null) {
        aggregatedValues[i] =
            (lastEntryForPeriod[valueKey] as num?)?.toDouble();
      }
    }
    double? lastKnownWeight;
    final lastEntryBeforeView = sortedHistory.lastWhereOrNull((entry) {
      final entryDate = DateTime.parse(entry[dateKey] as String).toLocal();
      return entryDate.isBefore(firstPeriodStartForView);
    });
    if (lastEntryBeforeView != null) {
      lastKnownWeight = (lastEntryBeforeView[valueKey] as num?)?.toDouble();
    }
    for (int i = 0; i < aggregatedValues.length; i++) {
      if (aggregatedValues[i] != null) {
        lastKnownWeight = aggregatedValues[i];
      } else {
        aggregatedValues[i] = lastKnownWeight;
      }
    }
    return aggregatedValues.map((w) => w ?? 0.0).toList();
  }

  List<double> _getCaloriesData(String view) {
    if (_metricsData == null || _metricsData!.caloriesHistory.isEmpty)
      return List.filled(
          view == 'D'
              ? 24
              : view == 'W'
                  ? 7
                  : view == 'M'
                      ? 4
                      : 6,
          0.0);
    const String outerCaloriesKey = "calories";
    const String innerCaloriesKey = "calories";
    final now = DateTime.now();
    switch (view) {
      case 'D':
        final todayStart = DateTime(now.year, now.month, now.day);
        final todayEnd = todayStart.add(const Duration(days: 1));
        final todayEntries = _metricsData!.caloriesHistory.where((entry) {
          try {
            final entryDate =
                DateTime.parse(entry['logged_at'] as String).toLocal();
            return entryDate.isAfter(todayStart) &&
                entryDate.isBefore(todayEnd);
          } catch (e) {
            return false;
          }
        }).toList();
        final hourlyData = List<double>.filled(24, 0.0);
        for (var entry in todayEntries) {
          try {
            final entryDate =
                DateTime.parse(entry['logged_at'] as String).toLocal();
            final hour = entryDate.hour;
            final calories = (entry[outerCaloriesKey] is Map
                ? (entry[outerCaloriesKey]
                    as Map<String, dynamic>)[innerCaloriesKey]
                : entry[outerCaloriesKey]) as num?;
            if (calories != null) hourlyData[hour] += calories.toDouble();
          } catch (e) {
            continue;
          }
        }
        return hourlyData;
      case 'W':
        return _aggregateDataByPeriod(
            _metricsData!.caloriesHistory,
            'logged_at',
            outerCaloriesKey,
            innerCaloriesKey,
            7,
            const Duration(days: 1));
      case 'M':
        return _aggregateDataByPeriod(
            _metricsData!.caloriesHistory,
            'logged_at',
            outerCaloriesKey,
            innerCaloriesKey,
            4,
            const Duration(days: 7));
      case '6M':
        return _aggregateDataByPeriod(
            _metricsData!.caloriesHistory,
            'logged_at',
            outerCaloriesKey,
            innerCaloriesKey,
            6,
            const Duration(days: 30));
      default:
        return List.filled(24, 0.0);
    }
  }

  List<double> _getWeightData(String view) {
    if (_metricsData == null || _metricsData!.weightHistory.isEmpty)
      return List.filled(
          view == 'D'
              ? 24
              : view == 'W'
                  ? 7
                  : view == 'M'
                      ? 4
                      : 6,
          0.0);
    const String weightKey = "weight";
    final now = DateTime.now();
    switch (view) {
      case 'D':
        final todayStart = DateTime(now.year, now.month, now.day);
        final todayEnd = todayStart.add(const Duration(days: 1));
        final todayEntries = _metricsData!.weightHistory.where((entry) {
          try {
            final entryDate =
                DateTime.parse(entry['logged_at'] as String).toLocal();
            return entryDate.isAfter(todayStart) &&
                entryDate.isBefore(todayEnd);
          } catch (e) {
            return false;
          }
        }).toList();
        final hourlyWeights = List<double?>.filled(24, null);
        for (var entry in todayEntries) {
          try {
            final entryDate =
                DateTime.parse(entry['logged_at'] as String).toLocal();
            final hour = entryDate.hour;
            final weight = entry[weightKey] as num?;
            if (weight != null) hourlyWeights[hour] = weight.toDouble();
          } catch (e) {
            continue;
          }
        }
        double? lastWeight;
        return hourlyWeights.map((weight) {
          if (weight != null) lastWeight = weight;
          return lastWeight ?? 0.0;
        }).toList();
      case 'W':
        return _aggregateLastWeightByPeriod(_metricsData!.weightHistory,
            'logged_at', weightKey, 7, const Duration(days: 1));
      case 'M':
        return _aggregateLastWeightByPeriod(_metricsData!.weightHistory,
            'logged_at', weightKey, 4, const Duration(days: 7));
      case '6M':
        return _aggregateLastWeightByPeriod(_metricsData!.weightHistory,
            'logged_at', weightKey, 6, const Duration(days: 30));
      default:
        return List.filled(24, 0.0);
    }
  }

  double _getAverageCaloriesOverDuration(
      List<Map<String, dynamic>> historyData, Duration duration) {
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
    return entriesInPeriod.length > 0
        ? totalCalories / entriesInPeriod.length
        : 0.0;
  }

  double _getRecommendedValueForView(String view,
      {required bool isWeightChart}) {
    if (isWeightChart) {
      return double.tryParse(
              (_metricsData?.metrics['ideal_weight'] as String?) ?? '0') ??
          70.0;
    } else {
      final dailyCalories =
          (_metricsData?.metrics['daily_calories'] as num?)?.toDouble() ??
              2000.0;
      switch (view) {
        case 'D':
          return dailyCalories;
        case 'W':
          return dailyCalories;
        case 'M':
          return dailyCalories * 7;
        case '6M':
          return dailyCalories * 30;
        default:
          return dailyCalories;
      }
    }
  }

  // Helper getters for chart data
  List<double> get currentActualCalories =>
      _getCaloriesData(_selectedCalorieView);
  List<double> get currentActualWeight => _getWeightData(_selectedWeightView);
  List<FlSpot> get currentCalorieIntakeSpots =>
      _generateSpots(currentActualCalories);
  List<String> get currentCalorieLabels =>
      _getLabelsForView(_selectedCalorieView, currentActualCalories.length);
  List<FlSpot> get currentWeightProgressSpots =>
      _generateSpots(currentActualWeight);
  List<String> get currentWeightLabels =>
      _getLabelsForView(_selectedWeightView, currentActualWeight.length);

  List<FlSpot> get currentRecommendedCalorieSpots {
    final labels = currentCalorieLabels;
    if (labels.isEmpty) return [];
    final double maxX = (labels.length - 1).toDouble();
    final double yValue =
        _getRecommendedValueForView(_selectedCalorieView, isWeightChart: false);
    return [FlSpot(0, yValue), FlSpot(maxX, yValue)];
  }

  List<FlSpot> get currentRecommendedWeightSpots {
    final labels = currentWeightLabels;
    if (labels.isEmpty) return [];
    final double maxX = (labels.length - 1).toDouble();
    final double yValue =
        _getRecommendedValueForView(_selectedWeightView, isWeightChart: true);
    return [FlSpot(0, yValue), FlSpot(maxX, yValue)];
  }

  void _startOrUpdateSummaryTimer() {
    _summaryTimer?.cancel();
    _updateCalorieSummary();
    if ((_selectedCalorieView == 'D' || _selectedCalorieView == 'W') &&
        currentActualCalories.isNotEmpty) {
      _summaryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted && currentActualCalories.isNotEmpty) {
          setState(() {
            _currentDayIndex =
                (_currentDayIndex + 1) % currentActualCalories.length;
            _calorieSummaryMessage =
                _getCalorieSummaryMessage(_currentDayIndex);
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
      if (currentActualCalories.isEmpty) {
        _calorieSummaryMessage = "Summary data unavailable.";
      } else if (_selectedCalorieView == 'D' || _selectedCalorieView == 'W') {
        _calorieSummaryMessage = _getCalorieSummaryMessage(_currentDayIndex);
      } else {
        _calorieSummaryMessage =
            _getAggregateSummaryMessage(_selectedCalorieView);
      }
    });
  }

  String _getCalorieSummaryMessage(int dayIndex) {
    final labels =
        _getLabelsForView(_selectedCalorieView, currentActualCalories.length);
    final recommended =
        _getRecommendedValueForView(_selectedCalorieView, isWeightChart: false);
    if (dayIndex < 0 ||
        dayIndex >= currentActualCalories.length ||
        dayIndex >= labels.length) return "Summary unavailable.";
    double actual = currentActualCalories[dayIndex];
    double calorieDiff = actual - recommended;
    String label = labels[dayIndex];
    if (calorieDiff == 0)
      return 'You hit your calorie target on $label! 🎉';
    else if (calorieDiff > 0)
      return 'Consumed ${calorieDiff.toStringAsFixed(0)} kcal more than recommended on $label.';
    else
      return 'Consumed ${(-calorieDiff).toStringAsFixed(0)} kcal less than recommended on $label.';
  }

  String _getAggregateSummaryMessage(String view) {
    if (currentActualCalories.isEmpty) return "Summary unavailable.";
    double sumActual = currentActualCalories.fold(0.0, (a, b) => a + b);
    double avgActual = sumActual / currentActualCalories.length;
    double avgRecommended =
        _getRecommendedValueForView(view, isWeightChart: false);
    double avgDiff = avgActual - avgRecommended;
    String period;
    switch (view) {
      case 'M':
        period = 'the last month (avg weekly)';
        break;
      case '6M':
        period = 'the last 6 months (avg monthly)';
        break;
      default:
        period = 'the selected period';
    }
    if (avgDiff.abs() < (avgRecommended * 0.05))
      return 'Your average intake was close to recommended over $period.';
    else if (avgDiff > 0)
      return 'On average, you consumed ${avgDiff.toStringAsFixed(0)} kcal more than recommended over $period.';
    else
      return 'On average, you consumed ${(-avgDiff).toStringAsFixed(0)} kcal less than recommended over $period.';
  }

  List<String> _getLabelsForView(String view, int dataLength) {
    final today = DateTime.now().toLocal();
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    switch (view) {
      case 'D':
        return List.generate(
            24, (h) => '${h % 12 == 0 ? 12 : h % 12}${h >= 12 ? 'PM' : 'AM'}');
      case 'W':
        return List.generate(
            7,
            (i) =>
                '${dayNames[today.subtract(Duration(days: 6 - i)).weekday - 1]} ${today.subtract(Duration(days: 6 - i)).day}');
      case 'M':
        return List.generate(
            4,
            (i) =>
                'W${i + 1} (${today.subtract(Duration(days: (3 - i) * 7)).day}/${today.subtract(Duration(days: (3 - i) * 7)).month})');
      case '6M':
        return List.generate(
            6,
            (i) =>
                '${monthNames[DateTime(today.year, today.month - (5 - i)).month - 1]} ${DateTime(today.year, today.month - (5 - i)).year.toString().substring(2)}');
      default:
        return List.generate(dataLength, (i) => 'P${i + 1}');
    }
  }

  List<FlSpot> _generateSpots(List<double> data) => data
      .asMap()
      .entries
      .map((e) => FlSpot(e.key.toDouble(), e.value))
      .toList();

  void _handleViewChange(String? value, bool isCalorieChart) {
    if (value != null) {
      if (isCalorieChart && value != _selectedCalorieView) {
        setState(() => _selectedCalorieView = value);
        _startOrUpdateSummaryTimer();
      } else if (!isCalorieChart && value != _selectedWeightView) {
        setState(() => _selectedWeightView = value);
      }
    }
  }

  List<double> _getDailyMealCounts() {
    if (_metricsData == null || _metricsData!.caloriesHistory.isEmpty)
      return List.filled(7, 0.0);
    return _aggregateDataByPeriod(_metricsData!.caloriesHistory, 'logged_at',
        'calories', null, 7, const Duration(days: 1),
        countEntries: true);
  }

  List<String> get _mealTrendLabels {
    final now = DateTime.now().toLocal();
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return List.generate(
        7, (i) => dayNames[now.subtract(Duration(days: 6 - i)).weekday - 1]);
  }

  // --- BUILD METHOD AND WIDGETS ---

  @override
  Widget build(BuildContext context) {
    // Define text styles
    final smallLabelStyle =
        GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 11.0);
    final mediumLabelStyle = GoogleFonts.poppins(
        color: kColorTextSecondary,
        fontSize: 12.0,
        fontWeight: FontWeight.w500);
    final titleStyle = GoogleFonts.poppins(
        color: kColorPrimary, fontSize: 18.0, fontWeight: FontWeight.w600);
    final cardTitleStyle = GoogleFonts.poppins(
        color: kColorTextSecondary,
        fontSize: 16.0,
        fontWeight: FontWeight.w500);
    final metricValueStyle = GoogleFonts.poppins(
        color: kColorPrimaryDark, fontSize: 14.0, fontWeight: FontWeight.bold);
    final appBarTitleStyle = GoogleFonts.poppins(
        color: kColorTextOnPrimary,
        fontSize: 20.0,
        fontWeight: FontWeight.w600);
    final chartLegendLabelStyle =
        GoogleFonts.poppins(fontSize: 11.0, color: kColorTextPrimary);

    // --- Loading, Error, and No Data States ---
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
            title: Text('Analytics Dashboard', style: appBarTitleStyle),
            backgroundColor: kColorPrimaryDark,
            foregroundColor: kColorTextOnPrimary,
            centerTitle: true),
        drawer: const AppDrawer(),
        body: const Center(
            child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(kColorPrimary))),
      );
    }
    // <<< CHANGE: Show the error screen only if there's no data to display.
    if (_error != null && _metricsData == null) {
      return Scaffold(
        appBar: AppBar(
            title: Text('Analytics Dashboard', style: appBarTitleStyle),
            backgroundColor: kColorPrimaryDark,
            foregroundColor: kColorTextOnPrimary,
            centerTitle: true),
        drawer: const AppDrawer(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Error: $_error',
                  style: GoogleFonts.poppins(
                      color: kColorNegative, fontSize: 16.0),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20.0),
              // <<< CHANGE: The retry button triggers an initial load.
              ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  onPressed: () => _fetchData(isInitialLoad: true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kColorPrimary,
                      foregroundColor: kColorTextOnPrimary))
            ]),
          ),
        ),
      );
    }
    if (_metricsData == null) {
      return Scaffold(
        appBar: AppBar(
            title: Text('Analytics Dashboard', style: appBarTitleStyle),
            backgroundColor: kColorPrimaryDark,
            foregroundColor: kColorTextOnPrimary,
            centerTitle: true),
        drawer: const AppDrawer(),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('No data available. Please try again later.'),
            const SizedBox(height: 20.0),
            // <<< CHANGE: The fetch button triggers an initial load.
            ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Fetch Data'),
                onPressed: () => _fetchData(isInitialLoad: true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: kColorPrimary,
                    foregroundColor: kColorTextOnPrimary))
          ]),
        ),
      );
    }

    // --- Main UI ---
    return Scaffold(
      backgroundColor: kColorBackground,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text('Analytics Dashboard', style: appBarTitleStyle),
        centerTitle: true,
        backgroundColor: kColorPrimaryDark,
        foregroundColor: kColorTextOnPrimary,
        elevation: 1.0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _fetchData(),
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      // <<< CHANGE: onRefresh now calls the unified fetch method.
      body: RefreshIndicator(
        onRefresh: () => _fetchData(),
        color: kColorPrimary,
        // <<< CHANGE: Stack allows the "Refreshing" banner to overlay the content.
        child: Stack(
          children: [
            ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
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
                    viewSelector: _buildViewToggle(
                        selectedValue: _selectedCalorieView,
                        onChanged: (v) => _handleViewChange(v, true)),
                    summaryContent: _buildSummaryContainer(
                        _calorieSummaryMessage, Icons.info_outline)),
                const SizedBox(height: 24.0),
                _buildSectionTitle('Meal Trends', titleStyle),
                _AnimatedChartSection(
                    key: const ValueKey('meal_trend_chart'),
                    chartType: _ChartType.bar,
                    title: "Weekly Meal Logging",
                    cardTitleStyle: cardTitleStyle,
                    axisLabelStyle: smallLabelStyle,
                    barChartData:
                        _getDailyMealCounts().map((e) => e.toInt()).toList(),
                    barLabels: _mealTrendLabels,
                    summaryContent: _buildSummaryContainer(
                        "Consistent meal logging provides the best insights.",
                        Icons.check_circle_outline)),
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
                    viewSelector: _buildViewToggle(
                        selectedValue: _selectedWeightView,
                        onChanged: (v) => _handleViewChange(v, false))),
                const SizedBox(height: 16.0),
                _buildSectionTitle('Nutrition Overview', titleStyle),
                Card(
                  elevation: 2.0,
                  shadowColor: kColorPrimaryLighter.withOpacity(0.4),
                  margin: const EdgeInsets.only(bottom: 16.0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Macronutrient Balance',
                                style: cardTitleStyle),
                            const SizedBox(height: 8.0),
                            // FIX START: Removed Align and let the selector builder handle distribution.
                            _buildMacroPeriodSelector(),
                            // FIX END
                          ],
                        ),
                        const SizedBox(height: 16.0),
                        _AnimatedChartSection(
                          key: ValueKey(
                              'macro_chart_${_selectedMacroPeriod}_${_macroDateRange.start}_${_macroDateRange.end}'),
                          chartType: _ChartType.pie,
                          axisLabelStyle: smallLabelStyle,
                          title: null,
                          cardTitleStyle: cardTitleStyle,
                          pieChartData: macroData,
                          period: _selectedMacroPeriod,
                          macroGoals: macroGoals,
                          legendLabelStyle: chartLegendLabelStyle,
                          summaryContent: _buildRichTextSummary(
                              _getMacroSummaryMessage(),
                              Icons.pie_chart_outline),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24.0),
                _AnimatedChartSection(
                    key: const ValueKey('cuisine_chart'),
                    chartType: _ChartType.pie,
                    axisLabelStyle: smallLabelStyle,
                    title: "Popular Cuisines",
                    cardTitleStyle: cardTitleStyle,
                    pieChartData: cuisineData,
                    legendLabelStyle: chartLegendLabelStyle,
                    summaryContent: _buildSummaryContainer(
                        "African cuisine is your preferred choice.",
                        Icons.restaurant),
                    chartSubtype: 'cuisine'),
                const SizedBox(height: 24.0),
              ],
            ),
            // <<< CHANGE: This is the "Refreshing..." overlay widget.
            if (_isRefreshing)
              Positioned(
                top: 8.0,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF424242), // Dark grey
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          height: 14.0,
                          width: 14.0,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Text(
                          "Refreshing...",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 14.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, TextStyle style) => Padding(
      padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
      child: Text(title, style: style));

  Widget _buildMetricsSection(TextStyle labelStyle, TextStyle valueStyle) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Reduce card width slightly to fit 4 items
    final cardWidth = (screenWidth - 48) / 4; // Reduced padding and spacing
    return Card(
      elevation: 2.0,
      shadowColor: kColorPrimaryLighter.withOpacity(0.4),
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: kColorSurface,
      child: SizedBox(
        height: 130.0, // Fixed height for the container
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
          scrollDirection: Axis.horizontal,
          children: [
            // Meals Logged
            Container(
              width: cardWidth,
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: MetricCard(
                title: 'Meals Logged',
                icon: Icons.restaurant_menu,
                color: kColorPrimary,
                labelStyle: labelStyle,
                child: AnimatedBuilder(
                  animation: _mealsAnimation,
                  builder: (c, ch) => Text(
                    '${_mealsAnimation.value.toInt()}',
                    style: valueStyle,
                  ),
                ),
              ),
            ),

            // Avg Calories
            Container(
              width: cardWidth,
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: MetricCard(
                title: 'Avg Calories',
                icon: Icons.local_fire_department,
                color: kColorWarningHigh,
                labelStyle: labelStyle,
                child: AnimatedBuilder(
                  animation: _caloriesAnimation,
                  builder: (c, ch) => Text(
                    '${_caloriesAnimation.value.toInt()} kcal',
                    style: valueStyle.copyWith(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            // Weight Change
            Container(
              width: cardWidth,
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: MetricCard(
                title: 'Weight Change',
                icon: Icons.monitor_weight,
                color: kColorPrimaryLight,
                labelStyle: labelStyle,
                child: AnimatedBuilder(
                  animation: _weightAnimation,
                  builder: (c, ch) {
                    final wv = _weightAnimation.value;
                    final Color wc = wv == 0
                        ? kColorTextPrimary
                        : (wv > 0 ? kColorNegative : kColorPositiveOrTarget);
                    final String displayValue = wv > 0
                        ? '+${wv.toStringAsFixed(1)}'
                        : wv.toStringAsFixed(1);
                    return Text(
                      '$displayValue kg',
                      style: valueStyle.copyWith(
                        color: wc,
                        fontSize: 14.0,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
            ),

            // Update Weight Button
            Container(
              width: cardWidth,
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: GestureDetector(
                onTap: _showUpdateWeightDialog,
                child: Card(
                  elevation: 2.0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: kColorPrimary.withOpacity(0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12.0, horizontal: 4.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.edit_outlined,
                            color: kColorPrimary, size: 22.0),
                        const SizedBox(height: 6.0),
                        Text(
                          'Update\nWeight',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: kColorPrimary,
                            fontSize: 12.0,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
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
    );
  }

  Widget _buildSummaryContainer(String message, IconData icon) => Container(
        decoration: BoxDecoration(
            color: kColorPrimaryLightest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kColorPrimaryLighter.withOpacity(0.8))),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Row(
          children: [
            Icon(icon, size: 18.0, color: kColorPrimary),
            const SizedBox(width: 8.0),
            Expanded(
                child: Text(message,
                    style: GoogleFonts.poppins(
                        color: kColorPrimaryDark,
                        fontWeight: FontWeight.w500,
                        fontSize: 13.0))),
          ],
        ),
      );

  Widget _buildViewToggle(
      {required String selectedValue,
      required ValueChanged<String?> onChanged}) {
    final tts =
        GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12.0);
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        alignment: Alignment.center,
        child: ToggleButtons(
          isSelected: _views.map((v) => v == selectedValue).toList(),
          onPressed: (i) => onChanged(_views[i]),
          borderRadius: BorderRadius.circular(8.0),
          selectedBorderColor: kColorPrimary,
          selectedColor: kColorTextOnPrimary,
          fillColor: kColorPrimary,
          color: kColorPrimary,
          borderColor: kColorPrimaryLighter,
          constraints: BoxConstraints(
              minHeight: 36.0,
              minWidth: (constraints.maxWidth / _views.length) - 5.0),
          children: _views
              .map((v) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(v, style: tts)))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildMacroPeriodSelector() {
    // FIX START: Changed to a Row with spaceBetween to distribute the buttons.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: ['D', 'W', 'M'].map((value) {
        final labels = {'D': 'Day', 'W': 'Week', 'M': 'Month'};
        return Flexible(child: _buildPeriodButton(value, labels[value]!));
      }).toList(),
    );
    // FIX END
  }

  Widget _buildPeriodButton(String value, String label) {
    final isSelected = _selectedMacroPeriod == value;
    return GestureDetector(
      onTap: () {
        if (_selectedMacroPeriod == value) return;

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        DateTimeRange newRange;

        switch (value) {
          case 'D':
            newRange = DateTimeRange(
                start: today, end: today.add(const Duration(days: 1)));
            break;
          case 'W':
            newRange = DateTimeRange(
                start: now.subtract(const Duration(days: 6)),
                end: now.add(const Duration(days: 1)));
            break;
          case 'M':
            newRange = DateTimeRange(
                start: now.subtract(const Duration(days: 29)),
                end: now.add(const Duration(days: 1)));
            break;
          default:
            return;
        }

        setState(() {
          _selectedMacroPeriod = value;
          _macroDateRange = newRange;
        });
        _aggregateMacronutrients(_metricsData?.caloriesHistory);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: isSelected ? kColorPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isSelected ? kColorPrimary : kColorBorder, width: 1.0),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                color: isSelected ? Colors.white : kColorTextSecondary,
                fontSize: 12.0,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  // Show dialog to update weight
  Future<void> _showUpdateWeightDialog() async {
    // Get current weight if available
    if (_metricsData?.metrics['weight'] != null) {
      final currentWeight = _metricsData!.metrics['weight'] is double
          ? _metricsData!.metrics['weight']
          : double.tryParse(_metricsData!.metrics['weight'].toString()) ?? 0.0;
      _weightKg = currentWeight;
      _weightController.text = _weightKg.toStringAsFixed(1);
    } else {
      _weightKg = 0.0;
      _weightController.clear();
    }
    _weightUnit = 'kg'; // Reset to kg when dialog opens

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap a button to close
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Update Weight'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextField(
                  controller: _weightController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Weight',
                    suffixIcon: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _weightUnit,
                        items: <String>['kg', 'lbs']
                            .map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _updateWeightUnit(newValue);
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    _parseAndUpdateWeight();
                  },
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: _isUpdatingWeight
                  ? const SizedBox(
                      width: 20.0,
                      height: 20.0,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    )
                  : const Text('Update'),
              onPressed: _isUpdatingWeight ? null : _updateWeight,
            ),
          ],
        );
      },
    );
  }

  // Parse and update weight based on unit
  void _parseAndUpdateWeight() {
    final String text = _weightController.text.trim();
    final double? value = double.tryParse(text);
    if (value != null && value > 0) {
      if (_weightUnit == 'kg') {
        _weightKg = value;
      } else {
        _weightKg = value * 0.453592; // Convert lbs to kg
      }
    } else {
      _weightKg = 0;
    }
  }

  // Update weight unit and convert value if needed
  void _updateWeightUnit(String newUnit) {
    if (newUnit == _weightUnit) return;

    if (_weightController.text.isNotEmpty) {
      final currentValue = double.tryParse(_weightController.text) ?? 0;
      if (newUnit == 'kg') {
        // Convert from lbs to kg
        _weightKg = currentValue * 0.453592;
        _weightController.text = _weightKg.toStringAsFixed(1);
      } else {
        // Convert from kg to lbs
        _weightKg = currentValue;
        _weightController.text = (_weightKg / 0.453592).toStringAsFixed(1);
      }
    }

    setState(() {
      _weightUnit = newUnit;
    });
  }

  // Call API to update weight
  Future<void> _updateWeight() async {
    if (_weightKg <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid weight')),
        );
      }
      return;
    }

    setState(() {
      _isUpdatingWeight = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      if (userId == null) {
        throw Exception('User not logged in');
      }

      final response = await http.patch(
        Uri.parse('$apiBaseUrl/rr/metrics/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'weight': _weightKg.toString(),
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 204) {
        // Refresh the data
        await _fetchData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Weight updated successfully!')),
          );
          Navigator.of(context).pop(); // Close the dialog
        }
      } else {
        throw Exception('Failed to update weight: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating weight: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingWeight = false;
        });
      }
    }
  }
}

// --- Reusable Chart Section and Specific Chart Widgets ---

enum _ChartType { line, bar, pie }

class _AnimatedChartSection extends StatefulWidget {
  final _ChartType chartType;
  final TextStyle axisLabelStyle;
  final String? title;
  final TextStyle? cardTitleStyle;
  final TextStyle? legendLabelStyle;
  final Map<String, double>? pieChartData;
  final Map<String, double>? macroGoals;
  final Widget? viewSelector;
  final Widget? summaryContent;
  final String? period;
  final String? chartSubtype;

  final List<FlSpot>? lineChartData;
  final List<FlSpot>? lineRecommendedData;
  final List<String>? lineLabels;
  final bool? isWeightChart;
  final List<int>? barChartData;
  final List<String>? barLabels;

  const _AnimatedChartSection({
    required super.key,
    required this.chartType,
    required this.axisLabelStyle,
    this.title,
    this.cardTitleStyle,
    this.legendLabelStyle,
    this.pieChartData,
    this.macroGoals,
    this.viewSelector,
    this.summaryContent,
    this.lineChartData,
    this.lineRecommendedData,
    this.lineLabels,
    this.isWeightChart,
    this.barChartData,
    this.barLabels,
    this.period,
    this.chartSubtype,
  });

  @override
  _AnimatedChartSectionState createState() => _AnimatedChartSectionState();
}

class _AnimatedChartSectionState extends State<_AnimatedChartSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: kAnimationDuration, vsync: this);
    _animation = CurvedAnimation(parent: _controller, curve: kAnimationCurve);
  }

  @override
  void didUpdateWidget(covariant _AnimatedChartSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool dataChanged = false;
    if (widget.chartType == _ChartType.line)
      dataChanged =
          oldWidget.lineChartData.toString() != widget.lineChartData.toString();
    else if (widget.chartType == _ChartType.bar)
      dataChanged =
          oldWidget.barChartData.toString() != widget.barChartData.toString();
    else if (widget.chartType == _ChartType.pie)
      dataChanged =
          oldWidget.pieChartData.toString() != widget.pieChartData.toString();
    if (dataChanged && _hasData()) {
      _controller.reset();
      _hasAnimated = false;
      if (mounted)
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) _startAnimation();
        });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _hasData() {
    switch (widget.chartType) {
      case _ChartType.line:
        return widget.lineChartData?.isNotEmpty ?? false;
      case _ChartType.bar:
        return widget.barChartData?.isNotEmpty ?? false;
      case _ChartType.pie:
        return widget.pieChartData?.values.any((v) => v > 0) ?? false;
    }
  }

  void _startAnimation() {
    if (!_hasAnimated &&
        mounted &&
        _controller.status != AnimationStatus.forward) {
      _controller.forward();
      setState(() {
        _hasAnimated = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: widget.key!,
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.2 && !_hasAnimated && _hasData()) {
          Future.delayed(const Duration(milliseconds: 150), _startAnimation);
        }
      },
      child: Builder(builder: (context) {
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.title != null && widget.cardTitleStyle != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 15.0),
                  child: Text(widget.title!, style: widget.cardTitleStyle!)),
            if (widget.summaryContent != null) ...[
              widget.summaryContent!,
              const SizedBox(height: 15.0)
            ],
            if (widget.viewSelector != null) ...[
              widget.viewSelector!,
              const SizedBox(height: 20.0)
            ],
            if (!_hasData())
              SizedBox(
                  height: 200.0,
                  child: Center(
                      child: Text("No data for this chart.",
                          style: widget.axisLabelStyle)))
            else
              AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    switch (widget.chartType) {
                      case _ChartType.line:
                        List<FlSpot> animatedData = widget.lineChartData!
                            .map((s) => FlSpot(s.x, s.y * _animation.value))
                            .toList();
                        List<FlSpot> animatedRecommended = widget
                            .lineRecommendedData!
                            .map((s) => FlSpot(s.x, s.y * _animation.value))
                            .toList();
                        return _buildLineChartWidget(
                          data: animatedData,
                          recommendedData: animatedRecommended,
                          labels: widget.lineLabels!,
                          isWeightChart: widget.isWeightChart!,
                          axisLabelStyle: widget.axisLabelStyle,
                          maxX: (widget.lineLabels!.length - 1).toDouble(),
                          animationValue: _animation.value,
                        );
                      case _ChartType.bar:
                        return WeeklyMealTrendChart(
                          mealsPerDay: widget.barChartData!,
                          labels: widget.barLabels!,
                          animationProgress: _animation.value,
                          axisLabelStyle: widget.axisLabelStyle,
                        );
                      case _ChartType.pie:
                        if (widget.pieChartData != null) {
                          if (widget.chartSubtype == 'cuisine') {
                            return _buildGenericPieChartWithLegend();
                          } else {
                            return MacronutrientBreakdownChart(
                              data: widget.pieChartData!,
                              animationProgress: _animation.value,
                              period: widget.period ?? 'D',
                            );
                          }
                        } else {
                          return _buildGenericPieChartWithLegend();
                        }
                    }
                  }),
          ],
        );

        if (widget.title == null) {
          return content;
        }

        return Card(
          elevation: 1.5,
          shadowColor: kColorPrimaryLighter.withOpacity(0.3),
          margin: const EdgeInsets.only(bottom: 16.0),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side:
                  BorderSide(color: kColorBorder.withOpacity(0.7), width: 1.0)),
          color: kColorSurface,
          child: Padding(padding: const EdgeInsets.all(16.0), child: content),
        );
      }),
    );
  }

  Widget _buildGenericPieChartWithLegend() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240.0), // Increased height
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4, // More space for the chart
            child: PopularCuisinesChart(
              data: widget.pieChartData!,
              animationProgress: _animation.value,
            ),
          ),
          const SizedBox(width: 16.0),
          Expanded(
            flex: 3, // Less space for the legend
            child: _buildLegendWidget(
              widget.pieChartData!,
              (widget.legendLabelStyle ?? widget.axisLabelStyle)
                  .copyWith(fontSize: 12.0),
              _animation.value, // Pass animation value for sync
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChartWidget(
      {required List<FlSpot> data,
      required List<FlSpot> recommendedData,
      required List<String> labels,
      required bool isWeightChart,
      required TextStyle axisLabelStyle,
      required double maxX,
      required double animationValue}) {
    if (data.isEmpty && labels.isEmpty)
      return SizedBox(
          height: 250.0,
          child:
              Center(child: Text("No data for chart", style: axisLabelStyle)));
    List<FlSpot> originalActualData = widget.lineChartData ?? [];
    List<FlSpot> originalRecommendedData = widget.lineRecommendedData ?? [];
    double minY = double.infinity, maxY = double.negativeInfinity;
    [...originalActualData, ...originalRecommendedData].forEach((s) {
      minY = min(minY, s.y);
      maxY = max(maxY, s.y);
    });
    if (minY == maxY) {
      minY -= (minY * 0.1).abs();
      maxY += (maxY * 0.1).abs();
      if (minY == 0 && maxY == 0) maxY = isWeightChart ? 10 : 500;
    }
    double paddingY = (maxY - minY) * 0.15;
    minY = max(0, minY - paddingY);
    maxY += paddingY;
    if (minY.isInfinite || minY.isNaN) minY = 0;
    if (maxY.isInfinite || maxY.isNaN) maxY = isWeightChart ? 90 : 2500;
    double yInterval =
        ((maxY - minY) / 5).clamp(isWeightChart ? 1.0 : 50.0, double.infinity);
    if (yInterval <= 0) yInterval = isWeightChart ? 5 : 250;

    return SizedBox(
      height: 250.0,
      child: LineChart(LineChartData(
        minX: 0,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          getTouchedSpotIndicator: (barData, spotIndexes) => spotIndexes
              .map((i) => TouchedSpotIndicatorData(
                  FlLine(
                      color: kChartLineColor.withOpacity(0.5),
                      strokeWidth: 2.0),
                  FlDotData(
                      getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                          radius: 6,
                          color: kChartLineColor,
                          strokeWidth: 2.0,
                          strokeColor: kColorSurface))))
              .toList(),
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (s) => kChartTooltipBg,
            getTooltipItems: (touchedSpots) {
              final mainDataSpot =
                  touchedSpots.firstWhereOrNull((s) => s.barIndex == 0);

              if (mainDataSpot == null) {
                return touchedSpots
                    .map((_) => LineTooltipItem('', const TextStyle()))
                    .toList();
              }

              final index = mainDataSpot.x.toInt();

              if (index < 0 ||
                  index >= labels.length ||
                  index >= originalActualData.length) {
                return touchedSpots
                    .map((_) => LineTooltipItem('', const TextStyle()))
                    .toList();
              }

              final label = labels[index];
              final actual = originalActualData[index].y;
              final recommended = originalRecommendedData.isNotEmpty
                  ? originalRecommendedData.first.y
                  : 0.0;
              final diff = actual - recommended;
              String diffStr;
              Color diffColor;

              if (diff.abs() <= (isWeightChart ? 0.2 : 50)) {
                diffStr = 'On Target';
                diffColor = kColorPositiveOrTarget;
              } else if (diff > 0) {
                diffStr =
                    '+${isWeightChart ? diff.toStringAsFixed(1) : diff.toStringAsFixed(0)} ${isWeightChart ? "kg" : "kcal"}';
                diffColor = kColorWarningHigh;
              } else {
                diffStr =
                    '${isWeightChart ? diff.toStringAsFixed(1) : diff.toStringAsFixed(0)} ${isWeightChart ? "kg" : "kcal"}';
                diffColor = kColorWarningLow;
              }

              final mainTooltipItem = LineTooltipItem(
                  '$label\n',
                  GoogleFonts.poppins(
                      color: kColorTooltipText, fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(
                        text: 'Actual: ',
                        style: GoogleFonts.poppins(color: kColorTooltipText)),
                    TextSpan(
                        text:
                            '${isWeightChart ? actual.toStringAsFixed(1) : actual.toStringAsFixed(0)}\n'),
                    TextSpan(
                        text: 'Target: ',
                        style: GoogleFonts.poppins(color: kColorTooltipText)),
                    TextSpan(
                        text:
                            '${isWeightChart ? recommended.toStringAsFixed(1) : recommended.toStringAsFixed(0)}\n'),
                    TextSpan(
                        text: diffStr,
                        style: GoogleFonts.poppins(
                            color: diffColor, fontWeight: FontWeight.bold)),
                  ]);

              return touchedSpots.map((spot) {
                if (spot.barIndex == mainDataSpot.barIndex &&
                    spot.spotIndex == mainDataSpot.spotIndex) {
                  return mainTooltipItem;
                }
                return LineTooltipItem('', const TextStyle());
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: yInterval,
            verticalInterval: 1.0,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: kColorDivider, strokeWidth: 0.5),
            getDrawingVerticalLine: (v) =>
                FlLine(color: kColorDivider, strokeWidth: 0.5)),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30.0,
                  interval: 1.0,
                  getTitlesWidget: (v, m) {
                    final i = v.toInt();
                    if (i < 0 ||
                        i >= labels.length ||
                        (labels.length > 10 &&
                            i % 2 != 0 &&
                            i != labels.length - 1 &&
                            i != 0)) return const SizedBox();
                    return SideTitleWidget(
                        meta: m, child: Text(labels[i], style: axisLabelStyle));
                  })),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 50.0,
                  interval: yInterval,
                  getTitlesWidget: (v, m) => Text(
                      v.toStringAsFixed(isWeightChart ? 1 : 0),
                      style: axisLabelStyle,
                      textAlign: TextAlign.left))),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData:
            FlBorderData(show: true, border: Border.all(color: kColorBorder)),
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
                    radius: 3.0,
                    color: kChartLineColor,
                    strokeWidth: 1.0,
                    strokeColor: kColorSurface)),
            belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(colors: [
                  kChartLineGradientStart.withOpacity(
                      kChartLineGradientStart.opacity * animationValue),
                  kChartLineGradientEnd.withOpacity(
                      kChartLineGradientEnd.opacity * animationValue)
                ], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            shadow: Shadow(
                color: kChartLineColor.withOpacity(0.3 * animationValue),
                blurRadius: 8,
                offset: const Offset(0, 4)),
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
                belowBarData: BarAreaData(show: false)),
        ],
      )),
    );
  }

  Widget _buildLegendWidget(Map<String, double> data,
      TextStyle legendLabelStyle, double animationProgress) {
    final List<Color> colorsToUse = [
      kColorPrimary,
      kColorPrimaryLight,
      kColorTextSecondary,
      kColorPrimaryLighter
    ];
    int ci = 0;
    // Calculate total based on animated values to ensure sync
    final animatedTotal =
        data.values.fold(0.0, (a, b) => a + (b * animationProgress));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: data.entries.map((e) {
        // Calculate percentage based on animated value
        final percentage = animatedTotal > 0
            ? ((e.value * animationProgress) / animatedTotal) * 100
            : 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Row(
            children: [
              Container(
                  width: 12.0,
                  height: 12.0,
                  decoration: BoxDecoration(
                      color: colorsToUse[ci++ % colorsToUse.length],
                      shape: BoxShape.circle),
                  margin: const EdgeInsets.only(right: 8.0)),
              Flexible(
                  child: Text('${e.key} (${percentage.toStringAsFixed(0)}%)',
                      style: legendLabelStyle,
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class WeeklyMealTrendChart extends StatelessWidget {
  final List<int> mealsPerDay;
  final List<String> labels;
  final double animationProgress;
  final TextStyle axisLabelStyle;

  const WeeklyMealTrendChart(
      {super.key,
      required this.mealsPerDay,
      required this.labels,
      required this.animationProgress,
      required this.axisLabelStyle});

  @override
  Widget build(BuildContext context) {
    if (mealsPerDay.isEmpty)
      return SizedBox(
          height: 200.0,
          child: Center(child: Text("No meal data", style: axisLabelStyle)));
    final maxValue = (mealsPerDay.reduce(max) + 1).toDouble();
    return SizedBox(
      height: 200.0,
      child: BarChart(BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxValue,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => kChartTooltipBg,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final day = labels[group.x.toInt()];
              final value = mealsPerDay[group.x.toInt()];
              return BarTooltipItem(
                  '$day\n',
                  GoogleFonts.poppins(
                      color: kColorTooltipText, fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(
                        text: '$value Meal${value == 1 ? "" : "s"}',
                        style: GoogleFonts.poppins(color: kColorTooltipText))
                  ]);
            },
          ),
        ),
        barGroups: mealsPerDay
            .asMap()
            .entries
            .map((entry) => BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(
                      toY: entry.value.toDouble() * animationProgress,
                      color: kChartBarColor,
                      width: 22.0,
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6)),
                      backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxValue,
                          color: kColorBackground.withOpacity(0.5)),
                    )
                  ],
                ))
            .toList(),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30.0,
                  getTitlesWidget: (v, m) => SideTitleWidget(
                      meta: m,
                      space: 4.0,
                      child: Text(labels[v.toInt()], style: axisLabelStyle)))),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: max(1.0, (maxValue / 5).floorToDouble()),
            getDrawingHorizontalLine: (v) => FlLine(
                color: kColorDivider.withOpacity(0.5), strokeWidth: 1.0)),
      )),
    );
  }
}

abstract class BasePieChart extends StatelessWidget {
  final Map<String, double> data;
  final double animationProgress;
  const BasePieChart(
      {super.key, required this.data, required this.animationProgress});

  List<Color> get chartColors;

  String getLabel(String label, double value, double percentage) {
    return '${percentage.toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty)
      return Center(
          child: Text("No data",
              style: GoogleFonts.poppins(
                  fontSize: 12.0, color: kColorTextSecondary)));

    final totalValue = data.values.fold(0.0, (sum, item) => sum + item);
    if (totalValue == 0)
      return Center(
          child: Text("No data to display",
              style: GoogleFonts.poppins(
                  fontSize: 12.0, color: kColorTextSecondary)));

    int ci = 0;
    final baseRadius = 65.0; // Increased radius

    return Container(
      padding: const EdgeInsets.all(8.0),
      child: AspectRatio(
        aspectRatio: 1,
        child: PieChart(
          PieChartData(
            sectionsSpace: 1.5,
            centerSpaceRadius: 15.0, // Reduced hole size
            centerSpaceColor: Colors.transparent,
            startDegreeOffset: -90,
            sections: data.entries.map((entry) {
              final animatedValue = entry.value * animationProgress;
              final animatedTotal = totalValue * animationProgress;
              final percentage = animatedTotal > 0
                  ? (animatedValue / animatedTotal) * 100
                  : 0.0;
              return PieChartSectionData(
                value: animatedValue,
                title: percentage > 8
                    ? getLabel(entry.key, entry.value.toDouble(), percentage)
                    : '',
                color: chartColors[ci++ % chartColors.length],
                radius: baseRadius,
                titleStyle: GoogleFonts.poppins(
                    fontSize: 10.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      const Shadow(color: Colors.black54, blurRadius: 2)
                    ]),
                borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.5), width: 1.0),
              );
            }).toList(),
          ),
          swapAnimationDuration: const Duration(milliseconds: 250),
        ),
      ),
    );
  }
}

class PopularCuisinesChart extends BasePieChart {
  const PopularCuisinesChart(
      {super.key,
      required Map<String, double> data,
      required double animationProgress})
      : super(data: data, animationProgress: animationProgress);

  @override
  List<Color> get chartColors => [
        kColorPrimary,
        kColorPrimaryLight,
        kColorTextSecondary,
        kColorPrimaryLighter
      ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty)
      return Center(
          child: Text("No data",
              style: GoogleFonts.poppins(
                  fontSize: 12.0, color: kColorTextSecondary)));

    final totalValue = data.values.fold(0.0, (sum, item) => sum + item);
    if (totalValue == 0)
      return Center(
          child: Text("No data to display",
              style: GoogleFonts.poppins(
                  fontSize: 12.0, color: kColorTextSecondary)));

    int ci = 0;
    final baseRadius = 70.0; // Increased radius

    return Container(
      padding: const EdgeInsets.all(8.0),
      child: AspectRatio(
        aspectRatio: 1,
        child: PieChart(
          PieChartData(
            sectionsSpace: 1.5,
            centerSpaceRadius: 20.0, // Reduced hole size
            centerSpaceColor: Colors.transparent,
            startDegreeOffset: -90,
            sections: data.entries.map((entry) {
              final animatedValue = entry.value * animationProgress;
              final animatedTotal = totalValue * animationProgress;
              final percentage = animatedTotal > 0
                  ? (animatedValue / animatedTotal) * 100
                  : 0.0;
              return PieChartSectionData(
                value: animatedValue,
                title: percentage > 8
                    ? getLabel(entry.key, entry.value.toDouble(), percentage)
                    : '',
                color: chartColors[ci++ % chartColors.length],
                radius: baseRadius,
                titleStyle: GoogleFonts.poppins(
                    fontSize: 10.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      const Shadow(color: Colors.black54, blurRadius: 2)
                    ]),
                borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.5), width: 1.0),
              );
            }).toList(),
          ),
          swapAnimationDuration: const Duration(milliseconds: 250),
        ),
      ),
    );
  }
}

class MacronutrientBreakdownChart extends StatelessWidget {
  final Map<String, double> data;
  final double animationProgress;
  final String period;

  const MacronutrientBreakdownChart({
    super.key,
    required this.data,
    required this.animationProgress,
    required this.period,
  });

  static final List<Color> chartColors = [
    kColorPrimaryLight,
    kColorPositiveOrTarget,
    kColorWarningHigh,
  ];

  static const List<String> macroOrder = ['Protein', 'Carbs', 'Fats'];

  String get _labelPrefix => (period == 'W' || period == 'M') ? 'Avg. ' : '';

  @override
  Widget build(BuildContext context) {
    final totalValue = data.values.fold(0.0, (sum, value) => sum + value);
    if (totalValue == 0) {
      return SizedBox(
        height: 200.0,
        child: Center(
          child: Text('No data available',
              style: GoogleFonts.poppins(color: kColorTextSecondary)),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 190.0,
          width: 190.0,
          child: _InternalPieChart(
            data: data,
            animationProgress: animationProgress,
            chartColors: chartColors,
            showPercentages: true,
          ),
        ),
        const SizedBox(height: 8.0),
        ..._buildMacroDetails(),
      ],
    );
  }

  List<Widget> _buildMacroDetails() {
    return macroOrder.map<Widget>((key) {
      if (!data.containsKey(key)) return const SizedBox.shrink();
      final index = macroOrder.indexOf(key);
      final percentage = data[key]!;
      final color = chartColors[index % chartColors.length];

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Row(
              children: [
                Container(
                    width: 10.0,
                    height: 10.0,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text('$_labelPrefix$key',
                      style: GoogleFonts.poppins(
                          fontSize: 12.0, color: kColorTextSecondary)),
                ),
                Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: GoogleFonts.poppins(
                      fontSize: 12.0,
                      color: kColorTextSecondary,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2.0, bottom: 8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: percentage / 100,
                minHeight: 5.0,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
        ],
      );
    }).toList();
  }
}

class _InternalPieChart extends BasePieChart {
  @override
  final List<Color> chartColors;
  final bool showPercentages;

  const _InternalPieChart({
    required Map<String, double> data,
    required double animationProgress,
    required this.chartColors,
    this.showPercentages = true,
  }) : super(data: data, animationProgress: animationProgress);

  @override
  String getLabel(String label, double value, double percentage) {
    if (!showPercentages) return '';
    return '${percentage.toStringAsFixed(0)}%';
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color color;
  final TextStyle labelStyle;
  const MetricCard(
      {super.key,
      required this.title,
      required this.icon,
      required this.child,
      required this.color,
      required this.labelStyle});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: kColorSurface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: kColorPrimaryLighter.withOpacity(0.2),
              blurRadius: 5,
              offset: const Offset(0, 2))
        ],
        border: Border.all(color: kColorBorder.withOpacity(0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20.0, color: color),
          const SizedBox(height: 4.0),
          Text(title,
              style: labelStyle,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
          const SizedBox(height: 8.0),
          Expanded(child: child),
        ],
      ),
    );
  }
}
