//cspell:disable
import 'package:flutter/material.dart';

class BMIIndicator extends StatelessWidget {
  final double bmi; // User's BMI value.
  final double minBmi; // Minimum BMI value.
  final double maxBmi; // Maximum BMI value.
  final bool animate; // Animate the progress bar and BMI value.

  BMIIndicator({
    required this.bmi,
    this.minBmi = 15,
    this.maxBmi = 40,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    double progress = (bmi - minBmi) / (maxBmi - minBmi);
    progress = progress.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Displaying BMI value
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: bmi),
          duration: animate ? const Duration(seconds: 1) : Duration.zero,
          builder: (context, value, child) {
            return Text(
              'BMI: ${value.toStringAsFixed(1)}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            );
          },
        ),
        SizedBox(height: 8),

        // Progress bar with animation and gradient
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: progress),
          duration: animate ? const Duration(seconds: 1) : Duration.zero,
          builder: (context, value, child) {
            return Stack(
              children: [
                // Background bar with more distinct gradient
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.shade400,
                        Colors.green.shade500,
                        Colors.yellow.shade700,
                        Colors.red.shade700
                      ],
                      stops: [
                        0.15,
                        0.25,
                        0.45,
                        1.0,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                // Animated progress
                FractionallySizedBox(
                  widthFactor: value,
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                // Indicator with more visibility
                Positioned(
                  left: value * MediaQuery.of(context).size.width - 20,
                  child: Icon(Icons.arrow_drop_down,
                      color: Colors.black, size: 30),
                ),
              ],
            );
          },
        ),

        SizedBox(height: 8),

        // BMI category markers and range labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Underweight', style: TextStyle(fontSize: 12)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Normal', style: TextStyle(fontSize: 12)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Overweight', style: TextStyle(fontSize: 12)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Obese', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
