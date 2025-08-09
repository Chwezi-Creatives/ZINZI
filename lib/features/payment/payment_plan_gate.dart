import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zinzi/features/meal_plan/choose_mealplan_meals.dart';
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
      if (mounted) {
        setState(() {
          _hasPlan = true;
          _isLoading = false;
        });
      }
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
      
      // Update state in the next frame
      if (mounted) {
        setState(() {
          _hasPlan = subscriptionProvider.hasActiveSubscription;
          _isLoading = false;
        });
        
        if (subscriptionProvider.hasActiveSubscription) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onPlanVerified?.call();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking subscription status: $e');
      // In case of error, allow access (fail open for better UX)
      if (mounted) {
        setState(() {
          _hasPlan = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onPlanSelected() async {
    if (!mounted) return;
    
    try {
      // Get the latest subscription status
      final subscriptionProvider = context.read<SubscriptionProvider>();
      await subscriptionProvider.loadSubscriptionStatus();
      
      if (subscriptionProvider.subscriptionStatus != null) {
        final subscriptionId = subscriptionProvider.subscriptionStatus!['subscription_id'];
        final planName = subscriptionProvider.subscriptionStatus!['current_plan']?['plan']?['name'] ?? 'Meal Plan';
        
        if (subscriptionId != null && mounted) {
          // Always navigate to ChooseMealPlanMealsScreen after successful payment
          // Even if there's an onPlanVerified callback, we'll still navigate to the meal selection
          if (mounted) {
            // Call the callback first if provided
            widget.onPlanVerified?.call();
            
            // Then navigate to the meal selection screen
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => ChooseMealPlanMealsScreen(
                  subscriptionId: subscriptionId as int,
                  subscriptionPlanName: planName as String,
                ),
              ),
            );
          }
          return;
        }
      }
      
      // Fallback to home if we couldn't get subscription details
      if (mounted) {
        // Still call the callback if provided
        widget.onPlanVerified?.call();
        
        // Then navigate to home as fallback
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          Navigator.of(context).pushReplacementNamed('/');
        }
      }
    } catch (e) {
      debugPrint('Error in payment plan selection: $e');
      if (mounted) {
        widget.onPlanVerified?.call();
        if (!context.mounted) return;
        
        // If the callback didn't navigate, go to home
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          Navigator.of(context).pushReplacementNamed('/');
        }
      }
    }
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