import 'package:flutter/material.dart';
import 'package:frienance/models/receipt.dart';

class ReceiptList extends StatelessWidget {
  final List<Receipt> receipts;

  const ReceiptList({super.key, required this.receipts});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Receipts',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (receipts.isEmpty)
          const Text('No receipts found.')
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: receipts.length,
            itemBuilder: (context, index) {
              final receipt = receipts[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Merchant: ${receipt.merchant}'),
                      Text('Amount: \$${receipt.amount.toStringAsFixed(2)}'),
                      Text('Date: ${receipt.date}'),
                      const SizedBox(height: 8),
                      ExpansionTile(
                        title: const Text('View Raw Text'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(receipt.rawText),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
