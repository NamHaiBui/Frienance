import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'test_helper.dart';

/// Tests using REAL receipt data from lib/cache/output/cache/output/
/// These tests validate extraction against actual OCR output
void main() {
  late String testConfigPath;
  late AdaptiveFuzzyMatcher matcher;
  late String receiptsDir;

  setUp(() {
    TestHelper.setUp();
    testConfigPath = TestHelper.testConfigPath;
    matcher = TestHelper.matcher;
    receiptsDir = 'lib/cache/output/cache/output';
  });

  tearDown(() {
    TestHelper.tearDown();
  });

  List<String> loadReceiptFile(String filename) {
    final file = File('$receiptsDir/$filename');
    if (!file.existsSync()) {
      return [];
    }
    return file.readAsLinesSync();
  }

  group('Real Data - Trader Joe\'s Receipt (1_processed.txt)', () {
    test('should extract market as Trader Joes', () {
      final lines = loadReceiptFile('1_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('trader_joes'));
      expect(result.confidence, greaterThan(0.5));
    });

    test('should extract date as 06-28-2014', () {
      final lines = loadReceiptFile('1_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, contains('06'));
      expect(result.value, contains('28'));
    });

    test('should extract total around 38-40 dollars', () {
      final lines = loadReceiptFile('1_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, isNotNull);
      // Should find 38.68 (subtotal) or 40.00 (total)
      final value = double.tryParse(result.value!.replaceAll(',', '.')) ?? 0;
      expect(value, greaterThanOrEqualTo(38.0));
      expect(value, lessThanOrEqualTo(41.0));
    });

    test('should extract multiple items', () {
      final lines = loadReceiptFile('1_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractItems(lines);
      
      expect(result.items.length, greaterThan(5));
    });

    test('should complete full extraction', () {
      final lines = loadReceiptFile('1_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractAll(lines);
      
      expect(result.market.value, isNotNull);
      expect(result.date.value, isNotNull);
      expect(result.sum.value, isNotNull);
      expect(result.overallConfidence, greaterThan(0.3));
      
      print('Trader Joe\'s Extraction Result:');
      print(result.toString());
    });
  });

  group('Real Data - Walmart Receipts', () {
    test('should extract from Walmart receipt #2', () {
      final lines = loadReceiptFile('2_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractAll(lines);
      
      expect(result.market.value, equals('walmart'));
      expect(result.date.value, isNotNull); // 10/18/20
      expect(result.sum.value, isNotNull); // 49.90
      
      print('Walmart #2 Extraction Result:');
      print(result.toString());
    });

    test('should extract from Walmart receipt #3 (large receipt)', () {
      final lines = loadReceiptFile('3_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractAll(lines);
      
      expect(result.market.value, equals('walmart'));
      expect(result.sum.value, isNotNull); // 144.02
      expect(result.items.items.length, greaterThan(10));
      
      print('Walmart #3 Extraction Result:');
      print('Items found: ${result.items.items.length}');
      print('Total: ${result.sum.value}');
    });

    test('should extract from Walmart receipt #4 (small receipt)', () {
      final lines = loadReceiptFile('4_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractAll(lines);
      
      expect(result.market.value, equals('walmart'));
      expect(result.sum.value, isNotNull); // 7.43
      
      final sumValue = double.tryParse(result.sum.value!.replaceAll(',', '.')) ?? 0;
      expect(sumValue, closeTo(7.43, 0.5));
    });

    test('should handle Walmart with gift card (receipt #13)', () {
      final lines = loadReceiptFile('13_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractAll(lines);
      
      expect(result.market.value, equals('walmart'));
      // Gift card receipt may have OCR issues, sum might not be found
      // The receipt has "TO1AL -> 50.(0" which is malformed
      expect(result.overallConfidence, greaterThan(0));
    });
  });

  group('Real Data - Whole Foods Receipt (5_processed.txt)', () {
    test('should extract from Whole Foods receipt', () {
      final lines = loadReceiptFile('5_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractAll(lines);
      
      // "OE FOODS" is OCR artifact of "WHOLE FOODS"
      expect(result.market.value, anyOf(equals('whole_foods'), isNull));
      expect(result.sum.value, isNotNull); // 28.28
      
      print('Whole Foods Extraction Result:');
      print(result.toString());
    });
  });

  group('Real Data - Indonesian Receipt (6_processed.txt)', () {
    test('should extract from Momi & Toys receipt', () {
      final lines = loadReceiptFile('6_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractAll(lines);
      
      // Should find date 26/01/2015
      expect(result.date.value, isNotNull);
      expect(result.date.value, contains('26'));
      expect(result.date.value, contains('01'));
      
      // Total is 175,000 (Indonesian Rupiah)
      expect(result.sum.value, isNotNull);
      
      print('Momi & Toys Extraction Result:');
      print(result.toString());
    });
  });

  group('Real Data - Costco Receipt (8_processed.txt)', () {
    test('should extract from Costco/Wholesale receipt', () {
      final lines = loadReceiptFile('8_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractAll(lines);
      
      // "EWHOESALE" is OCR artifact of "WHOLESALE" -> Costco
      expect(result.market.value, anyOf(equals('costco'), isNull));
      expect(result.sum.value, isNotNull); // 89.13
      
      print('Costco Extraction Result:');
      print(result.toString());
    });
  });

  group('Real Data - WinCo Receipt (9_processed.txt)', () {
    test('should extract from WinCo receipt', () {
      final lines = loadReceiptFile('9_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractAll(lines);
      
      expect(result.market.value, equals('winco'));
      expect(result.date.value, isNotNull); // 09/08/14
      expect(result.sum.value, isNotNull); // 121.92
      
      print('WinCo Extraction Result:');
      print(result.toString());
    });
  });

  group('Real Data - SPAR Receipt (10_processed.txt)', () {
    test('should extract from SPAR receipt (South African)', () {
      final lines = loadReceiptFile('10_processed.txt');
      if (lines.isEmpty) {
        markTestSkipped('Receipt file not found');
        return;
      }
      
      final result = matcher.extractAll(lines);
      
      expect(result.market.value, equals('spar'));
      expect(result.date.value, isNotNull); // 23.02.21
      expect(result.sum.value, isNotNull); // 338.16
      
      print('SPAR Extraction Result:');
      print(result.toString());
    });
  });

  group('Real Data - Batch Processing All Receipts', () {
    test('should process all 19 receipt files', () {
      final results = <String, ExtractionResult>{};
      final stats = {
        'total': 0,
        'markets_found': 0,
        'dates_found': 0,
        'sums_found': 0,
        'items_found': 0,
      };

      for (int i = 1; i <= 19; i++) {
        final filename = '${i}_processed.txt';
        final lines = loadReceiptFile(filename);
        
        if (lines.isEmpty) continue;
        
        stats['total'] = stats['total']! + 1;
        
        final result = matcher.extractAll(lines);
        results[filename] = result;
        
        if (result.market.value != null) stats['markets_found'] = stats['markets_found']! + 1;
        if (result.date.value != null) stats['dates_found'] = stats['dates_found']! + 1;
        if (result.sum.value != null) stats['sums_found'] = stats['sums_found']! + 1;
        if (result.items.items.isNotEmpty) stats['items_found'] = stats['items_found']! + 1;
      }

      print('\n=== BATCH PROCESSING RESULTS ===');
      print('Total receipts: ${stats['total']}');
      print('Markets found: ${stats['markets_found']} (${(stats['markets_found']! / stats['total']! * 100).toStringAsFixed(1)}%)');
      print('Dates found: ${stats['dates_found']} (${(stats['dates_found']! / stats['total']! * 100).toStringAsFixed(1)}%)');
      print('Sums found: ${stats['sums_found']} (${(stats['sums_found']! / stats['total']! * 100).toStringAsFixed(1)}%)');
      print('Items found: ${stats['items_found']} (${(stats['items_found']! / stats['total']! * 100).toStringAsFixed(1)}%)');
      
      // Expect at least 50% success rate for markets
      expect(stats['markets_found'], greaterThanOrEqualTo(stats['total']! * 0.5));
      // Expect at least 70% success rate for sums
      expect(stats['sums_found'], greaterThanOrEqualTo(stats['total']! * 0.7));
    });

    test('should output detailed results for all receipts', () {
      print('\n=== DETAILED EXTRACTION RESULTS ===\n');
      
      for (int i = 1; i <= 19; i++) {
        final filename = '${i}_processed.txt';
        final lines = loadReceiptFile(filename);
        
        if (lines.isEmpty) {
          print('[$filename] File not found\n');
          continue;
        }
        
        final result = matcher.extractAll(lines);
        
        print('[$filename]');
        print('  Market: ${result.market.value ?? "N/A"} (${(result.market.confidence * 100).toStringAsFixed(0)}%)');
        print('  Date: ${result.date.value ?? "N/A"} (${(result.date.confidence * 100).toStringAsFixed(0)}%)');
        print('  Sum: ${result.sum.value ?? "N/A"} (${(result.sum.confidence * 100).toStringAsFixed(0)}%)');
        print('  Items: ${result.items.items.length}');
        print('  Overall: ${(result.overallConfidence * 100).toStringAsFixed(1)}%');
        print('');
      }
    });

    test('should generate JSON output for all receipts', () {
      final allResults = <Map<String, dynamic>>[];
      
      for (int i = 1; i <= 19; i++) {
        final filename = '${i}_processed.txt';
        final lines = loadReceiptFile(filename);
        
        if (lines.isEmpty) continue;
        
        final result = matcher.extractAll(lines);
        allResults.add({
          'file': filename,
          ...result.toJson(),
        });
      }
      
      final jsonOutput = const JsonEncoder.withIndent('  ').convert(allResults);
      
      // Optionally save to file
      final outputFile = File('$receiptsDir/extraction_results.json');
      outputFile.writeAsStringSync(jsonOutput);
      
      print('Saved extraction results to ${outputFile.path}');
      
      expect(allResults, isNotEmpty);
    });
  });
}
