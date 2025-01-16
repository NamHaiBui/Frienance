import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:frienance/services/parser/receipt_recognizer.dart';
import 'package:frienance/src/templates/split_screen_template.dart';
import 'package:path/path.dart' as path;

class ReceiptConversionScreen extends StatefulWidget {
  const ReceiptConversionScreen({super.key});

  @override
  State<ReceiptConversionScreen> createState() => _ReceiptConversionScreenState();
}

class _ReceiptConversionScreenState extends State<ReceiptConversionScreen> {
  String? selectedImagePath;
  List<String> processedImages = [];
  int currentImageIndex = 0;
  bool isProcessing = false;

  Future<void> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null) {
      setState(() {
        selectedImagePath = result.files.first.path;
      });
    }
  }

  Future<void> processReceipt() async {
    if (selectedImagePath == null) return;

    setState(() {
      isProcessing = true;
      processedImages.clear();
    });

    try {
      final recognizer = await ReceiptRecognizer.create();
      await recognizer.processIndividualImage(selectedImagePath!);

      // Get all processed images from output directory
      final outputDir = Directory(path.join(recognizer.basePath, recognizer.outputFolder));
      final files = outputDir.listSync()
          .whereType<File>()
          .where((f) => path.basename(f.path).contains('step') || 
                       path.basename(f.path).contains('processed'))
          .map((f) => f.path)
          .toList()
        ..sort();

      setState(() {
        processedImages = files;
        currentImageIndex = 0;
        isProcessing = false;
      });
    } catch (e) {
      setState(() {
        isProcessing = false;
      });
      if (mounted){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing receipt: $e')),
      );}
    }
  }

  Widget _buildLeftPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (selectedImagePath == null)
            ElevatedButton(
              onPressed: pickImage,
              child: const Text('Upload Receipt'),
            )
          else
            Stack(
              alignment: Alignment.topRight,
              children: [
                Image.file(
                  File(selectedImagePath!),
                  height: 300,
                  fit: BoxFit.contain,
                ),
                IconButton(
                  icon: const Icon(Icons.check_circle),
                  onPressed: isProcessing ? null : processReceipt,
                  color: Colors.green,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: isProcessing
          ? const Center(child: CircularProgressIndicator())
          : processedImages.isEmpty
              ? const Center(child: Text('No processed images yet'))
              : Column(
                  children: [
                    Expanded(
                      child: Hero(
                        tag: 'receipt_image',
                        child: Image.file(
                          File(processedImages[currentImageIndex]),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: currentImageIndex > 0
                              ? () => setState(() => currentImageIndex--)
                              : null,
                        ),
                        Text('${currentImageIndex + 1}/${processedImages.length}'),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: currentImageIndex < processedImages.length - 1
                              ? () => setState(() => currentImageIndex++)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SplitScreenTemplate(
        ratio: 0.4,
        left: _buildLeftPanel(),
        right: _buildRightPanel(),
      ),
    );
  }
}
