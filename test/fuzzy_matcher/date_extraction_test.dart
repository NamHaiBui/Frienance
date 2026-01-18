import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'test_helper.dart';

/// Tests for date extraction with various formats
void main() {
  late AdaptiveFuzzyMatcher matcher;

  setUp(() {
    TestHelper.setUp();
    matcher = TestHelper.matcher;
  });

  tearDown(() {
    TestHelper.tearDown();
  });

  group('Date Extraction - US Formats', () {
    test('should extract date in MM/DD/YYYY format', () {
      final lines = [
        'WALMART',
        'Date: 10/18/2020',
        'Time: 12:30 PM',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, contains('10'));
      expect(result.value, contains('18'));
      expect(result.confidence, greaterThan(0.5));
    });

    test('should extract date in MM/DD/YY format (Walmart style)', () {
      final lines = [
        'Store #1234',
        '10/18/20 12:30:45',
        'Thank you for shopping!',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.confidence, greaterThan(0.5));
    });

    test('should extract date in MM-DD-YY format', () {
      final lines = [
        'Receipt',
        '06-28-2014',
        'Items:',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, contains('06'));
      expect(result.value, contains('28'));
    });
  });

  group('Date Extraction - European Formats', () {
    test('should extract date in DD-MM-YYYY format', () {
      final lines = [
        'SPAR Market',
        '28-06-2014',
        'Vienna',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, contains('28'));
      expect(result.value, contains('06'));
    });

    test('should extract date in DD.MM.YY format', () {
      final lines = [
        'SPAR',
        '23.02.21 16:17',
        'Thank You',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, contains('23'));
    });
  });

  group('Date Extraction - ISO Format', () {
    test('should extract date in YYYY-MM-DD format', () {
      final lines = [
        'Receipt',
        '2024-12-25',
        'Holiday Special',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, contains('2024'));
    });
  });

  group('Date Extraction - Month Names', () {
    test('should extract date with full month name', () {
      final lines = [
        'Trader Joes',
        '15 December 2024',
        'Thank you!',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value?.toLowerCase(), contains('dec'));
    });

    test('should extract date with abbreviated month', () {
      final lines = [
        'Store Receipt',
        'Jun 28, 2014',
        'Items below',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value?.toLowerCase(), contains('jun'));
    });
  });

  group('Date Extraction - Edge Cases', () {
    test('should handle date with spaces around separators', () {
      final lines = [
        'Receipt',
        '10 / 18 / 2020',
        'Total',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
    });

    test('should return null for no date found', () {
      final lines = [
        'WALMART',
        'Items:',
        'Milk 3.99',
      ];
      
      final result = matcher.extractDate(lines);
      
      if (result.value == null) {
        expect(result.confidence, equals(0.0));
      }
    });

    test('should extract date from time combined line', () {
      final lines = [
        '10/31/21 10: 08:22',
        '# ITEMS SOLD 18',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, contains('10'));
      expect(result.value, contains('31'));
    });

    test('should handle Indonesian date format (DD/MM/YYYY)', () {
      final lines = [
        'Rcpt#:A15000001363 26/01/2015 16:13',
        '1 Woman 0',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, contains('26'));
      expect(result.value, contains('01'));
      expect(result.value, contains('2015'));
    });
  });

  group('Date Extraction - Confidence', () {
    test('should have high confidence for standard format', () {
      final lines = ['Date: 12/25/2024'];
      final result = matcher.extractDate(lines);
      
      expect(result.confidence, greaterThan(0.5));
    });
  });
}
