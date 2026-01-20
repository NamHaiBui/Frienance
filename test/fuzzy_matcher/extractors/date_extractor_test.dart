import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/extractors/date_extractor.dart';

void main() {
  late String testConfigPath;
  late ConfigManager configManager;
  late DateExtractor extractor;

  setUp(() {
    testConfigPath = '${Directory.systemTemp.path}/test_date_${DateTime.now().millisecondsSinceEpoch}.json';
    
    final config = {
      'markets': {},
      'sum_keys': [],
      'ignore_keys': [],
      'date_format': r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b',
      'learned_patterns': {
        'successful_market_matches': {},
        'successful_date_patterns': <String>[],
        'successful_sum_patterns': [],
        'successful_item_patterns': [],
        'user_corrections': [],
        'extraction_stats': {},
      },
    };
    
    File(testConfigPath).writeAsStringSync(json.encode(config));
    configManager = ConfigManager(testConfigPath);
    extractor = DateExtractor(configManager);
  });

  tearDown(() {
    final file = File(testConfigPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  group('DateExtractor', () {
    group('MM/DD/YYYY format', () {
      test('extracts date with slashes', () {
        final lines = ['Date: 01/15/2024', 'Other text'];
        final result = extractor.extract(lines);
        expect(result.value, '01/15/2024');
        expect(result.confidence, greaterThan(0.7));
      });

      test('extracts date with single digit month/day', () {
        final lines = ['1/5/2024'];
        final result = extractor.extract(lines);
        expect(result.value, '1/5/2024');
      });

      test('extracts date with 2-digit year', () {
        final lines = ['12/25/24'];
        final result = extractor.extract(lines);
        expect(result.value, '12/25/24');
      });
    });

    group('DD-MM-YYYY format', () {
      test('extracts date with dashes', () {
        final lines = ['15-01-2024'];
        final result = extractor.extract(lines);
        expect(result.value, '15-01-2024');
      });
    });

    group('YYYY-MM-DD format', () {
      test('extracts ISO format date', () {
        final lines = ['2024-01-15'];
        final result = extractor.extract(lines);
        expect(result.value, '2024-01-15');
      });
    });

    group('text month formats', () {
      test('extracts date with abbreviated month', () {
        final lines = ['15 Jan 2024'];
        final result = extractor.extract(lines);
        expect(result.value, contains('Jan'));
      });

      test('extracts date with full month name', () {
        final lines = ['January 15, 2024'];
        final result = extractor.extract(lines);
        expect(result.value, contains('January'));
      });

      test('handles case insensitive month', () {
        final lines = ['15 JAN 2024'];
        final result = extractor.extract(lines);
        expect(result.value, isNotNull);
      });
    });

    group('confidence scoring', () {
      test('first pattern has highest confidence', () {
        final lines = ['01/15/2024'];
        final result = extractor.extract(lines);
        expect(result.confidence, greaterThanOrEqualTo(0.80));
      });

      test('pattern used is tracked', () {
        final lines = ['01/15/2024'];
        final result = extractor.extract(lines);
        expect(result.patternUsed, isNotNull);
        expect(result.patternUsed, startsWith('builtin:'));
      });
    });

    group('edge cases', () {
      test('handles empty lines', () {
        final result = extractor.extract([]);
        expect(result.value, isNull);
        expect(result.confidence, 0.0);
      });

      test('returns null for lines without dates', () {
        final lines = ['No date here', 'Just text'];
        final result = extractor.extract(lines);
        expect(result.value, isNull);
      });

      test('handles multiple dates - returns best match', () {
        final lines = ['01/15/2024', '2024-01-20'];
        final result = extractor.extract(lines);
        expect(result.value, isNotNull);
        // Should pick the one with highest confidence
      });

      test('handles date in middle of text', () {
        final lines = ['Transaction on 01/15/2024 at store'];
        final result = extractor.extract(lines);
        expect(result.value, '01/15/2024');
      });
    });

    group('learned patterns', () {
      test('uses learned patterns with high confidence', () {
        configManager.addLearnedDatePattern(r'DATE:\s*(\d{4}/\d{2}/\d{2})');
        
        final lines = ['DATE: 2024/01/15'];
        final result = extractor.extract(lines);
        
        expect(result.confidence, 0.95);
        expect(result.patternUsed, startsWith('learned:'));
      });

      test('handles invalid learned regex gracefully', () {
        configManager.addLearnedDatePattern(r'[invalid(regex');
        
        final lines = ['01/15/2024'];
        final result = extractor.extract(lines);
        
        // Should still work with built-in patterns
        expect(result.value, '01/15/2024');
      });
    });
  });
}
