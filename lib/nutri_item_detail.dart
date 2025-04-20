import 'package:flutter/material.dart';

class NutritionItemDetailPage extends StatelessWidget {
  const NutritionItemDetailPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Coming Soon",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text(
          "This feature is coming soon!",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
