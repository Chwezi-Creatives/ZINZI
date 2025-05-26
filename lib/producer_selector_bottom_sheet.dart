import 'package:flutter/material.dart';

class ProducerSelectorBottomSheet extends StatefulWidget {
  final List<Map<String, dynamic>> producers;
  final void Function(Map<String, dynamic>) onSelected;

  ProducerSelectorBottomSheet({
    required List<Map<String, dynamic>> producers,
    required void Function(Map<String, dynamic>) onSelected,
  })  : producers = producers,
        onSelected = onSelected;

  @override
  State<ProducerSelectorBottomSheet> createState() => ProducerSelectorBottomSheetState();
}

class ProducerSelectorBottomSheetState extends State<ProducerSelectorBottomSheet> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.producers.where((producer) {
      final name = (producer['name'] ?? '').toString().toLowerCase();
      final location = (producer['location'] ?? '').toString().toLowerCase();
      final type = (producer['type'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) || location.contains(_searchQuery) || type.contains(_searchQuery);
    }).toList();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search producers...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(child: Text('No producers found.')),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => Divider(),
                    itemBuilder: (context, index) {
                      final producer = filtered[index];
                      final isEmailVerified = producer['is_email_verified'];

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 2,
                        child: ListTile(
                          leading: Icon(Icons.store, color: Colors.teal),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  producer['name'] ?? 'Producer',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ),
                              if (isEmailVerified != null)
                                Icon(
                                  Icons.verified,
                                  color: isEmailVerified ? Colors.green : Colors.grey,
                                  size: 16.0,
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (producer['location'] != null)
                                Row(
                                  children: [
                                    Icon(Icons.location_on, size: 14, color: Colors.grey),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        producer['location'],
                                        style: TextStyle(fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              if (producer['type'] != null)
                                Row(
                                  children: [
                                    Icon(
                                      producer['type'] == 'Company' ? Icons.business : Icons.person,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        producer['type'],
                                        style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.teal),
                          onTap: () {
                            widget.onSelected(producer);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
