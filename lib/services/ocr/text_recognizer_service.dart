import 'dart:io';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Check if current platform supports Google ML Kit
bool get isMLKitSupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
         defaultTargetPlatform == TargetPlatform.iOS;
}

/// Service for text recognition using Google ML Kit
/// 
/// Note: Google ML Kit only works on Android and iOS.
/// For desktop/web, use alternative OCR solutions.
class TextRecognizerService {
  TextRecognizer? _textRecognizer;

  TextRecognizerService({TextRecognitionScript script = TextRecognitionScript.latin}) {
    if (isMLKitSupported) {
      _textRecognizer = TextRecognizer(script: script);
    }
  }

  /// Check if OCR is available on current platform
  bool get isAvailable => _textRecognizer != null;

  /// Recognize text from an image file
  Future<RecognizedText> recognizeFromFile(String imagePath) async {
    _checkAvailability();
    final inputImage = InputImage.fromFilePath(imagePath);
    return await _textRecognizer!.processImage(inputImage);
  }

  /// Recognize text from a File object
  Future<RecognizedText> recognizeFromImage(File imageFile) async {
    _checkAvailability();
    final inputImage = InputImage.fromFile(imageFile);
    return await _textRecognizer!.processImage(inputImage);
  }

  /// Extract raw text lines from an image
  Future<List<String>> extractLines(String imagePath) async {
    _checkAvailability();
    final recognizedText = await recognizeFromFile(imagePath);
    return recognizedText.blocks
        .expand((block) => block.lines)
        .map((line) => line.text)
        .toList();
  }

  /// Extract text blocks with position information
  Future<List<TextBlockInfo>> extractBlocksWithPosition(String imagePath) async {
    _checkAvailability();
    final recognizedText = await recognizeFromFile(imagePath);
    return recognizedText.blocks.map((block) {
      return TextBlockInfo(
        text: block.text,
        lines: block.lines.map((line) => TextLineInfo(
          text: line.text,
          boundingBox: line.boundingBox,
          elements: line.elements.map((e) => TextElementInfo(
            text: e.text,
            boundingBox: e.boundingBox,
          )).toList(),
        )).toList(),
        boundingBox: block.boundingBox,
      );
    }).toList();
  }

  void _checkAvailability() {
    if (_textRecognizer == null) {
      throw UnsupportedError(
        'Google ML Kit OCR is not supported on this platform. '
        'ML Kit only works on Android and iOS. '
        'Current platform: ${defaultTargetPlatform.name}'
      );
    }
  }

  /// Dispose of resources
  void dispose() {
    _textRecognizer?.close();
  }
}

/// Information about a text block
class TextBlockInfo {
  final String text;
  final List<TextLineInfo> lines;
  final Rect boundingBox;

  TextBlockInfo({
    required this.text,
    required this.lines,
    required this.boundingBox,
  });
}

/// Information about a text line
class TextLineInfo {
  final String text;
  final Rect boundingBox;
  final List<TextElementInfo> elements;

  TextLineInfo({
    required this.text,
    required this.boundingBox,
    required this.elements,
  });
}

/// Information about a text element (word)
class TextElementInfo {
  final String text;
  final Rect boundingBox;

  TextElementInfo({
    required this.text,
    required this.boundingBox,
  });
}
