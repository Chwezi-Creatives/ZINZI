import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class UserAnalyticsDashboard extends StatefulWidget {
  const UserAnalyticsDashboard({Key? key}) : super(key: key);

  @override
  _UserAnalyticsDashboardState createState() => _UserAnalyticsDashboardState();
}

class _UserAnalyticsDashboardState extends State<UserAnalyticsDashboard> {
  @override
  Widget build(BuildContext context) {
    UserAnalyticsData dummyData = UserAnalyticsData(
      totalMeals: 17,
      avgCalories: 2122,
      weightTrend: -2.0,
      nutrientIntake: {'Protein': 151, 'Carbohydrates': 250, 'Fats': 80},
      popularCuisines: {'Continental': 120, 'Asian': 80, 'Caribbean': 50},
      macronutrientBreakdown: {
        'Protein': 0.3,
        'Carbohydrates': 0.5,
        'Fats': 0.2,
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Analytics Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetricsSection(dummyData),
              const SizedBox(height: 20),
              _buildCalorieIntakeSection(), // Moved line graph section here
              const SizedBox(height: 20),
              _buildWeightGoalProgressSection(), // Moved line graph section here
              const SizedBox(height: 20),
              _buildWeeklyMealTrendSection(dummyData), // Bar graph section
              const SizedBox(height: 20),
              _buildMacronutrientBreakdownSection(dummyData),
              const SizedBox(height: 20),
              _buildPopularCuisinesSection(
                  dummyData), // Popular cuisines chart as the last
              const SizedBox(height: 20),
              _buildMessageSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsSection(UserAnalyticsData data) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Key Metrics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                MetricCard('Total Meals this week', '${data.totalMeals}'),
                MetricCard('Avg. Calories', '${data.avgCalories}'),
                MetricCard('Weight Trend', '${data.weightTrend} kg'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyMealTrendSection(UserAnalyticsData data) {
    List<int> weeklyMealData = [3, 2, 4, 3, 5, 1, 2];
    return _buildCardSection(
      'Weekly Meal Trend',
      WeeklyMealTrendChart(mealsPerDay: weeklyMealData),
    );
  }

  Widget _buildPopularCuisinesSection(UserAnalyticsData data) {
    return _buildCardSection(
      'Popular Cuisines',
      Row(
        children: [
          Expanded(child: PopularCuisinesChart(data: data.popularCuisines)),
          const SizedBox(width: 20),
          _buildCuisineLegend(data.popularCuisines),
        ],
      ),
    );
  }

  Widget _buildMacronutrientBreakdownSection(UserAnalyticsData data) {
    return _buildCardSection(
      'Macronutrient Breakdown',
      Row(
        children: [
          Expanded(
              child: MacronutrientBreakdownChart(
                  data: data.macronutrientBreakdown)),
          const SizedBox(width: 20),
          _buildMacronutrientLegend(data.macronutrientBreakdown),
        ],
      ),
    );
  }

  Widget _buildCalorieIntakeSection() {
    List<FlSpot> calorieIntake = [
      FlSpot(0, 1800),
      FlSpot(1, 2000),
      FlSpot(2, 2100),
      FlSpot(3, 2200),
      FlSpot(4, 1900),
      FlSpot(5, 1950),
      FlSpot(6, 2100),
    ];

    List<FlSpot> recommendedCalories = [
      for (int i = 0; i < 7; i++) FlSpot(i.toDouble(), 2000),
    ];

    return _buildCardSection(
      'Calorie Intake vs Daily Recommended Calories',
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

    // Ideal weight reference line at 72 kg
    List<FlSpot> idealWeight = [
      for (int i = 0; i < 7; i++)
        FlSpot(i.toDouble(), 77.5), // ideally you want this at 72 kg
    ];

    return _buildCardSection(
      'Weight Goal Progress',
      _buildLineChart(weightProgress, idealWeight, isWeightChart: true),
    );
  }

  Widget _buildMessageSection() {
    return _buildCardSection(
      '',
      const Text(
        'You have maintained a consistent meal schedule this week. Keep up the great work!',
        style: TextStyle(fontSize: 16),
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
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 10),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(List<FlSpot> data, List<FlSpot> guideData,
      {required bool isWeightChart}) {
    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: data,
              isCurved: false,
              color: Colors.teal, // Calorie Intake Line Color
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(show: false),
            ),
            if (guideData.isNotEmpty)
              LineChartBarData(
                spots: guideData,
                isCurved: false,
                color: isWeightChart
                    ? Colors.yellow[900] // Weight Progress Line Color
                    : Colors.yellow[900], // Recommended Calories Line Color
                dotData: FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
          ],
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
                    'Sun',
                  ];
                  return Text(
                    days[value.toInt() % days.length],
                    style: const TextStyle(fontSize: 12),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(show: true),
          borderData: FlBorderData(show: true),
        ),
      ),
    );
  }

  Widget _buildCuisineLegend(Map<String, int> data) {
    final colors = [Colors.blue, Colors.green, Colors.orange];
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
            Text(entry.key),
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
            Text(entry.key),
          ],
        );
      }).toList(),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;

  const MetricCard(this.title, this.value, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border.all(color: Colors.blue),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class WeeklyMealTrendChart extends StatelessWidget {
  final List<int> mealsPerDay;

  const WeeklyMealTrendChart({Key? key, required this.mealsPerDay})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceEvenly,
          maxY: 5,
          barGroups: mealsPerDay.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.toDouble(),
                  color: Colors.blue,
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
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(drawHorizontalLine: true),
        ),
      ),
    );
  }
}

class PopularCuisinesChart extends StatelessWidget {
  final Map<String, int> data;

  const PopularCuisinesChart({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = [Colors.blue, Colors.green, Colors.orange];
    final total = data.values.reduce((a, b) => a + b);
    int colorIndex = 0;

    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          sections: data.entries.map((entry) {
            final value = entry.value / total;
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
  }
}

class MacronutrientBreakdownChart extends StatelessWidget {
  final Map<String, double> data;

  const MacronutrientBreakdownChart({Key? key, required this.data})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = [Colors.purple, Colors.orange, Colors.cyan];
    int colorIndex = 0;

    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          sections: data.entries.map((entry) {
            final sectionColor = colors[colorIndex++ % colors.length];
            return PieChartSectionData(
              value: entry.value * 100,
              title: '${(entry.value * 100).toStringAsFixed(1)}%',
              color: sectionColor,
              radius: 50,
            );
          }).toList(),
          centerSpaceRadius: 40,
        ),
      ),
    );
  }
}

class UserAnalyticsData {
  final int totalMeals;
  final int avgCalories;
  final double weightTrend;
  final Map<String, int> nutrientIntake;
  final Map<String, int> popularCuisines;
  final Map<String, double> macronutrientBreakdown;

  UserAnalyticsData({
    required this.totalMeals,
    required this.avgCalories,
    required this.weightTrend,
    required this.nutrientIntake,
    required this.popularCuisines,
    required this.macronutrientBreakdown,
  });
}
