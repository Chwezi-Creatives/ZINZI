import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:zinzi/features/subscription/subscription_service.dart';

class ConsoleSubscriptionsTab extends StatefulWidget {
  final SubscriptionService subscriptionService;
  
  const ConsoleSubscriptionsTab({
    Key? key,
    required this.subscriptionService,
  }) : super(key: key);

  @override
  State<ConsoleSubscriptionsTab> createState() => _ConsoleSubscriptionsTabState();
}

class _ConsoleSubscriptionsTabState extends State<ConsoleSubscriptionsTab> {
  List<dynamic> _subscriptions = [];
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchSubscriptions();
  }

  Future<void> _fetchSubscriptions() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    print('🔍 [ConsoleSubscriptions] Fetching subscriptions...');
    
    try {
      final stopwatch = Stopwatch()..start();
      final subscriptions = await widget.subscriptionService.getAllSubscriptions();
      stopwatch.stop();
      
      print('✅ [ConsoleSubscriptions] Fetched ${subscriptions.length} subscriptions in ${stopwatch.elapsedMilliseconds}ms');
      print('📦 [ConsoleSubscriptions] First subscription data: ${subscriptions.isNotEmpty ? jsonEncode(subscriptions.first) : 'No subscriptions'}');
      
      if (!mounted) return;
      
      setState(() {
        _subscriptions = subscriptions;
        _error = null;
        print('🔄 [ConsoleSubscriptions] State updated with ${subscriptions.length} subscriptions');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load subscriptions: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateSubscriptionStatus(String subscriptionId, String status) async {
    print('🔄 [ConsoleSubscriptions] Starting status update for subscription $subscriptionId to $status');
    
    try {
      // Validate subscription ID
      if (subscriptionId.isEmpty || subscriptionId == 'null') {
        throw Exception('Invalid subscription ID: "$subscriptionId"');
      }

      print('✅ [ConsoleSubscriptions] Validated subscription ID: $subscriptionId');

      // Show loading indicator
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updating subscription status...')),
      );

      print('📡 [ConsoleSubscriptions] Calling subscription service...');
      
      // Call the API to update the subscription status
      final response = await widget.subscriptionService.updateSubscriptionStatus(
        subscriptionId: subscriptionId,
        status: status,
      );

      print('✅ [ConsoleSubscriptions] API call successful. Response: $response');

      // Refresh the subscriptions list
      print('🔄 [ConsoleSubscriptions] Refreshing subscriptions list...');
      await _fetchSubscriptions();

      // Show success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Subscription status updated to $status'),
          backgroundColor: Colors.green,
        ),
      );
      
      print('✅ [ConsoleSubscriptions] Status update completed successfully');
    } catch (e, stackTrace) {
      print('❌ [ConsoleSubscriptions] Error updating subscription status:');
      print('   Error: $e');
      print('   Stack trace: $stackTrace');
      
      if (!mounted) return;
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to update subscription: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      
      // Re-throw to allow error handling in the calling method
      rethrow;
    }
  }

  void _showSubscriptionDetails(Map<String, dynamic> subscription) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Subscription Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('User ID', subscription['user_id']?.toString() ?? 'N/A'),
              _buildDetailRow('Plan', subscription['plan_name']?.toString() ?? 'N/A'),
              _buildDetailRow('Status', subscription['status']?.toString().toUpperCase() ?? 'N/A'),
              _buildDetailRow('Start Date', _formatDate(subscription['start_date'])),
              _buildDetailRow('End Date', _formatDate(subscription['end_date'])),
              _buildDetailRow('Billing Cycle', subscription['billing_cycle']?.toString().toLowerCase() ?? 'N/A'),
              _buildDetailRow('Price', 'UGX ${_formatPrice(subscription['price'])}'),
              const SizedBox(height: 16),
              const Text(
                'Features:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              ..._parseFeatures(subscription['features'] ?? []).map((feature) => 
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                  child: Text('• $feature'),
                ),
              ).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    try {
      final number = price is num ? price : double.tryParse(price.toString()) ?? 0.0;
      return number.toStringAsFixed(0);  // Changed from 2 to 0 decimal places
    } catch (e) {
      return price.toString().replaceAll(RegExp(r'\.0+$'), '');  // Remove .0 if present
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) return '${date.toLocal()}'.split('.')[0];
    if (date is String) {
      try {
        return '${DateTime.parse(date).toLocal()}'.split('.')[0];
      } catch (e) {
        return date.toString();
      }
    }
    return date.toString();
  }

  List<String> _parseFeatures(dynamic features) {
    if (features == null) return [];
    if (features is List) {
      return features.map((e) => e.toString()).toList();
    }
    if (features is String) {
      try {
        final parsed = json.decode(features) as List;
        return parsed.map((e) => e.toString()).toList();
      } catch (e) {
        return [features.toString()];
      }
    }
    return [];
  }

  void _printSubscriptionDetails(dynamic subscription) {
    print('📋 [ConsoleSubscriptions] Subscription details:');
    print('   Subscription ID: ${subscription['subscription_id']}');
    print('   User: ${subscription['user_name']} (${subscription['user_id']})');
    print('   Plan: ${subscription['plan_name']} (${subscription['plan_id']})');
    print('   Status: ${subscription['status']}');
    print('   Start: ${subscription['start_date']}');
    print('   End: ${subscription['end_date']}');
    print('   Price: ${subscription['price']} ${subscription['billing_cycle']}');
    print('   All keys: ${subscription.keys.toList()}');
    print('   Subscription map type: ${subscription.runtimeType}');
    print('   Full subscription data: $subscription');
  }

  @override
  Widget build(BuildContext context) {
    print('🏗️ [ConsoleSubscriptions] Building widget with ${_subscriptions.length} subscriptions');
    if (_subscriptions.isNotEmpty) {
      print('📊 [ConsoleSubscriptions] First subscription in build: ${_subscriptions.first['id']}');
    }
    
    return Scaffold(
      body: _buildSubscriptionList(),
    );
  }

  Widget _buildSubscriptionList() {
    // Warning banner for admin
    final warningBanner = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'WARNING: Changes here directly affect user subscriptions. Please proceed with caution.',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    if (_isLoading) {
      print('⏳ [ConsoleSubscriptions] Showing loading indicator');
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      print('❌ [ConsoleSubscriptions] Error: $_error');
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    if (_subscriptions.isEmpty) {
      print('ℹ️ [ConsoleSubscriptions] No subscriptions to display');
      return const Center(child: Text('No subscriptions found'));
    }
    
    print('📱 [ConsoleSubscriptions] Building list with ${_subscriptions.length} subscriptions');
    if (_subscriptions.isEmpty) {
      return const Center(child: Text('No subscriptions found'));
    }
    
    return RefreshIndicator(
      onRefresh: _fetchSubscriptions,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _subscriptions.length + 1, // +1 for the warning banner
        itemBuilder: (context, index) {
          if (index == 0) return warningBanner;
          return _buildSubscriptionCard(_subscriptions[index - 1]);
        },
      ),
    );
  }

  Widget _buildSubscriptionCard(Map<String, dynamic> subscription) {
    print('🖼️ [ConsoleSubscriptions] Building card for subscription ${subscription['id']}');
    _printSubscriptionDetails(subscription);
    
    final status = subscription['status']?.toString().toLowerCase() ?? 'active';
    Color statusColor = Colors.green;
    
    if (status == 'expired') {
      statusColor = Colors.red;
    } else if (status == 'canceled' || status == 'cancelled') {  // Handle both US and UK spellings
      statusColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    subscription['plan_name']?.toString() ?? 'Unknown Plan',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha((statusColor.alpha * 0.1).round()),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withAlpha((statusColor.alpha * 0.3).round())),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildInfoChip(
                  Icons.person_outline,
                  'User: ${subscription['user_id'] ?? 'N/A'}',
                ),
                const SizedBox(width: 8),
                _buildInfoChip(
                  Icons.calendar_today,
                  'Expires: ${_formatDate(subscription['end_date']).split(' ')[0]}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'UGX ${_formatPrice(subscription['price'])}\n${subscription['billing_cycle']?.toString().toLowerCase() ?? ''}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _showSubscriptionDetails(subscription),
                      child: const Text('View Details'),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) async {
                        // Debug the subscription object
                        print('🔍 [ConsoleSubscriptions] Selected subscription: $subscription');
                        print('🔑 Subscription keys: ${subscription.keys.join(', ')}');
                        print('🔢 Subscription ID: ${subscription['subscription_id']} (type: ${subscription['subscription_id']?.runtimeType})');
                        
                        final subId = subscription['subscription_id']?.toString();
                        if (subId == null || subId == 'null') {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Error: Could not find subscription ID in the data'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        
                        try {
                          if (value == 'expire' || value == 'cancel') {
                            await _updateSubscriptionStatus(
                              subId,
                              value == 'expire' ? 'expired' : 'canceled',
                            );
                          } else if (value == 'activate') {
                            await _updateSubscriptionStatus(
                              subId,
                              'active',
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error updating subscription: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'expire',
                          child: Text('Mark as Expired'),
                        ),
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('Cancel Subscription'),
                        ),
                        const PopupMenuItem(
                          value: 'activate',
                          child: Text('Reactivate Subscription'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}
