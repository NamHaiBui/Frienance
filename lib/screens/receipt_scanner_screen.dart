import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:frienance/services/parser/enhancer.dart';
import 'package:frienance/services/parser/receipt_recognizer.dart';

class ReceiptScannerScreen extends StatefulWidget {
  const ReceiptScannerScreen({Key? key}) : super(key: key);

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  List<String> processingImages = [];
  String? extractedText;
  bool isProcessing = false;

  Future<void> _processImage(String imagePath) async {
    setState(() {
      isProcessing = true;
      processingImages = [];
      extractedText = null;
    });

    try {
      // Initialize services
      final recognizer = await ReceiptRecognizer.create();
      final enhancer =
          await Enhancer.create(sharedBasePath: recognizer.basePath);

      // Copy image to processing directory
      final fileName = path.basename(imagePath);
      await recognizer.copyImagesToSourceDir([imagePath]);

      // Process receipt
      // await recognizer.processReceipts();
      await enhancer.processReceipt(fileName);

      // Collect all processing step images
      final tempImages = await enhancer.findImages(enhancer.INPUT_FOLDER);
      final outputImages = await enhancer.findImages(enhancer.OUTPUT_FOLDER);
      final contourImages = await enhancer.findImages('with_contours');

      // Get extracted text
      final textFile = File(path.join(
        enhancer.basePath,
        enhancer.OUTPUT_FOLDER,
        '${fileName.split('.').first}.txt',
      ));

      setState(() {
        processingImages = [...tempImages, ...outputImages, ...contourImages];
        extractedText =
            textFile.existsSync() ? textFile.readAsStringSync() : null;
        isProcessing = false;
      });
    } catch (e) {
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing image: $e')),
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        await _processImage(image.path);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Scanner'),
      ),
      body: Column(
        children: [
          if (isProcessing)
            const LinearProgressIndicator()
          else
            const SizedBox(height: 4),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.75,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= processingImages.length) return null;
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: Text('placeholder')
                                  // child: Image.file(
                                  //   File(processingImages[index]),
                                  //   fit: BoxFit.cover,
                                  // ),
                                  ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  path.basename(processingImages[index]),
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (extractedText != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Extracted Text:',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(extractedText!),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isProcessing ? null : _pickImage,
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
