import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../features/subscription/subscription_provider.dart';
import 'subscription_payment_dialog.dart';

class PaymentPlanWall extends StatefulWidget {
  final VoidCallback? onPlanSelected;
  final bool isLoading;

  const PaymentPlanWall({
    Key? key,
    this.onPlanSelected,
    this.isLoading = false,
  }) : super(key: key);

  @override
  _PaymentPlanWallState createState() => _PaymentPlanWallState();
}

class _PaymentPlanWallState extends State<PaymentPlanWall> {
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Load subscription plans when widget initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPlans();
    });
  }

  Future<void> _loadPlans() async {
    final provider = context.read<SubscriptionProvider>();
    await provider.loadSubscriptionPlans();
  }

  Future<void> _handlePlanSelected(int planId) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Find the selected plan
      final provider = context.read<SubscriptionProvider>();
      final plan = provider.plans.firstWhere((p) => p.id == planId);
      
      // Show the payment dialog
      final paymentSuccessful = await showDialog<bool>(
        context: context,
        builder: (context) => SubscriptionPaymentDialog(
          plan: plan,
        ),
      ) ?? false;

      if (paymentSuccessful && mounted) {
        // Call the onPlanSelected callback if payment was successful
        if (widget.onPlanSelected != null) {
          widget.onPlanSelected!();
        }

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subscription successful!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to process subscription. Please try again.';
      });
      debugPrint('Subscription error: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionProvider>(
      builder: (context, subscriptionProvider, _) {
        final isLoading =
            widget.isLoading || _isProcessing || subscriptionProvider.isLoading;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Choose Your Plan'),
            backgroundColor: const Color(0xFF00796B),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFE0F2F1), Color(0xFFB2DFDB)],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Header
                    Text(
                      'Unlock All Meals',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF004D40),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Choose a subscription plan to access our full menu of delicious meals',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: const Color(0xFF455A64),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),

                    // Error message
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          _errorMessage!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // Loading indicator
                    if (subscriptionProvider.plans.isEmpty &&
                        subscriptionProvider.isLoading)
                      const CircularProgressIndicator()
                    else if (subscriptionProvider.plans.isEmpty)
                      const Text('No subscription plans available')
                    else
                      ..._buildPlanCards(
                          context, subscriptionProvider, isLoading),

                    const SizedBox(height: 32),

                    // Terms and Conditions
                    Text(
                      'By subscribing, you agree to our Terms of Service and Privacy Policy',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: const Color(0xFF78909C),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        // TODO: Handle terms and privacy policy
                      },
                      child: const Text(
                          'View Terms of Service and Privacy Policy'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildPlanCards(
    BuildContext context,
    SubscriptionProvider provider,
    bool isLoading,
  ) {
    return provider.plans.map((plan) {
      final isPopular = plan.name.toLowerCase().contains('bi-weekly') ||
          plan.name.toLowerCase().contains('Bi weekly');
      final priceInShillings = plan.price.toInt(); // Display the price as is
      final period = plan.billingCycle.toLowerCase().contains('month')
          ? 'per month'
          : 'every 2 weeks';

      // Use features from the plan, or fallback to default if empty
      final features = plan.features.isNotEmpty 
          ? plan.features 
          : [
              'Unlimited access to all meals',
              'Free delivery on all orders',
              'Exclusive member discounts',
              if (plan.billingCycle.toLowerCase().contains('month'))
                'Priority customer support',
              'Cancel anytime',
            ];

      return Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: _buildPlanCard(
          context,
          title: plan.name,
          price: 'UGX $priceInShillings',
          period: period,
          features: features,
          isPopular: isPopular,
          onTap: () => _handlePlanSelected(plan.id),
          isLoading: isLoading,
        ),
      );
    }).toList();
  }

  Widget _buildPlanCard(
    BuildContext context, {
    required String title,
    required String price,
    required String period,
    required List<String> features,
    required bool isPopular,
    required VoidCallback? onTap,
    required bool isLoading,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPopular ? const Color(0xFFFFA000) : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'MOST POPULAR',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFE65100),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF004D40),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                price,
                style: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF00796B),
                ),
              ),
              Text(
                period,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF546E7A),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(height: 1, color: Color(0xFFB0BEC5)),
              const SizedBox(height: 16),
              ...features.map((feature) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 20,
                          color: Color(0xFF00796B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            feature,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: const Color(0xFF37474F),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00796B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Get Started',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
