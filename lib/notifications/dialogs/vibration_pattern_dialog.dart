import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

class VibrationPatternDialog extends StatefulWidget {
  final List<int>? initialPattern;

  const VibrationPatternDialog({
    Key? key,
    this.initialPattern,
  }) : super(key: key);

  @override
  State<VibrationPatternDialog> createState() => _VibrationPatternDialogState();
}

class _VibrationPatternDialogState extends State<VibrationPatternDialog> {
  late List<int> _pattern;
  final _patternController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pattern = widget.initialPattern ?? [0, 500, 200, 500];
    _patternController.text = _pattern.join(',');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom Vibration Pattern'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter vibration pattern (comma-separated values):'),
          TextField(
            controller: _patternController,
            decoration: const InputDecoration(
              hintText: 'Example: 0,500,200,500 (delay,duration,delay,duration)',
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              try {
                final pattern = value.split(',').map(int.parse).toList();
                if (pattern.length >= 2 && pattern.every((v) => v >= 0)) {
                  setState(() {
                    _pattern = pattern;
                  });
                }
              } catch (e) {
                setState(() {
                  _pattern = [0, 500, 200, 500];
                });
              }
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              if (await Vibration.hasVibrator() == true) {
                await Vibration.vibrate(pattern: _pattern);
              }
            },
            child: const Text('Test Pattern'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _pattern),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
