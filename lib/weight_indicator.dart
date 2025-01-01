import 'package:flutter/material.dart';

class WeightIndicator extends StatelessWidget {
  final double currentWeight;
  final double idealWeight;
  final String healthGoal; // Added health goal to modify progress
  final bool animate; // Added animate parameter

  const WeightIndicator({
    Key? key,
    required this.currentWeight,
    required this.idealWeight,
    required this.healthGoal, // Include health goal as a parameter
    this.animate = false, // Default to no animation
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double progress = 0.0;

    // Adjust progress based on the health goal
    if (healthGoal == 'Weight Loss') {
      progress = (idealWeight / currentWeight).clamp(0.0, 1.0);
    } else if (healthGoal == 'Muscle Gain') {
      progress = (currentWeight / idealWeight).clamp(0.0, 1.0);
    } else if (healthGoal == 'Maintain Weight') {
      double weightDifference = (currentWeight - idealWeight).abs();
      progress = (1 - (weightDifference / currentWeight)).clamp(0.0, 1.0);
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4.0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 1.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Current: ${currentWeight.toStringAsFixed(1)} kg'),
                Text('Ideal: ${idealWeight.toStringAsFixed(1)} kg'),
              ],
            ),
            const SizedBox(height: 16.0),

            // Animated progress bar
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: progress),
              duration: animate ? const Duration(seconds: 1) : Duration.zero,
              builder: (context, value, child) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 10.0,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(5.0),
                      ),
                    ),
                    Container(
                      height: 10.0,
                      width: MediaQuery.of(context).size.width * value * 0.6,
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        borderRadius: BorderRadius.circular(5.0),
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 8.0),

            // Animated text for weight progress
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: progress),
              duration: animate ? const Duration(seconds: 1) : Duration.zero,
              builder: (context, value, child) {
                return Text(
                  '${(value * 100).toStringAsFixed(0)}% towards your ideal weight!',
                  style: const TextStyle(color: Colors.teal),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
