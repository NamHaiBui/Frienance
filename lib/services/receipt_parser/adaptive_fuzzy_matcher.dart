import 'dart:io';

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
import 'package:frienance/src/core/feature/feature.dart';
import 'package:frienance/src/core/feature/health_monitoring.dart';

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
/// ## Feature Integration
///
/// This class extends [Feature] for production-ready capabilities:
/// - Lifecycle management (initialize, warmup, dispose)
/// - Retry logic with exponential backoff
/// - Circuit breaker for fault tolerance
/// - Health checks and metrics collection
/// - Log buffering for diagnostics
///
/// ## Riverpod Integration
///
/// Use the providers in `adaptive_fuzzy_matcher_provider.dart` for state management:
/// - `adaptiveFuzzyMatcherProvider`: Main provider with async lifecycle
/// - `extractionResultProvider`: For extraction operations
/// - `storesProvider`, `categoriesProvider`: For store data
/// - `matcherHealthCheckProvider`: For health monitoring
///
/// ```dart
/// // Example usage with Riverpod
/// final matcher = ref.watch(adaptiveFuzzyMatcherProvider);
/// matcher.when(
///   data: (m) => m.extractAll(lines),
///   loading: () => showLoading(),
///   error: (e, st) => showError(e),
/// );
/// ```
class AdaptiveFuzzyMatcher extends Feature with FileSystemFeature {
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

  /// Whether components have been initialized.
  bool _componentsInitialized = false;

  AdaptiveFuzzyMatcher(
    this.configPath, {
    this.onLearned,
    super.config,
  }):super(name: 'FuzzyMatcher');

  // ============================================================
  // FEATURE LIFECYCLE IMPLEMENTATION
  // ============================================================

  @override
  Future<void> onInitialize() async {
    logInfo('Initializing AdaptiveFuzzyMatcher with config: $configPath');

    // Ensure config directory exists
    final configFile = File(configPath);
    final configDir = configFile.parent;
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
      logDebug('Created config directory: ${configDir.path}');
    }

    // Set base directory for FileSystemFeature mixin
    setBaseDirectory(configDir.path);

    // Initialize components
    _initializeComponents();
    _componentsInitialized = true;

    logInfo('Components initialized successfully');
  }

  @override
  Future<void> onWarmUp() async {
    logInfo('Warming up AdaptiveFuzzyMatcher');

    // Pre-load config into memory
    _configManager.reload();

    // Pre-compile regex patterns by doing a dummy extraction
    // This warms up the pattern caches in extractors
    final warmupLines = ['Store Name', '01/01/2024', 'Total: \$10.00'];
    extractAll(warmupLines);

    logInfo('Warm-up complete');
  }

  @override
  Future<HealthCheckResult> performHealthCheck() async {
    final issues = <String>[];

    // Check if components are initialized
    if (!_componentsInitialized) {
      return HealthCheckResult(
        featureName: name,
        status: HealthStatus.unhealthy,
        message: 'Components not initialized',
      );
    }

    // Check config file accessibility
    final configFile = File(configPath);
    if (!await configFile.exists()) {
      issues.add('Config file does not exist');
    }

    // Check markets configuration
    final markets = _configManager.markets;
    if (markets.isEmpty) {
      issues.add('No markets configured');
    }

    // Check learned patterns
    final stats =
        _configManager.config['learned_patterns']?['extraction_stats'];
    final totalExtractions = stats?['total_extractions'] ?? 0;

    // Determine health status
    HealthStatus status;
    String message;

    if (issues.isEmpty) {
      status = HealthStatus.healthy;
      message = 'Matcher is fully operational';
    } else if (issues.length == 1 && issues.first == 'No markets configured') {
      status = HealthStatus.degraded;
      message = 'Matcher operational but no markets configured';
    } else {
      status = HealthStatus.unhealthy;
      message = 'Issues detected: ${issues.join(', ')}';
    }

    return HealthCheckResult(
      featureName: name,
      status: status,
      message: message,
      details: {
        'configPath': configPath,
        'marketsCount': markets.length,
        'totalExtractions': totalExtractions,
        'issues': issues,
      },
    );
  }

  @override
  Future<void> onDispose() async {
    logInfo('Disposing AdaptiveFuzzyMatcher');

    // Save any pending config changes
    if (_componentsInitialized) {
      _configManager.saveConfig();
    }

    _componentsInitialized = false;
    logInfo('Disposed successfully');
  }

  // ============================================================
  // PRIVATE COMPONENT INITIALIZATION
  // ============================================================

  void _initializeComponents() {
    _configManager =
        ConfigManager(configPath, onConfigChanged: _onConfigChanged);
    _marketExtractor = MarketExtractor(_configManager);
    _dateExtractor = DateExtractor(_configManager);
    _sumExtractor = SumExtractor(_configManager);
    _itemsExtractor = ItemsExtractor(_configManager);
    _patternLearner = PatternLearner(_configManager);
    _storeManager = StoreManager(_configManager);
  }

  void _onConfigChanged() {
    // Log the config change
    logDebug('Config changed, notifying listeners');
    // Notify external listeners (e.g., UI) for instant re-rendering
    onLearned?.call();
  }

  void _ensureInitialized() {
    if (!_componentsInitialized) {
      throw StateError(
        'AdaptiveFuzzyMatcher is not initialized. '
        'Call initialize() first or use the Riverpod provider.',
      );
    }
  }

  // ============================================================
  // PUBLIC API
  // ============================================================

  /// Reload config and reinitialize all components.
  /// Call this to refresh the matcher with latest config changes.
  void reload() {
    _ensureInitialized();
    logInfo('Reloading config');
    _configManager.reload();
    // Recreate extractors with fresh config state
    _marketExtractor = MarketExtractor(_configManager);
    _dateExtractor = DateExtractor(_configManager);
    _sumExtractor = SumExtractor(_configManager);
    _itemsExtractor = ItemsExtractor(_configManager);
    logInfo('Config reloaded');
  }

  /// Merge any new store presets into existing config (useful for app upgrades).
  void upgradeStorePresets() {
    _ensureInitialized();
    logInfo('Upgrading store presets');
    _configManager.mergeStorePresets();
  }

  // ==========================================
  // EXTRACTION METHODS
  // ==========================================

  /// Extract all receipt data with confidence scores.
  ExtractionResult extractAll(List<String> lines) {
    _ensureInitialized();
    final normalizedLines = StringUtils.normalizeLines(lines);

    final marketResult = extractMarket(normalizedLines);
    final dateResult = extractDate(normalizedLines);
    final sumResult = extractSum(normalizedLines);
    final itemsResult = extractItems(normalizedLines);

    _patternLearner.updateExtractionStats(
        marketResult, dateResult, sumResult, itemsResult);

    return ExtractionResult(
      market: marketResult,
      date: dateResult,
      sum: sumResult,
      items: itemsResult,
      rawLines: lines,
    );
  }

  /// Extract market/store name with confidence.
  MatchResult extractMarket(List<String> lines) {
    _ensureInitialized();
    return _marketExtractor.extract(lines);
  }

  /// Extract date with multiple pattern attempts.
  MatchResult extractDate(List<String> lines) {
    _ensureInitialized();
    return _dateExtractor.extract(lines);
  }

  /// Extract total sum with multiple pattern attempts.
  MatchResult extractSum(List<String> lines) {
    _ensureInitialized();
    return _sumExtractor.extract(lines);
  }

  /// Extract line items with prices.
  ItemsResult extractItems(List<String> lines) {
    _ensureInitialized();
    return _itemsExtractor.extract(lines);
  }

  // ==========================================
  // LEARNING METHODS
  // ==========================================

  /// Confirm extraction and learn from it.
  void confirmExtraction(
    ExtractionResult result, {
    String? confirmedMarket,
    String? confirmedDate,
    String? confirmedSum,
    List<ItemMatch>? confirmedItems,
  }) {
    _ensureInitialized();
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
    _ensureInitialized();
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
  }) {
    _ensureInitialized();
    return _storeManager.addStore(
        name: name, spellings: spellings, category: category);
  }

  /// Add multiple stores/restaurants at once.
  int addStores(Map<String, List<String>> stores, {String? category}) {
    _ensureInitialized();
    return _storeManager.addStores(stores, category: category);
  }

  /// Add spelling variations to an existing store.
  bool addSpellings(String name, List<String> newSpellings) {
    _ensureInitialized();
    return _storeManager.addSpellings(name, newSpellings);
  }

  /// Remove a store/restaurant from the config.
  bool removeStore(String name, {bool removeLearnedPatterns = false}) {
    _ensureInitialized();
    return _storeManager.removeStore(name,
        removeLearnedPatterns: removeLearnedPatterns);
  }

  /// Remove specific spellings from a store.
  int removeSpellings(String name, List<String> spellingsToRemove) {
    _ensureInitialized();
    return _storeManager.removeSpellings(name, spellingsToRemove);
  }

  /// Get all stores/restaurants in the config.
  Map<String, List<String>> getStores() {
    _ensureInitialized();
    return _storeManager.getStores();
  }

  /// Get spellings for a specific store.
  List<String>? getSpellings(String name) {
    _ensureInitialized();
    return _storeManager.getSpellings(name);
  }

  /// Check if a store exists in the config.
  bool hasStore(String name) {
    _ensureInitialized();
    return _storeManager.hasStore(name);
  }

  /// Search for stores matching a query.
  List<MapEntry<String, double>> searchStores(String query,
      {double threshold = 0.5}) {
    _ensureInitialized();
    return _storeManager.searchStores(query, threshold: threshold);
  }

  // ==========================================
  // STORE CATEGORY MANAGEMENT
  // ==========================================

  /// Add a store to a category.
  bool addStoreToCategory(String storeName, String category) {
    _ensureInitialized();
    return _storeManager.addStoreToCategory(storeName, category);
  }

  /// Remove a store from a category.
  bool removeStoreFromCategory(String storeName, String category) {
    _ensureInitialized();
    return _storeManager.removeStoreFromCategory(storeName, category);
  }

  /// Get all stores in a specific category.
  List<String> getStoresInCategory(String category) {
    _ensureInitialized();
    return _storeManager.getStoresInCategory(category);
  }

  /// Get all categories.
  List<String> getCategories() {
    _ensureInitialized();
    return _storeManager.getCategories();
  }

  /// Get the category of a store.
  String? getStoreCategory(String storeName) {
    _ensureInitialized();
    return _storeManager.getStoreCategory(storeName);
  }

  // ==========================================
  // PRESET MANAGEMENT
  // ==========================================

  /// Add common fast food restaurants with their spelling variations.
  int addFastFoodRestaurants() {
    _ensureInitialized();
    return _storeManager.addFastFoodRestaurants();
  }

  /// Add common casual dining restaurants with their spelling variations.
  int addCasualDiningRestaurants() {
    _ensureInitialized();
    return _storeManager.addCasualDiningRestaurants();
  }

  /// Add common coffee shops with their spelling variations.
  int addCoffeeShops() {
    _ensureInitialized();
    return _storeManager.addCoffeeShops();
  }

  /// Add common grocery stores with their spelling variations.
  int addGroceryStores() {
    _ensureInitialized();
    return _storeManager.addGroceryStores();
  }

  /// Add all preset stores (fast food, casual dining, coffee shops, grocery).
  int addAllPresets() {
    _ensureInitialized();
    return _storeManager.addAllPresets();
  }

  // ==========================================
  // CONFIG & STATS MANAGEMENT
  // ==========================================

  /// Get extraction statistics.
  Map<String, dynamic> getStats() {
    _ensureInitialized();
    return _configManager.getStats();
  }

  /// Reset learned patterns (for testing).
  void resetLearnedPatterns() {
    _ensureInitialized();
    _configManager.resetLearnedPatterns();
  }

  /// Export current config.
  String exportConfig() {
    _ensureInitialized();
    return _configManager.exportConfig();
  }

  /// Import config.
  void importConfig(String jsonConfig) {
    _ensureInitialized();
    _configManager.importConfig(jsonConfig);
  }

  // ==========================================
  // INTERNAL ACCESSORS (for testing)
  // ==========================================

  /// Access to the config manager (for testing).
  ConfigManager get configManager {
    _ensureInitialized();
    return _configManager;
  }

  /// Access to the store manager (for testing).
  StoreManager get storeManager {
    _ensureInitialized();
    return _storeManager;
  }

  /// Access to the pattern learner (for testing).
  PatternLearner get patternLearner {
    _ensureInitialized();
    return _patternLearner;
  }

  /// Whether components have been initialized.
  bool get componentsInitialized => _componentsInitialized;
}
