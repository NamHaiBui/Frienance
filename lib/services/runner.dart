import 'dart:io';

import 'package:frienance/services/parser/config.dart';
import 'package:frienance/services/parser/parse.dart';
import 'package:frienance/services/parser/receipt_recognizer.dart';
import 'package:path/path.dart' as path;

/// CLI runner for pure Dart execution (image preprocessing only)
/// For OCR functionality, use the Flutter app or flutter_runner.dart
void main() async {
  await preworkImage();
  final basePath = path.join(Directory.current.path, 'lib', 'cache');
  var config = readConfig(configPath: path.join(basePath, 'config.json'));
  
  // OCR requires Flutter runtime (Google ML Kit)
  // For full pipeline, use: flutter run -t lib/services/flutter_runner.dart
  // Or run the main app and use the OCR service
  
  var ocrOutputPath = path.join(basePath, '2_temp_img');
  var receiptFiles = getFilesInFolder(ocrOutputPath)
      .where((f) => f.endsWith('.txt'))
      .toList();
  
  if (receiptFiles.isEmpty) {
    print('');
    print('Image preprocessing completed.');
    print('Processed images saved to: $ocrOutputPath');
    print('');
    print('To run OCR, use Flutter:');
    print('  flutter run -t lib/services/flutter_runner.dart');
    print('');
    print('Or integrate ReceiptOcrService in your Flutter app:');
    print('  import "package:frienance/services/ocr/ocr.dart";');
    print('  final processor = ReceiptProcessor();');
    print('  final result = await processor.processImage(imagePath);');
    return;
  }
  
  ocrReceipts(config, receiptFiles);
}

List<String> getFilesInFolder(String folderPath) {
  return Directory(folderPath)
      .listSync()
      .where((entity) => entity is File && !(entity).path.startsWith('.'))
      .map((entity) => entity.path)
      .toList();
}
