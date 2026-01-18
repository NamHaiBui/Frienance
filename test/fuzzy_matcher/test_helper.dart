import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';

/// Shared test utilities and fixtures for fuzzy matcher tests
class TestHelper {
  static late String testConfigPath;
  static late AdaptiveFuzzyMatcher matcher;

  static Map<String, dynamic> get defaultConfig => {
    'markets': {
      'default': ['store', 'market', 'shop'],
      'walmart': ['walmart', 'wal-mart', 'wal mart', 'walmartk'],
      'target': ['target'],
      'costco': ['costco', 'wholesale'],
      'trader_joes': ['trader joe', "trader joe's", 'trader joes', 'atrader joe'],
      'whole_foods': ['whole foods', 'wholefoods', 'wfm', 'whole', 'oe foods'],
      'winco': ['winco', 'winco foods'],
      'spar': ['spar', 'sparo'],
      'momi_toys': ['momi', "momi & toy's"],
    },
    'sum_keys': [
      'total', 'subtotal', 'amount', 'due', 'sum', 'grand total',
      'net total', 'balance', 'payment', 'total due', 'jotal',
    ],
    'ignore_keys': [
      'tax', 'tip', 'change', 'cash', 'debit', 'credit', 'visa',
      'mastercard', 'approval', 'ref', 'terminal', 'network', 'tend',
    ],
    'sum_format': r'\d+[.,]\d{2}',
    'date_format': r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b',
    'item_format': r'^(.+?)\s+(\d+[.,]\d{2})\s*[A-Z]?$',
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
    'confidence_thresholds': {
      'high': 0.85,
      'medium': 0.65,
      'low': 0.45,
    },
  };

  static void setUp() {
    testConfigPath = '${Directory.systemTemp.path}/test_fuzzy_config_${DateTime.now().millisecondsSinceEpoch}.json';
    
    File(testConfigPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(defaultConfig),
    );
    
    matcher = AdaptiveFuzzyMatcher(testConfigPath);
  }

  static void tearDown() {
    final file = File(testConfigPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
