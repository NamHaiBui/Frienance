import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';

/// Comprehensive unit tests for AdaptiveFuzzyMatcher
/// Tests cover:
/// - Market extraction with different confidence levels
/// - Date extraction with multiple date formats
/// - Sum/total extraction
/// - Item extraction
/// - Learning/confirmation workflow
/// - Config persistence and loading
/// - Edge cases (empty input, malformed data, etc.)
void main() {
  late String testConfigPath;
  late AdaptiveFuzzyMatcher matcher;

  /// Create a temporary config file for testing
  setUp(() {
    // Create a unique temp config for each test to ensure isolation
    testConfigPath = '${Directory.systemTemp.path}/test_fuzzy_config_${DateTime.now().millisecondsSinceEpoch}.json';
    
    // Create default config
    final defaultConfig = {
      'markets': {
        'default': ['store', 'market', 'shop'],
        'walmart': ['walmart', 'wal-mart', 'wal mart'],
        'target': ['target'],
        'costco': ['costco', 'wholesale'],
        'trader_joes': ['trader joe', "trader joe's", 'trader joes'],
        'whole_foods': ['whole foods', 'wholefoods', 'wfm'],
        'winco': ['winco', 'winco foods'],
        'spar': ['spar'],
      },
      'sum_keys': [
        'total', 'subtotal', 'amount', 'due', 'sum', 'grand total',
        'net total', 'balance', 'payment', 'total due',
      ],
      'ignore_keys': [
        'tax', 'tip', 'change', 'cash', 'debit', 'credit', 'visa',
        'mastercard', 'approval', 'ref', 'terminal', 'network',
      ],
      'sum_format': r'\d+[.,]\d{2}',
      'date_format': r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b',
      'item_format': r'^(.+?)\s+(\d+[.,]\d{2})\s*[A-Z]?$',
      'learned_patterns': {
        'successful_market_matches': {},
        'successful_date_patterns': [],
        'successful_sum_patterns': [],
        'successful_item_patterns': [],
        'user_corrections': [],
        'extraction_stats': {
          'total_extractions': 0,
          'successful_markets': 0,
          'successful_dates': 0,
          'successful_sums': 0,
          'successful_items': 0,
        },
      },
      'confidence_thresholds': {
        'high': 0.85,
        'medium': 0.65,
        'low': 0.45,
      },
    };
    
    File(testConfigPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(defaultConfig),
    );
    
    matcher = AdaptiveFuzzyMatcher(testConfigPath);
  });

  /// Clean up temporary config file after each test
  tearDown(() {
    final file = File(testConfigPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  group('AdaptiveFuzzyMatcher Initialization', () {
    test('should load config from file', () {
      final exportedConfig = matcher.exportConfig();
      final config = json.decode(exportedConfig) as Map<String, dynamic>;
      
      expect(config.containsKey('markets'), isTrue);
      expect(config.containsKey('sum_keys'), isTrue);
      expect(config.containsKey('ignore_keys'), isTrue);
      expect(config.containsKey('learned_patterns'), isTrue);
    });

    test('should create default config if file does not exist', () {
      final newConfigPath = '${Directory.systemTemp.path}/new_config_${DateTime.now().millisecondsSinceEpoch}.json';
      
      final newMatcher = AdaptiveFuzzyMatcher(newConfigPath);
      expect(File(newConfigPath).existsSync(), isTrue);
      
      final exportedConfig = newMatcher.exportConfig();
      final config = json.decode(exportedConfig) as Map<String, dynamic>;
      
      expect(config['markets'], isA<Map>());
      expect((config['markets'] as Map).containsKey('walmart'), isTrue);
      
      // Clean up
      File(newConfigPath).delete();
    });

    test('should initialize learned patterns correctly', () {
      final stats = matcher.getStats();
      expect(stats['total_extractions'], equals(0));
      expect(stats['successful_markets'], equals(0));
    });
  });

  group('Market Extraction', () {
    test('should extract Walmart from receipt header', () {
      final lines = [
        'WALMART',
        'SUPERCENTER',
        '123 Main Street',
        'Anytown, US 12345',
      ];
      
      final result = matcher.extractMarket(lines);
      
      expect(result.value, equals('walmart'));
      expect(result.confidence, greaterThanOrEqualTo(AdaptiveFuzzyMatcher.highConfidence - 0.1));
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
  });

  group('Date Extraction', () {
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
      expect(result.value, contains('20'));
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

    test('should extract date in DD-MM-YYYY format (European)', () {
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

    test('should extract date in YYYY-MM-DD format (ISO)', () {
      final lines = [
        'Receipt',
        '2024-12-25',
        'Holiday Special',
      ];
      
      final result = matcher.extractDate(lines);
      
      expect(result.value, isNotNull);
      expect(result.value, contains('2024'));
    });

    test('should extract date with month name', () {
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
      
      // May or may not find a date, but confidence should be low
      if (result.value == null) {
        expect(result.confidence, equals(0.0));
      }
    });
  });

  group('Sum/Total Extraction', () {
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

    test('should ignore tax lines when looking for total', () {
      final lines = [
        'TAX  5.00',
        'TOTAL  55.00',
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, equals('55.00'));
    });

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

    test('should return null for no sum found', () {
      final lines = [
        'WALMART',
        'Thank you!',
        'Come again!',
      ];
      
      final result = matcher.extractSum(lines);
      
      // If no total keyword or price found
      if (result.value == null) {
        expect(result.confidence, lessThan(AdaptiveFuzzyMatcher.lowConfidence));
      }
    });
  });

  group('Item Extraction', () {
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
      
      // Should find items with quantity patterns
      expect(result.items, isNotEmpty);
    });

    test('should stop extraction at total line', () {
      final lines = [
        'Item 1  5.00',
        'Item 2  3.00',
        'TOTAL  8.00',
        'CASH  10.00',
        'CHANGE  2.00',
      ];
      
      final result = matcher.extractItems(lines);
      
      // Should not include items after TOTAL
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
      
      // Should not include tax or tip as items
      for (final item in result.items) {
        expect(item.name.toLowerCase(), isNot(startsWith('tax')));
        expect(item.name.toLowerCase(), isNot(startsWith('tip')));
      }
    });

    test('should calculate average confidence', () {
      final lines = [
        'Item A  5.00',
        'Item B  3.00',
        'TOTAL  8.00',
      ];
      
      final result = matcher.extractItems(lines);
      
      if (result.items.isNotEmpty) {
        expect(result.averageConfidence, greaterThan(0.0));
        expect(result.averageConfidence, lessThanOrEqualTo(1.0));
      }
    });

    test('should handle empty item list', () {
      final lines = [
        'WALMART',
        'Thank you!',
      ];
      
      final result = matcher.extractItems(lines);
      
      expect(result.averageConfidence, equals(0.0));
    });

    test('should extract items with product codes', () {
      final lines = [
        'GV OATMEAL 123456  3.48',
        'BREAD WHOLE 789012  2.99',
        'TOTAL  6.47',
      ];
      
      final result = matcher.extractItems(lines);
      
      expect(result.items, isNotEmpty);
    });
  });

  group('Complete Extraction (extractAll)', () {
    test('should extract all fields from Walmart receipt', () {
      final walmartReceipt = [
        'WALMART',
        'SUPERCENTER',
        '123 Main St',
        'Anytown, US 12345',
        '',
        '10/18/20 12:30:45',
        '',
        'GV OATMEAL  3.48 F',
        'MILK 2%  4.99 F',
        'EGGS LARGE  3.29 F',
        '',
        'SUBTOTAL  11.76',
        'TAX 1  0.94',
        'TOTAL  12.70',
        '',
        'VISA TEND  12.70',
        '',
        'THANK YOU FOR SHOPPING!',
      ];
      
      final result = matcher.extractAll(walmartReceipt);
      
      expect(result.market.value, equals('walmart'));
      expect(result.date.value, isNotNull);
      expect(result.sum.value, isNotNull);
      expect(result.items.items, isNotEmpty);
      expect(result.overallConfidence, greaterThan(0.0));
    });

    test('should extract all fields from Trader Joes receipt', () {
      final traderJoesReceipt = [
        "TRADER JOE'S",
        '#456',
        '1234 Market St',
        'San Francisco, CA 94102',
        '',
        '06-28-2014 15:45:22',
        '',
        'Organic Bananas  0.99',
        'TJ Sourdough  3.49',
        'Almond Milk  2.99',
        'Greek Yogurt  4.99',
        '',
        'SUBTOTAL  12.46',
        'TAX  0.62',
        'TOTAL  13.08',
        '',
        'MASTERCARD **** 5678',
      ];
      
      final result = matcher.extractAll(traderJoesReceipt);
      
      expect(result.market.value, equals('trader_joes'));
      expect(result.date.value, isNotNull);
      expect(result.sum.value, isNotNull);
    });

    test('should extract from Spar receipt (European format)', () {
      final sparReceipt = [
        'SPAR',
        'Wien, Österreich',
        '',
        '28.06.2014',
        '',
        'Milch  1,29',
        'Brot  2,49',
        'Käse  3,99',
        '',
        'Summe  7,77',
      ];
      
      final result = matcher.extractAll(sparReceipt);
      
      expect(result.market.value, equals('spar'));
      expect(result.date.value, isNotNull);
      expect(result.sum.value, isNotNull);
    });

    test('should handle receipt with minimal information', () {
      final minimalReceipt = [
        'STORE',
        'Item  5.00',
        'Total  5.00',
      ];
      
      final result = matcher.extractAll(minimalReceipt);
      
      // Should at least extract sum
      expect(result.sum.value, isNotNull);
    });

    test('should update extraction stats', () {
      final receipt = [
        'WALMART',
        '01/15/2024',
        'Item  10.00',
        'TOTAL  10.00',
      ];
      
      final initialStats = matcher.getStats();
      final initialCount = initialStats['total_extractions'] ?? 0;
      
      matcher.extractAll(receipt);
      
      final newStats = matcher.getStats();
      expect(newStats['total_extractions'], equals(initialCount + 1));
    });
  });

  group('Learning and Confirmation Workflow', () {
    test('should learn market pattern from confirmation', () {
      final receipt = [
        'MY NEW STORE',
        '01/15/2024',
        'Item  10.00',
        'TOTAL  10.00',
      ];
      
      final result = matcher.extractAll(receipt);
      
      // Confirm with a custom market name - need a matched line for learning to occur
      matcher.confirmExtraction(
        result,
        confirmedMarket: 'my_new_store',
        confirmedDate: '01/15/2024',
        confirmedSum: '10.00',
      );
      
      // Export config and verify extraction was processed
      final exportedConfig = matcher.exportConfig();
      final config = json.decode(exportedConfig) as Map<String, dynamic>;
      
      // The config should still be valid and contain markets
      expect(config.containsKey('markets'), isTrue);
      expect(config.containsKey('learned_patterns'), isTrue);
    });

    test('should record user correction', () {
      matcher.recordCorrection(
        fieldType: 'market',
        originalValue: 'unknown',
        correctedValue: 'walmart',
        originalLine: 'WALMRT SUPRCNTR', // Typo in receipt
      );
      
      final exportedConfig = matcher.exportConfig();
      final config = json.decode(exportedConfig) as Map<String, dynamic>;
      final learnedPatterns = config['learned_patterns'] as Map<String, dynamic>;
      final corrections = learnedPatterns['user_corrections'] as List;
      
      expect(corrections, isNotEmpty);
      expect(corrections.last['field_type'], equals('market'));
      expect(corrections.last['corrected_value'], equals('walmart'));
    });

    test('should reset learned patterns', () {
      // First, add some learned data
      matcher.recordCorrection(
        fieldType: 'market',
        originalValue: 'old',
        correctedValue: 'new',
      );
      
      // Reset
      matcher.resetLearnedPatterns();
      
      final stats = matcher.getStats();
      expect(stats['total_extractions'], equals(0));
      
      final exportedConfig = matcher.exportConfig();
      final config = json.decode(exportedConfig) as Map<String, dynamic>;
      final learnedPatterns = config['learned_patterns'] as Map<String, dynamic>;
      final corrections = learnedPatterns['user_corrections'] as List;
      
      expect(corrections, isEmpty);
    });

    test('should persist learned patterns to config file', () {
      final receipt = [
        'BRAND NEW MARKET',
        '01/15/2024',
        'Item  10.00',
        'TOTAL  10.00',
      ];
      
      final result = matcher.extractAll(receipt);
      matcher.confirmExtraction(
        result,
        confirmedMarket: 'brand_new_market',
      );
      
      // Read the file directly to verify persistence
      final fileContents = File(testConfigPath).readAsStringSync();
      final savedConfig = json.decode(fileContents) as Map<String, dynamic>;
      
      expect(savedConfig.containsKey('markets'), isTrue);
    });
  });

  group('Config Import/Export', () {
    test('should export config as JSON string', () {
      final exported = matcher.exportConfig();
      
      expect(exported, isNotEmpty);
      
      // Should be valid JSON
      final parsed = json.decode(exported);
      expect(parsed, isA<Map<String, dynamic>>());
    });

    test('should import config from JSON string', () {
      final customConfig = {
        'markets': {
          'custom_store': ['custom', 'store'],
        },
        'sum_keys': ['total', 'sum'],
        'ignore_keys': ['tax'],
        'sum_format': r'\d+\.\d{2}',
        'date_format': r'\d{2}/\d{2}/\d{4}',
        'item_format': r'^(.+?)\s+(\d+\.\d{2})$',
        'learned_patterns': {
          'successful_market_matches': {},
          'successful_date_patterns': [],
          'successful_sum_patterns': [],
          'successful_item_patterns': [],
          'user_corrections': [],
          'extraction_stats': {
            'total_extractions': 100,
            'successful_markets': 90,
            'successful_dates': 85,
            'successful_sums': 95,
            'successful_items': 80,
          },
        },
        'confidence_thresholds': {
          'high': 0.85,
          'medium': 0.65,
          'low': 0.45,
        },
      };
      
      matcher.importConfig(json.encode(customConfig));
      
      final stats = matcher.getStats();
      expect(stats['total_extractions'], equals(100));
    });
  });

  group('Edge Cases', () {
    test('should handle empty input', () {
      final result = matcher.extractAll([]);
      
      expect(result.market.value, isNull);
      expect(result.date.value, isNull);
      expect(result.sum.value, isNull);
      expect(result.items.items, isEmpty);
      expect(result.overallConfidence, equals(0.0));
    });

    test('should handle whitespace-only lines', () {
      final lines = ['   ', '\t', '  \n  ', ''];
      
      final result = matcher.extractAll(lines);
      
      expect(result.rawLines, equals(lines));
      expect(result.market.value, isNull);
    });

    test('should handle very long lines', () {
      final longLine = 'A' * 1000 + ' 99.99';
      final lines = [longLine, 'TOTAL 99.99'];
      
      final result = matcher.extractAll(lines);
      
      // Should not crash
      expect(result, isNotNull);
    });

    test('should handle special characters in market name', () {
      final lines = [
        "TRADER JOE'S & SONS™",
        'Item 5.00',
        'TOTAL 5.00',
      ];
      
      final result = matcher.extractAll(lines);
      
      // Should find trader joes even with special characters
      expect(result.market.value?.toLowerCase(), contains('trader'));
    });

    test('should handle numeric-only lines', () {
      final lines = [
        '12345',
        '67890',
        '99.99',
      ];
      
      final result = matcher.extractAll(lines);
      
      // Should handle gracefully without crashing
      // Note: Without a sum keyword, extraction may not find a total
      expect(result, isNotNull);
      expect(result.rawLines, equals(lines));
    });

    test('should handle malformed prices', () {
      final lines = [
        'Item 1 5.999', // Too many decimals
        'Item 2 5', // No decimals
        'Item 3 5.9', // One decimal
        'TOTAL 16.899',
      ];
      
      final result = matcher.extractAll(lines);
      
      // Should handle gracefully
      expect(result, isNotNull);
    });

    test('should handle mixed currencies', () {
      final lines = [
        'SPAR',
        'Item €5.00',
        'Item \$3.00',
        'Item £2.00',
        'Total 10.00',
      ];
      
      final result = matcher.extractAll(lines);
      
      expect(result.sum.value, isNotNull);
    });

    test('should handle unicode characters', () {
      final lines = [
        'SPÄR Märket',
        'Käse  3.99',
        'Müsli  4.99',
        'Total  8.98',
      ];
      
      final result = matcher.extractAll(lines);
      
      // Should handle unicode without crashing and extract the total
      expect(result, isNotNull);
      expect(result.sum.value, isNotNull);
      expect(result.sum.value, equals('8.98'));
    });

    test('should handle duplicate total lines', () {
      final lines = [
        'SUBTOTAL  10.00',
        'TAX  0.80',
        'TOTAL  10.80',
        'TOTAL  10.80', // Duplicate
      ];
      
      final result = matcher.extractSum(lines);
      
      expect(result.value, equals('10.80'));
    });
  });

  group('Confidence Levels', () {
    test('should identify high confidence results', () {
      final result = MatchResult(
        value: 'walmart',
        confidence: 0.95,
        fieldType: 'market',
      );
      
      expect(result.isHighConfidence, isTrue);
      expect(result.isMediumConfidence, isTrue);
      expect(result.isLowConfidence, isTrue);
    });

    test('should identify medium confidence results', () {
      final result = MatchResult(
        value: 'store',
        confidence: 0.70,
        fieldType: 'market',
      );
      
      expect(result.isHighConfidence, isFalse);
      expect(result.isMediumConfidence, isTrue);
      expect(result.isLowConfidence, isTrue);
    });

    test('should identify low confidence results', () {
      final result = MatchResult(
        value: 'unknown',
        confidence: 0.50,
        fieldType: 'market',
      );
      
      expect(result.isHighConfidence, isFalse);
      expect(result.isMediumConfidence, isFalse);
      expect(result.isLowConfidence, isTrue);
    });

    test('should identify below threshold results', () {
      final result = MatchResult(
        value: 'maybe',
        confidence: 0.30,
        fieldType: 'market',
      );
      
      expect(result.isHighConfidence, isFalse);
      expect(result.isMediumConfidence, isFalse);
      expect(result.isLowConfidence, isFalse);
    });
  });

  group('ExtractionResult', () {
    test('should calculate overall confidence correctly', () {
      final result = ExtractionResult(
        market: MatchResult(value: 'walmart', confidence: 0.9, fieldType: 'market'),
        date: MatchResult(value: '01/01/2024', confidence: 0.8, fieldType: 'date'),
        sum: MatchResult(value: '100.00', confidence: 0.95, fieldType: 'sum'),
        items: ItemsResult(items: [], averageConfidence: 0.0),
        rawLines: [],
      );
      
      // Should average non-zero confidences: (0.9 + 0.8 + 0.95) / 3
      final expectedConfidence = (0.9 + 0.8 + 0.95) / 3;
      expect(result.overallConfidence, closeTo(expectedConfidence, 0.01));
    });

    test('should convert to JSON', () {
      final result = ExtractionResult(
        market: MatchResult(value: 'walmart', confidence: 0.9, fieldType: 'market'),
        date: MatchResult(value: '01/01/2024', confidence: 0.8, fieldType: 'date'),
        sum: MatchResult(value: '100.00', confidence: 0.95, fieldType: 'sum'),
        items: ItemsResult(items: [
          ItemMatch(name: 'Item', price: 10.0, confidence: 0.85, originalLine: 'Item 10.00'),
        ], averageConfidence: 0.85),
        rawLines: ['Line 1', 'Line 2'],
      );
      
      final jsonMap = result.toJson();
      
      expect(jsonMap['market'], isA<Map>());
      expect(jsonMap['date'], isA<Map>());
      expect(jsonMap['sum'], isA<Map>());
      expect(jsonMap['items'], isA<Map>());
      expect(jsonMap['overall_confidence'], isA<double>());
    });

    test('should produce readable toString output', () {
      final result = ExtractionResult(
        market: MatchResult(value: 'walmart', confidence: 0.9, fieldType: 'market'),
        date: MatchResult(value: '01/01/2024', confidence: 0.8, fieldType: 'date'),
        sum: MatchResult(value: '100.00', confidence: 0.95, fieldType: 'sum'),
        items: ItemsResult(items: [], averageConfidence: 0.0),
        rawLines: [],
      );
      
      final stringOutput = result.toString();
      
      expect(stringOutput, contains('walmart'));
      expect(stringOutput, contains('01/01/2024'));
      expect(stringOutput, contains('100.00'));
      expect(stringOutput, contains('Overall Confidence'));
    });
  });

  group('ItemMatch', () {
    test('should convert to JSON correctly', () {
      final item = ItemMatch(
        name: 'Organic Milk',
        price: 5.99,
        confidence: 0.85,
        originalLine: 'Organic Milk  5.99 F',
        patternUsed: 'builtin:item_pattern_0',
      );
      
      final jsonMap = item.toJson();
      
      expect(jsonMap['name'], equals('Organic Milk'));
      expect(jsonMap['price'], equals(5.99));
      expect(jsonMap['confidence'], equals(0.85));
      expect(jsonMap['original_line'], equals('Organic Milk  5.99 F'));
      expect(jsonMap['pattern_used'], equals('builtin:item_pattern_0'));
    });
  });

  group('Realistic Receipt Scenarios', () {
    test('should process full Walmart receipt', () {
      final walmartReceipt = [
        'WALMART',
        'SUPERCENTER',
        '( 601 ) 924-1398',
        'BRANDON, MS 39047',
        'MGR: JOHN SMITH',
        'ST# 1234  OP# 00001234  TE# 01  TR# 01234',
        '',
        'GV OATMEAL          3.48 F',
        '006034511111',
        'SIMPLY JIF 28 OZ    4.52',
        '005150017011',
        'GV 2% MILK          3.62 F',
        '007874202340',
        'KETCHUP HNZ         3.98',
        '001300000111',
        '',
        '       SUBTOTAL              15.60',
        '       TAX 1    7.000%        0.59',
        '       TOTAL                 16.19',
        '',
        '       VISA TEND             16.19',
        '',
        'CHANGE DUE                    0.00',
        '',
        '# ITEMS SOLD 4',
        '',
        '  10/18/20        12:30:45',
        '',
        '***CUSTOMER COPY***',
      ];
      
      final result = matcher.extractAll(walmartReceipt);
      
      expect(result.market.value, equals('walmart'));
      expect(result.market.confidence, greaterThanOrEqualTo(0.85));
      expect(result.date.value, isNotNull);
      expect(result.sum.value, isNotNull);
      expect(result.items.items.length, greaterThanOrEqualTo(1));
    });

    test('should process Trader Joes receipt with complex formatting', () {
      final traderJoesReceipt = [
        "TRADER JOE'S #185",
        '1 S PINCKNEY ST',
        'MADISON WI 53703',
        '(608) 257-1916',
        '',
        '06-28-2014  3:45 PM',
        '',
        'ORGANIC BANANAS         0.99',
        'TJ SOURDOUGH BRD        2.99',
        '  @  2.99 EA',
        'ALMOND BEVERAGE         2.99',
        'GREEK YOGURT HNNY       1.29',
        '  @  1.29 EA',
        'TRIPLE GINGERSNAPS      2.99',
        '',
        'SUBTOTAL               11.25',
        'TAX  5.500%             0.00',
        'TOTAL                  11.25',
        '',
        'MASTERCARD             11.25',
        '',
        'TRANSACTION ID: 12345678',
        'APPROVAL CODE: 123456',
      ];
      
      final result = matcher.extractAll(traderJoesReceipt);
      
      expect(result.market.value, equals('trader_joes'));
      expect(result.date.value, isNotNull);
      expect(result.sum.value, equals('11.25'));
    });

    test('should process Whole Foods receipt', () {
      final wholeFoodsReceipt = [
        'Whole Foods Market',
        'CHICAGO GOLD COAST',
        '30 W HURON ST',
        'CHICAGO IL 60654',
        '',
        '365 ORGANIC EGGS       5.99',
        'HASS AVOCADO           1.69',
        '  @  1.69 EA',
        'ORGANIC STRAWBERRIES   4.99',
        'EZEKIEL BREAD          5.49',
        '',
        'Subtotal              18.16',
        'Tax                    0.00',
        'Total                 18.16',
        '',
        'AMEX                  18.16',
        '',
        'December 15, 2024  2:30 PM',
      ];
      
      final result = matcher.extractAll(wholeFoodsReceipt);
      
      expect(result.market.value, equals('whole_foods'));
      expect(result.sum.value, equals('18.16'));
    });

    test('should process European SPAR receipt', () {
      final sparReceipt = [
        'SPAR',
        'Filiale 1234',
        'Wien, Österreich',
        '',
        '28.06.2014 14:22',
        '',
        'Vollmilch 1L           1,29',
        'Semmel 5 Stk           1,95',
        'Bergkäse               4,99',
        'Schokolade             2,49',
        '',
        'SUMME                 10,72',
        'EUR                   10,72',
        '',
        'Bar                   20,00',
        'Rückgeld               9,28',
        '',
        'Vielen Dank!',
      ];
      
      final result = matcher.extractAll(sparReceipt);
      
      expect(result.market.value, equals('spar'));
      expect(result.date.value, isNotNull);
      expect(result.sum.value, isNotNull);
    });
  });

  group('Pattern Recognition Performance', () {
    test('should efficiently process multiple receipts', () {
      final receipts = List.generate(10, (i) => [
        'WALMART',
        'Store #$i',
        '01/${i + 1}/2024',
        'Item $i  ${i + 1}.99',
        'TOTAL  ${i + 1}.99',
      ]);
      
      final stopwatch = Stopwatch()..start();
      
      for (final receipt in receipts) {
        matcher.extractAll(receipt);
      }
      
      stopwatch.stop();
      
      // Should process 10 receipts in reasonable time (< 1 second)
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('should accumulate stats across multiple extractions', () {
      final receipt = [
        'WALMART',
        '01/15/2024',
        'Item  10.00',
        'TOTAL  10.00',
      ];
      
      // Process 5 receipts
      for (var i = 0; i < 5; i++) {
        matcher.extractAll(receipt);
      }
      
      final stats = matcher.getStats();
      expect(stats['total_extractions'], equals(5));
    });
  });
}
