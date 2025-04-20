import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:zinzi2/widgets/app_drawer.dart'; // Import the AppDrawer

// --- Constants ---
const Duration kAnimationDuration = Duration(milliseconds: 1200);
const Curve kAnimationCurve = Curves.easeOutCubic;

const Color kColorPrimaryDark = Color(0xFF004D40);
const Color kColorPrimary = Color(0xFF00796B);
const Color kColorPrimaryLight = Color(0xFF4DB6AC);
const Color kColorPrimaryLighter = Color(0xFFB2DFDB);
const Color kColorPrimaryLightest = Color(0xFFE0F2F1);
const Color kColorBackground = Color(0xFFF8F8F8);
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary = kColorPrimaryDark;
const Color kColorTextSecondary = Color(0xFF546E7A);
const Color kColorTextOnPrimary = Colors.white;
const Color kColorTextOnSurface = kColorTextPrimary;
const Color kColorBorder = kColorPrimaryLighter;
const Color kColorDivider = Color(0xFFE0E0E0);
const Color kColorWarningHigh = Color(0xFFFFA000);
const Color kColorWarningLow = Color(0xFF00B0FF);
const Color kColorNegative = Color(0xFFFF5252);
const Color kColorPositiveOrTarget = Color(0xFF00E676);
const Color kChartLineColor = kColorPrimaryLight;
const Color kChartLineGradientStart = Color(0x554DB6AC);
const Color kChartLineGradientEnd = Color(0x004DB6AC);
const Color kChartGuideLineColor = kColorTextSecondary;
const Color kChartBarColor = kColorPrimary;
const Color kChartTooltipBg = Color(0xEE333333);
const Color kChartTooltipText = Colors.white;

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

  String _selectedCalorieView = 'W';
  String _selectedWeightView = 'W';
  final List<String> _views = ['D', 'W', 'M', '6M'];

  Timer? _summaryTimer;
  int _currentDayIndex = 0;
  String _calorieSummaryMessage = '';

  final Map<String, List<double>> actualCaloriesData = {
    'D': [1700, 1550, 1300, 1600, 1800, 1450, 1750], 
    'W': [1700, 1550, 1300, 1600, 1800, 1450, 1750], 
    'M': [1650, 1700, 1500, 1600, 1750, 1400, 1550], 
    '6M': [1600, 1650, 1550, 1620, 1700, 1480, 1600],
  };
  
  final Map<String, List<double>> recommendedCaloriesData = {
    'D': [1500, 1500, 1500, 1500, 1500, 1500, 1500], 
    'W': [1500, 1500, 1500, 1500, 1500, 1500, 1500], 
    'M': [1550, 1550, 1550, 1550, 1550, 1550, 1550], 
    '6M': [1600, 1600, 1600, 1600, 1600, 1600, 1600],
  };
  
  final Map<String, List<double>> actualWeightData = {
    'D': [80, 77.8, 77.7, 77.7, 77.6, 77.6, 77.6], 
    'W': [77.9, 77.9, 77.8, 77.7, 77.6, 77.5,80], 
    'M': [80, 79, 78, 76, 75, 74,75], 
    '6M': [82, 81, 79, 78, 76, 75, 74],
  };
  
  final Map<String, List<double>> recommendedWeightData = {
    'D': [76, 76, 76, 76, 76, 76, 76], 
    'W': [76, 76, 76, 76, 76, 76, 76], 
    'M': [75, 75, 75, 75, 75, 75, 75], 
    '6M': [74, 74, 74, 74, 74, 74, 74],
  };
  
  final List<int> weeklyMealData = [3, 2, 4, 3, 5, 1, 2];
  final Map<String, double> macroData = {'Protein': 30, 'Carbs': 50, 'Fats': 20};
  final Map<String, double> cuisineData = {'Continental': 45, 'Asian': 35, 'Other': 20};

  List<double> get currentActualCalories => actualCaloriesData[_selectedCalorieView] ?? actualCaloriesData['W']!;
  List<double> get currentRecommendedCalories => recommendedCaloriesData[_selectedCalorieView] ?? recommendedCaloriesData['W']!;
  List<double> get currentActualWeight => actualWeightData[_selectedWeightView] ?? actualWeightData['W']!;
  List<double> get currentRecommendedWeight => recommendedWeightData[_selectedWeightView] ?? recommendedWeightData['W']!;
  List<FlSpot> get currentCalorieIntakeSpots => _generateSpots(currentActualCalories);
  List<String> get currentCalorieLabels => _getLabelsForView(_selectedCalorieView);
  List<FlSpot> get currentWeightProgressSpots => _generateSpots(currentActualWeight);
  List<String> get currentWeightLabels => _getLabelsForView(_selectedWeightView);
  List<FlSpot> get currentRecommendedCalorieSpots => _generateSpots(currentRecommendedCalories);
  List<FlSpot> get currentRecommendedWeightSpots => _generateSpots(currentRecommendedWeight);

  @override
  void initState() {
    super.initState();
    _setupMetricsAnimations();
    _updateCalorieSummary();
  }

  @override
  void dispose() {
    _metricsController.dispose();
    _summaryTimer?.cancel();
    super.dispose();
  }

  void _setupMetricsAnimations() {
    _metricsController = AnimationController(duration: kAnimationDuration, vsync: this)..forward();
    final curvedMetricsAnimation = CurvedAnimation(parent: _metricsController, curve: kAnimationCurve);
    _mealsAnimation = Tween<double>(begin: 0, end: 17).animate(curvedMetricsAnimation);
    _caloriesAnimation = Tween<double>(begin: 0, end: 2122).animate(curvedMetricsAnimation);
    _weightAnimation = Tween<double>(begin: 0, end: -2.0).animate(curvedMetricsAnimation);
  }

  void _startOrUpdateSummaryTimer() {
    _summaryTimer?.cancel();
    if (_selectedCalorieView == 'D' || _selectedCalorieView == 'W') {
       _summaryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (mounted) {
          setState(() {
            _currentDayIndex = (_currentDayIndex + 1) % currentActualCalories.length;
            _calorieSummaryMessage = _getCalorieSummaryMessage(_currentDayIndex);
          });
        } else { timer.cancel(); }
      });
    }
    _updateCalorieSummary();
  }

  void _updateCalorieSummary() {
     _currentDayIndex = 0;
     setState(() {
         _calorieSummaryMessage = (_selectedCalorieView == 'D' || _selectedCalorieView == 'W')
                                ? _getCalorieSummaryMessage(_currentDayIndex)
                                : _getAggregateSummaryMessage(_selectedCalorieView);
     });
  }

  String _getCalorieSummaryMessage(int dayIndex) {
    final labels = _getLabelsForView(_selectedCalorieView);
    if (currentActualCalories.isEmpty || currentRecommendedCalories.isEmpty || labels.isEmpty || 
        dayIndex < 0 || dayIndex >= currentActualCalories.length || 
        dayIndex >= currentRecommendedCalories.length || dayIndex >= labels.length) {
        return "Summary unavailable.";
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
      double avgActual = currentActualCalories.reduce((a,b)=>a+b)/currentActualCalories.length;
      double avgRecommended = currentRecommendedCalories.reduce((a,b)=>a+b)/currentRecommendedCalories.length;
      double avgDiff = avgActual - avgRecommended; 
      String period = view == 'M' ? 'last month' : 'last 6 months';
      if(avgDiff.abs() < 10) return 'Your average intake was close to recommended over the $period.';
      else if (avgDiff > 0) return 'On average, you consumed ${avgDiff.toStringAsFixed(0)} kcal more than recommended over the $period.';
      else return 'On average, you consumed ${(-avgDiff).toStringAsFixed(0)} kcal less than recommended over the $period.';
  }

  List<String> _getLabelsForView(String view) {
       switch (view) {
           case 'W': return ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']; 
           case 'M': return ['Wk 1','Wk 2','Wk 3','Wk 4'];
           case '6M': 
             DateTime n=DateTime.now(); 
             return List.generate(6,(i){
               DateTime m=DateTime(n.year,n.month-i,1); 
               const mo=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']; 
               return mo[m.month-1];
             }).reversed.toList();
           case 'D': default: return ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
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
    final baseTextStyle = GoogleFonts.poppins(color: kColorTextPrimary);
    final smallLabelStyle = GoogleFonts.poppins(
      color: kColorTextSecondary,
      fontSize: 11,
    );
    final mediumLabelStyle = GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 12);
    final titleStyle = GoogleFonts.poppins(color: kColorPrimary, fontSize: 18, fontWeight: FontWeight.w600);
    final cardTitleStyle = GoogleFonts.poppins(color: kColorTextSecondary, fontSize: 16, fontWeight: FontWeight.w500);
    final metricValueStyle = GoogleFonts.poppins(color: kColorPrimaryDark, fontSize: 14, fontWeight: FontWeight.bold);
    final appBarTitleStyle = GoogleFonts.poppins(color: kColorTextOnPrimary, fontSize: 20, fontWeight: FontWeight.w600);

    return Scaffold(
      drawer: const AppDrawer(), // Add the drawer here
      appBar: AppBar(
        title: Text('Analytics Dashboard', style: appBarTitleStyle),
        centerTitle: true,
        backgroundColor: kColorPrimaryDark,
        foregroundColor: kColorTextOnPrimary,
        elevation: 1.0,
      ),
      body: Container(
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
                axisLabelStyle: smallLabelStyle,
                barChartData: weeklyMealData,
                summaryContent: _buildSummaryContainer("Maintain consistent meal times...", Icons.check_circle_outline),
            ),
            const SizedBox(height: 24.0),

            _buildSectionTitle('Weight Progress', titleStyle),
            _AnimatedChartSection(
                key: const ValueKey('weight_chart'),
                chartType: _ChartType.line,
                axisLabelStyle: smallLabelStyle,
                lineChartData: currentWeightProgressSpots,
                lineRecommendedData: currentRecommendedWeightSpots,
                lineLabels: currentWeightLabels,
                isWeightChart: true,
                viewSelector: _buildViewToggle(selectedValue: _selectedWeightView, onChanged: (v) => _handleViewChange(v, false)),
            ),
            const SizedBox(height: 16.0),
            _AnimatedChartSection(
                 key: const ValueKey('macro_chart'),
                 chartType: _ChartType.pie,
                 axisLabelStyle: smallLabelStyle,
                 title: "Macronutrient Balance",
                 cardTitleStyle: cardTitleStyle,
                 pieChartData: macroData,
                 legendLabelStyle: smallLabelStyle,
                 summaryContent: _buildSummaryContainer("Consider balancing carbs...", Icons.pie_chart_outline),
            ),
            const SizedBox(height: 16.0),
            _AnimatedChartSection(
                 key: const ValueKey('cuisine_chart'),
                 chartType: _ChartType.pie,
                 axisLabelStyle: smallLabelStyle,
                 title: "Popular Cuisines",
                 cardTitleStyle: cardTitleStyle,
                 pieChartData: cuisineData,
                 legendLabelStyle: smallLabelStyle,
                 summaryContent: _buildSummaryContainer("Continental and Asian cuisines are your top choices.", Icons.restaurant),
            ),
            const SizedBox(height: 24.0),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, TextStyle style) {
     return Padding(
       padding: const EdgeInsets.only(bottom: 12.0), 
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
              children: [
                SizedBox(
                  width: 100,
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
                SizedBox(width: 8),
                SizedBox(
                  width: 100,
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
                        children: [
                          SizedBox(height: 14),
                          Text('${_caloriesAnimation.value.toInt()} kcal', style: valueStyle),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 100,
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
                        return Text('${wv.toStringAsFixed(1)} kg', style: valueStyle.copyWith(color: wc));
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
    final tts = GoogleFonts.poppins(fontWeight: FontWeight.w600);

    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 32),
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
          minWidth: 40.0,
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
    required Key key,
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
  }) : super(key: key);

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

    if (widget.isWeightChart == true) {
      _controller.forward();
      _hasAnimated = true;
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedChartSection oldWidget) {
     super.didUpdateWidget(oldWidget);
     if (widget.chartType == _ChartType.line) {
         bool labelsChanged = oldWidget.lineLabels?.join(',') != widget.lineLabels?.join(',');
         if (labelsChanged) {
             _controller.reset();
             _hasAnimated = false;
         }
     }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startAnimation() {
    if (!_hasAnimated && mounted) {
      _controller.forward();
      setState(() { _hasAnimated = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: widget.key!,
      onVisibilityChanged: (visibilityInfo) {
        if (visibilityInfo.visibleFraction > 0.2 && !_hasAnimated) {
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
              AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                   switch(widget.chartType) {
                      case _ChartType.line:
                         assert(widget.lineChartData != null);
                         assert(widget.lineRecommendedData != null);
                         assert(widget.lineLabels != null);
                         assert(widget.isWeightChart != null);
                         final double currentMaxX = (widget.lineLabels?.isNotEmpty ?? false ? widget.lineLabels!.length - 1 : 0).toDouble() * _animation.value;
                         return _buildLineChartWidget(
                           data: widget.lineChartData!,
                           recommendedData: widget.lineRecommendedData!,
                           labels: widget.lineLabels!,
                           isWeightChart: widget.isWeightChart!,
                           axisLabelStyle: widget.axisLabelStyle,
                           animatedMaxX: currentMaxX,
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
                         if (widget.title == "Macronutrient Balance") {
                           return Row(
                             crossAxisAlignment: CrossAxisAlignment.center,
                             children: [
                               Expanded(
                                 flex: 3,
                                 child: Center(
                                   child: SizedBox(
                                     height: 220,
                                     width: 220,
                                     child: MacronutrientBreakdownChart(
                                       data: widget.pieChartData!,
                                       animationProgress: _animation.value,
                                     ),
                                   ),
                                 ),
                               ),
                               Expanded(
                                 flex: 2,
                                 child: Padding(
                                   padding: const EdgeInsets.only(left: 8.0),
                                   child: _buildLegendWidget(widget.pieChartData!, widget.legendLabelStyle!),
                                 ),
                               ),
                             ],
                           );
                         } else {
                           return Row(
                             crossAxisAlignment: CrossAxisAlignment.center,
                             children: [
                               Expanded(
                                 flex: 3,
                                 child: Center(
                                   child: SizedBox(
                                     height: 220,
                                     width: 220,
                                     child: PopularCuisinesChart(
                                       data: widget.pieChartData!,
                                       animationProgress: _animation.value,
                                     ),
                                   ),
                                 ),
                               ),
                               Expanded(
                                 flex: 2,
                                 child: Padding(
                                   padding: const EdgeInsets.only(left: 8.0),
                                   child: _buildLegendWidget(widget.pieChartData!, widget.legendLabelStyle!),
                                 ),
                               ),
                             ],
                           );
                         }
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
     required double animatedMaxX,
   }) {
    double minY = double.infinity; 
    double maxY = double.negativeInfinity; 
    List<FlSpot> allSpots = [...data, ...recommendedData]; 
    if (allSpots.isEmpty) { 
      minY = isWeightChart ? 60 : 0; 
      maxY = isWeightChart ? 90 : 2500; 
    } else { 
      for (var spot in allSpots) { 
        minY = min(minY, spot.y); 
        maxY = max(maxY, spot.y); 
      } 
      double paddingY = (maxY - minY) * 0.1; 
      minY = (minY - paddingY).floorToDouble(); 
      maxY = (maxY + paddingY).ceilToDouble(); 
      if (!isWeightChart) minY = max(0, minY); 
    } 
    double yInterval = ((maxY - minY) / 5).ceilToDouble(); 
    if (isWeightChart && yInterval < 1) yInterval = 1; 
    if (!isWeightChart && yInterval < 100) yInterval = 100; 
    final tooltipTextStyle = GoogleFonts.poppins(color: kChartTooltipText, fontSize: 11); 
    final tooltipBoldTextStyle = tooltipTextStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 12);
    
    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: animatedMaxX,
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
                return touchedSpots.map((spot) {
                  final originalSpot = data.firstWhere((s) => s.x == spot.x, orElse: () => spot);
                  final int index = originalSpot.x.toInt();
                  final String label = (index >= 0 && index < labels.length) ? labels[index] : '';
                  final double actualValue = originalSpot.y;
                  final double recommendedValue = (index >= 0 && index < recommendedData.length) ? recommendedData[index].y : 0.0;
                  final double difference = actualValue - recommendedValue;
                  String valueStr = isWeightChart ? '${actualValue.toStringAsFixed(1)} kg' : '${actualValue.toStringAsFixed(0)} kcal';
                  String diffStr;
                  Color diffColor;
                  double tolerance = isWeightChart ? 0.1 : 10.0;
                  if (difference.abs() < tolerance) {
                    diffStr = 'On Target';
                    diffColor = kColorPositiveOrTarget;
                  } else {
                    diffStr = '${difference > 0 ? '+' : ''}${isWeightChart ? difference.toStringAsFixed(1) : difference.toStringAsFixed(0)} ${difference > 0 ? 'above' : 'below'} target';
                    diffColor = difference > 0 ? kColorWarningHigh : kColorWarningLow;
                  }
                  return LineTooltipItem(
                    '$label\n',
                    tooltipBoldTextStyle,
                    children: [
                      TextSpan(text: '$valueStr\n', style: tooltipTextStyle),
                      TextSpan(
                        text: diffStr,
                        style: tooltipTextStyle.copyWith(color: diffColor, fontWeight: FontWeight.w500)
                      ),
                    ]
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: yInterval,
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
                interval: yInterval,
                getTitlesWidget: (double value, TitleMeta meta) {
                  return Text(
                    value.toStringAsFixed(0),
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
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                  radius: 3,
                  color: kChartLineColor,
                  strokeWidth: 1,
                  strokeColor: kColorSurface
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: const LinearGradient(
                  colors: [kChartLineGradientStart, kChartLineGradientEnd],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              shadow: Shadow(
                color: kChartLineColor.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4)
              ),
            ),
            LineChartBarData(
              spots: recommendedData,
              isCurved: true,
              curveSmoothness: 0.4,
              color: kChartGuideLineColor,
              barWidth: 1,
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
      final List<Color> colors = [kColorPrimary, kColorPrimaryLight, kColorPrimaryLighter, kColorTextSecondary]; 
      int ci = 0; 
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: data.entries.map((e) {
          final lc = colors[ci++ % colors.length];
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
    final barColor = kChartBarColor;
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final maxValue = (mealsPerDay.reduce(max) + 1).toDouble();
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
                final day = days[group.x.toInt()];
                final value = mealsPerDay[group.x.toInt()];
                return BarTooltipItem(
                  '$day\n',
                  tooltipBoldTextStyle,
                  children: [TextSpan(text: '$value Meals', style: tooltipTextStyle)],
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response != null && response.spot != null) {
                final dayIndex = response.spot!.touchedBarGroupIndex;
                final meals = mealsPerDay[dayIndex];
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('You ordered $meals meals on ${days[dayIndex]}',
                        style: tooltipTextStyle.copyWith(color: kColorTextPrimary)),
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
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxValue,
                    color: kColorBackground,
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
                  return SideTitleWidget(
                    meta: meta,
                    space: 4.0,
                    child: Text(days[index % days.length], style: axisLabelStyle),
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
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) => FlLine(color: kColorDivider, strokeWidth: 1),
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
    int ci = 0;
    final labelStyle = GoogleFonts.poppins(
      fontSize: 10,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      shadows: [const Shadow(color: Colors.black54, blurRadius: 2)],
    );
    return SizedBox(
      height: 200,
      width: 200,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 2,
          startDegreeOffset: -90,
          sections: data.entries.map((entry) {
            final sc = chartColors[ci++ % chartColors.length];
            return PieChartSectionData(
              value: entry.value * animationProgress,
              title: '${(entry.value * animationProgress).toStringAsFixed(0)}%',
              color: sc,
              radius: 90,
              titleStyle: labelStyle,
              borderSide: BorderSide(color: Colors.white, width: 0.5),
            );
          }).toList(),
        ),
        swapAnimationDuration: Duration.zero,
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
    kColorPrimary,
    kColorPrimaryLight,
    kColorPrimaryLighter,
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
      constraints: const BoxConstraints(minWidth: 120),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 2),
          Text(
            title,
            style: labelStyle,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 6),
          Flexible(
            child: DefaultTextStyle(
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Analytics Dashboard',
      theme: ThemeData(
        textTheme: GoogleFonts.poppinsTextTheme(),
        scaffoldBackgroundColor: kColorBackground,
        useMaterial3: true
      ),
      home: const UserAnalyticsDashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}