import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zinzi/features/payment/payment_plan_wall.dart';
import 'package:zinzi/features/subscription/subscription_provider.dart';
import 'package:flutter/foundation.dart';

class PaymentPlanGate extends StatefulWidget {
  final Widget child;
  final bool requirePlan;
  final VoidCallback? onPlanVerified;

  const PaymentPlanGate({
    Key? key,
    required this.child,
    this.requirePlan = true,
    this.onPlanVerified,
  }) : super(key: key);

  @override
  _PaymentPlanGateState createState() => _PaymentPlanGateState();

  // Helper method to check if a plan is required for a specific route
  static bool isPaymentRequiredForRoute(String routeName) {
    // Add any routes that require payment plan verification
    final protectedRoutes = [
      '/all-meals',
      // Add other protected routes here
    ];
    
    return protectedRoutes.contains(routeName);
  }
}

class _PaymentPlanGateState extends State<PaymentPlanGate> {
  bool _isLoading = true;
  bool _hasPlan = false;

  @override
  void initState() {
    super.initState();
    _checkPlanStatus();
  }

  Future<void> _checkPlanStatus() async {
    if (!widget.requirePlan) {
      setState(() {
        _hasPlan = true;
        _isLoading = false;
      });
      return;
    }

    try {
      // Get the subscription provider
      final subscriptionProvider = Provider.of<SubscriptionProvider>(
        context,
        listen: false,
      );

      // Load the subscription status
      await subscriptionProvider.loadSubscriptionStatus();

      setState(() {
        _hasPlan = subscriptionProvider.hasActiveSubscription;
        _isLoading = false;
      });

      if (subscriptionProvider.hasActiveSubscription) {
        widget.onPlanVerified?.call();
      }
    } catch (e) {
      debugPrint('Error checking subscription status: $e');
      // In case of error, allow access (fail open for better UX)
      setState(() {
        _hasPlan = true;
        _isLoading = false;
      });
    }
  }

  void _onPlanSelected() {
    // The actual plan selection and subscription is now handled by the PaymentPlanWall
    // which uses the SubscriptionProvider to manage the subscription state
    // This method is kept for backward compatibility but doesn't need to do anything
    // as the PaymentPlanWall will handle the subscription flow
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_hasPlan && widget.requirePlan) {
      return ChangeNotifierProvider.value(
        value: Provider.of<SubscriptionProvider>(context, listen: false),
        child: Consumer<SubscriptionProvider>(
          builder: (context, subscriptionProvider, _) {
            return PaymentPlanWall(
              onPlanSelected: _onPlanSelected,
              isLoading: subscriptionProvider.isLoading,
            );
          },
        ),
      );
    }

    return widget.child;
  }
}