import 'dart:io';
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'text_recognizer_service.dart';

/// Specialized OCR service for receipt processing
/// 
/// Uses Google ML Kit for text recognition (Android/iOS only)
class ReceiptOcrService {
  final TextRecognizerService _textRecognizer;

  ReceiptOcrService() : _textRecognizer = TextRecognizerService();

  /// Check if OCR is available on current platform
  bool get isAvailable => _textRecognizer.isAvailable;

  /// Process a receipt image and extract structured data
  Future<ReceiptOcrResult> processReceipt(String imagePath) async {
    if (!isAvailable) {
      throw UnsupportedError(
        'OCR is not available on this platform. '
        'Google ML Kit only works on Android and iOS.'
      );
    }
    
    final blocks = await _textRecognizer.extractBlocksWithPosition(imagePath);
    
    // Sort blocks by vertical position (top to bottom)
    final sortedLines = _extractAndSortLines(blocks);
    
    // Extract receipt components
    final items = _extractItems(sortedLines);
    final total = _extractTotal(sortedLines);
    final subtotal = _extractSubtotal(sortedLines);
    final tax = _extractTax(sortedLines);
    final date = _extractDate(sortedLines);
    final storeName = _extractStoreName(sortedLines);
    
    return ReceiptOcrResult(
      rawLines: sortedLines.map((l) => l.text).toList(),
      items: items,
      total: total,
      subtotal: subtotal,
      tax: tax,
      date: date,
      storeName: storeName,
    );
  }

  /// Process multiple receipt images
  Future<List<ReceiptOcrResult>> processReceipts(List<String> imagePaths) async {
    final results = <ReceiptOcrResult>[];
    for (final path in imagePaths) {
      try {
        results.add(await processReceipt(path));
      } catch (e) {
        print('Error processing $path: $e');
      }
    }
    return results;
  }

  /// Extract and sort lines by vertical position
  List<TextLineInfo> _extractAndSortLines(List<TextBlockInfo> blocks) {
    final allLines = blocks.expand((block) => block.lines).toList();
    
    // Sort by Y position (top to bottom), then by X position (left to right)
    allLines.sort((a, b) {
      final yDiff = a.boundingBox.top - b.boundingBox.top;
      // If lines are roughly on the same row (within 10 pixels), sort by X
      if (yDiff.abs() < 10) {
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      }
      return yDiff.toInt();
    });
    
    return allLines;
  }

  /// Extract item entries (name + price pairs)
  List<ReceiptItem> _extractItems(List<TextLineInfo> lines) {
    final items = <ReceiptItem>[];
    
    // Price patterns
    final pricePattern = RegExp(
      r'[\$£€]?\s*(\d{1,4})[.,](\d{2})\s*[\$£€]?|'   // $12.99 or 12.99 or 12,99
      r'(\d{1,4})[.,](\d{2})\s*[A-Z]?$',             // 12.99 at end of line
      caseSensitive: false,
    );
    
    // Quantity pattern (e.g., "2 x", "2@", "QTY: 2")
    final qtyPattern = RegExp(
      r'^(\d+)\s*[x@]\s*|'
      r'QTY[:\s]*(\d+)|'
      r'^(\d+)\s+',
      caseSensitive: false,
    );

    // Skip patterns (lines that aren't items)
    final skipPatterns = [
      RegExp(r'^\s*(sub\s*)?total', caseSensitive: false),
      RegExp(r'^\s*tax', caseSensitive: false),
      RegExp(r'^\s*change', caseSensitive: false),
      RegExp(r'^\s*cash', caseSensitive: false),
      RegExp(r'^\s*card', caseSensitive: false),
      RegExp(r'^\s*credit', caseSensitive: false),
      RegExp(r'^\s*debit', caseSensitive: false),
      RegExp(r'^\s*visa', caseSensitive: false),
      RegExp(r'^\s*mastercard', caseSensitive: false),
      RegExp(r'^\s*balance', caseSensitive: false),
      RegExp(r'^\s*tip', caseSensitive: false),
      RegExp(r'^\s*discount', caseSensitive: false),
      RegExp(r'^\s*savings', caseSensitive: false),
      RegExp(r'^\s*thank', caseSensitive: false),
      RegExp(r'^\d{2}[/-]\d{2}[/-]\d{2,4}'),  // Date
      RegExp(r'^\d{1,2}:\d{2}'),               // Time
    ];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].text.trim();
      
      // Skip empty lines
      if (line.isEmpty) continue;
      
      // Skip non-item lines
      bool shouldSkip = skipPatterns.any((p) => p.hasMatch(line));
      if (shouldSkip) continue;
      
      // Try to extract price
      final priceMatch = pricePattern.firstMatch(line);
      if (priceMatch != null) {
        final priceStr = priceMatch.group(0)!;
        final price = _parsePrice(priceStr);
        
        if (price != null && price > 0 && price < 10000) {  // Reasonable price range
          // Extract item name (everything before the price)
          String itemName = line.substring(0, priceMatch.start).trim();
          
          // Try to extract quantity
          int quantity = 1;
          final qtyMatch = qtyPattern.firstMatch(itemName);
          if (qtyMatch != null) {
            final qtyStr = qtyMatch.group(1) ?? qtyMatch.group(2) ?? qtyMatch.group(3);
            if (qtyStr != null) {
              quantity = int.tryParse(qtyStr) ?? 1;
              itemName = itemName.substring(qtyMatch.end).trim();
            }
          }
          
          // Clean up item name
          itemName = _cleanItemName(itemName);
          
          if (itemName.isNotEmpty && itemName.length > 1) {
            items.add(ReceiptItem(
              name: itemName,
              price: price,
              quantity: quantity,
              rawText: line,
            ));
          }
        }
      }
    }
    
    return items;
  }

  /// Extract total amount
  double? _extractTotal(List<TextLineInfo> lines) {
    final totalPatterns = [
      RegExp(r'^\s*total\s*[:\s]*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
      RegExp(r'^\s*grand\s*total\s*[:\s]*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
      RegExp(r'^\s*amount\s*due\s*[:\s]*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
      RegExp(r'^\s*balance\s*due\s*[:\s]*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
      RegExp(r'total\s*[\$£€]?\s*(\d+[.,]\d{2})\s*$', caseSensitive: false),
    ];
    
    // Search from bottom up (total usually at bottom)
    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].text;
      for (final pattern in totalPatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          return _parsePrice(match.group(1)!);
        }
      }
    }
    
    return null;
  }

  /// Extract subtotal amount
  double? _extractSubtotal(List<TextLineInfo> lines) {
    final subtotalPatterns = [
      RegExp(r'^\s*sub\s*-?\s*total\s*[:\s]*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
      RegExp(r'subtotal\s*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
    ];
    
    for (final line in lines) {
      for (final pattern in subtotalPatterns) {
        final match = pattern.firstMatch(line.text);
        if (match != null) {
          return _parsePrice(match.group(1)!);
        }
      }
    }
    
    return null;
  }

  /// Extract tax amount
  double? _extractTax(List<TextLineInfo> lines) {
    final taxPatterns = [
      RegExp(r'^\s*tax\s*[:\s]*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
      RegExp(r'^\s*sales\s*tax\s*[:\s]*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
      RegExp(r'^\s*vat\s*[:\s]*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
      RegExp(r'^\s*gst\s*[:\s]*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
      RegExp(r'^\s*hst\s*[:\s]*[\$£€]?\s*(\d+[.,]\d{2})', caseSensitive: false),
    ];
    
    for (final line in lines) {
      for (final pattern in taxPatterns) {
        final match = pattern.firstMatch(line.text);
        if (match != null) {
          return _parsePrice(match.group(1)!);
        }
      }
    }
    
    return null;
  }

  /// Extract date from receipt
  String? _extractDate(List<TextLineInfo> lines) {
    final datePatterns = [
      // MM/DD/YYYY or MM-DD-YYYY
      RegExp(r'(0?[1-9]|1[0-2])[/-](0?[1-9]|[12]\d|3[01])[/-](20\d{2}|\d{2})'),
      // DD/MM/YYYY or DD-MM-YYYY
      RegExp(r'(0?[1-9]|[12]\d|3[01])[/-](0?[1-9]|1[0-2])[/-](20\d{2}|\d{2})'),
      // YYYY-MM-DD
      RegExp(r'(20\d{2})[-/](0?[1-9]|1[0-2])[-/](0?[1-9]|[12]\d|3[01])'),
      // Month DD, YYYY
      RegExp(r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2}),?\s*(20\d{2})', caseSensitive: false),
    ];
    
    // Search from top (date usually near top)
    for (int i = 0; i < min(lines.length, 10); i++) {
      final line = lines[i].text;
      for (final pattern in datePatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          return match.group(0);
        }
      }
    }
    
    return null;
  }

  /// Extract store name (usually first few lines)
  String? _extractStoreName(List<TextLineInfo> lines) {
    if (lines.isEmpty) return null;
    
    // Store name is typically in the first few lines, often centered and in larger text
    // We'll take the first non-empty, non-numeric line
    for (int i = 0; i < min(lines.length, 5); i++) {
      final line = lines[i].text.trim();
      
      // Skip empty lines, dates, times, numbers-only lines
      if (line.isEmpty) continue;
      if (RegExp(r'^\d+[/-]\d+[/-]\d+$').hasMatch(line)) continue;
      if (RegExp(r'^\d+:\d+').hasMatch(line)) continue;
      if (RegExp(r'^\d+$').hasMatch(line)) continue;
      if (RegExp(r'^tel|phone|fax', caseSensitive: false).hasMatch(line)) continue;
      if (RegExp(r'^\d{3}[-.\s]?\d{3}[-.\s]?\d{4}$').hasMatch(line)) continue;  // Phone number
      
      // This might be the store name
      if (line.length > 2 && line.length < 50) {
        return line;
      }
    }
    
    return null;
  }

  /// Parse price string to double
  double? _parsePrice(String priceStr) {
    // Remove currency symbols and whitespace
    String cleaned = priceStr.replaceAll(RegExp(r'[\$£€\s]'), '');
    // Replace comma with dot for decimal
    cleaned = cleaned.replaceAll(',', '.');
    return double.tryParse(cleaned);
  }

  /// Clean item name
  String _cleanItemName(String name) {
    // Remove leading/trailing punctuation and whitespace
    name = name.replaceAll(RegExp(r'^[\s\-_*#]+|[\s\-_*#]+$'), '');
    // Remove SKU/product codes (long numbers)
    name = name.replaceAll(RegExp(r'\b\d{6,}\b'), '');
    // Remove weight indicators at end
    name = name.replaceAll(RegExp(r'\s*\d+\.?\d*\s*(oz|lb|kg|g|ml|l)\s*$', caseSensitive: false), '');
    return name.trim();
  }

  /// Dispose resources
  void dispose() {
    _textRecognizer.dispose();
  }
}

/// Result of receipt OCR processing
class ReceiptOcrResult {
  final List<String> rawLines;
  final List<ReceiptItem> items;
  final double? total;
  final double? subtotal;
  final double? tax;
  final String? date;
  final String? storeName;

  ReceiptOcrResult({
    required this.rawLines,
    required this.items,
    this.total,
    this.subtotal,
    this.tax,
    this.date,
    this.storeName,
  });

  /// Calculate items total
  double get itemsTotal => items.fold(0.0, (sum, item) => sum + item.totalPrice);

  /// Check if total matches items sum (within tolerance)
  bool get isTotalValid {
    if (total == null) return false;
    final diff = (total! - itemsTotal).abs();
    // Allow for tax difference
    return diff < (tax ?? 0) + 0.10;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'storeName': storeName,
    'date': date,
    'items': items.map((i) => i.toJson()).toList(),
    'subtotal': subtotal,
    'tax': tax,
    'total': total,
    'itemsTotal': itemsTotal,
    'rawLines': rawLines,
  };

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== Receipt ===');
    if (storeName != null) buffer.writeln('Store: $storeName');
    if (date != null) buffer.writeln('Date: $date');
    buffer.writeln('');
    buffer.writeln('Items:');
    for (final item in items) {
      buffer.writeln('  ${item.quantity}x ${item.name}: \$${item.price.toStringAsFixed(2)}');
    }
    buffer.writeln('');
    if (subtotal != null) buffer.writeln('Subtotal: \$${subtotal!.toStringAsFixed(2)}');
    if (tax != null) buffer.writeln('Tax: \$${tax!.toStringAsFixed(2)}');
    if (total != null) buffer.writeln('Total: \$${total!.toStringAsFixed(2)}');
    buffer.writeln('Items Total: \$${itemsTotal.toStringAsFixed(2)}');
    return buffer.toString();
  }
}

/// A single item on a receipt
class ReceiptItem {
  final String name;
  final double price;
  final int quantity;
  final String rawText;

  ReceiptItem({
    required this.name,
    required this.price,
    this.quantity = 1,
    required this.rawText,
  });

  double get totalPrice => price * quantity;

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'quantity': quantity,
    'totalPrice': totalPrice,
    'rawText': rawText,
  };

  @override
  String toString() => '$quantity x $name @ \$${price.toStringAsFixed(2)}';
}
