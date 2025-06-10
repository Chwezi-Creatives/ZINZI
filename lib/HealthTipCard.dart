//cspell:disable
import 'package:flutter/material.dart';

class HealthTipCard extends StatelessWidget {
  final double bmi;

  const HealthTipCard({
    Key? key,
    required this.bmi,
  }) : super(key: key);

  String _getHealthTip() {
    if (bmi < 18.5) {
      return 'Tip: Increase calorie intake and consider consulting a nutritionist.';
    } else if (bmi < 25) {
      return 'Great job! Maintain a balanced diet and stay active.';
    } else if (bmi < 30) {
      return 'Tip: Incorporate regular exercise and monitor your diet.';
    } else {
      return 'Tip: Consult a healthcare provider for personalized advice.';
    }
  }

  @override
  Widget build(BuildContext context) {
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
              'Health Tips',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 16.0),

            // Health tip card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3.0,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _getHealthTip(),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
