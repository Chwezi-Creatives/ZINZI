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
  bool _isTouching = false;

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
        backgroundColor: Colors.teal[600]!.withOpacity(0.7),
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
              decoration: BoxDecoration(
                  //color: Colors.black.withOpacity(0.3),
                  ),
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
                    _buildMacronutrientBreakdownSection(),
                    const SizedBox(height: 20),
                    _buildPopularCuisinesSection(),
                    const SizedBox(height: 20),
                    _buildMessageSection(),
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
              'Key Metrics',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[800]),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                MetricCard(
                  title: 'Total Meals\nthis week',
                  child: AnimatedBuilder(
                    animation: _mealsAnimation,
                    builder: (context, child) => Text(
                      '${_mealsAnimation.value.toInt()}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[800]),
                    ),
                  ),
                ),
                MetricCard(
                  title: 'Calories this week',
                  child: AnimatedBuilder(
                    animation: _caloriesAnimation,
                    builder: (context, child) => Text(
                      '${_caloriesAnimation.value.toInt()}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[800]),
                    ),
                  ),
                ),
                MetricCard(
                  title: 'Weight  this week',
                  child: AnimatedBuilder(
                    animation: _weightAnimation,
                    builder: (context, child) => Text(
                      '${_weightAnimation.value.toStringAsFixed(1)} kg',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[800]),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyMealTrendSection() {
    List<int> weeklyMealData = [3, 2, 4, 3, 5, 1, 2];
    return _buildCardSection(
      'Number of meals ordered this week',
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
      'Popular Cuisines this week',
      Row(
        children: [
          Expanded(
              child: PopularCuisinesChart(
                  data: cuisineData, animation: _chartAnimation)),
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
      'Nutrient intake this week',
      Row(
        children: [
          Expanded(
              child: MacronutrientBreakdownChart(
                  data: macroData, animation: _chartAnimation)),
          const SizedBox(width: 20),
          _buildMacronutrientLegend(macroData),
        ],
      ),
    );
  }

  Widget _buildCalorieIntakeSection() {
    List<FlSpot> calorieIntake = [
      FlSpot(0, 1000),
      FlSpot(1, 1300),
      FlSpot(2, 1300),
      FlSpot(3, 1500),
      FlSpot(4, 2000),
      FlSpot(5, 1800),
      FlSpot(6, 2000),
    ];

    List<FlSpot> recommendedCalories = [
      for (int i = 0; i < 7; i++) FlSpot(i.toDouble(), 1500),
    ];

    return _buildCardSection(
      'Calorie intake this week',
      _buildLineChart(calorieIntake, recommendedCalories, isWeightChart: false),
    );
  }

  Widget _buildWeightGoalProgressSection() {
    List<FlSpot> weightProgress = [
      FlSpot(0, 82),
      FlSpot(1, 80),
      FlSpot(2, 79),
      FlSpot(3, 78),
      FlSpot(4, 77),
      FlSpot(5, 76),
      FlSpot(6, 75),
    ];

    List<FlSpot> idealWeight = [
      for (int i = 0; i < 7; i++) FlSpot(i.toDouble(), 72),
    ];

    return _buildCardSection(
      'Weight Goal Progress this week',
      _buildLineChart(weightProgress, idealWeight, isWeightChart: true),
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
                    color: Colors.teal[800]),
              ),
            const SizedBox(height: 20),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(List<FlSpot> data, List<FlSpot> guideData,
      {required bool isWeightChart}) {
    final guideColor = Colors.orange[600]!;

    return AnimatedBuilder(
      animation: _chartAnimation,
      builder: (context, child) {
        final animatedData = data
            .map((spot) => FlSpot(spot.x, spot.y * _chartAnimation.value))
            .toList();

        return SizedBox(
          height: 200,
          child: Stack(
            children: [
              LineChart(
                LineChartData(
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: true,
                    touchCallback:
                        (FlTouchEvent event, LineTouchResponse? touchResponse) {
                      setState(() {
                        _isTouching = touchResponse != null &&
                            touchResponse.lineBarSpots?.isNotEmpty == true;
                      });
                    },
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (spot) => Colors.teal[800]!,
                      getTooltipItems: (List<LineBarSpot> touchedSpots) {
                        return touchedSpots.map((spot) {
                          final textStyle = TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          );
                          return LineTooltipItem(
                            isWeightChart
                                ? '${spot.y.toInt()} kg'
                                : '${spot.y.toInt()} kcal',
                            textStyle,
                          );
                        }).toList();
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
                          const days = [
                            'Mon',
                            'Tue',
                            'Wed',
                            'Thu',
                            'Fri',
                            'Sat',
                            'Sun'
                          ];
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              days[value.toInt() % days.length],
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
                            isWeightChart
                                ? '${value.toInt()} kg'
                                : '${value.toInt()} kcal',
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
                  maxY: isWeightChart ? 85 : 2500,
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
                    if (guideData.isNotEmpty)
                      LineChartBarData(
                        spots: guideData,
                        isCurved: true,
                        curveSmoothness: 0.3,
                        color: guideColor,
                        barWidth: 2,
                        dashArray: [5, 5],
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                  ],
                ),
              ),
            ],
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
          ),
        );
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
          ),
        );
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
          ),
        );
      },
    );
  }
}
