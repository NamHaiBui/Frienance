import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/learning/pattern_learner.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/extraction_results.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/match_result.dart';

void main() {
  late String testConfigPath;
  late ConfigManager configManager;
  late PatternLearner learner;

  setUp(() {
    testConfigPath = '${Directory.systemTemp.path}/test_learner_${DateTime.now().millisecondsSinceEpoch}.json';
    
    final config = {
      'markets': {
        'walmart': ['walmart'],
      },
      'sum_keys': ['total'],
      'ignore_keys': [],
      'learned_patterns': {
        'successful_market_matches': <String, dynamic>{},
        'successful_date_patterns': <String>[],
        'successful_sum_patterns': <String>[],
        'successful_item_patterns': <String>[],
        'user_corrections': <Map<String, dynamic>>[],
        'extraction_stats': <String, dynamic>{
          'total_extractions': 0,
          'successful_markets': 0,
          'successful_dates': 0,
          'successful_sums': 0,
          'successful_items': 0,
        },
      },
    };
    
    File(testConfigPath).writeAsStringSync(json.encode(config));
    configManager = ConfigManager(testConfigPath);
    learner = PatternLearner(configManager);
  });

  tearDown(() {
    final file = File(testConfigPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  group('PatternLearner', () {
    group('updateExtractionStats', () {
      test('increments total extractions', () {
        final market = MatchResult(value: 'walmart', confidence: 0.9, fieldType: 'market');
        final date = MatchResult(value: '01/15/2024', confidence: 0.8, fieldType: 'date');
        final sum = MatchResult(value: '10.00', confidence: 0.85, fieldType: 'sum');
        final items = ItemsResult(items: [], averageConfidence: 0.0);
        
        learner.updateExtractionStats(market, date, sum, items);
        
        final stats = configManager.getStats();
        expect(stats['total_extractions'], 1);
      });

      test('increments successful markets when high confidence', () {
        final market = MatchResult(value: 'walmart', confidence: 0.9, fieldType: 'market');
        final date = MatchResult(value: null, confidence: 0.0, fieldType: 'date');
        final sum = MatchResult(value: null, confidence: 0.0, fieldType: 'sum');
        final items = ItemsResult(items: [], averageConfidence: 0.0);
        
        learner.updateExtractionStats(market, date, sum, items);
        
        final stats = configManager.getStats();
        expect(stats['successful_markets'], 1);
      });

      test('does not increment when low confidence', () {
        final market = MatchResult(value: 'walmart', confidence: 0.3, fieldType: 'market');
        final date = MatchResult(value: null, confidence: 0.0, fieldType: 'date');
        final sum = MatchResult(value: null, confidence: 0.0, fieldType: 'sum');
        final items = ItemsResult(items: [], averageConfidence: 0.0);
        
        learner.updateExtractionStats(market, date, sum, items);
        
        final stats = configManager.getStats();
        expect(stats['successful_markets'], 0);
      });

      test('increments successful items when items exist', () {
        final market = MatchResult(value: null, confidence: 0.0, fieldType: 'market');
        final date = MatchResult(value: null, confidence: 0.0, fieldType: 'date');
        final sum = MatchResult(value: null, confidence: 0.0, fieldType: 'sum');
        final items = ItemsResult(
          items: [ItemMatch(name: 'Item', price: 5.0, confidence: 0.8, originalLine: 'ITEM 5.00')],
          averageConfidence: 0.8,
        );
        
        learner.updateExtractionStats(market, date, sum, items);
        
        final stats = configManager.getStats();
        expect(stats['successful_items'], 1);
      });
    });

    group('learnMarketPattern', () {
      test('adds market pattern to learned matches', () {
        learner.learnMarketPattern('Custom Store', 'CUSTOM STORE #123');
        
        final matches = configManager.learnedMarketMatches;
        expect(matches.containsKey('custom_store'), true);
      });

      test('extracts tokens from matched line', () {
        learner.learnMarketPattern('MyStore', 'MYSTORE SUPERMARKET #456');
        
        final matches = configManager.learnedMarketMatches;
        final patterns = (matches['mystore'] as List).cast<String>();
        expect(patterns, contains('mystore'));
        expect(patterns, contains('supermarket'));
      });

      test('adds to existing config markets', () {
        learner.learnMarketPattern('newmarket', 'NEW MARKET STORE');
        configManager.saveConfig();
        
        final markets = configManager.markets;
        expect(markets.containsKey('newmarket'), true);
      });
    });

    group('learnDatePattern', () {
      test('learns custom date pattern', () {
        learner.learnDatePattern('learned:custom_date_pattern');
        
        expect(configManager.learnedDatePatterns, contains('custom_date_pattern'));
      });

      test('does not learn builtin patterns', () {
        learner.learnDatePattern('builtin:date_pattern_0');
        
        expect(configManager.learnedDatePatterns, isEmpty);
      });

      test('does not learn config patterns', () {
        learner.learnDatePattern('config:date_format');
        
        expect(configManager.learnedDatePatterns, isEmpty);
      });
    });

    group('learnSumPattern', () {
      test('learns custom sum pattern', () {
        learner.learnSumPattern('learned:custom_sum_pattern');
        
        expect(configManager.learnedSumPatterns, contains('custom_sum_pattern'));
      });

      test('does not learn builtin patterns', () {
        learner.learnSumPattern('builtin:sum_pattern_0');
        
        expect(configManager.learnedSumPatterns, isEmpty);
      });
    });

    group('learnItemPattern', () {
      test('learns custom item pattern', () {
        learner.learnItemPattern('learned:custom_item_pattern');
        
        expect(configManager.learnedItemPatterns, contains('custom_item_pattern'));
      });

      test('does not learn builtin patterns', () {
        learner.learnItemPattern('builtin:item_pattern_0');
        
        expect(configManager.learnedItemPatterns, isEmpty);
      });

      test('does not learn simple patterns', () {
        learner.learnItemPattern('simple:name_price');
        
        expect(configManager.learnedItemPatterns, isEmpty);
      });
    });

    group('confirmExtraction', () {
      test('learns from confirmed market', () {
        final result = ExtractionResult(
          market: MatchResult(
            value: 'walmart',
            confidence: 0.9,
            matchedLine: 'WALMART STORE #123',
            patternUsed: 'contains:walmart',
            fieldType: 'market',
          ),
          date: MatchResult(value: null, confidence: 0.0, fieldType: 'date'),
          sum: MatchResult(value: null, confidence: 0.0, fieldType: 'sum'),
          items: ItemsResult(items: [], averageConfidence: 0.0),
          rawLines: ['WALMART STORE #123'],
        );
        
        learner.confirmExtraction(result, confirmedMarket: 'walmart');
        
        // Should have learned the pattern
        final matches = configManager.learnedMarketMatches;
        expect(matches.containsKey('walmart'), true);
      });

      test('learns from confirmed date', () {
        final result = ExtractionResult(
          market: MatchResult(value: null, confidence: 0.0, fieldType: 'market'),
          date: MatchResult(
            value: '01/15/2024',
            confidence: 0.9,
            patternUsed: 'learned:custom_pattern',
            fieldType: 'date',
          ),
          sum: MatchResult(value: null, confidence: 0.0, fieldType: 'sum'),
          items: ItemsResult(items: [], averageConfidence: 0.0),
          rawLines: [],
        );
        
        learner.confirmExtraction(result, confirmedDate: '01/15/2024');
        
        // Should have learned the pattern
        expect(configManager.learnedDatePatterns, contains('custom_pattern'));
      });
    });

    group('recordCorrection', () {
      test('stores user correction', () {
        learner.recordCorrection(
          fieldType: 'market',
          originalValue: 'walmar',
          correctedValue: 'walmart',
          originalLine: 'WALMAR #123',
        );
        
        final corrections = configManager.learnedPatterns['user_corrections'] as List;
        expect(corrections.length, 1);
        expect(corrections[0]['field_type'], 'market');
        expect(corrections[0]['original_value'], 'walmar');
        expect(corrections[0]['corrected_value'], 'walmart');
        expect(corrections[0]['original_line'], 'WALMAR #123');
        expect(corrections[0]['timestamp'], isNotNull);
      });

      test('saves config after recording', () {
        learner.recordCorrection(
          fieldType: 'date',
          originalValue: '2024-01-15',
          correctedValue: '01/15/2024',
        );
        
        // Verify by creating new config manager
        final newConfig = ConfigManager(testConfigPath);
        final corrections = newConfig.learnedPatterns['user_corrections'] as List;
        expect(corrections.length, 1);
      });
    });
  });
}
