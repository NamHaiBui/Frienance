import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';

void main() {
  late String testConfigPath;
  late ConfigManager configManager;

  setUp(() {
    testConfigPath = '${Directory.systemTemp.path}/test_config_${DateTime.now().millisecondsSinceEpoch}.json';
  });

  tearDown(() {
    final file = File(testConfigPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  group('ConfigManager', () {
    group('initialization', () {
      test('creates default config when file does not exist', () {
        configManager = ConfigManager(testConfigPath);
        
        expect(File(testConfigPath).existsSync(), true);
        expect(configManager.markets, isNotEmpty);
        expect(configManager.sumKeys, isNotEmpty);
        expect(configManager.ignoreKeys, isNotEmpty);
      });

      test('loads existing config file', () {
        final existingConfig = {
          'markets': {'custom_store': ['custom']},
          'sum_keys': ['total'],
          'ignore_keys': ['tax'],
          'learned_patterns': {},
        };
        
        File(testConfigPath).writeAsStringSync(json.encode(existingConfig));
        configManager = ConfigManager(testConfigPath);
        
        expect(configManager.markets.containsKey('custom_store'), true);
      });
    });

    group('config accessors', () {
      setUp(() {
        configManager = ConfigManager(testConfigPath);
      });

      test('markets returns market map', () {
        final markets = configManager.markets;
        expect(markets, isA<Map<String, dynamic>>());
        expect(markets.containsKey('walmart'), true);
      });

      test('sumKeys returns list of sum keywords', () {
        final sumKeys = configManager.sumKeys;
        expect(sumKeys, isA<List<String>>());
        expect(sumKeys.contains('total'), true);
      });

      test('ignoreKeys returns list of ignore keywords', () {
        final ignoreKeys = configManager.ignoreKeys;
        expect(ignoreKeys, isA<List<String>>());
        expect(ignoreKeys.contains('tax'), true);
      });
    });

    group('learned patterns', () {
      setUp(() {
        configManager = ConfigManager(testConfigPath);
      });

      test('learnedMarketMatches returns empty map initially', () {
        expect(configManager.learnedMarketMatches, isEmpty);
      });

      test('learnedDatePatterns returns empty list initially', () {
        expect(configManager.learnedDatePatterns, isEmpty);
      });

      test('learnedSumPatterns returns empty list initially', () {
        expect(configManager.learnedSumPatterns, isEmpty);
      });

      test('learnedItemPatterns returns empty list initially', () {
        expect(configManager.learnedItemPatterns, isEmpty);
      });

      test('addLearnedDatePattern adds pattern', () {
        configManager.addLearnedDatePattern(r'\d{4}-\d{2}-\d{2}');
        expect(configManager.learnedDatePatterns, contains(r'\d{4}-\d{2}-\d{2}'));
      });

      test('addLearnedDatePattern does not add duplicates', () {
        configManager.addLearnedDatePattern(r'\d{4}-\d{2}-\d{2}');
        configManager.addLearnedDatePattern(r'\d{4}-\d{2}-\d{2}');
        expect(configManager.learnedDatePatterns.length, 1);
      });

      test('addLearnedSumPattern adds pattern', () {
        configManager.addLearnedSumPattern(r'total:\s*\$(\d+\.\d{2})');
        expect(configManager.learnedSumPatterns, contains(r'total:\s*\$(\d+\.\d{2})'));
      });

      test('addLearnedItemPattern adds pattern', () {
        configManager.addLearnedItemPattern(r'^(.+?)\s+(\d+\.\d{2})$');
        expect(configManager.learnedItemPatterns, contains(r'^(.+?)\s+(\d+\.\d{2})$'));
      });
    });

    group('user corrections', () {
      setUp(() {
        configManager = ConfigManager(testConfigPath);
      });

      test('addUserCorrection stores correction', () {
        configManager.addUserCorrection(
          fieldType: 'market',
          originalValue: 'walmar',
          correctedValue: 'walmart',
          originalLine: 'WALMAR #1234',
        );
        
        final corrections = configManager.learnedPatterns['user_corrections'] as List;
        expect(corrections.length, 1);
        expect(corrections[0]['field_type'], 'market');
        expect(corrections[0]['original_value'], 'walmar');
        expect(corrections[0]['corrected_value'], 'walmart');
      });
    });

    group('config persistence', () {
      setUp(() {
        configManager = ConfigManager(testConfigPath);
      });

      test('saveConfig persists changes', () {
        configManager.addLearnedDatePattern(r'\d{4}-\d{2}-\d{2}');
        configManager.saveConfig();
        
        // Create new instance to verify persistence
        final newManager = ConfigManager(testConfigPath);
        expect(newManager.learnedDatePatterns, contains(r'\d{4}-\d{2}-\d{2}'));
      });

      test('exportConfig returns formatted JSON', () {
        final exported = configManager.exportConfig();
        expect(exported, isA<String>());
        expect(() => json.decode(exported), returnsNormally);
      });

      test('importConfig loads from JSON string', () {
        final customConfig = {
          'markets': {'imported_store': ['imported']},
          'sum_keys': ['imported_total'],
          'ignore_keys': [],
          'learned_patterns': {},
        };
        
        configManager.importConfig(json.encode(customConfig));
        expect(configManager.markets.containsKey('imported_store'), true);
        expect(configManager.sumKeys.contains('imported_total'), true);
      });
    });

    group('resetLearnedPatterns', () {
      setUp(() {
        configManager = ConfigManager(testConfigPath);
      });

      test('clears all learned patterns', () {
        configManager.addLearnedDatePattern(r'\d{4}-\d{2}-\d{2}');
        configManager.addLearnedSumPattern(r'total:\s*\d+');
        
        configManager.resetLearnedPatterns();
        
        expect(configManager.learnedDatePatterns, isEmpty);
        expect(configManager.learnedSumPatterns, isEmpty);
        expect(configManager.learnedMarketMatches, isEmpty);
      });

      test('resets extraction stats', () {
        configManager.resetLearnedPatterns();
        
        final stats = configManager.getStats();
        expect(stats['total_extractions'], 0);
        expect(stats['successful_markets'], 0);
      });
    });

    group('getStats', () {
      setUp(() {
        configManager = ConfigManager(testConfigPath);
      });

      test('returns extraction statistics', () {
        final stats = configManager.getStats();
        expect(stats, isA<Map<String, dynamic>>());
        expect(stats.containsKey('total_extractions'), true);
      });
    });
  });
}
