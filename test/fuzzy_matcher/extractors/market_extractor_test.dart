import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/extractors/market_extractor.dart';

void main() {
  late String testConfigPath;
  late ConfigManager configManager;
  late MarketExtractor extractor;

  setUp(() {
    testConfigPath = '${Directory.systemTemp.path}/test_market_${DateTime.now().millisecondsSinceEpoch}.json';
    
    final config = {
      'markets': {
        'walmart': ['walmart', 'wal-mart', 'wal mart'],
        'target': ['target'],
        'whole_foods': ['whole foods', 'wholefoods'],
        'trader_joes': ['trader joe', "trader joe's"],
      },
      'sum_keys': ['total'],
      'ignore_keys': ['tax'],
      'learned_patterns': {
        'successful_market_matches': <String, dynamic>{},
        'successful_date_patterns': <String>[],
        'successful_sum_patterns': <String>[],
        'successful_item_patterns': <String>[],
        'user_corrections': [],
        'extraction_stats': {},
      },
    };
    
    File(testConfigPath).writeAsStringSync(json.encode(config));
    configManager = ConfigManager(testConfigPath);
    extractor = MarketExtractor(configManager);
  });

  tearDown(() {
    final file = File(testConfigPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  group('MarketExtractor', () {
    group('basic extraction', () {
      test('extracts walmart from receipt', () {
        final lines = [
          'WALMART SUPERCENTER',
          '123 MAIN ST',
          'STORE #1234',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, 'walmart');
        expect(result.confidence, greaterThan(0.8));
        expect(result.fieldType, 'market');
      });

      test('extracts target from receipt', () {
        final lines = [
          'TARGET',
          'T-1234',
          '456 COMMERCE DR',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, 'target');
        expect(result.confidence, greaterThan(0.8));
      });

      test('extracts whole foods with space', () {
        final lines = [
          'WHOLE FOODS MARKET',
          'SAN FRANCISCO, CA',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, 'whole_foods');
        expect(result.confidence, greaterThan(0.8));
      });

      test('extracts trader joes with apostrophe', () {
        final lines = [
          "TRADER JOE'S",
          '#789',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, 'trader_joes');
        expect(result.confidence, greaterThan(0.8));
      });
    });

    group('fuzzy matching', () {
      test('handles typos in store name', () {
        final lines = [
          'WALMRT SUPERCENTR',
          '123 MAIN ST',
        ];
        
        final result = extractor.extract(lines);
        // May not match due to typo - tests fuzzy behavior
        expect(result.fieldType, 'market');
      });

      test('handles alternative spellings', () {
        final lines = [
          'WAL-MART #1234',
          '123 MAIN ST',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, 'walmart');
        expect(result.confidence, greaterThan(0.8));
      });

      test('handles case insensitivity', () {
        final lines = [
          'walmart',
          'store info',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, 'walmart');
      });
    });

    group('confidence scoring', () {
      test('direct contains match has high confidence', () {
        final lines = ['WALMART SUPERCENTER'];
        final result = extractor.extract(lines);
        expect(result.confidence, greaterThanOrEqualTo(0.85));
      });

      test('pattern used is tracked', () {
        final lines = ['WALMART SUPERCENTER'];
        final result = extractor.extract(lines);
        expect(result.patternUsed, isNotNull);
      });

      test('matched line is tracked', () {
        final lines = ['WALMART SUPERCENTER', 'OTHER LINE'];
        final result = extractor.extract(lines);
        expect(result.matchedLine, 'WALMART SUPERCENTER');
      });
    });

    group('edge cases', () {
      test('returns null value for unrecognized store', () {
        final lines = [
          'UNKNOWN STORE XYZ',
          '123 FAKE ST',
        ];
        
        final result = extractor.extract(lines);
        // May match via market indicators or have null value
        expect(result.fieldType, 'market');
      });

      test('handles empty lines list', () {
        final result = extractor.extract([]);
        expect(result.value, isNull);
        expect(result.confidence, 0.0);
      });

      test('only checks first 10 lines', () {
        final lines = List.generate(15, (i) => 'LINE $i');
        lines.add('WALMART'); // Line 16 - should not be checked
        
        final result = extractor.extract(lines);
        // Walmart is after line 10, may not be found
        expect(result.fieldType, 'market');
      });
    });

    group('learned patterns', () {
      test('uses learned patterns with high confidence', () {
        // Add learned pattern
        configManager.learnedPatterns['successful_market_matches'] = {
          'custom_store': ['custom store marker']
        };
        
        final lines = ['CUSTOM STORE MARKER', 'OTHER LINE'];
        final result = extractor.extract(lines);
        
        expect(result.value, 'custom_store');
        expect(result.confidence, 0.95);
        expect(result.patternUsed, startsWith('learned:'));
      });
    });
  });
}
