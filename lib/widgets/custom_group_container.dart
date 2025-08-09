//cspell:disable
import 'package:flutter/material.dart';

/// Use this to wrap any metrics group that should NOT be wrapped in an extra border.
class CustomGroupContainer extends StatelessWidget {
  final Widget child;
  const CustomGroupContainer({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
