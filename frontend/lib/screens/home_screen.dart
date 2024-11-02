import 'package:flutter/material.dart';
import 'package:frienance/models/receipt.dart';
import 'package:frienance/widgets/get_receipt.dart';
import 'package:frienance/widgets/receipt_list.dart';
import 'package:frienance/widgets/search_receipt.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> receipts = [];
  List<Map<String, dynamic>> searchResults = [];

  void addReceipt(Map<String, dynamic> receipt) {
    setState(() {
      receipts.add(receipt);
    });
  }

  void updateSearchResults(List<Map<String, dynamic>> results) {
    setState(() {
      searchResults = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Manager'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CaptureReceipt(addReceipt: addReceipt),
              const SizedBox(height: 16),
              SearchReceipts(
                receipts: receipts,
                updateSearchResults: updateSearchResults,
              ),
              const SizedBox(height: 16),
              ReceiptList(
                receipts: searchResults.isNotEmpty
                    ? searchResults.map((e) => Receipt.fromJson(e)).toList()
                    : receipts.map((e) => Receipt.fromJson(e)).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
