import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/string_utils.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/extractors/date_extractor.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/extractors/items_extractor.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/extractors/market_extractor.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/extractors/sum_extractor.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/learning/pattern_learner.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/extraction_results.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/match_result.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/store/store_manager.dart';

/// Self-improving fuzzy matching algorithm for receipt parsing.
/// 
/// Learns from user confirmations and persists patterns to config.json.
/// Uses composition with specialized modules for extraction, learning, and store management.
/// 
/// ## Architecture
/// 
/// - **ConfigManager**: Handles config loading, saving, and access
/// - **MarketExtractor**: Extracts store/restaurant names
/// - **DateExtractor**: Extracts dates using multiple pattern strategies
/// - **SumExtractor**: Extracts total amounts
/// - **ItemsExtractor**: Extracts line items with prices
/// - **PatternLearner**: Handles pattern learning from confirmations
/// - **StoreManager**: CRUD operations for stores/restaurants
/// 
/// ```
class AdaptiveFuzzyMatcher {
  final String configPath;
  
  /// Callback invoked when the matcher learns something new.
  /// Use this to trigger UI re-renders or state updates.
  ConfigChangeCallback? onLearned;
  
  // Core components
  late ConfigManager _configManager;
  
  // Extractors
  late MarketExtractor _marketExtractor;
  late DateExtractor _dateExtractor;
  late SumExtractor _sumExtractor;
  late ItemsExtractor _itemsExtractor;
  
  // Learning and store management
  late PatternLearner _patternLearner;
  late StoreManager _storeManager;

  AdaptiveFuzzyMatcher(this.configPath, {this.onLearned}) {
    _initializeComponents();
  }

  void _initializeComponents() {
    _configManager = ConfigManager(configPath, onConfigChanged: _onConfigChanged);
    _marketExtractor = MarketExtractor(_configManager);
    _dateExtractor = DateExtractor(_configManager);
    _sumExtractor = SumExtractor(_configManager);
    _itemsExtractor = ItemsExtractor(_configManager);
    _patternLearner = PatternLearner(_configManager);
    _storeManager = StoreManager(_configManager);
  }

  void _onConfigChanged() {
    // Notify external listeners (e.g., UI) for instant re-rendering
    onLearned?.call();
  }

  /// Reload config and reinitialize all components.
  /// Call this to refresh the matcher with latest config changes.
  void reload() {
    _configManager.reload();
    // Recreate extractors with fresh config state
    _marketExtractor = MarketExtractor(_configManager);
    _dateExtractor = DateExtractor(_configManager);
    _sumExtractor = SumExtractor(_configManager);
    _itemsExtractor = ItemsExtractor(_configManager);
  }

  /// Merge any new store presets into existing config (useful for app upgrades).
  void upgradeStorePresets() {
    _configManager.mergeStorePresets();
  }

  // ==========================================
  // EXTRACTION METHODS
  // ==========================================

  /// Extract all receipt data with confidence scores.
  ExtractionResult extractAll(List<String> lines) {
    final normalizedLines = StringUtils.normalizeLines(lines);
    
    final marketResult = extractMarket(normalizedLines);
    final dateResult = extractDate(normalizedLines);
    final sumResult = extractSum(normalizedLines);
    final itemsResult = extractItems(normalizedLines);

    _patternLearner.updateExtractionStats(marketResult, dateResult, sumResult, itemsResult);

    return ExtractionResult(
      market: marketResult,
      date: dateResult,
      sum: sumResult,
      items: itemsResult,
      rawLines: lines,
    );
  }

  /// Extract market/store name with confidence.
  MatchResult extractMarket(List<String> lines) => _marketExtractor.extract(lines);

  /// Extract date with multiple pattern attempts.
  MatchResult extractDate(List<String> lines) => _dateExtractor.extract(lines);

  /// Extract total sum with multiple pattern attempts.
  MatchResult extractSum(List<String> lines) => _sumExtractor.extract(lines);

  /// Extract line items with prices.
  ItemsResult extractItems(List<String> lines) => _itemsExtractor.extract(lines);

  // ==========================================
  // LEARNING METHODS
  // ==========================================

  /// Confirm extraction and learn from it.
  void confirmExtraction(ExtractionResult result, {
    String? confirmedMarket,
    String? confirmedDate,
    String? confirmedSum,
    List<ItemMatch>? confirmedItems,
  }) {
    _patternLearner.confirmExtraction(
      result,
      confirmedMarket: confirmedMarket,
      confirmedDate: confirmedDate,
      confirmedSum: confirmedSum,
      confirmedItems: confirmedItems,
    );
  }

  /// Record a user correction for future learning.
  void recordCorrection({
    required String fieldType,
    required String originalValue,
    required String correctedValue,
    String? originalLine,
  }) {
    _patternLearner.recordCorrection(
      fieldType: fieldType,
      originalValue: originalValue,
      correctedValue: correctedValue,
      originalLine: originalLine,
    );
  }

  // ==========================================
  // STORE & RESTAURANT MANAGEMENT
  // ==========================================

  /// Add a new store/restaurant with optional spelling variations.
  bool addStore({
    required String name,
    List<String>? spellings,
    String? category,
  }) => _storeManager.addStore(name: name, spellings: spellings, category: category);

  /// Add multiple stores/restaurants at once.
  int addStores(Map<String, List<String>> stores, {String? category}) =>
      _storeManager.addStores(stores, category: category);

  /// Add spelling variations to an existing store.
  bool addSpellings(String name, List<String> newSpellings) =>
      _storeManager.addSpellings(name, newSpellings);

  /// Remove a store/restaurant from the config.
  bool removeStore(String name, {bool removeLearnedPatterns = false}) =>
      _storeManager.removeStore(name, removeLearnedPatterns: removeLearnedPatterns);

  /// Remove specific spellings from a store.
  int removeSpellings(String name, List<String> spellingsToRemove) =>
      _storeManager.removeSpellings(name, spellingsToRemove);

  /// Get all stores/restaurants in the config.
  Map<String, List<String>> getStores() => _storeManager.getStores();

  /// Get spellings for a specific store.
  List<String>? getSpellings(String name) => _storeManager.getSpellings(name);

  /// Check if a store exists in the config.
  bool hasStore(String name) => _storeManager.hasStore(name);

  /// Search for stores matching a query.
  List<MapEntry<String, double>> searchStores(String query, {double threshold = 0.5}) =>
      _storeManager.searchStores(query, threshold: threshold);

  // ==========================================
  // STORE CATEGORY MANAGEMENT
  // ==========================================

  /// Add a store to a category.
  bool addStoreToCategory(String storeName, String category) =>
      _storeManager.addStoreToCategory(storeName, category);

  /// Remove a store from a category.
  bool removeStoreFromCategory(String storeName, String category) =>
      _storeManager.removeStoreFromCategory(storeName, category);

  /// Get all stores in a specific category.
  List<String> getStoresInCategory(String category) =>
      _storeManager.getStoresInCategory(category);

  /// Get all categories.
  List<String> getCategories() => _storeManager.getCategories();

  /// Get the category of a store.
  String? getStoreCategory(String storeName) => _storeManager.getStoreCategory(storeName);

  // ==========================================
  // PRESET MANAGEMENT
  // ==========================================

  /// Add common fast food restaurants with their spelling variations.
  int addFastFoodRestaurants() => _storeManager.addFastFoodRestaurants();

  /// Add common casual dining restaurants with their spelling variations.
  int addCasualDiningRestaurants() => _storeManager.addCasualDiningRestaurants();

  /// Add common coffee shops with their spelling variations.
  int addCoffeeShops() => _storeManager.addCoffeeShops();

  /// Add common grocery stores with their spelling variations.
  int addGroceryStores() => _storeManager.addGroceryStores();

  /// Add all preset stores (fast food, casual dining, coffee shops, grocery).
  int addAllPresets() => _storeManager.addAllPresets();

  // ==========================================
  // CONFIG & STATS MANAGEMENT
  // ==========================================

  /// Get extraction statistics.
  Map<String, dynamic> getStats() => _configManager.getStats();

  /// Reset learned patterns (for testing).
  void resetLearnedPatterns() => _configManager.resetLearnedPatterns();

  /// Export current config.
  String exportConfig() => _configManager.exportConfig();

  /// Import config.
  void importConfig(String jsonConfig) => _configManager.importConfig(jsonConfig);

  // ==========================================
  // INTERNAL ACCESSORS (for testing)
  // ==========================================

  /// Access to the config manager (for testing).
  ConfigManager get configManager => _configManager;

  /// Access to the store manager (for testing).
  StoreManager get storeManager => _storeManager;

  /// Access to the pattern learner (for testing).
  PatternLearner get patternLearner => _patternLearner;
}
