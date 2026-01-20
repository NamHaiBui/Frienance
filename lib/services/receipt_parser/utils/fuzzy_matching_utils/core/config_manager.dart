import 'dart:convert';
import 'dart:io';

import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/base_configs.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/store_presets.dart';

/// Callback type for config change notifications.
typedef ConfigChangeCallback = void Function();

/// Manages loading, saving, and manipulation of the fuzzy matcher config.
class ConfigManager {
  final String configPath;
  late Map<String, dynamic> _config;
  late Map<String, dynamic> _learnedPatterns;
  
  /// Callback invoked when config changes (for instant re-rendering).
  ConfigChangeCallback? onConfigChanged;

  ConfigManager(this.configPath, {this.onConfigChanged}) {
    loadConfig();
    _loadLearnedPatterns();
  }

  /// Get the current config.
  Map<String, dynamic> get config => _config;

  /// Get the learned patterns section of the config.
  Map<String, dynamic> get learnedPatterns => _learnedPatterns;

  /// Load config from file.
  void loadConfig() {
    final file = File(configPath);
    if (file.existsSync()) {
      _config = json.decode(file.readAsStringSync());
    } else {
      _config = getDefaultConfig();
      saveConfig();
    }
  }

  void _loadLearnedPatterns() {
    _learnedPatterns = _config['learned_patterns'] as Map<String, dynamic>? ?? {};
    if (!_config.containsKey('learned_patterns')) {
      _config['learned_patterns'] = _learnedPatterns;
    }
  }

  /// Save config to file and notify listeners.
  void saveConfig() {
    final file = File(configPath);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_config),
    );
    // Notify listeners for instant re-rendering
    onConfigChanged?.call();
  }

  /// Reload config from file and refresh internal state.
  void reload() {
    loadConfig();
    _loadLearnedPatterns();
    onConfigChanged?.call();
  }

  /// Export current config as formatted JSON string.
  String exportConfig() {
    return const JsonEncoder.withIndent('  ').convert(_config);
  }

  /// Import config from JSON string.
  void importConfig(String jsonConfig) {
    _config = json.decode(jsonConfig);
    _loadLearnedPatterns();
    saveConfig();
  }

  /// Reset learned patterns to defaults.
  void resetLearnedPatterns() {
    _learnedPatterns = {
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
    };
    _config['learned_patterns'] = _learnedPatterns;
    saveConfig();
  }

  /// Get the markets map from config.
  Map<String, dynamic> get markets => 
      _config['markets'] as Map<String, dynamic>? ?? {};

  /// Get sum keys from config.
  List<String> get sumKeys => 
      (_config['sum_keys'] as List?)?.cast<String>() ?? [];

  /// Get ignore keys from config.
  List<String> get ignoreKeys => 
      (_config['ignore_keys'] as List?)?.cast<String>() ?? [];

  /// Get store categories from config.
  Map<String, dynamic>? get storeCategories => 
      _config['store_categories'] as Map<String, dynamic>?;

  /// Set store categories in config.
  set storeCategories(Map<String, dynamic>? value) {
    if (value != null) {
      _config['store_categories'] = value;
    }
  }

  /// Get extraction statistics.
  Map<String, dynamic> getStats() {
    return Map<String, dynamic>.from(
      _learnedPatterns['extraction_stats'] as Map<String, dynamic>? ?? {},
    );
  }

  /// Get learned market matches.
  Map<String, dynamic> get learnedMarketMatches =>
      _learnedPatterns['successful_market_matches'] as Map<String, dynamic>? ?? {};

  /// Get learned date patterns.
  List<String> get learnedDatePatterns =>
      (_learnedPatterns['successful_date_patterns'] as List?)?.cast<String>() ?? [];

  /// Get learned sum patterns.
  List<String> get learnedSumPatterns =>
      (_learnedPatterns['successful_sum_patterns'] as List?)?.cast<String>() ?? [];

  /// Get learned item patterns.
  List<String> get learnedItemPatterns =>
      (_learnedPatterns['successful_item_patterns'] as List?)?.cast<String>() ?? [];

  /// Update learned market matches.
  void updateLearnedMarketMatches(Map<String, dynamic> matches) {
    _learnedPatterns['successful_market_matches'] = matches;
  }

  /// Add a learned date pattern.
  void addLearnedDatePattern(String pattern) {
    final patterns = learnedDatePatterns;
    if (!patterns.contains(pattern)) {
      patterns.add(pattern);
      _learnedPatterns['successful_date_patterns'] = patterns;
    }
  }

  /// Add a learned sum pattern.
  void addLearnedSumPattern(String pattern) {
    final patterns = learnedSumPatterns;
    if (!patterns.contains(pattern)) {
      patterns.add(pattern);
      _learnedPatterns['successful_sum_patterns'] = patterns;
    }
  }

  /// Add a learned item pattern.
  void addLearnedItemPattern(String pattern) {
    final patterns = learnedItemPatterns;
    if (!patterns.contains(pattern)) {
      patterns.add(pattern);
      _learnedPatterns['successful_item_patterns'] = patterns;
    }
  }

  /// Add a user correction.
  void addUserCorrection({
    required String fieldType,
    required String originalValue,
    required String correctedValue,
    String? originalLine,
  }) {
    final corrections = (_learnedPatterns['user_corrections'] as List?) ?? [];
    
    corrections.add({
      'field_type': fieldType,
      'original_value': originalValue,
      'corrected_value': correctedValue,
      'original_line': originalLine,
      'timestamp': DateTime.now().toIso8601String(),
    });

    _learnedPatterns['user_corrections'] = corrections;
  }

  /// Get the default config structure with all store presets built-in.
  static Map<String, dynamic> getDefaultConfig() {
    // Build markets map with all presets
    final markets = <String, dynamic>{
      'default': ['store', 'market', 'shop'],
    };
    
    // Add all store presets directly to base config
    markets.addAll(Map<String, dynamic>.from(StorePresets.fastFood));
    markets.addAll(Map<String, dynamic>.from(StorePresets.casualDining));
    markets.addAll(Map<String, dynamic>.from(StorePresets.coffeeShops));
    markets.addAll(Map<String, dynamic>.from(StorePresets.grocery));

    // Build store categories from presets
    final storeCategories = <String, dynamic>{
      'fast_food': StorePresets.fastFood.keys.toList(),
      'casual_dining': StorePresets.casualDining.keys.toList(),
      'coffee_shop': StorePresets.coffeeShops.keys.toList(),
      'grocery': StorePresets.grocery.keys.toList(),
    };

    return {
      'markets': markets,
      'store_categories': storeCategories,
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
      'learned_patterns': <String, dynamic>{
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
        'high': FuzzyMatchingConfidence.high.value,
        'medium': FuzzyMatchingConfidence.medium.value,
        'low': FuzzyMatchingConfidence.low.value,
      },
    };
  }

  /// Merge new store presets into existing config (for upgrades).
  void mergeStorePresets() {
    final currentMarkets = markets;
    bool changed = false;

    for (final preset in StorePresets.allPresetsFlat.entries) {
      if (!currentMarkets.containsKey(preset.key)) {
        currentMarkets[preset.key] = preset.value;
        changed = true;
      }
    }

    if (changed) {
      saveConfig();
    }
  }
}
