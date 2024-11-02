import 'package:flutter/material.dart';
import 'package:frienance/services/python_bridge.dart';

class SearchReceipts extends StatefulWidget {
  final List<Map<String, dynamic>> receipts;
  final Function(List<Map<String, dynamic>>) updateSearchResults;

  const SearchReceipts({super.key, required this.receipts, required this.updateSearchResults});

  @override
  _SearchReceiptsState createState() => _SearchReceiptsState();
}

class _SearchReceiptsState extends State<SearchReceipts> {
  final TextEditingController _searchController = TextEditingController();

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      widget.updateSearchResults([]);
      return;
    }

    try {
      final results = await PythonBridge.fuzzySearch(query, widget.receipts);
      widget.updateSearchResults(results);
    } catch (e) {
      // print('Search Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error performing search')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search Receipts',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search receipts...',
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _performSearch(_searchController.text),
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: _performSearch,
        ),
      ],
    );
  }
}