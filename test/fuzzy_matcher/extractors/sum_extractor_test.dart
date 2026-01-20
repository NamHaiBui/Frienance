import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/extractors/sum_extractor.dart';

void main() {
  late String testConfigPath;
  late ConfigManager configManager;
  late SumExtractor extractor;

  setUp(() {
    testConfigPath = '${Directory.systemTemp.path}/test_sum_${DateTime.now().millisecondsSinceEpoch}.json';
    
    final config = {
      'markets': {},
      'sum_keys': ['total', 'subtotal', 'amount', 'due', 'grand total', 'balance'],
      'ignore_keys': ['tax', 'tip', 'change', 'cash', 'debit', 'credit'],
      'learned_patterns': {
        'successful_market_matches': {},
        'successful_date_patterns': [],
        'successful_sum_patterns': <String>[],
        'successful_item_patterns': [],
        'user_corrections': [],
        'extraction_stats': {},
      },
    };
    
    File(testConfigPath).writeAsStringSync(json.encode(config));
    configManager = ConfigManager(testConfigPath);
    extractor = SumExtractor(configManager);
  });

  tearDown(() {
    final file = File(testConfigPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  group('SumExtractor', () {
    group('basic extraction', () {
      test('extracts total with keyword', () {
        final lines = [
          'ITEM 1    5.99',
          'ITEM 2    3.50',
          'TOTAL    9.49',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, '9.49');
        expect(result.confidence, greaterThan(0.8));
      });

      test('extracts subtotal', () {
        final lines = [
          'SUBTOTAL   15.99',
          'TAX         1.20',
          'TOTAL      17.19',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, '17.19');
      });

      test('extracts amount due', () {
        final lines = [
          'AMOUNT DUE: \$25.50',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, '25.50');
      });

      test('extracts grand total', () {
        final lines = [
          'GRAND TOTAL     \$100.00',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, '100.00');
      });
    });

    group('price formats', () {
      test('handles dollar sign prefix', () {
        final lines = ['TOTAL \$12.99'];
        final result = extractor.extract(lines);
        expect(result.value, '12.99');
      });

      test('handles comma decimal separator', () {
        final lines = ['TOTAL 12,99'];
        final result = extractor.extract(lines);
        expect(result.value, '12,99');
      });

      test('handles colon after keyword', () {
        final lines = ['TOTAL: 45.00'];
        final result = extractor.extract(lines);
        expect(result.value, '45.00');
      });
    });

    group('ignore keys', () {
      test('skips tax lines', () {
        final lines = [
          'SUBTOTAL   10.00',
          'TAX         0.80',
          'TOTAL      10.80',
        ];
        
        final result = extractor.extract(lines);
        // Should extract total, not tax
        expect(result.matchedLine?.toLowerCase(), contains('total'));
      });

      test('does not skip lines with total keyword even if ignore key present', () {
        final lines = [
          'TAX TOTAL   0.80',
        ];
        
        final result = extractor.extract(lines);
        // Should still match because "total" is present
        expect(result.value, '0.80');
      });
    });

    group('confidence scoring', () {
      test('higher confidence with sum keyword', () {
        final linesWithKeyword = ['TOTAL 10.00'];
        final linesWithoutKeyword = ['10.00'];
        
        final resultWith = extractor.extract(linesWithKeyword);
        final resultWithout = extractor.extract(linesWithoutKeyword);
        
        expect(resultWith.confidence, greaterThan(resultWithout.confidence));
      });

      test('pattern used is tracked', () {
        final lines = ['TOTAL 10.00'];
        final result = extractor.extract(lines);
        expect(result.patternUsed, isNotNull);
      });
    });

    group('edge cases', () {
      test('handles empty lines', () {
        final result = extractor.extract([]);
        expect(result.value, isNull);
        expect(result.confidence, 0.0);
      });

      test('prefers totals at bottom of receipt', () {
        final lines = [
          'ITEM    5.00',
          'SUBTOTAL   5.00',
          'TAX        0.40',
          'TOTAL      5.40',
        ];
        
        final result = extractor.extract(lines);
        expect(result.value, '5.40');
      });

      test('handles multiple prices on same line', () {
        final lines = ['2 @ 5.00    TOTAL 10.00'];
        final result = extractor.extract(lines);
        // Should extract a price associated with total
        expect(result.value, isNotNull);
      });
    });

    group('learned patterns', () {
      test('uses learned patterns', () {
        configManager.addLearnedSumPattern(r'TOTAL_AMT:\s*\$?(\d+\.\d{2})');
        
        final lines = ['TOTAL_AMT: \$99.99'];
        final result = extractor.extract(lines);
        
        expect(result.confidence, greaterThan(0.7));
      });
    });
  });
}
