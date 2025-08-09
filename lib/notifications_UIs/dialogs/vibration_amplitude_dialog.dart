//cspell:disable
import 'package:flutter/material.dart';

class VibrationAmplitudeDialog extends StatefulWidget {
  final int initialAmplitude;

  const VibrationAmplitudeDialog({
    Key? key,
    required this.initialAmplitude,
  }) : super(key: key);

  @override
  State<VibrationAmplitudeDialog> createState() => _VibrationAmplitudeDialogState();
}

class _VibrationAmplitudeDialogState extends State<VibrationAmplitudeDialog> {
  late int _amplitude;

  @override
  void initState() {
    super.initState();
    _amplitude = widget.initialAmplitude;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vibration Intensity'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select vibration intensity (0-255):'),
          Slider(
            value: _amplitude.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            label: '${_amplitude}/255',
            onChanged: (value) {
              setState(() {
                _amplitude = value.toInt();
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
          onPressed: () => Navigator.pop(context, _amplitude),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
