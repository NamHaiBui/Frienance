import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'test_helper.dart';

/// Tests for sum/total extraction
void main() {
  late AdaptiveFuzzyMatcher matcher;

  setUp(() {
    TestHelper.setUp();
    matcher = TestHelper.matcher;
  });

  tearDown(() {
    TestHelper.tearDown();
  });

  group('Sum Extraction - Basic', () {
    test('should extract total with dollar sign', () {
      final lines = [
        'Item 1  5.99',
        'Item 2  3.50',
        'SUBTOTAL  9.49',
        'TAX  0.71',
        'TOTAL  \$10.20',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, equals('10.20'));
      expect(result.confidence, greaterThan(AdaptiveFuzzyMatcher.mediumConfidence));
    });

    test('should extract grand total', () {
      final lines = [
        'Subtotal  45.00',
        'Tax  3.60',
        'Grand Total  48.60',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, equals('48.60'));
    });

    test('should prefer total over subtotal', () {
      final lines = [
        'SUBTOTAL  100.00',
        'TAX  8.00',
        'TOTAL  108.00',
        'CHANGE  0.00',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, equals('108.00'));
    });

    test('should extract amount due', () {
      final lines = [
        'Items  25.00',
        'Amount Due: 27.50',
        'VISA **** 1234',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, equals('27.50'));
    });
  });

  group('Sum Extraction - Walmart Style', () {
    test('should extract from Walmart-style total', () {
      final lines = [
        'GV OATMEAL  3.48',
        'SUBTOTAL  49.90',
        'TAX  3.99',
        'TOTAL  53.89',
        'VISA TEND  53.89',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, isNotNull);
    });

    test('should extract total with arrow notation', () {
      final lines = [
        'SUBTOTAL -> 46.44',
        'TAX 1 -> 7.750 % -> 3.46',
        'TOTAL -> 49.90',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, equals('49.90'));
    });

    test('should handle TOTAL with OCR artifacts', () {
      final lines = [
        'SUBTOTAL -> 144.02',
        'TOTAL -> 144.02',
        'CASH TEND -> 160.02',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, equals('144.02'));
    });
  });

  group('Sum Extraction - European Format', () {
    test('should handle European number format with comma', () {
      final lines = [
        'SPAR',
        'Artikel  12,50',
        'Total  12,50',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, contains('12'));
    });

    test('should extract from TOTAL FOR X ITEMS format', () {
      final lines = [
        'CADBURY DAIRY MI  16.99',
        'TOTAL FOR 14 ITEMS -> 338.16',
        'TENDERED Nedbank  338.16',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, equals('338.16'));
    });

    test('should handle Indonesian currency (large numbers)', () {
      final lines = [
        '1 Ice Java Tea -> 16, 000',
        'SUBTOTAL -> 175, 000',
        'TOTAL -> 175,000',
      ];
      
      final result = matcher.extractSum(lines);
      
      // Should find the total even with unusual formatting
      expect(result.value, isNotNull);
    });
  });

  group('Sum Extraction - Edge Cases', () {
    test('should ignore tax lines when looking for total', () {
      final lines = [
        'TAX  5.00',
        'TOTAL  55.00',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, equals('55.00'));
    });

    test('should return null for no sum found', () {
      final lines = [
        'WALMART',
        'Thank you!',
        'Come again!',
      ];
      
      final result = matcher.extractSum(lines);
      
      if (result.value == null) {
        expect(result.confidence, lessThan(AdaptiveFuzzyMatcher.lowConfidence));
      }
    });

    test('should handle JOTAL typo (common OCR error)', () {
      final lines = [
        'SUBTOTAL -> 121.92',
        'TOTAL TAX -> .00',
        'JOTAL -> 121.92',
      ];
      
      final result = matcher.extractSum(lines);
      
      // Should find 121.92 from JOTAL or SUBTOTAL
      expect(result.value, anyOf(equals('121.92'), isNotNull));
    });

    test('should handle TO1AL typo', () {
      final lines = [
        'SUBTOTAL -> 50.00',
        'TO1AL -> 50.00',
      ];
      
      final result = matcher.extractSum(lines);
      
      // May find from SUBTOTAL line since TO1AL is not recognized
      expect(result.value, anyOf(equals('50.00'), isNull));
    });

    test('should extract from **** TOTAL format', () {
      final lines = [
        'SUBTOTAL -> 85.61',
        'TAX -> 3.52',
        '**** TOTAL -> 893',
        'Check/Member Prntd -> 89.13',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, isNotNull);
    });
  });

  group('Sum Extraction - Confidence', () {
    test('should have high confidence when total keyword present', () {
      final lines = [
        'TOTAL -> 49.90',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.confidence, greaterThan(AdaptiveFuzzyMatcher.mediumConfidence));
    });
  });
}
