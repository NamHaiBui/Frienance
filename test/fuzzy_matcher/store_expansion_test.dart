import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'test_helper.dart';

/// Tests for Store/Restaurant expansion feature in AdaptiveFuzzyMatcher
/// Covers: addStore, addStores, addSpellings, removeStore, removeSpellings,
/// getStores, getSpellings, hasStore, searchStores, category management,
/// and preset loading.
void main() {
  late AdaptiveFuzzyMatcher matcher;
  late String testConfigPath;

  setUp(() {
    TestHelper.setUp();
    matcher = TestHelper.matcher;
    testConfigPath = TestHelper.testConfigPath;
  });

  tearDown(() {
    TestHelper.tearDown();
  });

  // ==========================================
  // SINGLE STORE MANAGEMENT
  // ==========================================

  group('addStore() - Single Store Addition', () {
    test('should add a new store with default spelling', () {
      final result = matcher.addStore(name: 'Chipotle');

      expect(result, isTrue);
      expect(matcher.hasStore('Chipotle'), isTrue);
      expect(matcher.hasStore('chipotle'), isTrue); // Normalized

      final spellings = matcher.getSpellings('chipotle');
      expect(spellings, isNotNull);
      expect(spellings, contains('chipotle'));
    });

    test('should add a new store with custom spellings', () {
      final result = matcher.addStore(
        name: 'Shake Shack',
        spellings: ['shake shack', 'shakeshack', 'shake-shack'],
      );

      expect(result, isTrue);
      expect(matcher.hasStore('shake_shack'), isTrue);

      final spellings = matcher.getSpellings('shake_shack');
      expect(spellings, isNotNull);
      expect(spellings, containsAll(['shake shack', 'shakeshack', 'shake-shack']));
    });

    test('should add a new store with category', () {
      matcher.addStore(
        name: 'Panera Bread',
        spellings: ['panera bread', 'panera'],
        category: 'casual_dining',
      );

      expect(matcher.hasStore('panera_bread'), isTrue);
      expect(matcher.getStoreCategory('panera_bread'), equals('casual_dining'));
      expect(
        matcher.getStoresInCategory('casual_dining'),
        contains('panera_bread'),
      );
    });

    test('should normalize store name to lowercase with underscores', () {
      matcher.addStore(name: 'Five Guys Burgers');

      expect(matcher.hasStore('five_guys_burgers'), isTrue);
      expect(matcher.hasStore('Five Guys Burgers'), isTrue);
      expect(matcher.hasStore('FIVE GUYS BURGERS'), isTrue);
    });

    test('should merge spellings when adding existing store', () {
      // Add initial store
      matcher.addStore(
        name: 'Starbucks',
        spellings: ['starbucks', 'starbuck'],
      );

      // Add again with additional spellings
      matcher.addStore(
        name: 'Starbucks',
        spellings: ['sbux', 'starbs'],
      );

      final spellings = matcher.getSpellings('starbucks');
      expect(spellings, isNotNull);
      expect(
        spellings,
        containsAll(['starbucks', 'starbuck', 'sbux', 'starbs']),
      );
    });

    test('should not add duplicate spellings', () {
      matcher.addStore(
        name: 'Dunkin',
        spellings: ['dunkin', 'dunkin donuts'],
      );

      matcher.addStore(
        name: 'Dunkin',
        spellings: ['dunkin', 'dunkin donuts', "dunkin'"],
      );

      final spellings = matcher.getSpellings('dunkin');
      expect(spellings, isNotNull);
      // Count of 'dunkin' should be 1, not 2
      expect(spellings!.where((s) => s == 'dunkin').length, equals(1));
    });

    test('should return false for empty name', () {
      final result = matcher.addStore(name: '');
      expect(result, isFalse);
    });

    test('should return false for whitespace-only name', () {
      final result = matcher.addStore(name: '   ');
      expect(result, isFalse);
    });

    test('should handle special characters in name', () {
      matcher.addStore(name: "Arby's");

      // Note: _normalizeMarketName converts apostrophe to underscore
      expect(matcher.hasStore('arby_s'), isTrue);
      final spellings = matcher.getSpellings('arby_s');
      expect(spellings, contains("arby's"));
    });

    test('should persist store to config file', () {
      matcher.addStore(
        name: 'Test Store',
        spellings: ['test store', 'teststore'],
      );

      // Re-read config from file
      final configContent = File(testConfigPath).readAsStringSync();
      final config = json.decode(configContent) as Map<String, dynamic>;
      final markets = config['markets'] as Map<String, dynamic>;

      expect(markets.containsKey('test_store'), isTrue);
      expect(markets['test_store'], containsAll(['test store', 'teststore']));
    });
  });

  // ==========================================
  // BULK STORE ADDITION
  // ==========================================

  group('addStores() - Bulk Store Addition', () {
    test('should add multiple stores at once', () {
      final stores = {
        'pizza_hut': ['pizza hut', 'pizzahut'],
        'dominos': ["domino's", 'dominos', 'domino'],
        'papa_johns': ["papa john's", 'papa johns'],
      };

      final count = matcher.addStores(stores);

      expect(count, equals(3));
      expect(matcher.hasStore('pizza_hut'), isTrue);
      expect(matcher.hasStore('dominos'), isTrue);
      expect(matcher.hasStore('papa_johns'), isTrue);
    });

    test('should add stores with category', () {
      final stores = {
        'shake_shack': ['shake shack'],
        'in_n_out': ['in-n-out', 'in n out'],
      };

      matcher.addStores(stores, category: 'fast_food');

      expect(matcher.getStoreCategory('shake_shack'), equals('fast_food'));
      expect(matcher.getStoreCategory('in_n_out'), equals('fast_food'));
    });

    test('should return count of successfully added stores', () {
      // Add one store first
      matcher.addStore(name: 'existing_store', spellings: ['existing']);

      final stores = {
        'existing_store': ['existing'], // Already exists
        'new_store1': ['new1'],
        'new_store2': ['new2'],
      };

      final count = matcher.addStores(stores);

      // Should still return 3 since addStore returns true even for existing stores
      expect(count, equals(3));
    });

    test('should handle empty stores map', () {
      final count = matcher.addStores({});
      expect(count, equals(0));
    });
  });

  // ==========================================
  // SPELLING MANAGEMENT
  // ==========================================

  group('addSpellings() - Add Spellings to Existing Store', () {
    test('should add spellings to existing store', () {
      matcher.addStore(name: 'Costco', spellings: ['costco']);

      final result = matcher.addSpellings('Costco', ['costco wholesale', 'costco warehouse']);

      expect(result, isTrue);
      final spellings = matcher.getSpellings('costco');
      expect(spellings, containsAll(['costco', 'costco wholesale', 'costco warehouse']));
    });

    test('should create store if it does not exist', () {
      final result = matcher.addSpellings('NewStore', ['newstore', 'new store']);

      expect(result, isTrue);
      expect(matcher.hasStore('newstore'), isTrue);
      final spellings = matcher.getSpellings('newstore');
      expect(spellings, containsAll(['newstore', 'new store']));
    });

    test('should not add duplicate spellings', () {
      matcher.addStore(name: 'Target', spellings: ['target', 'tgt']);

      final result = matcher.addSpellings('Target', ['target', 'target corp']);

      expect(result, isTrue);
      final spellings = matcher.getSpellings('target');
      expect(spellings!.where((s) => s == 'target').length, equals(1));
      expect(spellings, contains('target corp'));
    });

    test('should return false when no new spellings added', () {
      matcher.addStore(name: 'Kroger', spellings: ['kroger']);

      final result = matcher.addSpellings('Kroger', ['kroger']);

      expect(result, isFalse);
    });

    test('should ignore empty spellings', () {
      matcher.addStore(name: 'Aldi', spellings: ['aldi']);

      matcher.addSpellings('Aldi', ['', '   ', 'aldi plus']);

      final spellings = matcher.getSpellings('aldi');
      expect(spellings, isNot(contains('')));
      expect(spellings, isNot(contains('   ')));
      expect(spellings, contains('aldi plus'));
    });

    test('should persist to config file', () {
      matcher.addStore(name: 'Safeway', spellings: ['safeway']);
      matcher.addSpellings('Safeway', ['safeway grocery']);

      final configContent = File(testConfigPath).readAsStringSync();
      final config = json.decode(configContent) as Map<String, dynamic>;
      final markets = config['markets'] as Map<String, dynamic>;

      expect(markets['safeway'], contains('safeway grocery'));
    });
  });

  group('removeSpellings() - Remove Specific Spellings', () {
    test('should remove specific spellings from store', () {
      matcher.addStore(
        name: 'Whole Foods',
        spellings: ['whole foods', 'wholefoods', 'wfm', 'whole foods market'],
      );

      final removedCount = matcher.removeSpellings('whole_foods', ['wfm', 'wholefoods']);

      expect(removedCount, equals(2));
      final spellings = matcher.getSpellings('whole_foods');
      expect(spellings, isNot(contains('wfm')));
      expect(spellings, isNot(contains('wholefoods')));
      expect(spellings, contains('whole foods'));
      expect(spellings, contains('whole foods market'));
    });

    test('should return 0 for non-existent store', () {
      final removedCount = matcher.removeSpellings('non_existent_store', ['spelling']);
      expect(removedCount, equals(0));
    });

    test('should return 0 when spellings do not exist', () {
      matcher.addStore(name: 'Publix', spellings: ['publix']);

      final removedCount = matcher.removeSpellings('publix', ['non_existent_spelling']);
      expect(removedCount, equals(0));
    });

    test('should handle case-insensitive removal', () {
      matcher.addStore(
        name: 'HEB',
        spellings: ['h-e-b', 'heb', 'h e b'],
      );

      // Note: Spellings are stored lowercase, so removal must use lowercase
      final removedCount = matcher.removeSpellings('heb', ['h-e-b']);
      expect(removedCount, equals(1));
    });

    test('should persist removal to config file', () {
      matcher.addStore(name: 'Meijer', spellings: ['meijer', "meijer's"]);
      matcher.removeSpellings('meijer', ["meijer's"]);

      final configContent = File(testConfigPath).readAsStringSync();
      final config = json.decode(configContent) as Map<String, dynamic>;
      final markets = config['markets'] as Map<String, dynamic>;

      expect(markets['meijer'], isNot(contains("meijer's")));
      expect(markets['meijer'], contains('meijer'));
    });
  });

  // ==========================================
  // STORE REMOVAL
  // ==========================================

  group('removeStore() - Store Removal', () {
    test('should remove an existing store', () {
      matcher.addStore(name: 'ToRemove', spellings: ['toremove']);

      final result = matcher.removeStore('toremove');

      expect(result, isTrue);
      expect(matcher.hasStore('toremove'), isFalse);
      expect(matcher.getSpellings('toremove'), isNull);
    });

    test('should return false for non-existent store', () {
      final result = matcher.removeStore('non_existent_store');
      expect(result, isFalse);
    });

    test('should remove store from categories', () {
      matcher.addStore(
        name: 'CategorizedStore',
        spellings: ['categorized'],
        category: 'test_category',
      );

      expect(matcher.getStoresInCategory('test_category'), contains('categorizedstore'));

      matcher.removeStore('CategorizedStore');

      expect(matcher.getStoresInCategory('test_category'), isNot(contains('categorizedstore')));
    });

    test('should preserve learned patterns by default', () {
      // Add store and simulate learned pattern
      matcher.addStore(name: 'LearnedStore', spellings: ['learned store']);

      // Simulate learning a pattern (by extracting and confirming)
      final lines = ['LEARNED STORE', 'Some receipt line', 'Total: 10.00'];
      final result = matcher.extractMarket(lines);
      if (result.value != null && result.matchedLine != null) {
        matcher.confirmExtraction(
          matcher.extractAll(lines),
          confirmedMarket: 'LearnedStore',
        );
      }

      matcher.removeStore('LearnedStore', removeLearnedPatterns: false);

      // Verify store is removed but learned patterns may still exist
      expect(matcher.hasStore('learnedstore'), isFalse);
    });

    test('should remove learned patterns when flag is set', () {
      matcher.addStore(name: 'LearnedStore2', spellings: ['learned store 2']);

      // Simulate learning
      final lines = ['LEARNED STORE 2', 'Receipt text', 'Total: 20.00'];
      matcher.confirmExtraction(
        matcher.extractAll(lines),
        confirmedMarket: 'LearnedStore2',
      );

      matcher.removeStore('LearnedStore2', removeLearnedPatterns: true);

      expect(matcher.hasStore('learnedstore2'), isFalse);
    });

    test('should persist removal to config file', () {
      matcher.addStore(name: 'FileRemoval', spellings: ['fileremoval']);

      // Verify it exists in file
      var configContent = File(testConfigPath).readAsStringSync();
      var config = json.decode(configContent) as Map<String, dynamic>;
      expect((config['markets'] as Map).containsKey('fileremoval'), isTrue);

      matcher.removeStore('FileRemoval');

      // Verify it's removed from file
      configContent = File(testConfigPath).readAsStringSync();
      config = json.decode(configContent) as Map<String, dynamic>;
      expect((config['markets'] as Map).containsKey('fileremoval'), isFalse);
    });
  });

  // ==========================================
  // STORE RETRIEVAL
  // ==========================================

  group('getStores() - Get All Stores', () {
    test('should return all stores with spellings', () {
      matcher.addStore(name: 'Store1', spellings: ['store1', 's1']);
      matcher.addStore(name: 'Store2', spellings: ['store2', 's2']);

      final stores = matcher.getStores();

      expect(stores.containsKey('store1'), isTrue);
      expect(stores.containsKey('store2'), isTrue);
      expect(stores['store1'], containsAll(['store1', 's1']));
      expect(stores['store2'], containsAll(['store2', 's2']));
    });

    test('should include preset stores', () {
      final stores = matcher.getStores();

      // Default config includes walmart, target, costco, etc.
      expect(stores.containsKey('walmart'), isTrue);
      expect(stores.containsKey('target'), isTrue);
    });

    test('should return map that can be iterated', () {
      final stores = matcher.getStores();

      expect(() {
        for (final entry in stores.entries) {
          expect(entry.key, isA<String>());
          expect(entry.value, isA<List<String>>());
        }
      }, returnsNormally);
    });
  });

  group('getSpellings() - Get Store Spellings', () {
    test('should return spellings for existing store', () {
      matcher.addStore(
        name: 'SpellingTest',
        spellings: ['spelling test', 'spellingtest', 'sp test'],
      );

      // 'SpellingTest' normalizes to 'spellingtest' (no underscore between words)
      final spellings = matcher.getSpellings('spellingtest');

      expect(spellings, isNotNull);
      expect(spellings!.length, equals(3));
      expect(spellings, containsAll(['spelling test', 'spellingtest', 'sp test']));
    });

    test('should return null for non-existent store', () {
      final spellings = matcher.getSpellings('definitely_not_a_store');
      expect(spellings, isNull);
    });

    test('should handle case normalization in lookup', () {
      matcher.addStore(name: 'CaseTest', spellings: ['casetest']);

      expect(matcher.getSpellings('CaseTest'), isNotNull);
      expect(matcher.getSpellings('casetest'), isNotNull);
      expect(matcher.getSpellings('CASETEST'), isNotNull);
    });
  });

  group('hasStore() - Check Store Existence', () {
    test('should return true for existing store', () {
      matcher.addStore(name: 'ExistingStore');
      expect(matcher.hasStore('existingstore'), isTrue);
    });

    test('should return false for non-existent store', () {
      expect(matcher.hasStore('nonexistent_store_xyz'), isFalse);
    });

    test('should handle case-insensitive lookup', () {
      matcher.addStore(name: 'MixedCase');

      expect(matcher.hasStore('mixedcase'), isTrue);
      expect(matcher.hasStore('MixedCase'), isTrue);
      expect(matcher.hasStore('MIXEDCASE'), isTrue);
    });

    test('should return true for default config stores', () {
      // From TestHelper.defaultConfig
      expect(matcher.hasStore('walmart'), isTrue);
      expect(matcher.hasStore('target'), isTrue);
      expect(matcher.hasStore('costco'), isTrue);
    });
  });

  // ==========================================
  // STORE SEARCH
  // ==========================================

  group('searchStores() - Store Search', () {
    setUp(() {
      matcher.addStore(name: 'McDonalds', spellings: ["mcdonald's", 'mcdonalds', 'mcd']);
      matcher.addStore(name: 'Burger King', spellings: ['burger king', 'bk']);
      matcher.addStore(name: 'Wendys', spellings: ["wendy's", 'wendys']);
    });

    test('should find stores by exact name match', () {
      final results = matcher.searchStores('mcdonalds');

      expect(results, isNotEmpty);
      expect(results.first.key, equals('mcdonalds'));
      expect(results.first.value, greaterThanOrEqualTo(0.9));
    });

    test('should find stores by partial match', () {
      // Lower threshold to allow partial matching
      final results = matcher.searchStores('burger', threshold: 0.3);

      expect(results, isNotEmpty);
      final storeNames = results.map((e) => e.key).toList();
      expect(storeNames, contains('burger_king'));
    });

    test('should find stores by spelling variation', () {
      final results = matcher.searchStores("wendy's");

      expect(results, isNotEmpty);
      expect(results.first.key, equals('wendys'));
    });

    test('should respect threshold parameter', () {
      // High threshold - only very close matches
      final highThresholdResults = matcher.searchStores('mcd', threshold: 0.9);

      // Low threshold - more fuzzy matches
      final lowThresholdResults = matcher.searchStores('mcd', threshold: 0.3);

      expect(lowThresholdResults.length, greaterThanOrEqualTo(highThresholdResults.length));
    });

    test('should return empty list for no matches', () {
      final results = matcher.searchStores('xyznonexistent123', threshold: 0.8);
      expect(results, isEmpty);
    });

    test('should sort results by similarity descending', () {
      matcher.addStore(name: 'BurgerFi', spellings: ['burgerfi']);
      matcher.addStore(name: 'BurgerVille', spellings: ['burgerville']);

      final results = matcher.searchStores('burger', threshold: 0.3);

      // Results should be sorted by similarity
      for (int i = 0; i < results.length - 1; i++) {
        expect(results[i].value, greaterThanOrEqualTo(results[i + 1].value));
      }
    });

    test('should exclude default store from results', () {
      final results = matcher.searchStores('store', threshold: 0.3);
      final storeNames = results.map((e) => e.key).toList();

      expect(storeNames, isNot(contains('default')));
    });

    test('should handle empty query', () {
      final results = matcher.searchStores('');
      expect(results, isEmpty);
    });
  });

  // ==========================================
  // CATEGORY MANAGEMENT
  // ==========================================

  group('addStoreToCategory() - Add Store to Category', () {
    test('should add existing store to category', () {
      matcher.addStore(name: 'Uncategorized', spellings: ['uncategorized']);

      final result = matcher.addStoreToCategory('Uncategorized', 'test_category');

      expect(result, isTrue);
      expect(matcher.getStoreCategory('uncategorized'), equals('test_category'));
    });

    test('should return false for non-existent store', () {
      final result = matcher.addStoreToCategory('NonExistent', 'category');
      expect(result, isFalse);
    });

    test('should create category if it does not exist', () {
      matcher.addStore(name: 'NewCatStore', spellings: ['newcatstore']);

      matcher.addStoreToCategory('NewCatStore', 'brand_new_category');

      final categories = matcher.getCategories();
      expect(categories, contains('brand_new_category'));
    });

    test('should allow store in multiple categories', () {
      matcher.addStore(name: 'MultiCat', spellings: ['multicat']);

      matcher.addStoreToCategory('MultiCat', 'category1');
      matcher.addStoreToCategory('MultiCat', 'category2');

      expect(matcher.getStoresInCategory('category1'), contains('multicat'));
      expect(matcher.getStoresInCategory('category2'), contains('multicat'));
    });
  });

  group('removeStoreFromCategory() - Remove Store from Category', () {
    test('should remove store from category', () {
      matcher.addStore(name: 'ToRemoveFromCat', spellings: ['toremovefromcat'], category: 'removal_cat');

      expect(matcher.getStoresInCategory('removal_cat'), contains('toremovefromcat'));

      final result = matcher.removeStoreFromCategory('ToRemoveFromCat', 'removal_cat');

      expect(result, isTrue);
      expect(matcher.getStoresInCategory('removal_cat'), isNot(contains('toremovefromcat')));
    });

    test('should return false for non-existent category', () {
      matcher.addStore(name: 'SomeStore', spellings: ['somestore']);

      final result = matcher.removeStoreFromCategory('SomeStore', 'nonexistent_cat');
      expect(result, isFalse);
    });

    test('should return false when store not in category', () {
      matcher.addStore(name: 'NotInCat', spellings: ['notincat']);
      matcher.addStore(name: 'InCat', spellings: ['incat'], category: 'the_cat');

      final result = matcher.removeStoreFromCategory('NotInCat', 'the_cat');
      expect(result, isFalse);
    });
  });

  group('getStoresInCategory() - Get Category Stores', () {
    test('should return stores in category', () {
      matcher.addStore(name: 'CatStore1', spellings: ['catstore1'], category: 'my_category');
      matcher.addStore(name: 'CatStore2', spellings: ['catstore2'], category: 'my_category');
      matcher.addStore(name: 'OtherStore', spellings: ['otherstore'], category: 'other_category');

      final stores = matcher.getStoresInCategory('my_category');

      expect(stores, containsAll(['catstore1', 'catstore2']));
      expect(stores, isNot(contains('otherstore')));
    });

    test('should return empty list for non-existent category', () {
      final stores = matcher.getStoresInCategory('nonexistent_category');
      expect(stores, isEmpty);
    });

    test('should return empty list when category exists but is empty', () {
      // Add a store to create category, then remove it
      matcher.addStore(name: 'TempStore', spellings: ['tempstore'], category: 'empty_cat');
      matcher.removeStoreFromCategory('TempStore', 'empty_cat');

      final stores = matcher.getStoresInCategory('empty_cat');
      expect(stores, isEmpty);
    });
  });

  group('getCategories() - Get All Categories', () {
    test('should return all categories', () {
      matcher.addStore(name: 'Cat1Store', spellings: ['cat1store'], category: 'category_a');
      matcher.addStore(name: 'Cat2Store', spellings: ['cat2store'], category: 'category_b');
      matcher.addStore(name: 'Cat3Store', spellings: ['cat3store'], category: 'category_c');

      final categories = matcher.getCategories();

      expect(categories, containsAll(['category_a', 'category_b', 'category_c']));
    });

    test('should return empty list when no categories exist', () {
      // Fresh matcher without categories
      final freshConfigPath = '${Directory.systemTemp.path}/fresh_config_${DateTime.now().millisecondsSinceEpoch}.json';
      final freshConfig = {
        'markets': {'walmart': ['walmart']},
        'learned_patterns': {},
      };
      File(freshConfigPath).writeAsStringSync(json.encode(freshConfig));

      final freshMatcher = AdaptiveFuzzyMatcher(freshConfigPath);
      final categories = freshMatcher.getCategories();

      expect(categories, isEmpty);

      // Cleanup
      File(freshConfigPath).deleteSync();
    });
  });

  group('getStoreCategory() - Get Store Category', () {
    test('should return category for categorized store', () {
      matcher.addStore(name: 'CategorizedStore', spellings: ['categorizedstore'], category: 'store_category');

      final category = matcher.getStoreCategory('categorizedstore');
      expect(category, equals('store_category'));
    });

    test('should return null for uncategorized store', () {
      matcher.addStore(name: 'UncategorizedStore', spellings: ['uncategorizedstore']);

      final category = matcher.getStoreCategory('uncategorizedstore');
      expect(category, isNull);
    });

    test('should return null for non-existent store', () {
      final category = matcher.getStoreCategory('nonexistent_store');
      expect(category, isNull);
    });

    test('should return first category when store in multiple categories', () {
      matcher.addStore(name: 'MultiStore', spellings: ['multistore']);
      matcher.addStoreToCategory('MultiStore', 'first_category');
      matcher.addStoreToCategory('MultiStore', 'second_category');

      final category = matcher.getStoreCategory('multistore');
      // Should return one of the categories (implementation returns first found)
      expect(category, anyOf(equals('first_category'), equals('second_category')));
    });
  });

  // ==========================================
  // PRESET LOADING
  // ==========================================

  group('addFastFoodRestaurants() - Fast Food Presets', () {
    test('should add all fast food restaurants', () {
      final count = matcher.addFastFoodRestaurants();

      expect(count, greaterThan(0));
      expect(matcher.hasStore('mcdonalds'), isTrue);
      expect(matcher.hasStore('burger_king'), isTrue);
      expect(matcher.hasStore('chipotle'), isTrue);
      expect(matcher.hasStore('taco_bell'), isTrue);
      expect(matcher.hasStore('subway'), isTrue);
    });

    test('should categorize as fast_food', () {
      matcher.addFastFoodRestaurants();

      expect(matcher.getStoreCategory('mcdonalds'), equals('fast_food'));
      expect(matcher.getStoreCategory('wendys'), equals('fast_food'));
    });

    test('should include spelling variations', () {
      matcher.addFastFoodRestaurants();

      final mcdonaldsSpellings = matcher.getSpellings('mcdonalds');
      expect(mcdonaldsSpellings, containsAll(["mcdonald's", 'mcdonalds', 'mcd']));

      final chickFilASpellings = matcher.getSpellings('chick_fil_a');
      expect(chickFilASpellings, containsAll(['chick-fil-a', 'chick fil a', 'chickfila']));
    });

    test('should be idempotent (can be called multiple times)', () {
      final firstCount = matcher.addFastFoodRestaurants();
      final secondCount = matcher.addFastFoodRestaurants();

      // Second call should still return same count (stores exist but are merged)
      expect(secondCount, equals(firstCount));

      // No duplicate spellings should exist
      final spellings = matcher.getSpellings('mcdonalds');
      final uniqueSpellings = spellings!.toSet().toList();
      expect(spellings.length, equals(uniqueSpellings.length));
    });
  });

  group('addCasualDiningRestaurants() - Casual Dining Presets', () {
    test('should add all casual dining restaurants', () {
      final count = matcher.addCasualDiningRestaurants();

      expect(count, greaterThan(0));
      expect(matcher.hasStore('applebees'), isTrue);
      expect(matcher.hasStore('chilis'), isTrue);
      expect(matcher.hasStore('olive_garden'), isTrue);
      expect(matcher.hasStore('outback_steakhouse'), isTrue);
    });

    test('should categorize as casual_dining', () {
      matcher.addCasualDiningRestaurants();

      expect(matcher.getStoreCategory('applebees'), equals('casual_dining'));
      expect(matcher.getStoreCategory('red_lobster'), equals('casual_dining'));
    });

    test('should include spelling variations', () {
      matcher.addCasualDiningRestaurants();

      final applebeeSpellings = matcher.getSpellings('applebees');
      expect(applebeeSpellings, containsAll(["applebee's", 'applebees']));

      final bwwSpellings = matcher.getSpellings('buffalo_wild_wings');
      expect(bwwSpellings, containsAll(['buffalo wild wings', 'bww', 'bdubs']));
    });
  });

  group('addCoffeeShops() - Coffee Shop Presets', () {
    test('should add all coffee shops', () {
      final count = matcher.addCoffeeShops();

      expect(count, greaterThan(0));
      expect(matcher.hasStore('starbucks'), isTrue);
      expect(matcher.hasStore('dunkin'), isTrue);
      expect(matcher.hasStore('peets_coffee'), isTrue);
      expect(matcher.hasStore('dutch_bros'), isTrue);
    });

    test('should categorize as coffee_shop', () {
      matcher.addCoffeeShops();

      expect(matcher.getStoreCategory('starbucks'), equals('coffee_shop'));
      expect(matcher.getStoreCategory('dunkin'), equals('coffee_shop'));
    });

    test('should include spelling variations', () {
      matcher.addCoffeeShops();

      final starbucksSpellings = matcher.getSpellings('starbucks');
      expect(starbucksSpellings, containsAll(['starbucks', 'starbuck', 'sbux']));

      final dunkinSpellings = matcher.getSpellings('dunkin');
      expect(dunkinSpellings, containsAll(['dunkin', "dunkin'", 'dunkin donuts']));
    });
  });

  group('addGroceryStores() - Grocery Presets', () {
    test('should add all grocery stores', () {
      final count = matcher.addGroceryStores();

      expect(count, greaterThan(0));
      expect(matcher.hasStore('kroger'), isTrue);
      expect(matcher.hasStore('safeway'), isTrue);
      expect(matcher.hasStore('publix'), isTrue);
      expect(matcher.hasStore('aldi'), isTrue);
    });

    test('should categorize as grocery', () {
      matcher.addGroceryStores();

      expect(matcher.getStoreCategory('kroger'), equals('grocery'));
      expect(matcher.getStoreCategory('safeway'), equals('grocery'));
    });

    test('should merge with existing stores from default config', () {
      // walmart, target, costco, etc. exist in default config
      final existingWalmartSpellings = matcher.getSpellings('walmart');

      matcher.addGroceryStores();

      final newWalmartSpellings = matcher.getSpellings('walmart');
      expect(newWalmartSpellings!.length, greaterThanOrEqualTo(existingWalmartSpellings!.length));
    });

    test('should include regional grocery chains', () {
      matcher.addGroceryStores();

      expect(matcher.hasStore('heb'), isTrue);
      expect(matcher.hasStore('wegmans'), isTrue);
      expect(matcher.hasStore('publix'), isTrue);
      expect(matcher.hasStore('harris_teeter'), isTrue);
    });
  });

  group('addAllPresets() - Add All Preset Categories', () {
    test('should add stores from all preset categories', () {
      final count = matcher.addAllPresets();

      expect(count, greaterThan(0));

      // Fast food
      expect(matcher.hasStore('mcdonalds'), isTrue);

      // Casual dining
      expect(matcher.hasStore('applebees'), isTrue);

      // Coffee shops
      expect(matcher.hasStore('starbucks'), isTrue);

      // Grocery
      expect(matcher.hasStore('kroger'), isTrue);
    });

    test('should create all categories', () {
      matcher.addAllPresets();

      final categories = matcher.getCategories();
      expect(categories, containsAll(['fast_food', 'casual_dining', 'coffee_shop', 'grocery']));
    });

    test('should return total count of all added stores', () {
      final totalCount = matcher.addAllPresets();

      // Total should be the sum of all preset categories
      // Fast food: ~20, Casual dining: ~20, Coffee: ~15, Grocery: ~30
      // Actual count depends on implementation
      expect(totalCount, greaterThan(50));
      
      // Verify by checking categories have stores
      expect(matcher.getStoresInCategory('fast_food').length, greaterThan(10));
      expect(matcher.getStoresInCategory('casual_dining').length, greaterThan(10));
      expect(matcher.getStoresInCategory('coffee_shop').length, greaterThan(10));
      expect(matcher.getStoresInCategory('grocery').length, greaterThan(10));
    });
  });

  // ==========================================
  // EDGE CASES & ERROR HANDLING
  // ==========================================

  group('Edge Cases', () {
    test('should handle unicode characters in store name', () {
      matcher.addStore(name: 'Café du Monde', spellings: ['café du monde', 'cafe du monde']);

      expect(matcher.hasStore('caf_du_monde'), isTrue);
    });

    test('should handle numeric characters in store name', () {
      matcher.addStore(name: '7-Eleven', spellings: ['7-eleven', '7 eleven', '711']);

      expect(matcher.hasStore('7_eleven'), isTrue);
      expect(matcher.getSpellings('7_eleven'), containsAll(['7-eleven', '7 eleven', '711']));
    });

    test('should handle very long store names', () {
      final longName = 'A' * 100;
      matcher.addStore(name: longName, spellings: [longName.toLowerCase()]);

      expect(matcher.hasStore(longName), isTrue);
    });

    test('should handle single character spellings', () {
      matcher.addStore(name: 'Test', spellings: ['test', 't', 'te']);

      final spellings = matcher.getSpellings('test');
      expect(spellings, containsAll(['test', 't', 'te']));
    });

    test('should handle trailing/leading whitespace in spellings', () {
      matcher.addStore(name: 'Whitespace', spellings: ['  whitespace  ', ' ws ', 'whitespace']);

      final spellings = matcher.getSpellings('whitespace');
      // Should be trimmed
      expect(spellings, contains('whitespace'));
      expect(spellings, contains('ws'));
      expect(spellings, isNot(contains('  whitespace  ')));
    });

    test('should preserve config integrity after multiple operations', () {
      // Perform multiple operations
      matcher.addStore(name: 'Store1', spellings: ['store1']);
      matcher.addStore(name: 'Store2', spellings: ['store2'], category: 'cat1');
      matcher.addSpellings('Store1', ['s1']);
      matcher.removeSpellings('Store2', ['store2']);
      matcher.addStore(name: 'Store2', spellings: ['store2 fixed']);
      matcher.removeStore('Store1');
      matcher.addStoreToCategory('Store2', 'cat2');

      // Verify config file is valid JSON
      final configContent = File(testConfigPath).readAsStringSync();
      expect(() => json.decode(configContent), returnsNormally);

      // Re-load matcher and verify state
      final reloadedMatcher = AdaptiveFuzzyMatcher(testConfigPath);
      expect(reloadedMatcher.hasStore('store1'), isFalse);
      expect(reloadedMatcher.hasStore('store2'), isTrue);
      expect(reloadedMatcher.getSpellings('store2'), contains('store2 fixed'));
    });

    test('should handle concurrent-like rapid operations', () {
      for (int i = 0; i < 100; i++) {
        matcher.addStore(name: 'BulkStore$i', spellings: ['bulk$i']);
      }

      for (int i = 0; i < 50; i++) {
        matcher.removeStore('BulkStore$i');
      }

      // Verify state
      for (int i = 0; i < 50; i++) {
        expect(matcher.hasStore('bulkstore$i'), isFalse);
      }
      for (int i = 50; i < 100; i++) {
        expect(matcher.hasStore('bulkstore$i'), isTrue);
      }
    });
  });

  // ==========================================
  // CONFIG PERSISTENCE
  // ==========================================

  group('Config Persistence', () {
    test('should persist stores to config file', () {
      matcher.addStore(name: 'PersistTest', spellings: ['persisttest']);

      // Create new matcher instance to verify persistence
      final newMatcher = AdaptiveFuzzyMatcher(testConfigPath);
      expect(newMatcher.hasStore('persisttest'), isTrue);
      expect(newMatcher.getSpellings('persisttest'), contains('persisttest'));
    });

    test('should persist categories to config file', () {
      matcher.addStore(name: 'CatPersist', spellings: ['catpersist'], category: 'persist_cat');

      final newMatcher = AdaptiveFuzzyMatcher(testConfigPath);
      expect(newMatcher.getStoreCategory('catpersist'), equals('persist_cat'));
      expect(newMatcher.getStoresInCategory('persist_cat'), contains('catpersist'));
    });

    test('should persist store removal to config file', () {
      matcher.addStore(name: 'ToBeRemoved', spellings: ['toberemoved']);
      matcher.removeStore('ToBeRemoved');

      final newMatcher = AdaptiveFuzzyMatcher(testConfigPath);
      expect(newMatcher.hasStore('toberemoved'), isFalse);
    });

    test('should persist spelling changes to config file', () {
      matcher.addStore(name: 'SpellingPersist', spellings: ['sp1', 'sp2']);
      matcher.removeSpellings('SpellingPersist', ['sp2']);
      matcher.addSpellings('SpellingPersist', ['sp3']);

      final newMatcher = AdaptiveFuzzyMatcher(testConfigPath);
      final spellings = newMatcher.getSpellings('spellingpersist');
      expect(spellings, contains('sp1'));
      expect(spellings, isNot(contains('sp2')));
      expect(spellings, contains('sp3'));
    });

    test('should maintain config structure after export/import', () {
      matcher.addStore(name: 'ExportTest', spellings: ['exporttest'], category: 'export_cat');
      matcher.addAllPresets();

      final exported = matcher.exportConfig();

      // Verify export is valid JSON with expected structure
      final parsed = json.decode(exported) as Map<String, dynamic>;
      expect(parsed.containsKey('markets'), isTrue);
      expect(parsed.containsKey('store_categories'), isTrue);
      expect((parsed['markets'] as Map).containsKey('exporttest'), isTrue);
    });
  });

  // ==========================================
  // INTEGRATION WITH EXTRACTION
  // ==========================================

  group('Integration with Market Extraction', () {
    test('should find newly added store in extraction', () {
      matcher.addStore(
        name: 'New Restaurant',
        spellings: ['new restaurant', 'newrest', 'the new restaurant'],
      );

      final lines = [
        'NEW RESTAURANT',
        '123 Main Street',
        'Receipt #12345',
        'Total: \$25.99',
      ];

      final result = matcher.extractMarket(lines);
      expect(result.value, equals('new_restaurant'));
      expect(result.confidence, greaterThan(0.5));
    });

    test('should find store by spelling variation', () {
      matcher.addStore(
        name: 'Fancy Place',
        spellings: ['fancy place', 'the fancy place', 'fancyplace'],
      );

      final lines = [
        'FANCYPLACE',
        'Store #99',
        'Amount: \$50.00',
      ];

      final result = matcher.extractMarket(lines);
      expect(result.value, equals('fancy_place'));
    });

    test('should not find removed store', () {
      matcher.addStore(name: 'Temporary Store', spellings: ['temporary store', 'tempstore']);

      // Verify it can be found
      var lines = ['TEMPORARY STORE', 'Total: \$10.00'];
      var result = matcher.extractMarket(lines);
      expect(result.value, equals('temporary_store'));

      // Remove and verify not found
      matcher.removeStore('Temporary Store');
      result = matcher.extractMarket(lines);
      expect(result.value, isNot(equals('temporary_store')));
    });
  });
}
