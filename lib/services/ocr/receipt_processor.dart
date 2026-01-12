import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'receipt_ocr_service.dart';
import 'text_recognizer_service.dart' show isMLKitSupported;

/// High-level receipt processor that combines image processing and OCR
/// 
/// Note: Requires Android or iOS for ML Kit OCR functionality
class ReceiptProcessor {
  final ReceiptOcrService _ocrService;
  final String? outputDir;

  ReceiptProcessor({this.outputDir}) : _ocrService = ReceiptOcrService();

  /// Check if OCR is available
  bool get isAvailable => _ocrService.isAvailable;

  /// Process a single receipt image
  Future<ReceiptOcrResult> processImage(String imagePath) async {
    if (!isAvailable) {
      throw UnsupportedError(
        'OCR is not available on this platform. '
        'Google ML Kit requires Android or iOS.'
      );
    }
    
    print('Processing: $imagePath');
    
    final result = await _ocrService.processReceipt(imagePath);
    
    // Save result if output directory is specified
    if (outputDir != null) {
      await _saveResult(imagePath, result);
    }
    
    return result;
  }

  /// Process multiple receipt images
  Future<List<ReceiptOcrResult>> processImages(List<String> imagePaths) async {
    final results = <ReceiptOcrResult>[];
    
    for (final imagePath in imagePaths) {
      try {
        final result = await processImage(imagePath);
        results.add(result);
        print(result);
        print('---');
      } catch (e) {
        print('Error processing $imagePath: $e');
      }
    }
    
    return results;
  }

  /// Process all images in a directory
  Future<List<ReceiptOcrResult>> processDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      throw ArgumentError('Directory does not exist: $dirPath');
    }

    final imagePaths = dir
        .listSync()
        .whereType<File>()
        .where((f) => _isImageFile(f.path))
        .map((f) => f.path)
        .toList();

    if (imagePaths.isEmpty) {
      print('No images found in $dirPath');
      return [];
    }

    print('Found ${imagePaths.length} images');
    return await processImages(imagePaths);
  }

  /// Check if file is an image
  bool _isImageFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.bmp', '.webp'].contains(ext);
  }

  /// Save OCR result to JSON file
  Future<void> _saveResult(String imagePath, ReceiptOcrResult result) async {
    final baseName = path.basenameWithoutExtension(imagePath);
    final outputPath = path.join(outputDir!, '${baseName}_ocr.json');
    
    final jsonStr = const JsonEncoder.withIndent('  ').convert(result.toJson());
    await File(outputPath).writeAsString(jsonStr);
    print('Saved result to: $outputPath');
  }

  /// Save raw OCR lines to text file
  Future<void> saveRawText(String imagePath, ReceiptOcrResult result) async {
    if (outputDir == null) return;
    
    final baseName = path.basenameWithoutExtension(imagePath);
    final outputPath = path.join(outputDir!, '${baseName}_ocr.txt');
    
    await File(outputPath).writeAsString(result.rawLines.join('\n'));
    print('Saved raw text to: $outputPath');
  }

  void dispose() {
    _ocrService.dispose();
  }
}

/// Batch processing statistics
class ProcessingStats {
  int totalProcessed = 0;
  int successful = 0;
  int failed = 0;
  double totalAmount = 0.0;
  int totalItems = 0;

  void addResult(ReceiptOcrResult result) {
    totalProcessed++;
    successful++;
    if (result.total != null) {
      totalAmount += result.total!;
    }
    totalItems += result.items.length;
  }

  void addFailure() {
    totalProcessed++;
    failed++;
  }

  @override
  String toString() {
    return '''
Processing Statistics:
  Total Processed: $totalProcessed
  Successful: $successful
  Failed: $failed
  Total Amount: \$${totalAmount.toStringAsFixed(2)}
  Total Items: $totalItems
''';
  }
}
