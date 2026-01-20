import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/store_presets.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/string_utils.dart';

/// Manages store/restaurant CRUD operations and categorization.
class StoreManager {
  final ConfigManager configManager;

  StoreManager(this.configManager);

  /// Add a new store/restaurant with optional spelling variations.
  /// 
  /// [name] - The canonical name of the store/restaurant (e.g., "chipotle")
  /// [spellings] - Optional list of spelling variations (e.g., ["chipotle mexican grill", "chipoltle"])
  /// [category] - Optional category for the store (e.g., "restaurant", "grocery", "fast_food")
  /// 
  /// Returns true if the store was added successfully.
  bool addStore({
    required String name,
    List<String>? spellings,
    String? category,
  }) {
    final normalizedName = StringUtils.normalizeMarketName(name);
    if (normalizedName.isEmpty) return false;

    final markets = configManager.markets;
    
    // Initialize with the name itself if no spellings provided
    final variations = spellings ?? [name.toLowerCase()];
    
    if (markets.containsKey(normalizedName)) {
      // Merge with existing variations
      final existing = (markets[normalizedName] as List).cast<String>();
      for (final variation in variations) {
        final lowerVariation = variation.toLowerCase().trim();
        if (!existing.contains(lowerVariation) && lowerVariation.isNotEmpty) {
          existing.add(lowerVariation);
        }
      }
    } else {
      // Add new store
      markets[normalizedName] = variations
          .map((v) => v.toLowerCase().trim())
          .where((v) => v.isNotEmpty)
          .toList();
    }

    // Track category if provided
    if (category != null) {
      _addStoreCategory(normalizedName, category);
    }

    configManager.saveConfig();
    return true;
  }

  /// Add multiple stores/restaurants at once.
  /// 
  /// [stores] - Map of store name to spelling variations
  /// [category] - Optional category to apply to all stores
  /// 
  /// Returns the number of stores successfully added.
  int addStores(Map<String, List<String>> stores, {String? category}) {
    int added = 0;
    for (final entry in stores.entries) {
      if (addStore(name: entry.key, spellings: entry.value, category: category)) {
        added++;
      }
    }
    return added;
  }

  /// Add spelling variations to an existing store.
  /// 
  /// [name] - The canonical store name
  /// [newSpellings] - Additional spelling variations to add
  /// 
  /// Returns true if variations were added.
  bool addSpellings(String name, List<String> newSpellings) {
    final normalizedName = StringUtils.normalizeMarketName(name);
    final markets = configManager.markets;
    
    if (!markets.containsKey(normalizedName)) {
      // Store doesn't exist, create it with the new spellings
      return addStore(name: name, spellings: newSpellings);
    }

    final existing = (markets[normalizedName] as List).cast<String>();
    int addedCount = 0;
    
    for (final spelling in newSpellings) {
      final lowerSpelling = spelling.toLowerCase().trim();
      if (!existing.contains(lowerSpelling) && lowerSpelling.isNotEmpty) {
        existing.add(lowerSpelling);
        addedCount++;
      }
    }

    if (addedCount > 0) configManager.saveConfig();
    return addedCount > 0;
  }

  /// Remove a store/restaurant from the config.
  /// 
  /// [name] - The store name to remove
  /// [removeLearnedPatterns] - If true, also removes learned patterns for this store
  /// 
  /// Returns true if the store was removed.
  bool removeStore(String name, {bool removeLearnedPatterns = false}) {
    final normalizedName = StringUtils.normalizeMarketName(name);
    final markets = configManager.markets;
    
    if (!markets.containsKey(normalizedName)) return false;

    markets.remove(normalizedName);

    // Remove from categories
    final categories = configManager.storeCategories;
    if (categories != null) {
      for (final categoryList in categories.values) {
        (categoryList as List).remove(normalizedName);
      }
    }

    // Remove learned patterns if requested
    if (removeLearnedPatterns) {
      final marketMatches = configManager.learnedMarketMatches;
      marketMatches.remove(normalizedName);
    }

    configManager.saveConfig();
    return true;
  }

  /// Remove specific spellings from a store.
  /// 
  /// [name] - The store name
  /// [spellingsToRemove] - The spellings to remove
  /// 
  /// Returns the number of spellings removed.
  int removeSpellings(String name, List<String> spellingsToRemove) {
    final normalizedName = StringUtils.normalizeMarketName(name);
    final markets = configManager.markets;
    
    if (!markets.containsKey(normalizedName)) return 0;

    final existing = (markets[normalizedName] as List).cast<String>();
    int removedCount = 0;
    
    for (final spelling in spellingsToRemove) {
      if (existing.remove(spelling.toLowerCase().trim())) {
        removedCount++;
      }
    }

    if (removedCount > 0) configManager.saveConfig();
    return removedCount;
  }

  /// Get all stores/restaurants in the config.
  /// 
  /// Returns a map of normalized store names to their spelling variations.
  Map<String, List<String>> getStores() {
    final markets = configManager.markets;
    return markets.map((key, value) => MapEntry(
      key,
      (value as List).cast<String>(),
    ));
  }

  /// Get spellings for a specific store.
  /// 
  /// [name] - The store name
  /// 
  /// Returns the list of spellings or null if store not found.
  List<String>? getSpellings(String name) {
    final normalizedName = StringUtils.normalizeMarketName(name);
    final markets = configManager.markets;
    
    if (!markets.containsKey(normalizedName)) return null;
    return (markets[normalizedName] as List).cast<String>();
  }

  /// Check if a store exists in the config.
  bool hasStore(String name) {
    final normalizedName = StringUtils.normalizeMarketName(name);
    return configManager.markets.containsKey(normalizedName);
  }

  /// Search for stores matching a query.
  /// 
  /// [query] - The search query
  /// [threshold] - Minimum similarity threshold (default: 0.5)
  /// 
  /// Returns a list of matching store names with their similarity scores.
  List<MapEntry<String, double>> searchStores(String query, {double threshold = 0.5}) {
    final markets = configManager.markets;
    final matches = <MapEntry<String, double>>[];
    final lowerQuery = query.toLowerCase();

    for (final entry in markets.entries) {
      if (entry.key == 'default') continue;

      double bestSimilarity = 0.0;

      // Check against store name
      final nameSimilarity = StringUtils.calculateSimilarity(lowerQuery, entry.key);
      if (nameSimilarity > bestSimilarity) bestSimilarity = nameSimilarity;

      // Check against spellings
      for (final spelling in (entry.value as List).cast<String>()) {
        final spellingSimilarity = StringUtils.calculateSimilarity(lowerQuery, spelling);
        if (spellingSimilarity > bestSimilarity) bestSimilarity = spellingSimilarity;
      }

      if (bestSimilarity >= threshold) {
        matches.add(MapEntry(entry.key, bestSimilarity));
      }
    }

    // Sort by similarity descending
    matches.sort((a, b) => b.value.compareTo(a.value));
    return matches;
  }

  // ==========================================
  // STORE CATEGORY MANAGEMENT
  // ==========================================

  void _addStoreCategory(String normalizedName, String category) {
    var categories = configManager.storeCategories;
    if (categories == null) {
      categories = <String, dynamic>{};
      configManager.storeCategories = categories;
    }

    final normalizedCategory = StringUtils.normalizeMarketName(category);
    
    if (!categories.containsKey(normalizedCategory)) {
      categories[normalizedCategory] = <String>[];
    }

    final categoryList = (categories[normalizedCategory] as List).cast<String>();
    if (!categoryList.contains(normalizedName)) {
      categoryList.add(normalizedName);
    }
  }

  /// Add a store to a category.
  bool addStoreToCategory(String storeName, String category) {
    final normalizedStore = StringUtils.normalizeMarketName(storeName);
    final markets = configManager.markets;
    
    if (!markets.containsKey(normalizedStore)) return false;

    _addStoreCategory(normalizedStore, category);
    configManager.saveConfig();
    return true;
  }

  /// Remove a store from a category.
  bool removeStoreFromCategory(String storeName, String category) {
    final normalizedStore = StringUtils.normalizeMarketName(storeName);
    final normalizedCategory = StringUtils.normalizeMarketName(category);
    
    final categories = configManager.storeCategories;
    if (categories == null || !categories.containsKey(normalizedCategory)) {
      return false;
    }

    final categoryList = (categories[normalizedCategory] as List).cast<String>();
    final removed = categoryList.remove(normalizedStore);
    
    if (removed) configManager.saveConfig();
    return removed;
  }

  /// Get all stores in a specific category.
  List<String> getStoresInCategory(String category) {
    final normalizedCategory = StringUtils.normalizeMarketName(category);
    final categories = configManager.storeCategories;
    
    if (categories == null || !categories.containsKey(normalizedCategory)) {
      return [];
    }

    return (categories[normalizedCategory] as List).cast<String>();
  }

  /// Get all categories.
  List<String> getCategories() {
    final categories = configManager.storeCategories;
    return categories?.keys.toList() ?? [];
  }

  /// Get the category of a store.
  String? getStoreCategory(String storeName) {
    final normalizedStore = StringUtils.normalizeMarketName(storeName);
    final categories = configManager.storeCategories;
    
    if (categories == null) return null;

    for (final entry in categories.entries) {
      final stores = (entry.value as List).cast<String>();
      if (stores.contains(normalizedStore)) {
        return entry.key;
      }
    }
    return null;
  }

  // ==========================================
  // BULK RESTAURANT PRESETS
  // ==========================================

  /// Add common fast food restaurants with their spelling variations.
  int addFastFoodRestaurants() {
    return addStores(StorePresets.fastFood, category: 'fast_food');
  }

  /// Add common casual dining restaurants with their spelling variations.
  int addCasualDiningRestaurants() {
    return addStores(StorePresets.casualDining, category: 'casual_dining');
  }

  /// Add common coffee shops with their spelling variations.
  int addCoffeeShops() {
    return addStores(StorePresets.coffeeShops, category: 'coffee_shop');
  }

  /// Add common grocery stores with their spelling variations.
  int addGroceryStores() {
    return addStores(StorePresets.grocery, category: 'grocery');
  }

  /// Add all preset stores (fast food, casual dining, coffee shops, grocery).
  int addAllPresets() {
    int total = 0;
    total += addFastFoodRestaurants();
    total += addCasualDiningRestaurants();
    total += addCoffeeShops();
    total += addGroceryStores();
    return total;
  }
}
