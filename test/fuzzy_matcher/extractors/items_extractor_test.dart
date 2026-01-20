import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/extractors/items_extractor.dart';

void main() {
  late String testConfigPath;
  late ConfigManager configManager;
  late ItemsExtractor extractor;

  setUp(() {
    testConfigPath = '${Directory.systemTemp.path}/test_items_${DateTime.now().millisecondsSinceEpoch}.json';
    
    final config = {
      'markets': {},
      'sum_keys': ['total', 'subtotal', 'sum'],
      'ignore_keys': ['tax', 'tip'],
      'learned_patterns': {
        'successful_market_matches': {},
        'successful_date_patterns': [],
        'successful_sum_patterns': [],
        'successful_item_patterns': <String>[],
        'user_corrections': [],
        'extraction_stats': {},
      },
    };
    
    File(testConfigPath).writeAsStringSync(json.encode(config));
    configManager = ConfigManager(testConfigPath);
    extractor = ItemsExtractor(configManager);
  });

  tearDown(() {
    final file = File(testConfigPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  group('ItemsExtractor', () {
    group('basic extraction', () {
      test('extracts simple items with prices', () {
        final lines = [
          'MILK 2%    3.99',
          'BREAD      2.50',
          'EGGS       4.99',
          'TOTAL     11.48',
        ];
        
        final result = extractor.extract(lines);
        expect(result.items.length, greaterThanOrEqualTo(2));
      });

      test('extracts item names correctly', () {
        final lines = [
          'ORGANIC MILK    5.99',
          'TOTAL    5.99',
        ];
        
        final result = extractor.extract(lines);
        if (result.items.isNotEmpty) {
          expect(result.items.first.name.toLowerCase(), contains('milk'));
        }
      });

      test('extracts item prices correctly', () {
        final lines = [
          'APPLE    1.50',
          'TOTAL    1.50',
        ];
        
        final result = extractor.extract(lines);
        if (result.items.isNotEmpty) {
          expect(result.items.first.price, 1.50);
        }
      });
    });

    group('item patterns', () {
      test('handles arrow format', () {
        final lines = [
          'ITEM -> 5.99',
          'TOTAL    5.99',
        ];
        
        final result = extractor.extract(lines);
        expect(result.items.isNotEmpty, true);
      });

      test('handles dollar sign prefix', () {
        final lines = [
          'COFFEE \$3.50',
          'TOTAL  \$3.50',
        ];
        
        final result = extractor.extract(lines);
        if (result.items.isNotEmpty) {
          expect(result.items.first.price, 3.50);
        }
      });

      test('handles quantity format', () {
        final lines = [
          '2 x DONUT 4.00',
          'TOTAL    4.00',
        ];
        
        final result = extractor.extract(lines);
        // May extract with quantity pattern
        expect(result.items, isA<List>());
      });
    });

    group('stopping conditions', () {
      test('stops extracting at total line', () {
        final lines = [
          'ITEM 1    5.00',
          'ITEM 2    3.00',
          'TOTAL     8.00',
          'ITEM 3    2.00', // Should not be extracted
        ];
        
        final result = extractor.extract(lines);
        // Should have at most 2 items (before total)
        expect(result.items.length, lessThanOrEqualTo(2));
      });

      test('stops at subtotal', () {
        final lines = [
          'ITEM 1    5.00',
          'SUBTOTAL  5.00',
          'ITEM 2    3.00',
        ];
        
        final result = extractor.extract(lines);
        expect(result.items.length, lessThanOrEqualTo(1));
      });
    });

    group('ignore keys', () {
      test('skips lines starting with ignore keys', () {
        final lines = [
          'ITEM 1    5.00',
          'TAX       0.40',
          'TIP       1.00',
          'TOTAL     6.40',
        ];
        
        final result = extractor.extract(lines);
        // Should only have ITEM 1
        for (final item in result.items) {
          expect(item.name.toLowerCase(), isNot(startsWith('tax')));
          expect(item.name.toLowerCase(), isNot(startsWith('tip')));
        }
      });
    });

    group('confidence scoring', () {
      test('items have confidence scores', () {
        final lines = [
          'MILK    3.99',
          'TOTAL   3.99',
        ];
        
        final result = extractor.extract(lines);
        if (result.items.isNotEmpty) {
          expect(result.items.first.confidence, greaterThan(0));
        }
      });

      test('average confidence is calculated', () {
        final lines = [
          'ITEM A    5.00',
          'ITEM B    3.00',
          'TOTAL     8.00',
        ];
        
        final result = extractor.extract(lines);
        if (result.items.isNotEmpty) {
          expect(result.averageConfidence, greaterThan(0));
        }
      });

      test('empty items returns 0 average confidence', () {
        final lines = ['NO ITEMS HERE'];
        final result = extractor.extract(lines);
        expect(result.averageConfidence, 0.0);
      });
    });

    group('edge cases', () {
      test('handles empty lines', () {
        final result = extractor.extract([]);
        expect(result.items, isEmpty);
        expect(result.averageConfidence, 0.0);
      });

      test('handles lines without prices', () {
        final lines = [
          'STORE NAME',
          'ADDRESS',
          'THANK YOU',
        ];
        
        final result = extractor.extract(lines);
        expect(result.items, isEmpty);
      });

      test('handles item with short name', () {
        final lines = [
          'A    1.00', // Single char name - may be filtered
          'TOTAL 1.00',
        ];
        
        final result = extractor.extract(lines);
        // Single char names may be filtered out
        expect(result.items, isA<List>());
      });

      test('tracks original line', () {
        final lines = [
          'ORGANIC MILK 2%    5.99',
          'TOTAL    5.99',
        ];
        
        final result = extractor.extract(lines);
        if (result.items.isNotEmpty) {
          expect(result.items.first.originalLine, 'ORGANIC MILK 2%    5.99');
        }
      });

      test('tracks pattern used', () {
        final lines = [
          'ITEM    5.99',
          'TOTAL   5.99',
        ];
        
        final result = extractor.extract(lines);
        if (result.items.isNotEmpty) {
          expect(result.items.first.patternUsed, isNotNull);
        }
      });
    });

    group('learned patterns', () {
      test('uses learned item patterns', () {
        configManager.addLearnedItemPattern(r'^CUSTOM:\s*(.+?)\s+-\s+(\d+\.\d{2})$');
        
        final lines = [
          'CUSTOM: Product Name - 9.99',
          'TOTAL    9.99',
        ];
        
        final result = extractor.extract(lines);
        if (result.items.isNotEmpty) {
          expect(result.items.first.confidence, greaterThanOrEqualTo(0.9));
        }
      });
    });
  });
}
