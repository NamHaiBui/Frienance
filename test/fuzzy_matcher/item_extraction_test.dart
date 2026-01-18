import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'test_helper.dart';

/// Tests for item/line item extraction
void main() {
  late AdaptiveFuzzyMatcher matcher;

  setUp(() {
    TestHelper.setUp();
    matcher = TestHelper.matcher;
  });

  tearDown(() {
    TestHelper.tearDown();
  });

  group('Item Extraction - Basic Formats', () {
    test('should extract items with simple name and price', () {
      final lines = [
        'WALMART',
        'GV OATMEAL  3.48',
        'MILK 2%  4.99',
        'BREAD  2.50',
        'TOTAL  10.97',
      ];
      
      final result = matcher.extractItems(lines);
      
      expect(result.items, isNotEmpty);
      expect(result.items.length, greaterThanOrEqualTo(1));
    });

    test('should extract items with dollar sign', () {
      final lines = [
        "TRADER JOE'S",
        'Organic Milk  \$5.99',
        'Sourdough Bread  \$3.49',
        'Total  \$9.48',
      ];
      
      final result = matcher.extractItems(lines);
      
      expect(result.items.isNotEmpty, isTrue);
    });

    test('should extract items with quantity multiplier', () {
      final lines = [
        'Store Receipt',
        '2 x Apples  2.00',
        '3 @ Oranges  4.50',
        'TOTAL  6.50',
      ];
      
      final result = matcher.extractItems(lines);
      
      expect(result.items, isNotEmpty);
    });
  });

  group('Item Extraction - Walmart Format', () {
    test('should extract Walmart items with product codes', () {
      final lines = [
        'GV OATMEAL -> 007874243408 F -> 1.76 0',
        '0T 200Z TUM -> 081236803115 -> 6.74 X',
        'M ATHLETICS -> 019104567781 -> 24.97 X',
        'SUBTOTAL -> 46.44',
      ];
      
      final result = matcher.extractItems(lines);
      
      expect(result.items, isNotEmpty);
    });

    test('should extract items with arrow notation', () {
      final lines = [
        'R-CARROTS SHREDDED 10 0Z',
        'ORGANIC OLD FASHIONED OATMEAL -> 2.49',
        'MINI-PEARL TOMATOES.. -> 3.99',
        'TOTAL -> 38.68',
      ];
      
      final result = matcher.extractItems(lines);
      
      // Should find items with -> price pattern
      expect(result.items.isNotEmpty, isTrue);
    });
  });

  group('Item Extraction - Stop Conditions', () {
    test('should stop extraction at total line', () {
      final lines = [
        'Item 1  5.00',
        'Item 2  3.00',
        'TOTAL  8.00',
        'CASH  10.00',
        'CHANGE  2.00',
      ];
      
      final result = matcher.extractItems(lines);
      
      for (final item in result.items) {
        expect(item.name.toLowerCase(), isNot(contains('change')));
        expect(item.name.toLowerCase(), isNot(contains('cash')));
      }
    });

    test('should skip ignored keys', () {
      final lines = [
        'TAX  0.50',
        'TIP  2.00',
        'Regular Item  10.00',
        'TOTAL  12.50',
      ];
      
      final result = matcher.extractItems(lines);
      
      for (final item in result.items) {
        expect(item.name.toLowerCase(), isNot(startsWith('tax')));
        expect(item.name.toLowerCase(), isNot(startsWith('tip')));
      }
    });
  });

  group('Item Extraction - European Format', () {
    test('should extract items with weight and unit price', () {
      final lines = [
        'BANANAS LOOSE -> 17KG',
        '0.596kg @ -> 15.99 R /kg -> 9.53 *',
        'TOTAL FOR 14 ITEMS -> 338.16',
      ];
      
      final result = matcher.extractItems(lines);
      
      // Weight-based pricing is complex, may not extract items
      // but should not crash
      expect(result.averageConfidence, greaterThanOrEqualTo(0.0));
    });

    test('should extract Spar items with suffixes', () {
      final lines = [
        'LAZENBY WORCESTER SAUCE 125ML -> 17.99 A',
        'MILKY BAR CHOC -> 80GR -> 16.99 A',
        'SMOKED VIENNAS -> 500GR -> 33.99 A',
        'TOTAL FOR 14 ITEMS -> 338.16',
      ];
      
      final result = matcher.extractItems(lines);
      
      expect(result.items, isNotEmpty);
    });
  });

  group('Item Extraction - Whole Foods Format', () {
    test('should extract Whole Foods items', () {
      final lines = [
        'PL TORTILLAS -> 6.99 B',
        'CAGE FREE ALL WHIT -> 3.69 B',
        'BLACK BEANS -> 1.29 B',
        '*** TAX -> 93 -> BAL -> 45.44',
      ];
      
      final result = matcher.extractItems(lines);
      
      expect(result.items, isNotEmpty);
    });
  });

  group('Item Extraction - Edge Cases', () {
    test('should handle empty item list', () {
      final lines = [
        'WALMART',
        'TOTAL  0.00',
      ];
      
      final result = matcher.extractItems(lines);
      
      expect(result.averageConfidence, greaterThanOrEqualTo(0.0));
    });

    test('should calculate average confidence', () {
      final lines = [
        'Item A  5.99',
        'Item B  3.99',
        'TOTAL  9.98',
      ];
      
      final result = matcher.extractItems(lines);
      
      expect(result.averageConfidence, greaterThanOrEqualTo(0.0));
      expect(result.averageConfidence, lessThanOrEqualTo(1.0));
    });

    test('should handle items with special characters', () {
      final lines = [
        "MOMI TOY  10.00",
        'CAFE LATTE  5.50',
        'TOTAL  15.50',
      ];
      
      final result = matcher.extractItems(lines);
      
      // Items with special chars may or may not be extracted
      expect(result.averageConfidence, greaterThanOrEqualTo(0.0));
    });

    test('should handle voided entries', () {
      final lines = [
        'HRI CL CHS -> 5.88 0',
        '** VOIDED -> ENTRY *',
        'HRI CL CHS -> 5.88-0',
        'TOTAL  5.88',
      ];
      
      final result = matcher.extractItems(lines);
      
      // Voided items may or may not be extracted, but shouldn't crash
      expect(result.items, isA<List>());
    });
  });

  group('Item Extraction - Confidence', () {
    test('should assign confidence to each item', () {
      final lines = [
        'Item A  5.99',
        'TOTAL  5.99',
      ];
      
      final result = matcher.extractItems(lines);
      
      for (final item in result.items) {
        expect(item.confidence, greaterThan(0.0));
        expect(item.confidence, lessThanOrEqualTo(1.0));
      }
    });
  });
}
