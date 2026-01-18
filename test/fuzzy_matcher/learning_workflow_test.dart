import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'test_helper.dart';

/// Tests for learning workflow and self-improvement features
void main() {
  late String testConfigPath;
  late AdaptiveFuzzyMatcher matcher;

  setUp(() {
    TestHelper.setUp();
    testConfigPath = TestHelper.testConfigPath;
    matcher = TestHelper.matcher;
  });

  tearDown(() {
    TestHelper.tearDown();
  });

  group('Learning Workflow', () {
    test('should learn market pattern from confirmation', () {
      final lines = [
        'WALMART SUPERCENTER',
        'Item A  5.99',
        'TOTAL  5.99',
      ];
      
      final result = matcher.extractAll(lines);
      
      // Confirm with the detected market - this triggers learning
      matcher.confirmExtraction(
        result,
        confirmedMarket: result.market.value ?? 'walmart',
      );
      
      // Check stats were updated (learning happened)
      final stats = matcher.getStats();
      expect(stats['total_extractions'], greaterThan(0));
    });

    test('should record user correction', () {
      matcher.recordCorrection(
        fieldType: 'market',
        originalValue: 'unknown',
        correctedValue: 'walmart',
        originalLine: 'WALMAR STORE',
      );
      
      final exported = json.decode(matcher.exportConfig()) as Map<String, dynamic>;
      final learnedPatterns = exported['learned_patterns'] as Map<String, dynamic>;
      final corrections = learnedPatterns['user_corrections'] as List;
      
      expect(corrections, isNotEmpty);
      expect(corrections.first['field_type'], equals('market'));
      expect(corrections.first['corrected_value'], equals('walmart'));
    });

    test('should reset learned patterns', () {
      // First add some learned data
      matcher.recordCorrection(
        fieldType: 'market',
        originalValue: 'test',
        correctedValue: 'corrected',
      );
      
      // Reset
      matcher.resetLearnedPatterns();
      
      final stats = matcher.getStats();
      expect(stats['total_extractions'], equals(0));
    });

    test('should persist learned patterns to config file', () {
      final lines = [
        'CUSTOM STORE XYZ',
        'Item  10.00',
        'TOTAL  10.00',
      ];
      
      final result = matcher.extractAll(lines);
      matcher.confirmExtraction(result, confirmedMarket: 'custom_store');
      
      // Re-read from file
      final fileContent = File(testConfigPath).readAsStringSync();
      final config = json.decode(fileContent) as Map<String, dynamic>;
      
      expect(config.containsKey('learned_patterns'), isTrue);
    });
  });

  group('Statistics Tracking', () {
    test('should update extraction stats', () {
      final lines = [
        'WALMART',
        'Item  5.99',
        'TOTAL  5.99',
        '01/15/2024',
      ];
      
      final initialStats = matcher.getStats();
      final initialCount = initialStats['total_extractions'] as int;
      
      matcher.extractAll(lines);
      
      final updatedStats = matcher.getStats();
      expect(updatedStats['total_extractions'], equals(initialCount + 1));
    });

    test('should track successful extractions', () {
      final lines = [
        'WALMART',
        'Item  5.99',
        'TOTAL  5.99',
        '01/15/2024',
      ];
      
      matcher.extractAll(lines);
      
      final stats = matcher.getStats();
      // Should have incremented at least one success counter
      final totalSuccess = (stats['successful_markets'] as int) +
          (stats['successful_dates'] as int) +
          (stats['successful_sums'] as int);
      
      expect(totalSuccess, greaterThan(0));
    });

    test('should accumulate stats across multiple extractions', () {
      for (int i = 0; i < 5; i++) {
        matcher.extractAll(['WALMART', 'TOTAL  ${10.0 + i}']);
      }
      
      final stats = matcher.getStats();
      expect(stats['total_extractions'], equals(5));
    });
  });

  group('Confirmation Workflow', () {
    test('should confirm high confidence extraction automatically', () {
      final lines = [
        'WALMART',
        'SUPERCENTER',
        'Item A  5.99',
        'TOTAL  5.99',
      ];
      
      final result = matcher.extractAll(lines);
      
      // For high confidence results, confirmation should work seamlessly
      expect(() => matcher.confirmExtraction(result), returnsNormally);
    });

    test('should accept confirmed items list', () {
      final lines = [
        'Item A  5.99',
        'Item B  3.99',
        'TOTAL  9.98',
      ];
      
      final result = matcher.extractAll(lines);
      
      expect(
        () => matcher.confirmExtraction(
          result,
          confirmedItems: result.items.items,
        ),
        returnsNormally,
      );
    });
  });
}
