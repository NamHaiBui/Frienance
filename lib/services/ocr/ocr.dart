/// OCR Services for Receipt Processing
/// 
/// This module provides Google ML Kit-based OCR functionality
/// specialized for receipt text extraction.
/// 
/// Usage:
/// ```dart
/// import 'package:frienance/services/ocr/ocr.dart';
/// 
/// final processor = ReceiptProcessor(outputDir: '/path/to/output');
/// final result = await processor.processImage('/path/to/receipt.jpg');
/// print(result);
/// ```

export 'text_recognizer_service.dart';
export 'receipt_ocr_service.dart';
export 'receipt_processor.dart';
