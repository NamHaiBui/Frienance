import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'test_helper.dart';

/// Tests for data structures: MatchResult, ItemMatch, ItemsResult, ExtractionResult
void main() {
  late AdaptiveFuzzyMatcher matcher;

  setUp(() {
    TestHelper.setUp();
    matcher = TestHelper.matcher;
  });

  tearDown(() {
    TestHelper.tearDown();
  });

  group('MatchResult', () {
    test('should identify high confidence results', () {
      final result = MatchResult(
        value: 'walmart',
        confidence: 0.90,
        matchedLine: 'WALMART',
        patternUsed: 'contains:walmart',
        fieldType: 'market',
      );
      
      expect(result.isHighConfidence, isTrue);
      expect(result.isMediumConfidence, isTrue);
      expect(result.isLowConfidence, isTrue);
    });

    test('should identify medium confidence results', () {
      final result = MatchResult(
        value: 'walmart',
        confidence: 0.70,
        matchedLine: 'WAL MART',
        patternUsed: 'fuzzy:walmart',
        fieldType: 'market',
      );
      
      expect(result.isHighConfidence, isFalse);
      expect(result.isMediumConfidence, isTrue);
      expect(result.isLowConfidence, isTrue);
    });

    test('should identify low confidence results', () {
      final result = MatchResult(
        value: 'walmart',
        confidence: 0.50,
        matchedLine: 'WALM',
        patternUsed: 'partial:wal',
        fieldType: 'market',
      );
      
      expect(result.isHighConfidence, isFalse);
      expect(result.isMediumConfidence, isFalse);
      expect(result.isLowConfidence, isTrue);
    });

    test('should identify below threshold results', () {
      final result = MatchResult(
        value: null,
        confidence: 0.30,
        matchedLine: null,
        patternUsed: null,
        fieldType: 'market',
      );
      
      expect(result.isHighConfidence, isFalse);
      expect(result.isMediumConfidence, isFalse);
      expect(result.isLowConfidence, isFalse);
    });

    test('should convert to JSON correctly', () {
      final result = MatchResult(
        value: 'walmart',
        confidence: 0.85,
        matchedLine: 'WALMART',
        patternUsed: 'contains:walmart',
        fieldType: 'market',
      );
      
      final json = result.toJson();
      
      expect(json['value'], equals('walmart'));
      expect(json['confidence'], equals(0.85));
      expect(json['matched_line'], equals('WALMART'));
      expect(json['pattern_used'], equals('contains:walmart'));
      expect(json['field_type'], equals('market'));
    });
  });

  group('ItemMatch', () {
    test('should convert to JSON correctly', () {
      final item = ItemMatch(
        name: 'GV OATMEAL',
        price: 3.48,
        confidence: 0.80,
        originalLine: 'GV OATMEAL  3.48 F',
        patternUsed: 'builtin:item_pattern_0',
      );
      
      final json = item.toJson();
      
      expect(json['name'], equals('GV OATMEAL'));
      expect(json['price'], equals(3.48));
      expect(json['confidence'], equals(0.80));
      expect(json['original_line'], equals('GV OATMEAL  3.48 F'));
      expect(json['pattern_used'], equals('builtin:item_pattern_0'));
    });

    test('should handle null pattern', () {
      final item = ItemMatch(
        name: 'Item',
        price: 5.99,
        confidence: 0.60,
        originalLine: 'Item  5.99',
        patternUsed: null,
      );
      
      final json = item.toJson();
      
      expect(json['pattern_used'], isNull);
    });
  });

  group('ItemsResult', () {
    test('should convert to JSON with items', () {
      final itemsResult = ItemsResult(
        items: [
          ItemMatch(name: 'Item A', price: 5.99, confidence: 0.8, originalLine: 'Item A  5.99'),
          ItemMatch(name: 'Item B', price: 3.99, confidence: 0.75, originalLine: 'Item B  3.99'),
        ],
        averageConfidence: 0.775,
      );
      
      final json = itemsResult.toJson();
      
      expect(json['count'], equals(2));
      expect(json['average_confidence'], equals(0.775));
      expect((json['items'] as List).length, equals(2));
    });

    test('should handle empty items list', () {
      final itemsResult = ItemsResult(
        items: [],
        averageConfidence: 0.0,
      );
      
      final json = itemsResult.toJson();
      
      expect(json['count'], equals(0));
      expect(json['average_confidence'], equals(0.0));
      expect((json['items'] as List), isEmpty);
    });
  });

  group('ExtractionResult', () {
    test('should calculate overall confidence correctly', () {
      final result = ExtractionResult(
        market: MatchResult(value: 'walmart', confidence: 0.9, fieldType: 'market'),
        date: MatchResult(value: '01/15/2024', confidence: 0.85, fieldType: 'date'),
        sum: MatchResult(value: '49.90', confidence: 0.95, fieldType: 'sum'),
        items: ItemsResult(items: [], averageConfidence: 0.0),
        rawLines: ['WALMART', 'TOTAL  49.90'],
      );
      
      // Should average non-zero confidences: (0.9 + 0.85 + 0.95) / 3 = 0.9
      expect(result.overallConfidence, closeTo(0.9, 0.01));
    });

    test('should handle zero confidences in overall calculation', () {
      final result = ExtractionResult(
        market: MatchResult(value: null, confidence: 0.0, fieldType: 'market'),
        date: MatchResult(value: null, confidence: 0.0, fieldType: 'date'),
        sum: MatchResult(value: '5.99', confidence: 0.8, fieldType: 'sum'),
        items: ItemsResult(items: [], averageConfidence: 0.0),
        rawLines: ['TOTAL  5.99'],
      );
      
      // Only sum has non-zero confidence
      expect(result.overallConfidence, equals(0.8));
    });

    test('should return 0 for all zero confidences', () {
      final result = ExtractionResult(
        market: MatchResult(value: null, confidence: 0.0, fieldType: 'market'),
        date: MatchResult(value: null, confidence: 0.0, fieldType: 'date'),
        sum: MatchResult(value: null, confidence: 0.0, fieldType: 'sum'),
        items: ItemsResult(items: [], averageConfidence: 0.0),
        rawLines: [],
      );
      
      expect(result.overallConfidence, equals(0.0));
    });

    test('should convert to JSON', () {
      final result = ExtractionResult(
        market: MatchResult(value: 'walmart', confidence: 0.9, fieldType: 'market'),
        date: MatchResult(value: '01/15/2024', confidence: 0.85, fieldType: 'date'),
        sum: MatchResult(value: '49.90', confidence: 0.95, fieldType: 'sum'),
        items: ItemsResult(
          items: [ItemMatch(name: 'Item', price: 49.90, confidence: 0.8, originalLine: 'Item  49.90')],
          averageConfidence: 0.8,
        ),
        rawLines: ['WALMART', 'Item  49.90', 'TOTAL  49.90'],
      );
      
      final json = result.toJson();
      
      expect(json['market'], isA<Map>());
      expect(json['date'], isA<Map>());
      expect(json['sum'], isA<Map>());
      expect(json['items'], isA<Map>());
      expect(json['overall_confidence'], isA<double>());
    });

    test('should produce readable toString output', () {
      final result = ExtractionResult(
        market: MatchResult(value: 'walmart', confidence: 0.9, fieldType: 'market'),
        date: MatchResult(value: '01/15/2024', confidence: 0.85, fieldType: 'date'),
        sum: MatchResult(value: '49.90', confidence: 0.95, fieldType: 'sum'),
        items: ItemsResult(
          items: [ItemMatch(name: 'Item', price: 49.90, confidence: 0.8, originalLine: 'Item  49.90')],
          averageConfidence: 0.8,
        ),
        rawLines: [],
      );
      
      final output = result.toString();
      
      expect(output, contains('Extraction Result'));
      expect(output, contains('Market:'));
      expect(output, contains('Date:'));
      expect(output, contains('Sum:'));
      expect(output, contains('Items'));
      expect(output, contains('Overall Confidence'));
    });
  });

  group('Confidence Thresholds', () {
    test('should have correct static threshold values', () {
      expect(AdaptiveFuzzyMatcher.highConfidence, equals(0.85));
      expect(AdaptiveFuzzyMatcher.mediumConfidence, equals(0.65));
      expect(AdaptiveFuzzyMatcher.lowConfidence, equals(0.45));
    });

    test('thresholds should be in descending order', () {
      expect(AdaptiveFuzzyMatcher.highConfidence, greaterThan(AdaptiveFuzzyMatcher.mediumConfidence));
      expect(AdaptiveFuzzyMatcher.mediumConfidence, greaterThan(AdaptiveFuzzyMatcher.lowConfidence));
      expect(AdaptiveFuzzyMatcher.lowConfidence, greaterThan(0));
    });
  });
}
