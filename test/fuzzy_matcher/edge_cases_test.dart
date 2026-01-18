import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'test_helper.dart';

/// Tests for edge cases and error handling
void main() {
  late AdaptiveFuzzyMatcher matcher;

  setUp(() {
    TestHelper.setUp();
    matcher = TestHelper.matcher;
  });

  tearDown(() {
    TestHelper.tearDown();
  });

  group('Edge Cases - Empty/Invalid Input', () {
    test('should handle empty input', () {
      final result = matcher.extractAll([]);
      
      expect(result.market.value, isNull);
      expect(result.date.value, isNull);
      expect(result.sum.value, isNull);
      expect(result.items.items, isEmpty);
      expect(result.overallConfidence, equals(0.0));
    });

    test('should handle whitespace-only lines', () {
      final lines = ['   ', '\t\t', '  \n  ', ''];
      
      final result = matcher.extractAll(lines);
      
      expect(result.items.items, isEmpty);
    });

    test('should handle very long lines', () {
      final longLine = 'A' * 10000 + ' 5.99';
      final lines = [longLine, 'TOTAL  5.99'];
      
      expect(() => matcher.extractAll(lines), returnsNormally);
    });

    test('should handle special characters in market name', () {
      final lines = [
        '!@#\$%^&*() STORE',
        'Item  5.99',
        'TOTAL  5.99',
      ];
      
      expect(() => matcher.extractAll(lines), returnsNormally);
    });
  });

  group('Edge Cases - OCR Artifacts', () {
    test('should handle numeric-only lines', () {
      final lines = [
        '12345678901234567890',
        '99999999999',
        'TOTAL  5.99',
      ];
      
      final result = matcher.extractSum(lines);
      expect(result.value, isNotNull);
    });

    test('should handle malformed prices', () {
      final lines = [
        'Item  5.9.9',
        'Item  .99',
        'Item  99.',
        'TOTAL  5.99',
      ];
      
      expect(() => matcher.extractAll(lines), returnsNormally);
    });

    test('should handle mixed currencies', () {
      final lines = [
        'Item  \$5.99',
        'Item  €3.50',
        'Item  £2.00',
        'TOTAL  11.49',
      ];
      
      final result = matcher.extractAll(lines);
      expect(result.sum.value, isNotNull);
    });

    test('should handle unicode characters', () {
      final lines = [
        'STÖRE NÅME',
        'Itém  5.99',
        'Tötäl  5.99',
      ];
      
      expect(() => matcher.extractAll(lines), returnsNormally);
    });

    test('should handle common OCR errors', () {
      // 0 vs O, 1 vs l, etc.
      final lines = [
        'WALM0RT',
        'T0TAL -> l0.99',
      ];
      
      expect(() => matcher.extractAll(lines), returnsNormally);
    });

    test('should handle reversed arrow notation', () {
      final lines = [
        '<- 5.99 ITEM',
        'TOTAL -> 5.99',
      ];
      
      final result = matcher.extractSum(lines);
      expect(result.value, isNotNull);
    });
  });

  group('Edge Cases - Duplicate/Multiple Values', () {
    test('should handle duplicate total lines', () {
      final lines = [
        'SUBTOTAL  100.00',
        'TOTAL  105.00',
        'TOTAL  105.00',
        '*** TOTAL ***  105.00',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, equals('105.00'));
    });

    test('should handle multiple date formats in same receipt', () {
      final lines = [
        '01/15/2024 10:30 AM',
        'Jan 15, 2024',
        '2024-01-15',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
    });

    test('should handle multiple market mentions', () {
      final lines = [
        'WALMART SUPERCENTER',
        'walmart.com',
        'Save money. Live better.',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('walmart'));
    });
  });

  group('Edge Cases - Boundary Conditions', () {
    test('should handle minimum price (0.01)', () {
      final lines = [
        'Item  0.01',
        'TOTAL  0.01',
      ];
      
      final result = matcher.extractSum(lines);
      expect(result.value, equals('0.01'));
    });

    test('should handle large prices', () {
      final lines = [
        'Item  99999.99',
        'TOTAL  99999.99',
      ];
      
      final result = matcher.extractSum(lines);
      expect(result.value, isNotNull);
    });

    test('should handle single character lines', () {
      final lines = ['A', 'B', 'C', 'TOTAL  5.99'];
      
      expect(() => matcher.extractAll(lines), returnsNormally);
    });

    test('should handle only header info', () {
      final lines = [
        'WALMART',
        '123 Main St',
        'City, ST 12345',
        '(555) 555-5555',
      ];
      
      final result = matcher.extractAll(lines);
      
      expect(result.market.value, equals('walmart'));
      expect(result.sum.value, isNull);
    });
  });

  group('Edge Cases - Special Receipt Types', () {
    test('should handle return/refund receipt', () {
      final lines = [
        'WALMART',
        'RETURN/REFUND',
        'Item  -5.99',
        'REFUND TOTAL  -5.99',
      ];
      
      expect(() => matcher.extractAll(lines), returnsNormally);
    });

    test('should handle void transaction', () {
      final lines = [
        'WALMART',
        '** VOIDED TRANSACTION **',
        'Item  0.00',
        'TOTAL  0.00',
      ];
      
      final result = matcher.extractAll(lines);
      expect(result.sum.value, equals('0.00'));
    });

    test('should handle gift card receipt', () {
      final lines = [
        'WALMART',
        'GIFT CARD PURCHASE',
        'Gift Card  50.00',
        'TOTAL  50.00',
        'Card Balance: 50.00',
      ];
      
      final result = matcher.extractSum(lines);
      expect(result.value, equals('50.00'));
    });
  });
}
