//cspell:disable
import 'package:flutter/material.dart';
import 'notification_widget.dart';

void showNotificationPanel(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const SizedBox(
      height: 400,
      child: NotificationWidget(),
    ),
  );
}
