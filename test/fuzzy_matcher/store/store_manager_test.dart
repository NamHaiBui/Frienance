import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/store/store_manager.dart';

void main() {
  late String testConfigPath;
  late ConfigManager configManager;
  late StoreManager storeManager;

  setUp(() {
    testConfigPath = '${Directory.systemTemp.path}/test_store_${DateTime.now().millisecondsSinceEpoch}.json';
    
    final config = {
      'markets': {
        'walmart': ['walmart', 'wal-mart'],
        'target': ['target'],
      },
      'sum_keys': ['total'],
      'ignore_keys': [],
      'learned_patterns': {
        'successful_market_matches': {},
        'successful_date_patterns': [],
        'successful_sum_patterns': [],
        'successful_item_patterns': [],
        'user_corrections': [],
        'extraction_stats': {},
      },
    };
    
    File(testConfigPath).writeAsStringSync(json.encode(config));
    configManager = ConfigManager(testConfigPath);
    storeManager = StoreManager(configManager);
  });

  tearDown(() {
    final file = File(testConfigPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  group('StoreManager', () {
    group('addStore', () {
      test('adds new store with spellings', () {
        final result = storeManager.addStore(
          name: 'Costco',
          spellings: ['costco', 'costco wholesale'],
        );
        
        expect(result, true);
        expect(storeManager.hasStore('costco'), true);
      });

      test('adds store with default spelling if none provided', () {
        final result = storeManager.addStore(name: 'NewStore');
        
        expect(result, true);
        final spellings = storeManager.getSpellings('newstore');
        expect(spellings, contains('newstore'));
      });

      test('merges spellings for existing store', () {
        storeManager.addStore(name: 'walmart', spellings: ['walmart new']);
        
        final spellings = storeManager.getSpellings('walmart');
        expect(spellings, contains('walmart'));
        expect(spellings, contains('walmart new'));
      });

      test('adds category if provided', () {
        storeManager.addStore(
          name: 'Chipotle',
          spellings: ['chipotle'],
          category: 'fast_food',
        );
        
        expect(storeManager.getStoreCategory('chipotle'), 'fast_food');
      });

      test('returns false for empty name', () {
        final result = storeManager.addStore(name: '');
        expect(result, false);
      });
    });

    group('addStores', () {
      test('adds multiple stores at once', () {
        final stores = {
          'store_a': ['store a', 'store-a'],
          'store_b': ['store b'],
        };
        
        final added = storeManager.addStores(stores);
        
        expect(added, 2);
        expect(storeManager.hasStore('store_a'), true);
        expect(storeManager.hasStore('store_b'), true);
      });

      test('applies category to all stores', () {
        final stores = {
          'mcdonalds': ['mcdonalds'],
          'wendys': ['wendys'],
        };
        
        storeManager.addStores(stores, category: 'fast_food');
        
        expect(storeManager.getStoreCategory('mcdonalds'), 'fast_food');
        expect(storeManager.getStoreCategory('wendys'), 'fast_food');
      });
    });

    group('addSpellings', () {
      test('adds spellings to existing store', () {
        storeManager.addSpellings('walmart', ['wm', 'walmrt']);
        
        final spellings = storeManager.getSpellings('walmart');
        expect(spellings, contains('wm'));
        expect(spellings, contains('walmrt'));
      });

      test('creates store if does not exist', () {
        storeManager.addSpellings('newstore', ['new store', 'new-store']);
        
        expect(storeManager.hasStore('newstore'), true);
      });

      test('does not add duplicate spellings', () {
        storeManager.addSpellings('walmart', ['walmart']);
        
        final spellings = storeManager.getSpellings('walmart');
        final walmartCount = spellings!.where((s) => s == 'walmart').length;
        expect(walmartCount, 1);
      });
    });

    group('removeStore', () {
      test('removes existing store', () {
        final removed = storeManager.removeStore('walmart');
        
        expect(removed, true);
        expect(storeManager.hasStore('walmart'), false);
      });

      test('returns false for non-existent store', () {
        final removed = storeManager.removeStore('nonexistent');
        expect(removed, false);
      });

      test('removes from categories', () {
        storeManager.addStore(name: 'test_store', category: 'test_category');
        storeManager.removeStore('test_store');
        
        final stores = storeManager.getStoresInCategory('test_category');
        expect(stores, isNot(contains('test_store')));
      });
    });

    group('removeSpellings', () {
      test('removes specified spellings', () {
        final removed = storeManager.removeSpellings('walmart', ['wal-mart']);
        
        expect(removed, 1);
        final spellings = storeManager.getSpellings('walmart');
        expect(spellings, isNot(contains('wal-mart')));
      });

      test('returns 0 for non-existent store', () {
        final removed = storeManager.removeSpellings('nonexistent', ['test']);
        expect(removed, 0);
      });
    });

    group('getStores', () {
      test('returns all stores with spellings', () {
        final stores = storeManager.getStores();
        
        expect(stores, isA<Map<String, List<String>>>());
        expect(stores.containsKey('walmart'), true);
        expect(stores['walmart'], contains('walmart'));
      });
    });

    group('hasStore', () {
      test('returns true for existing store', () {
        expect(storeManager.hasStore('walmart'), true);
      });

      test('returns false for non-existent store', () {
        expect(storeManager.hasStore('nonexistent'), false);
      });

      test('normalizes name before checking', () {
        expect(storeManager.hasStore('WALMART'), true);
        // Note: 'Wal-Mart' normalizes to 'wal_mart', different from 'walmart'
        expect(storeManager.hasStore('Wal Mart'), false); // wal_mart != walmart
      });
    });

    group('searchStores', () {
      test('finds stores by name similarity', () {
        final matches = storeManager.searchStores('walmart');
        
        expect(matches.isNotEmpty, true);
        expect(matches.first.key, 'walmart');
      });

      test('finds stores by spelling similarity', () {
        final matches = storeManager.searchStores('wal mart');
        
        expect(matches.isNotEmpty, true);
      });

      test('respects threshold', () {
        final matches = storeManager.searchStores('xyz', threshold: 0.9);
        
        expect(matches, isEmpty);
      });

      test('sorts by similarity descending', () {
        storeManager.addStore(name: 'walmart2', spellings: ['walmart2']);
        
        final matches = storeManager.searchStores('walmart');
        
        if (matches.length >= 2) {
          expect(matches[0].value, greaterThanOrEqualTo(matches[1].value));
        }
      });
    });

    group('category management', () {
      test('addStoreToCategory adds store to category', () {
        final added = storeManager.addStoreToCategory('walmart', 'grocery');
        
        expect(added, true);
        expect(storeManager.getStoreCategory('walmart'), 'grocery');
      });

      test('addStoreToCategory returns false for non-existent store', () {
        final added = storeManager.addStoreToCategory('nonexistent', 'grocery');
        expect(added, false);
      });

      test('removeStoreFromCategory removes store', () {
        storeManager.addStoreToCategory('walmart', 'grocery');
        final removed = storeManager.removeStoreFromCategory('walmart', 'grocery');
        
        expect(removed, true);
        expect(storeManager.getStoreCategory('walmart'), isNull);
      });

      test('getStoresInCategory returns stores in category', () {
        storeManager.addStore(name: 'store1', category: 'test_cat');
        storeManager.addStore(name: 'store2', category: 'test_cat');
        
        final stores = storeManager.getStoresInCategory('test_cat');
        
        expect(stores, contains('store1'));
        expect(stores, contains('store2'));
      });

      test('getCategories returns all categories', () {
        storeManager.addStore(name: 's1', category: 'cat1');
        storeManager.addStore(name: 's2', category: 'cat2');
        
        final categories = storeManager.getCategories();
        
        expect(categories, contains('cat1'));
        expect(categories, contains('cat2'));
      });
    });

    group('presets', () {
      test('addFastFoodRestaurants adds fast food stores', () {
        final added = storeManager.addFastFoodRestaurants();
        
        expect(added, greaterThan(0));
        expect(storeManager.hasStore('mcdonalds'), true);
        expect(storeManager.hasStore('burger_king'), true);
      });

      test('addCasualDiningRestaurants adds casual dining', () {
        final added = storeManager.addCasualDiningRestaurants();
        
        expect(added, greaterThan(0));
        expect(storeManager.hasStore('applebees'), true);
      });

      test('addCoffeeShops adds coffee shops', () {
        final added = storeManager.addCoffeeShops();
        
        expect(added, greaterThan(0));
        expect(storeManager.hasStore('starbucks'), true);
      });

      test('addGroceryStores adds grocery stores', () {
        final added = storeManager.addGroceryStores();
        
        expect(added, greaterThan(0));
        expect(storeManager.hasStore('costco'), true);
      });

      test('addAllPresets adds all presets', () {
        final added = storeManager.addAllPresets();
        
        expect(added, greaterThan(50));
        expect(storeManager.hasStore('mcdonalds'), true);
        expect(storeManager.hasStore('starbucks'), true);
        expect(storeManager.hasStore('costco'), true);
      });
    });
  });
}
