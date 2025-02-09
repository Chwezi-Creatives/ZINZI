import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class UserAnalyticsDashboard extends StatefulWidget {
  const UserAnalyticsDashboard({Key? key}) : super(key: key);

  @override
  _UserAnalyticsDashboardState createState() => _UserAnalyticsDashboardState();
}

class _UserAnalyticsDashboardState extends State<UserAnalyticsDashboard>
    with TickerProviderStateMixin {
  late AnimationController _mealsController;
  late Animation<double> _mealsAnimation;
  late AnimationController _caloriesController;
  late Animation<double> _caloriesAnimation;
  late AnimationController _weightController;
  late Animation<double> _weightAnimation;
  late AnimationController _chartController;
  late Animation<double> _chartAnimation;

  String _selectedCalorieView = 'D'; // Calorie view selection
  String _selectedWeightView = 'D'; // Weight view selection
  List<String> views = ['D', 'W', 'M', '6M']; // Available views

  final List<double> recommendedCalories = [
    1500,
    1500,
    1500,
    1500,
    1500,
    1500,
    1500
  ]; // Reference values for calorie intake
  final List<double> recommendedWeights = [
    76,
    76,
    76,
    76,
    76,
    76,
    76
  ]; // Reference values for weight

  @override
  void initState() {
    super.initState();
    _mealsController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..forward();
    _mealsAnimation =
        Tween<double>(begin: 0, end: 17).animate(_mealsController);
    _caloriesController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..forward();
    _caloriesAnimation =
        Tween<double>(begin: 0, end: 2122).animate(_caloriesController);
    _weightController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..forward();
    _weightAnimation =
        Tween<double>(begin: 0, end: -2.0).animate(_weightController);
    _chartController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..forward();
    _chartAnimation = Tween<double>(begin: 0, end: 1).animate(_chartController);
  }

  @override
  void dispose() {
    _mealsController.dispose();
    _caloriesController.dispose();
    _weightController.dispose();
    _chartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Analytics Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.teal[900]!.withOpacity(0.7),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/soft.jpg',
              fit: BoxFit.cover,
            ),
          ),
          SingleChildScrollView(
            child: Container(
              decoration: BoxDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMetricsSection(),
                    const SizedBox(height: 20),
                    _buildCalorieIntakeSection(),
                    const SizedBox(height: 20),
                    _buildWeightGoalProgressSection(),
                    const SizedBox(height: 20),
                    _buildWeeklyMealTrendSection(),
                    const SizedBox(height: 20),
                    _buildMessageSection(),
                    const SizedBox(height: 20),
                    _buildMacronutrientBreakdownSection(),
                    const SizedBox(height: 20),
                    _buildCarbMessageSection(),
                    const SizedBox(height: 20),
                    _buildPopularCuisinesSection(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly Metrics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  MetricCard(
                    title: 'Meals',
                    child: AnimatedBuilder(
                      animation: _mealsAnimation,
                      builder: (context, child) => Text(
                        '${_mealsAnimation.value.toInt()}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[800],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8), // Spacing between cards
                  MetricCard(
                    title: 'Calories',
                    child: AnimatedBuilder(
                      animation: _caloriesAnimation,
                      builder: (context, child) => Text(
                        '${_caloriesAnimation.value.toInt()}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[800],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8), // Spacing between cards
                  MetricCard(
                    title: 'Weight',
                    child: AnimatedBuilder(
                      animation: _weightAnimation,
                      builder: (context, child) => Text(
                        '${_weightAnimation.value.toStringAsFixed(1)} kg',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[800],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyMealTrendSection() {
    List<int> weeklyMealData = [3, 2, 4, 3, 5, 1, 2];
    return _buildCardSection(
      'Number of meals ordered',
      WeeklyMealTrendChart(
        mealsPerDay: weeklyMealData,
        animation: _chartAnimation,
      ),
    );
  }

  Widget _buildPopularCuisinesSection() {
    Map<String, int> cuisineData = {
      'Continental': 120,
      'Asian': 80,
      'Caribbean': 50
    };
    return _buildCardSection(
      'Popular Cuisines',
      Row(
        children: [
          Expanded(
            child: PopularCuisinesChart(
              data: cuisineData,
              animation: _chartAnimation,
            ),
          ),
          const SizedBox(width: 20),
          _buildCuisineLegend(cuisineData),
        ],
      ),
    );
  }

  Widget _buildMacronutrientBreakdownSection() {
    Map<String, double> macroData = {
      'Protein': 0.3,
      'Carbohydrates': 0.5,
      'Fats': 0.2
    };
    return _buildCardSection(
      'Nutrient intake',
      Row(
        children: [
          Expanded(
            child: MacronutrientBreakdownChart(
              data: macroData,
              animation: _chartAnimation,
            ),
          ),
          const SizedBox(width: 20),
          _buildMacronutrientLegend(macroData),
        ],
      ),
    );
  }

  Widget _buildCalorieIntakeSection() {
    List<FlSpot> calorieIntake;
    List<String> labels;

    switch (_selectedCalorieView) {
      case 'W':
        calorieIntake = [
          FlSpot(0, 1000),
          FlSpot(1, 1300),
          FlSpot(2, 1200),
          FlSpot(3, 1500),
          FlSpot(4, 1600),
          FlSpot(5, 1700),
          FlSpot(6, 1800),
        ];
        labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        break;
      case 'M':
        calorieIntake = [
          FlSpot(0, 1500),
          FlSpot(1, 1600),
          FlSpot(2, 1700),
          FlSpot(3, 1900),
          FlSpot(4, 2000),
          FlSpot(5, 2100),
          FlSpot(6, 2200),
        ];
        labels = [
          'Wk 1',
          'Wk 2',
          'Wk 3',
          'Wk 4',
          'Wk 5',
          'Wk 6',
          'Wk 7'
        ];
        break;
      case '6M':
        calorieIntake = [
          FlSpot(0, 1400),
          FlSpot(1, 1450),
          FlSpot(2, 1500),
          FlSpot(3, 1550),
          FlSpot(4, 1600),
          FlSpot(5, 1650),
          FlSpot(6, 1700),
        ];
        labels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul'];
        break;
      default: // 'D'
        calorieIntake = [
          FlSpot(0, 1000),
          FlSpot(1, 1300),
          FlSpot(2, 1200),
          FlSpot(3, 1500),
          FlSpot(4, 1600),
          FlSpot(5, 1700),
          FlSpot(6, 1800),
        ];
        labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        break;
    }

    return _buildCardSection(
      'Calorie intake (calories)',
      Column(
        children: [
          _buildViewToggleCalorie(),
          _buildLineChart(calorieIntake, isWeightChart: false, labels: labels),
        ],
      ),
    );
  }

  Widget _buildWeightGoalProgressSection() {
    List<FlSpot> weightProgress;
    List<String> labels;

    switch (_selectedWeightView) {
      case 'W':
        weightProgress = [
          FlSpot(0, 81),
          FlSpot(1, 80),
          FlSpot(2, 79),
          FlSpot(3, 78),
          FlSpot(4, 77),
          FlSpot(5, 76),
          FlSpot(6, 75),
        ];
        labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        break;
      case 'M':
        weightProgress = [
          FlSpot(0, 80),
          FlSpot(1, 79),
          FlSpot(2, 78),
          FlSpot(3, 77),
          FlSpot(4, 76),
          FlSpot(5, 75),
          FlSpot(6, 74),
        ];
        labels = [
          'Wk 1',
          'Wk 2',
          'Wk 3',
          'Wk 4',
          'Wk 5',
          'Wk 6',
          'Wk 7'
        ];
        break;
      case '6M':
        weightProgress = [
          FlSpot(0, 82),
          FlSpot(1, 81),
          FlSpot(2, 79),
          FlSpot(3, 78),
          FlSpot(4, 76),
          FlSpot(5, 75),
          FlSpot(6, 74),
        ];
        labels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul'];
        break;
      default: // 'D'
        weightProgress = [
          FlSpot(0, 82),
          FlSpot(1, 80),
          FlSpot(2, 79),
          FlSpot(3, 78),
          FlSpot(4, 77),
          FlSpot(5, 76),
          FlSpot(6, 75),
        ];
        labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        break;
    }

    return _buildCardSection(
      'Weight Progress (Kg)',
      Column(
        children: [
          _buildViewToggleWeight(),
          _buildLineChart(weightProgress, isWeightChart: true, labels: labels),
        ],
      ),
    );
  }

  Widget _buildMessageSection() {
    return _buildCardSection(
      '',
      Text(
        'You have maintained a consistent meal schedule this week. Keep up the great work!',
        style: TextStyle(fontSize: 16, color: Colors.teal[800]),
      ),
    );
  }

  Widget _buildCarbMessageSection() {
    return _buildCardSection(
      '',
      Text(
        'You have consumed more carbohydrates, consider exercising.',
        style: TextStyle(fontSize: 16, color: Colors.teal[800]),
      ),
    );
  }

  Widget _buildViewToggleCalorie() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: views.map((view) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedCalorieView == view
                  ? Colors.orange[200]
                  : Colors.teal[200],
              padding: const EdgeInsets.all(6),
            ),
            onPressed: () {
              setState(() {
                _selectedCalorieView = view; // Update the selected calorie view
              });
            },
            child: Text(view),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildViewToggleWeight() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: views.map((view) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedWeightView == view
                  ? Colors.orange[200]
                  : Colors.teal[200],
              padding: const EdgeInsets.all(6),
            ),
            onPressed: () {
              setState(() {
                _selectedWeightView = view; // Update the selected weight view
              });
            },
            child: Text(view),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCardSection(String title, Widget content) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[800],
                ),
              ),
            const SizedBox(height: 20),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(List<FlSpot> data,
      {required bool isWeightChart, required List<String> labels}) {
    final guideColor = Colors.orange[600]!;
    return AnimatedBuilder(
      animation: _chartAnimation,
      builder: (context, child) {
        final animatedData = data
            .map((spot) => FlSpot(spot.x, spot.y * _chartAnimation.value))
            .toList();
        return SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (spot) => Colors.teal[800]!,
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    return touchedSpots.map((spot) {
                      final index = spot.x.toInt(); // Get the index from the x value

                      // Check bounds
                      if (index >= 0 &&
                          index < recommendedCalories.length &&
                          index < recommendedWeights.length) {
                        final recommendedValue = isWeightChart
                            ? recommendedWeights[index]
                            : recommendedCalories[index];
                        final difference = spot.y - recommendedValue;

                        String message;
                        if (isWeightChart) {
                          if (difference == 0) {
                            message = 'You have reached your target weight! 🎉';
                          } else {
                            message = difference > 0
                                ? 'You are ${difference.toStringAsFixed(1)} kg overweight.'
                                : 'You are ${difference.abs().toStringAsFixed(1)} kg underweight.';
                          }
                        } else {
                          if (difference == 0) {
                            message = 'Perfect calorie intake! 🎯';
                          } else {
                            message = difference > 0
                                ? 'You consumed ${difference.toStringAsFixed(1)} calories more than recommended.'
                                : 'You consumed ${difference.abs().toStringAsFixed(1)} calories less than recommended.';
                          }
                        }

                        final textStyle = TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        );

                        return LineTooltipItem(
                          message,
                          textStyle,
                        );
                      } else {
                        return null; // Return null for out of bounds
                      }
                    }).where((element) => element != null).toList(); // Filter out null tooltips
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: isWeightChart ? 2 : 500,
                verticalInterval: 1,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.grey[300]!,
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (value) => FlLine(
                  color: Colors.grey[300]!,
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (value, _) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          labels[value.toInt()],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.teal[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      return Text(
                        value.toInt().toString(),
                        style: TextStyle(
                          color: Colors.teal[800],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    },
                    reservedSize: 50,
                    interval: isWeightChart ? 2 : 500,
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(
                  color: Colors.grey[400]!,
                  width: 1,
                ),
              ),
              minX: 0,
              maxX: 6,
              minY: isWeightChart ? 70 : 0,
              maxY: isWeightChart ? 84 : 2500,
              lineBarsData: [
                LineChartBarData(
                  spots: animatedData,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: Colors.teal[400],
                  barWidth: 3,
                  shadow: const Shadow(
                    color: Colors.teal,
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        Colors.teal.withOpacity(0.3),
                        Colors.teal.withOpacity(0.3),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) =>
                        FlDotCirclePainter(
                      radius: 4,
                      color: Colors.white,
                      strokeWidth: 2,
                      strokeColor: Colors.teal[400]!,
                    ),
                  ),
                ),
                LineChartBarData(
                  spots: List.generate(
                      7,
                      (i) => FlSpot(
                          i.toDouble(),
                          isWeightChart
                              ? recommendedWeights[i]
                              : recommendedCalories[i])),
                  isCurved: true,
                  color: guideColor,
                  barWidth: 1,
                  belowBarData: BarAreaData(show: false),
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCuisineLegend(Map<String, int> data) {
    final colors = [Colors.teal, Colors.green, Colors.orange];
    int colorIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: data.entries.map((entry) {
        return Row(
          children: [
            Container(
              width: 10,
              height: 10,
              color: colors[colorIndex++ % colors.length],
              margin: const EdgeInsets.only(right: 8),
            ),
            Text(entry.key, style: TextStyle(color: Colors.teal[800])),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildMacronutrientLegend(Map<String, double> data) {
    final colors = [Colors.purple, Colors.orange, Colors.cyan];
    int colorIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: data.entries.map((entry) {
        return Row(
          children: [
            Container(
              width: 10,
              height: 10,
              color: colors[colorIndex++ % colors.length],
              margin: const EdgeInsets.only(right: 8),
            ),
            Text(entry.key, style: TextStyle(color: Colors.teal[800])),
          ],
        );
      }).toList(),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final Widget child;

  const MetricCard({
    Key? key,
    required this.title,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        border: Border.all(color: Colors.teal),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 14, color: Colors.teal[700]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class WeeklyMealTrendChart extends StatelessWidget {
  final List<int> mealsPerDay;
  final Animation<double> animation;

  const WeeklyMealTrendChart({
    Key? key,
    required this.mealsPerDay,
    required this.animation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceEvenly,
                maxY: 5,
                barTouchData: BarTouchData(
                  touchCallback:
                      (FlTouchEvent event, BarTouchResponse? response) {
                    if (event is FlTapUpEvent &&
                        response != null &&
                        response.spot != null) {
                      const days = [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun'
                      ];
                      final dayIndex = response.spot!.touchedBarGroupIndex;
                      final meals = mealsPerDay[dayIndex];
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'You ordered $meals meals on ${days[dayIndex]}'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  enabled: true,
                ),
                barGroups: mealsPerDay.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.toDouble() * animation.value,
                        color: Colors.teal,
                        width: 20,
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) {
                        const days = [
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat',
                          'Sun'
                        ];
                        return Text(
                          days[value.toInt() % days.length],
                          style: const TextStyle(fontSize: 12),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(drawHorizontalLine: true),
              ),
            ));
      },
    );
  }
}

class PopularCuisinesChart extends StatelessWidget {
  final Map<String, int> data;
  final Animation<double> animation;

  const PopularCuisinesChart({
    Key? key,
    required this.data,
    required this.animation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = [Colors.teal[800], Colors.green, Colors.orange];
    final total = data.values.reduce((a, b) => a + b);
    int colorIndex = 0;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: data.entries.map((entry) {
                  final value = (entry.value / total) * animation.value;
                  final sectionColor = colors[colorIndex++ % colors.length];
                  return PieChartSectionData(
                    value: value,
                    title: '${(value * 100).toStringAsFixed(1)}%',
                    color: sectionColor,
                    radius: 50,
                  );
                }).toList(),
                centerSpaceRadius: 40,
              ),
            ));
      },
    );
  }
}

class MacronutrientBreakdownChart extends StatelessWidget {
  final Map<String, double> data;
  final Animation<double> animation;

  const MacronutrientBreakdownChart({
    Key? key,
    required this.data,
    required this.animation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = [Colors.purple, Colors.orange, Colors.cyan];
    int colorIndex = 0;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: data.entries.map((entry) {
                  final value = entry.value * 100 * animation.value;
                  final sectionColor = colors[colorIndex++ % colors.length];
                  return PieChartSectionData(
                    value: value,
                    title: '${(value).toStringAsFixed(1)}%',
                    color: sectionColor,
                    radius: 50,
                  );
                }).toList(),
                centerSpaceRadius: 40,
              ),
            ));
      },
    );
  }
}