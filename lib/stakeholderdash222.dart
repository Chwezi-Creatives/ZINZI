import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart'; // For formatting numbers/currency

// --- Reusing Color Palette (from previous examples) ---
const Color kColorPrimary = Color(0xFF00796B); // Teal Primary
const Color kColorPrimaryDark = Color(0xFF004D40); // Darker Teal
const Color kColorPrimaryLight = Color(0xFFB2DFDB); // Lighter Teal
const Color kColorAccent = Color(0xFFFFAB40); // Orange Accent
const Color kColorBackground = Color(0xFFF5F5F5); // Light Grey Background
const Color kColorSurface = Colors.white;
const Color kColorTextPrimary = Color(0xFF212121);
const Color kColorTextSecondary = Color(0xFF757575);
const Color kColorError = Color(0xFFD32F2F);
const Color kColorSuccess = Color(0xFF2E7D32); // Darker Green for Success
const Color kColorWarning = Color(0xFFFFA000); // Amber/Orange for Warning
const Color kColorDivider = Color(0xFFE0E0E0);
// --- End Color Palette ---

class stakeholderdas2222 extends StatefulWidget {
  const stakeholderdas2222({super.key});

  @override
  State<stakeholderdas2222> createState() => _stakeholderdas2222State();
}

class _stakeholderdas2222State extends State<stakeholderdas2222> {
  // --- UI Styling Constants ---
  static const double _horizontalPadding = 16.0;
  static const double _verticalPadding = 16.0;
  static const double _sectionSpacing = 20.0;
  static const double _cardElevation = 1.5;
  static const double _cardCornerRadius = 12.0;

  // --- Dummy Data ---
  final String stakeholderName = "Alice's Cuisine"; // Example Name
  final String stakeholderImageUrl =
      "https://placeholder.com/profile.jpg"; // Placeholder
  final int totalOrders = 138;
  final double monthlyEarnings = 975.50;
  final double averageRating = 4.7;
  final int pendingOrders = 5;

  final List<Map<String, dynamic>> recentOrders = [
    {
      'id': '#2105',
      'customer': 'Bob Johnson',
      'amount': 25.50,
      'status': 'Delivered'
    },
    {
      'id': '#2104',
      'customer': 'Charlie Brown',
      'amount': 15.00,
      'status': 'Processing'
    },
    {
      'id': '#2103',
      'customer': 'Diana Prince',
      'amount': 32.75,
      'status': 'Pending'
    },
    {
      'id': '#2101',
      'customer': 'Ethan Hunt',
      'amount': 18.20,
      'status': 'Delivered'
    },
  ];
  // --- End Dummy Data ---

  // --- Helper for Number Formatting ---
  final currencyFormatter =
      NumberFormat.currency(locale: 'en_US', symbol: '\$');
  final numberFormatter = NumberFormat.decimalPattern('en_US');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kColorBackground,
      appBar: AppBar(
        title: Text('Dashboard',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: kColorPrimary,
        foregroundColor: kColorSurface,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_outlined),
            tooltip: 'Notifications',
            onPressed: () {
              // TODO: Implement Notifications action
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Notifications Tapped (Not Implemented)')));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Logout',
            onPressed: () {
              // TODO: Implement Logout action
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Logout Tapped (Not Implemented)')));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: kColorPrimary,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(_horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWelcomeHeader(),
                const SizedBox(height: _sectionSpacing),
                _buildMetricsGrid(),
                const SizedBox(height: _sectionSpacing),
                _buildRecentOrdersCard(),
                const SizedBox(height: _sectionSpacing),
                _buildQuickActionsCard(),
                const SizedBox(height: _verticalPadding), // Bottom padding
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Pull-to-Refresh Handler ---
  Future<void> _handleRefresh() async {
    // Simulate fetching new data
    await Future.delayed(const Duration(seconds: 1));
    // In a real app, you'd fetch data here and call setState if needed
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Dashboard refreshed!', style: GoogleFonts.poppins()),
      backgroundColor: kColorPrimaryLight,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.all(10),
    ));
  }

  // --- Widget Builders ---

  Widget _buildWelcomeHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: kColorPrimaryLight,
            // backgroundImage: NetworkImage(stakeholderImageUrl), // Use if URL is real
            child: const Icon(Icons.storefront_outlined,
                color: kColorPrimaryDark, size: 30), // Placeholder Icon
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: GoogleFonts.poppins(
                      fontSize: 15, color: kColorTextSecondary),
                ),
                Text(
                  stakeholderName,
                  style: GoogleFonts.poppins(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: kColorTextPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return GridView.count(
      crossAxisCount: 2, // 2 cards per row
      shrinkWrap: true, // Important for GridView in SingleChildScrollView
      physics:
          const NeverScrollableScrollPhysics(), // Disable GridView's own scrolling
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4, // Adjust aspect ratio (width/height) as needed
      children: [
        _buildMetricCard(
          Icons.receipt_long_outlined,
          'Total Orders',
          numberFormatter.format(totalOrders),
          kColorPrimary,
        ),
        _buildMetricCard(
          Icons.attach_money_outlined,
          'Monthly Earnings',
          currencyFormatter.format(monthlyEarnings),
          kColorSuccess,
        ),
        _buildMetricCard(
          Icons.star_border_outlined,
          'Average Rating',
          '$averageRating ⭐', // Add star emoji
          kColorAccent,
        ),
        _buildMetricCard(
          Icons.pending_actions_outlined,
          'Pending Orders',
          numberFormatter.format(pendingOrders),
          Color(0xFFFB8C00), // Darker warning
        ),
      ],
    );
  }

  Widget _buildMetricCard(
      IconData icon, String label, String value, Color color) {
    return Card(
      elevation: _cardElevation,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardCornerRadius)),
      color: kColorSurface,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween, // Space out elements
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: kColorTextPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: kColorTextSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentOrdersCard() {
    return Card(
      elevation: _cardElevation,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardCornerRadius)),
      color: kColorSurface,
      child: Padding(
        padding: const EdgeInsets.only(
            top: _verticalPadding, bottom: 8), // Less bottom padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: _horizontalPadding),
              child: Text(
                'Recent Orders',
                style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: kColorPrimary),
              ),
            ),
            const SizedBox(height: 8),
            // Build list tiles from dummy data
            if (recentOrders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: _horizontalPadding, vertical: 20),
                child: Center(
                    child: Text("No recent orders.",
                        style:
                            GoogleFonts.poppins(color: kColorTextSecondary))),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentOrders.length,
                itemBuilder: (context, index) {
                  final order = recentOrders[index];
                  return _buildOrderListTile(
                    order['id'],
                    order['customer'],
                    order['amount'],
                    order['status'],
                  );
                },
                separatorBuilder: (context, index) => const Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 16,
                    endIndent: 16,
                    color: kColorDivider),
              ),

            // "View All" Button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  // TODO: Implement View All Orders navigation
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content:
                          Text('View All Orders Tapped (Not Implemented)')));
                },
                style: TextButton.styleFrom(foregroundColor: kColorPrimary),
                child: Text(
                  'View All Orders',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderListTile(
      String orderId, String customerName, double amount, String status) {
    Color statusColor = kColorTextSecondary;
    IconData statusIcon = Icons.help_outline; // Default

    switch (status.toLowerCase()) {
      case 'delivered':
      case 'completed':
        statusColor = kColorSuccess;
        statusIcon = Icons.check_circle_outline;
        break;
      case 'processing':
      case 'preparing':
        statusColor = Colors.blue.shade700;
        statusIcon = Icons.hourglass_top_outlined;
        break;
      case 'pending':
        statusColor = const Color(0xFFFB8C00); // Darker shade of amber
        statusIcon = Icons.pending_outlined;
        break;
      case 'cancelled':
      case 'failed':
        statusColor = kColorError;
        statusIcon = Icons.cancel_outlined;
        break;
    }

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: statusColor.withOpacity(0.1),
        foregroundColor: statusColor,
        radius: 18,
        child: Icon(statusIcon, size: 18),
      ),
      title: Text(
        'Order $orderId',
        style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: kColorTextPrimary),
      ),
      subtitle: Text(
        customerName,
        style: GoogleFonts.poppins(fontSize: 12, color: kColorTextSecondary),
      ),
      trailing: Text(
        currencyFormatter.format(amount),
        style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: kColorTextPrimary),
      ),
      onTap: () {
        // TODO: Implement tap action to view order details
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order $orderId Tapped (Not Implemented)')));
      },
    );
  }

  Widget _buildQuickActionsCard() {
    return Card(
      elevation: _cardElevation,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardCornerRadius)),
      color: kColorSurface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: 8.0), // Less vertical padding for list tiles
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  left: _horizontalPadding,
                  right: _horizontalPadding,
                  top: _verticalPadding / 2,
                  bottom: 8),
              child: Text(
                'Quick Actions',
                style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: kColorPrimary),
              ),
            ),
            _buildActionTile(Icons.person_outline, 'Manage Profile', () {
              // TODO: Navigate to Profile Management
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Manage Profile Tapped (Not Implemented)')));
            }),
            const Divider(
                height: 1,
                thickness: 0.5,
                indent: 16,
                endIndent: 16,
                color: kColorDivider),
            _buildActionTile(
                Icons.restaurant_menu_outlined, 'Update Menu/Offerings', () {
              // TODO: Navigate to Menu Management
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Update Menu Tapped (Not Implemented)')));
            }),
            const Divider(
                height: 1,
                thickness: 0.5,
                indent: 16,
                endIndent: 16,
                color: kColorDivider),
            _buildActionTile(
                Icons.account_balance_wallet_outlined, 'View Payout History',
                () {
              // TODO: Navigate to Payout History
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('View Payouts Tapped (Not Implemented)')));
            }),
            const Divider(
                height: 1,
                thickness: 0.5,
                indent: 16,
                endIndent: 16,
                color: kColorDivider),
            _buildActionTile(Icons.support_agent_outlined, 'Contact Support',
                () {
              // TODO: Implement Contact Support action
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Contact Support Tapped (Not Implemented)')));
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: kColorPrimary, size: 22),
      title: Text(
        title,
        style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: kColorTextPrimary),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: kColorTextSecondary, size: 20),
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: _horizontalPadding, vertical: 2), // Adjust padding
    );
  }

  // --- End Widget Builders ---
}
