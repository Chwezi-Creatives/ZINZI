import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zinzi/features/subscription/models/plan_model.dart';
import 'package:zinzi/features/subscription/services/plan_service.dart';


class ConsolePlansTab extends StatefulWidget {
  final PlanService planService;
  
  const ConsolePlansTab({super.key, required this.planService});

  @override
  State<ConsolePlansTab> createState() => _ConsolePlansTabState();
}

class _ConsolePlansTabState extends State<ConsolePlansTab> {
  List<Plan> _plans = [];
  bool _isLoading = true;
  String? _error;
  bool _showInactive = false;
  bool _showCreateButton = false;

  @override
  void initState() {
    super.initState();
    debugPrint('PlansUI: Initializing PlansTab');
    _fetchPlans();
  }

  Future<void> _fetchPlans() async {
    debugPrint('PlansUI: Fetching plans with showInactive=$_showInactive');
    setState(() => _isLoading = true);
    try {
      _plans = await widget.planService.getPlans(includeInactive: _showInactive);
      debugPrint('PlansUI: Successfully fetched ${_plans.length} plans');
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            // Header with title and toggle on separate lines
            Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 16.0, 24.0, 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available Plans', 
                    style: TextStyle(
                      fontSize: 20, 
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1976D2), // Blue color for header
                    ),
                  ),
                ],
              ),
            ),
            // Status indicator and toggle row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _isLoading
                      ? const Text('Loading plans...', style: TextStyle(color: Color(0xFF1976D2)))
                      : _error != null
                          ? Text('Error: $_error', style: const TextStyle(color: Colors.red))
                          : Text(
                              _plans.isEmpty 
                                  ? 'No plans found' 
                                  : '${_plans.length} plan${_plans.length == 1 ? '' : 's'} found',
                              style: TextStyle(
                                color: _plans.isEmpty 
                                    ? const Color(0xFF388E3C) // Green for empty state
                                    : const Color(0xFF388E3C), // Also Green when plans exist
                                fontSize: 14.0,
                              ),
                            ),
                  Row(
                    children: [
                      const Text(
                        'Show Inactive',
                        style: TextStyle(fontSize: 14.0, color: Color(0xFF666666)),
                      ),
                      const SizedBox(width: 8.0),
                      Switch(
                        value: _showInactive,
                        onChanged: (value) {
                          setState(() => _showInactive = value);
                          _fetchPlans();
                        },
                        activeColor: const Color(0xFF00897B),
                        activeTrackColor: const Color(0x8000897B),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Plans list or loading/error state
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00897B)),
                  ),
                ),
              )
            else if (_error != null)
              const SizedBox.shrink() // Error already shown in the status row
            else if (_plans.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No plans match your criteria',
                    style: TextStyle(color: Color(0xFF666666)),
                  ),
                ),
              )
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate crossAxisCount based on screen width
                    final crossAxisCount = (constraints.maxWidth / 400).floor().clamp(1, 3);
                    return GridView.builder(
                      padding: const EdgeInsets.all(16.0),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16.0,
                        mainAxisSpacing: 16.0,
                        childAspectRatio: 0.75, // Adjust this to control card height
                      ),
                      itemCount: _plans.length,
                      itemBuilder: (context, index) {
                        final plan = _plans[index];
                        return PlanCard(
                          plan: plan,
                          onEdit: () => _showPlanForm(plan: plan),
                          onDelete: () => _deletePlan(plan),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
        Positioned(
          bottom: 24,
          right: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_showCreateButton) ...[ 
                // Add a subtle animation for the reveal
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 150),
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: Opacity(
                        opacity: value,
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.withAlpha(25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() => _showCreateButton = false);
                        _showPlanForm();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF00897B),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 20, color: Colors.white),
                      label: const Text('Create New Plan', 
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8), // Space between button and FAB
              FloatingActionButton(
                onPressed: () {
                  setState(() => _showCreateButton = !_showCreateButton);
                },
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white,
                elevation: 4,
                highlightElevation: 8,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: _showCreateButton 
                      ? const Icon(Icons.close, key: ValueKey('close_icon')) 
                      : const Icon(Icons.add, key: ValueKey('add_icon')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showPlanForm({Plan? plan}) async {
    final isEditing = plan != null;
    final formKey = GlobalKey<FormState>();
    debugPrint('PlansUI: ${isEditing ? 'Editing' : 'Creating new'} plan form opened');
    
    // Create controllers with plan data or default values
    final nameController = TextEditingController(text: plan?.name ?? '');
    final descriptionController = TextEditingController(text: plan?.description ?? '');
    final priceController = TextEditingController(text: plan?.price.toString() ?? '');
    
    // Default values for new plans
    var billingCycle = plan?.billingCycle ?? BillingCycle.monthly;
    final features = <String>[...(plan?.features ?? [])]; // Create a new list to ensure state updates
    var isActive = plan?.isActive ?? true;

    await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9, // 90% of screen width
            maxHeight: MediaQuery.of(context).size.height * 0.9, // 90% of screen height
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Edit Plan' : 'Create New Plan',
                  style: const TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 24),
                Flexible(
                  child: SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: nameController,
                            style: const TextStyle(color: Color(0xFF333333)),
                            decoration: InputDecoration(
                              labelText: 'Plan Name',
                              labelStyle: const TextStyle(color: Color(0xFF666666)),
                              enabledBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Color(0xFFDDDDDD)),
                              ),
                              focusedBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Color(0xFF00897B)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              isDense: true,
                            ),
                            validator: (value) =>
                                value?.isEmpty ?? true ? 'Name is required' : null,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: descriptionController,
                            style: const TextStyle(color: Color(0xFF333333)),
                            decoration: InputDecoration(
                              labelText: 'Description',
                              labelStyle: const TextStyle(color: Color(0xFF666666)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFF00897B)),
                              ),
                              contentPadding: const EdgeInsets.all(12),
                              alignLabelWithHint: true,
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: priceController,
                            style: const TextStyle(color: Color(0xFF333333)),
                            decoration: InputDecoration(
                              labelText: 'Price (UGX)',
                              labelStyle: const TextStyle(color: Color(0xFF666666)),
                              prefixText: 'UGX ',
                              prefixStyle: const TextStyle(
                                color: Color(0xFF333333),
                                fontWeight: FontWeight.w500,
                              ),
                              enabledBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Color(0xFFDDDDDD)),
                              ),
                              focusedBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Color(0xFF00897B)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                            validator: (value) {
                              if (value?.isEmpty ?? true) return 'Price is required';
                              if (double.tryParse(value!) == null) return 'Invalid number';
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          DropdownButtonFormField<BillingCycle>(
                            value: billingCycle,
                            dropdownColor: Colors.white,
                            style: const TextStyle(color: Color(0xFF333333), fontSize: 16),
                            decoration: InputDecoration(
                              labelText: 'Billing Cycle',
                              labelStyle: const TextStyle(color: Color(0xFF666666)),
                              enabledBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Color(0xFFDDDDDD)),
                              ),
                              focusedBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Color(0xFF00897B)),
                              ),
                              contentPadding: const EdgeInsets.only(top: 12, bottom: 12),
                              isDense: true,
                            ),
                            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF666666)),
                            items: BillingCycle.values.map((cycle) {
                              return DropdownMenuItem(
                                value: cycle,
                                child: Text(
                                  cycle.displayName,
                                  style: const TextStyle(color: Color(0xFF333333)),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                billingCycle = value;
                              }
                            },
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Features:',
                            style: TextStyle(
                              color: Color(0xFF333333),
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          StatefulBuilder(
                            builder: (context, setState) {
                              return _buildFeatureChips(
                                features,
                                (feature) {
                                  // Update the local state when a feature is deleted
                                  setState(() {
                                    features.remove(feature);
                                  });
                                  // Also update the parent state to ensure UI refreshes
                                  if (mounted) {
                                    setState(() {});
                                  }
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Color(0xFF666666)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        debugPrint('🔄 Plan form submit button pressed');
                            
                        if (formKey.currentState?.validate() ?? false) {
                          debugPrint('✅ Form validation passed');
                              
                          try {
                            final planData = PlanCreateUpdateRequest(
                              name: nameController.text.trim(),
                              description: descriptionController.text.trim(),
                              price: double.tryParse(priceController.text) ?? 0.0,
                              billingCycle: billingCycle,
                              features: features,
                              isActive: isActive,
                            );

                            debugPrint('📝 Prepared plan data: ${planData.toJson()}');

                            if (isEditing) {
                              final planId = plan.id;
                              debugPrint('🔄 Updating plan ID: $planId');
                              await widget.planService.updatePlan(planId, planData);
                              debugPrint('✅ Plan update request completed');
                            } else {
                              debugPrint('🆕 Creating new plan');
                              await widget.planService.createPlan(planData);
                              debugPrint('✅ Plan creation request completed');
                            }
                            
                            if (mounted) {
                              debugPrint('✅ Dismissing plan form');
                              Navigator.of(context).pop(true);
                              _fetchPlans(); // Refresh the plans list
                            }
                          } catch (e, stackTrace) {
                            debugPrint('❌ Error ${isEditing ? 'updating' : 'creating'} plan: $e');
                            debugPrint('Stack trace: $stackTrace');
                                
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to ${isEditing ? 'update' : 'create'} plan: ${e.toString()}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        isEditing ? 'Update Plan' : 'Create Plan',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureChips(List<String> features, Function(String) onDelete) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (features.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: features.map((feature) => Chip(
                  label: Text(feature),
                  backgroundColor: Colors.grey[50],
                  deleteIcon: const Icon(Icons.close, size: 16, color: Color(0xFF666666)),
                  onDeleted: () {
                    onDelete(feature);
                    // Force a rebuild of the parent widget
                    if (mounted) {
                      setState(() {});
                    }
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFDDDDDD)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  labelPadding: const EdgeInsets.only(right: 4),
                )).toList(),
              ),
              const SizedBox(height: 8),
            ],
            ActionChip(
              label: const Text(
                '+ Add Feature',
                style: TextStyle(
                  color: Color(0xFF1E88E5),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              backgroundColor: Colors.blue[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFBBDEFB)),
              ),
              onPressed: () => _addNewFeature(context, (newFeature) {
                if (newFeature.isNotEmpty) {
                  setState(() {
                    features.add(newFeature);
                  });
                  // Also update the parent state to ensure UI refreshes
                  if (mounted) {
                    setState(() {});
                  }
                }
              }),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addNewFeature(
    BuildContext context,
    Function(String) onAdd,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Feature'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Feature',
            hintText: 'Enter a feature',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      onAdd(controller.text.trim());
    }
  }

  Future<bool?> _deletePlan(Plan plan) async {
    debugPrint('Initiating delete for plan: ${plan.id} (${plan.name})');
        
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Plan'),
        content: Text('Are you sure you want to delete "${plan.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('PlansUI: Delete cancelled by user');
              Navigator.of(context).pop(false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              debugPrint('PlansUI: User confirmed delete for plan: ${plan.id}');
              Navigator.of(context).pop(true);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return false;
      
      setState(() => _isLoading = true);
      
      try {
        debugPrint('Deleting plan: ${plan.id}');
        await widget.planService.deletePlan(plan.id);
        debugPrint('PlansUI: Successfully deleted plan: ${plan.id}');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Successfully deleted plan: ${plan.name}'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
          _fetchPlans();
        }
      } catch (e) {
        debugPrint('PlansUI: ❌ Failed to delete plan: $e');
        if (mounted) {
          final errorMessage = e.toString().contains('active subscriptions') 
              ? 'Cannot delete plan: There are active subscribers. Please cancel all subscriptions firs or wait for them to expire.'
              : 'Failed to delete plan. Please try again.';
              
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
            ),
          );
        }
        return false;
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
    return false;
  }
}

class PlanCard extends StatelessWidget {
  final Plan plan;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const PlanCard({
    super.key,
    required this.plan,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with plan name and price
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4.0),
                topRight: Radius.circular(4.0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!plan.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Inactive',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'UGX ${plan.priceAsDouble.toStringAsFixed(0)} / ${plan.billingCycle.displayName}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF00897B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          // Plan description
          if (plan.description?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                plan.description!,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),
          
          // Features section
          if (plan.features.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
              child: Text(
                'Features:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: plan.features.map((feature) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Color(0xFF00897B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ],
          
          // Spacer to push buttons to bottom
          const Spacer(),
          
          // Action buttons - Aligned to the left
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8.0),
                TextButton.icon(
                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
