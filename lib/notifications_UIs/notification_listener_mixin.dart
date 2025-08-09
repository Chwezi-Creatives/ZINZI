//cspell:disable
import 'package:flutter/material.dart';

mixin NotificationListenerMixin<T extends StatefulWidget> on State<T> {
  void onOrderStatusUpdate(String orderId, String status) {
    // To be implemented by the widget using this mixin
  }

  @override
  void dispose() {
    super.dispose();
  }
}
