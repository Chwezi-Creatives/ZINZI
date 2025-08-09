import 'package:flutter/material.dart';

class ChefSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> chefs;
  final Map<String, dynamic>? selectedChef;
  final Function(Map<String, dynamic>) onChefSelected;
  final bool isLoading;
  final bool hasError;

  const ChefSelectionDialog({
    Key? key,
    required this.chefs,
    this.selectedChef,
    required this.onChefSelected,
    this.isLoading = false,
    this.hasError = false,
  }) : super(key: key);

  @override
  _ChefSelectionDialogState createState() => _ChefSelectionDialogState();
}

class _ChefSelectionDialogState extends State<ChefSelectionDialog> {
  late TextEditingController _searchController;
  List<Map<String, dynamic>> _filteredChefs = [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredChefs = List.from(widget.chefs);
  }

  @override
  void didUpdateWidget(ChefSelectionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chefs != widget.chefs) {
      _filterChefs(_searchController.text);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterChefs(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredChefs = List.from(widget.chefs);
      });
      return;
    }

    final queryLower = query.toLowerCase();
    setState(() {
      _filteredChefs = widget.chefs.where((chef) {
        final name = chef['name']?.toString().toLowerCase() ?? '';
        final bio = chef['bio']?.toString().toLowerCase() ?? '';
        final specialties = chef['specialties'] is List
            ? (chef['specialties'] as List).map((e) => e.toString().toLowerCase()).toList()
            : <String>[];
        
        return name.contains(queryLower) ||
            bio.contains(queryLower) ||
            specialties.any((s) => s.contains(queryLower));
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select a Chef',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search chefs...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                isDense: true,
              ),
              onChanged: _filterChefs,
            ),
          ),
          
          // Loading indicator
          if (widget.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(),
            )
          
          // Error message
          else if (widget.hasError)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Failed to load chefs. Please try again.',
                style: TextStyle(color: Colors.red),
              ),
            )
          
          // Empty state
          else if (_filteredChefs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _searchController.text.isEmpty
                        ? 'No chefs available'
                        : 'No chefs found',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          
          // Chef list
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredChefs.length,
                itemBuilder: (context, index) {
                  final chef = _filteredChefs[index];
                  final isSelected = widget.selectedChef?['id'] == chef['id'];
                  
                  return _buildChefTile(chef, isSelected);
                },
              ),
            ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildChefTile(Map<String, dynamic> chef, bool isSelected) {
    final name = chef['name']?.toString() ?? 'Unknown Chef';
    final bio = chef['bio']?.toString() ?? '';
    final imageUrl = chef['image_url']?.toString();
    final specialties = chef['specialties'] is List
        ? (chef['specialties'] as List).map((e) => e.toString()).toList()
        : <String>[];

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: imageUrl != null && imageUrl.isNotEmpty
            ? NetworkImage(imageUrl) as ImageProvider
            : const AssetImage('assets/images/chef_placeholder.png'),
        backgroundColor: Colors.grey[200],
        onBackgroundImageError: (_, __) {
          // Handle image loading error
        },
        child: imageUrl == null || imageUrl.isEmpty
            ? const Icon(Icons.person, size: 24, color: Colors.grey)
            : null,
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bio.isNotEmpty)
            Text(
              bio,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          if (specialties.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: specialties.take(3).map((specialty) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    specialty,
                    style: TextStyle(
                      color: Colors.blue[800],
                      fontSize: 11,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.green)
          : null,
      onTap: () {
        widget.onChefSelected(chef);
        Navigator.pop(context, chef);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }
}

// Extension to show the dialog
Future<Map<String, dynamic>?> showChefSelectionDialog({
  required BuildContext context,
  required List<Map<String, dynamic>> chefs,
  Map<String, dynamic>? selectedChef,
  bool isLoading = false,
  bool hasError = false,
}) async {
  return await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (_, controller) => ChefSelectionDialog(
        chefs: chefs,
        selectedChef: selectedChef,
        onChefSelected: (chef) {},
        isLoading: isLoading,
        hasError: hasError,
      ),
    ),
  );
}
