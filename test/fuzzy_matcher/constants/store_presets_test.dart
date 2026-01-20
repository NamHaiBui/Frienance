import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/store_presets.dart';

void main() {
  group('StorePresets', () {
    group('fastFood', () {
      test('contains common fast food restaurants', () {
        expect(StorePresets.fastFood.containsKey('mcdonalds'), true);
        expect(StorePresets.fastFood.containsKey('burger_king'), true);
        expect(StorePresets.fastFood.containsKey('wendys'), true);
        expect(StorePresets.fastFood.containsKey('taco_bell'), true);
        expect(StorePresets.fastFood.containsKey('chipotle'), true);
      });

      test('has spelling variations', () {
        expect(StorePresets.fastFood['mcdonalds'], contains("mcdonald's"));
        expect(StorePresets.fastFood['mcdonalds'], contains('mcdonalds'));
        expect(StorePresets.fastFood['mcdonalds'], contains('mcd'));
      });

      test('has multiple entries', () {
        expect(StorePresets.fastFood.length, greaterThan(15));
      });
    });

    group('casualDining', () {
      test('contains common casual dining restaurants', () {
        expect(StorePresets.casualDining.containsKey('applebees'), true);
        expect(StorePresets.casualDining.containsKey('chilis'), true);
        expect(StorePresets.casualDining.containsKey('olive_garden'), true);
        expect(StorePresets.casualDining.containsKey('dennys'), true);
      });

      test('has spelling variations', () {
        expect(StorePresets.casualDining['applebees'], contains("applebee's"));
        expect(StorePresets.casualDining['applebees'], contains('applebees'));
      });
    });

    group('coffeeShops', () {
      test('contains common coffee shops', () {
        expect(StorePresets.coffeeShops.containsKey('starbucks'), true);
        expect(StorePresets.coffeeShops.containsKey('dunkin'), true);
        expect(StorePresets.coffeeShops.containsKey('peets_coffee'), true);
      });

      test('has spelling variations', () {
        expect(StorePresets.coffeeShops['starbucks'], contains('starbucks'));
        expect(StorePresets.coffeeShops['starbucks'], contains('sbux'));
      });
    });

    group('grocery', () {
      test('contains common grocery stores', () {
        expect(StorePresets.grocery.containsKey('walmart'), true);
        expect(StorePresets.grocery.containsKey('target'), true);
        expect(StorePresets.grocery.containsKey('costco'), true);
        expect(StorePresets.grocery.containsKey('trader_joes'), true);
        expect(StorePresets.grocery.containsKey('whole_foods'), true);
      });

      test('has spelling variations', () {
        expect(StorePresets.grocery['walmart'], contains('walmart'));
        expect(StorePresets.grocery['walmart'], contains('wal-mart'));
        expect(StorePresets.grocery['walmart'], contains('wal mart'));
      });

      test('has many entries', () {
        expect(StorePresets.grocery.length, greaterThan(25));
      });
    });

    group('allPresets', () {
      test('contains all categories', () {
        final all = StorePresets.allPresets;
        
        expect(all.containsKey('fast_food'), true);
        expect(all.containsKey('casual_dining'), true);
        expect(all.containsKey('coffee_shop'), true);
        expect(all.containsKey('grocery'), true);
      });

      test('categories contain correct data', () {
        final all = StorePresets.allPresets;
        
        expect(all['fast_food'], StorePresets.fastFood);
        expect(all['casual_dining'], StorePresets.casualDining);
        expect(all['coffee_shop'], StorePresets.coffeeShops);
        expect(all['grocery'], StorePresets.grocery);
      });
    });

    group('allPresetsFlat', () {
      test('contains all stores flattened', () {
        final flat = StorePresets.allPresetsFlat;
        
        // Should contain stores from all categories
        expect(flat.containsKey('mcdonalds'), true);
        expect(flat.containsKey('applebees'), true);
        expect(flat.containsKey('starbucks'), true);
        expect(flat.containsKey('walmart'), true);
      });

      test('total count equals sum of all categories', () {
        final flat = StorePresets.allPresetsFlat;
        final expected = StorePresets.fastFood.length +
            StorePresets.casualDining.length +
            StorePresets.coffeeShops.length +
            StorePresets.grocery.length;
        
        expect(flat.length, expected);
      });
    });
  });
}
