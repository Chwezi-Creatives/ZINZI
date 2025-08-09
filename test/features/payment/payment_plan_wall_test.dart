import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zinzi/features/payment/payment_plan_wall.dart';
import 'package:zinzi/features/payment/payment_service.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    
    // Set up SharedPreferences
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    
    // Clear any existing data
    await prefs.clear();
  });

  testWidgets('PaymentPlanWall shows plan options', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentPlanWall(
          onPlanSelected: () {},
          isLoading: false,
        ),
      ),
    );

    // Verify the title is shown
    expect(find.text('Unlock All Meals'), findsOneWidget);
    
    // Verify both plan options are shown
    expect(find.text('Bi-Weekly Plan'), findsOneWidget);
    expect(find.text('Monthly Plan'), findsOneWidget);
    
    // Verify features are shown
    expect(find.text('Unlimited access to all meals'), findsNWidgets(2));
    expect(find.text('Free delivery on all orders'), findsNWidgets(2));
  });

  testWidgets('PaymentPlanWall shows loading state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentPlanWall(
          onPlanSelected: () {},
          isLoading: true,
        ),
      ),
    );

    // Should show loading indicators in plan cards when isLoading is true
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2)); // One for each plan card
  });

  test('PaymentService sets and gets active plan', () async {
    // Clear any existing data first
    await prefs.clear();
    // Test setting and getting active plan
    final expiryDate = DateTime.now().add(const Duration(days: 14));
    
    // Set plan
    final result = await PaymentService.setActivePlan('monthly', durationInDays: 14);
    expect(result, isTrue);
    
    // Check plan status
    final hasPlan = await PaymentService.hasActivePlan();
    expect(hasPlan, isTrue);
    
    // Get plan details
    final planType = await PaymentService.getActivePlan();
    expect(planType, 'monthly');
    
    final planExpiry = await PaymentService.getPlanExpiryDate();
    expect(planExpiry, isNotNull);
    expect(planExpiry!.difference(expiryDate).inMinutes, lessThan(1)); // Within 1 minute
  });
  
  test('PaymentService handles expired plans', () async {
    // Set an expired plan
    final pastDate = DateTime.now().subtract(const Duration(days: 1));
    await prefs.setString('active_payment_plan', 'monthly');
    await prefs.setString('plan_expiry_date', pastDate.toIso8601String());
    
    // Should detect expired plan
    final hasPlan = await PaymentService.hasActivePlan();
    expect(hasPlan, isFalse);
    
    // Should clear expired plan details
    final planType = await PaymentService.getActivePlan();
    expect(planType, isNull);
  });
}
