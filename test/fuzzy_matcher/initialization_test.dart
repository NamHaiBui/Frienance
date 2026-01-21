import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/base_configs.dart';
import 'test_helper.dart';

/// Tests for AdaptiveFuzzyMatcher initialization and configuration
void main() {
  // ignore: unused_local_variable
  late String testConfigPath;
  late AdaptiveFuzzyMatcher matcher;
  late TestHelper helper;

  setUp(() async {
    helper = TestHelper();
    await helper.setUp();
    testConfigPath = helper.testConfigPath;
    matcher = helper.matcher;
  });

  tearDown(() {
    helper.tearDown();
  });

  group('Initialization', () {
    test('should load config from file', () {
      final exportedConfig = matcher.exportConfig();
      final config = json.decode(exportedConfig) as Map<String, dynamic>;
      
      expect(config.containsKey('markets'), isTrue);
      expect(config.containsKey('sum_keys'), isTrue);
      expect(config.containsKey('ignore_keys'), isTrue);
      expect(config.containsKey('learned_patterns'), isTrue);
    });

    test('should create default config if file does not exist', () async {
      final newConfigPath = '${Directory.systemTemp.path}/new_config_${DateTime.now().millisecondsSinceEpoch}.json';
      
      final newMatcher = AdaptiveFuzzyMatcher(newConfigPath);
      final initResult = await newMatcher.initialize();
      expect(initResult.isSuccess, isTrue);
      expect(File(newConfigPath).existsSync(), isTrue);
      
      final exportedConfig = newMatcher.exportConfig();
      final config = json.decode(exportedConfig) as Map<String, dynamic>;
      
      expect(config['markets'], isA<Map>());
      expect((config['markets'] as Map).containsKey('walmart'), isTrue);
      
      // Clean up
      File(newConfigPath).deleteSync();
    });

    test('should initialize learned patterns correctly', () {
      final stats = matcher.getStats();
      expect(stats['total_extractions'], equals(0));
      expect(stats['successful_markets'], equals(0));
    });

    test('should have valid confidence thresholds', () {
      expect(FuzzyMatchingConfidence.high.value, equals(0.85));
      expect(FuzzyMatchingConfidence.medium.value, equals(0.65));
      expect(FuzzyMatchingConfidence.low.value, equals(0.45));
    });
  });

  group('Config Import/Export', () {
    test('should export config as JSON string', () {
      final exported = matcher.exportConfig();
      expect(() => json.decode(exported), returnsNormally);
    });

    test('should import config from JSON string', () async {
      final customConfig = {
        ...TestHelper.defaultConfig,
        'markets': {
          'custom_market': ['custom', 'store'],
        },
      };
      
      final newConfigPath = '${Directory.systemTemp.path}/import_test_${DateTime.now().millisecondsSinceEpoch}.json';
      final newMatcher = AdaptiveFuzzyMatcher(newConfigPath);
      final initResult = await newMatcher.initialize();
      expect(initResult.isSuccess, isTrue);
      
      newMatcher.importConfig(json.encode(customConfig));
      final exported = json.decode(newMatcher.exportConfig()) as Map<String, dynamic>;
      
      expect((exported['markets'] as Map).containsKey('custom_market'), isTrue);
      
      File(newConfigPath).deleteSync();
    });
  });
}
