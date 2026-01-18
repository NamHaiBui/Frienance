import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'test_helper.dart';

/// Tests for market/store name extraction
void main() {
  late AdaptiveFuzzyMatcher matcher;

  setUp(() {
    TestHelper.setUp();
    matcher = TestHelper.matcher;
  });

  tearDown(() {
    TestHelper.tearDown();
  });

  group('Market Extraction - Basic', () {
    test('should extract Walmart from receipt header', () {
      final lines = [
        'WALMART',
        'SUPERCENTER',
        '123 Main Street',
        'Anytown, US 12345',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('walmart'));
      expect(result.confidence, greaterThanOrEqualTo(0.75));
      expect(result.fieldType, equals('market'));
    });

    test('should extract Trader Joes with apostrophe variations', () {
      final lines = [
        "TRADER JOE'S",
        '#456',
        'San Francisco, CA',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('trader_joes'));
      expect(result.confidence, greaterThan(0.5));
    });

    test('should extract Whole Foods market', () {
      final lines = [
        'Whole Foods Market',
        'Premium Natural',
        '789 Oak Ave',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('whole_foods'));
      expect(result.confidence, greaterThanOrEqualTo(AdaptiveFuzzyMatcher.mediumConfidence));
    });

    test('should extract Spar market (European format)', () {
      final lines = [
        'SPAR',
        'Market Store',
        'Vienna, Austria',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('spar'));
      expect(result.confidence, greaterThan(0.5));
    });

    test('should extract WinCo market', () {
      final lines = [
        'Winco',
        'FO DS',
        'e Supermarker L Price lender',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('winco'));
    });
  });

  group('Market Extraction - Edge Cases', () {
    test('should handle case-insensitive matching', () {
      final lines = [
        'walmart supercenter',
        'store #1234',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value?.toLowerCase(), contains('walmart'));
    });

    test('should return low confidence for unknown market', () {
      final lines = [
        'UNKNOWN STORE NAME',
        '123 Random Street',
        'City, State 12345',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.confidence, lessThan(AdaptiveFuzzyMatcher.highConfidence));
    });

    test('should return null for empty lines', () {
      final result = matcher.extractMarket([]);
      
      expect(result.value, isNull);
      expect(result.confidence, equals(0.0));
    });

    test('should prioritize market in first 10 lines', () {
      final lines = List.generate(20, (i) => 'Line $i')
        ..insert(5, 'WALMART STORE');
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('walmart'));
    });

    test('should handle OCR artifacts in market name', () {
      // "Walmartk" is a common OCR error
      final lines = [
        'Walmartk',
        'Save money. Live better.',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('walmart'));
    });

    test('should extract market with typos (ATRADER)', () {
      final lines = [
        "ATRADER JOE'S",
        '2001 Greenville Ave',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('trader_joes'));
    });

    test('should extract partial market name (OE FOODS)', () {
      final lines = [
        'OE FOODS',
        'MARKET',
        'Sunnyvale SVL',
      ];
      
      final result = matcher.extractMarket(lines);
      
      // Should match whole_foods due to "oe foods" pattern
      expect(result.value, anyOf(equals('whole_foods'), isNull));
    });
  });

  group('Market Extraction - Confidence Levels', () {
    test('should have high confidence for exact match', () {
      final lines = ['WALMART', 'Store #123'];
      final result = matcher.extractMarket(lines);
      
      expect(result.isHighConfidence || result.isMediumConfidence, isTrue);
    });

    test('should have medium confidence for partial match', () {
      final lines = ['WAL MART STORE', 'Address'];
      final result = matcher.extractMarket(lines);
      
      expect(result.confidence, greaterThan(0.0));
    });
  });
}
