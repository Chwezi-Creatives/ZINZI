import 'package:flutter/material.dart';

class VibrationDurationDialog extends StatefulWidget {
  final int initialDuration;

  const VibrationDurationDialog({
    Key? key,
    required this.initialDuration,
  }) : super(key: key);

  @override
  State<VibrationDurationDialog> createState() => _VibrationDurationDialogState();
}

class _VibrationDurationDialogState extends State<VibrationDurationDialog> {
  late int _duration;

  @override
  void initState() {
    super.initState();
    _duration = widget.initialDuration;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vibration Duration'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select vibration duration (in milliseconds):'),
          Slider(
            value: _duration.toDouble(),
            min: 100,
            max: 1000,
            divisions: 9,
            label: '${_duration}ms',
            onChanged: (value) {
              setState(() {
                _duration = value.toInt();
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _duration),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
