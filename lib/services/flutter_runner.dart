import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:frienance/services/ocr/ocr.dart';
import 'package:frienance/services/ocr/text_recognizer_service.dart' show isMLKitSupported;

/// Flutter runner for receipt OCR processing
/// Run with: flutter run -t lib/services/flutter_runner.dart
void main() {
  runApp(const ReceiptOcrApp());
}

class ReceiptOcrApp extends StatelessWidget {
  const ReceiptOcrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt OCR',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const ReceiptOcrScreen(),
    );
  }
}

class ReceiptOcrScreen extends StatefulWidget {
  const ReceiptOcrScreen({super.key});

  @override
  State<ReceiptOcrScreen> createState() => _ReceiptOcrScreenState();
}

class _ReceiptOcrScreenState extends State<ReceiptOcrScreen> {
  bool _isProcessing = false;
  List<ReceiptOcrResult> _results = [];
  String _statusMessage = 'Ready to process receipts';

  @override
  void initState() {
    super.initState();
    _checkPlatformSupport();
  }

  void _checkPlatformSupport() {
    if (!isMLKitSupported) {
      setState(() {
        _statusMessage = '⚠️ Google ML Kit OCR is only supported on Android and iOS.\n'
            'Current platform does not support OCR.\n\n'
            'To test:\n'
            '• Run on Android emulator: flutter run -d android\n'
            '• Run on iOS simulator: flutter run -d ios';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt OCR Processor'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Platform warning banner
            if (!isMLKitSupported)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade800),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'ML Kit OCR requires Android or iOS',
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            
            // Status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(_statusMessage),
                    if (_isProcessing) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isProcessing || !isMLKitSupported) ? null : _processSourceImages,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Process Source Images'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isProcessing || !isMLKitSupported) ? null : _processAssetsImages,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Process Assets'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Results
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        isMLKitSupported 
                            ? 'No results yet. Process some receipts!'
                            : 'Run on Android or iOS to use OCR',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        return _buildResultCard(_results[index], index);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ReceiptOcrResult result, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(result.storeName ?? 'Receipt ${index + 1}'),
        subtitle: Text(
          'Total: \$${result.total?.toStringAsFixed(2) ?? "N/A"} | '
          '${result.items.length} items',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.date != null)
                  Text('Date: ${result.date}'),
                const SizedBox(height: 8),
                const Text('Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...result.items.map((item) => Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text('${item.quantity}x ${item.name}: \$${item.price.toStringAsFixed(2)}'),
                )),
                const Divider(),
                if (result.subtotal != null)
                  Text('Subtotal: \$${result.subtotal!.toStringAsFixed(2)}'),
                if (result.tax != null)
                  Text('Tax: \$${result.tax!.toStringAsFixed(2)}'),
                if (result.total != null)
                  Text(
                    'Total: \$${result.total!.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                Text('Items Sum: \$${result.itemsTotal.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processSourceImages() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Looking for images in cache/1_source_img...';
      _results = [];
    });

    try {
      final basePath = path.join(Directory.current.path, 'lib', 'cache');
      final sourceDir = path.join(basePath, '1_source_img');
      final outputDir = path.join(basePath, '2_temp_img');
      
      // Ensure output directory exists
      await Directory(outputDir).create(recursive: true);
      
      final processor = ReceiptProcessor(outputDir: outputDir);
      
      setState(() {
        _statusMessage = 'Processing images from $sourceDir...';
      });

      final results = await processor.processDirectory(sourceDir);
      
      setState(() {
        _results = results;
        _statusMessage = 'Processed ${results.length} receipts. Results saved to $outputDir';
      });
      
      processor.dispose();
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _processAssetsImages() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Looking for images in assets/images...';
      _results = [];
    });

    try {
      final assetsDir = path.join(Directory.current.path, 'assets', 'images');
      final outputDir = path.join(Directory.current.path, 'lib', 'cache', '2_temp_img');
      
      // Ensure output directory exists
      await Directory(outputDir).create(recursive: true);
      
      final processor = ReceiptProcessor(outputDir: outputDir);
      
      setState(() {
        _statusMessage = 'Processing images from $assetsDir...';
      });

      final results = await processor.processDirectory(assetsDir);
      
      setState(() {
        _results = results;
        _statusMessage = 'Processed ${results.length} receipts. Results saved to $outputDir';
      });
      
      processor.dispose();
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
}
