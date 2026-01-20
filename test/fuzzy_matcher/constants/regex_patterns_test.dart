import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/regex_patterns.dart';

void main() {
  group('FuzzyMatchRegexPatterns', () {
    group('datePatterns', () {
      test('has 5 date patterns', () {
        expect(FuzzyMatchRegexPatterns.datePatterns.length, 5);
      });

      test('pattern 0 matches MM/DD/YYYY', () {
        final pattern = FuzzyMatchRegexPatterns.datePatterns[0];
        expect(pattern.hasMatch('01/15/2024'), true);
        expect(pattern.hasMatch('1/5/24'), true);
        expect(pattern.hasMatch('12-25-2023'), true);
      });

      test('pattern 1 matches YYYY-MM-DD', () {
        final pattern = FuzzyMatchRegexPatterns.datePatterns[1];
        expect(pattern.hasMatch('2024-01-15'), true);
        expect(pattern.hasMatch('2024/12/25'), true);
      });

      test('pattern 2 matches DD Mon YYYY', () {
        final pattern = FuzzyMatchRegexPatterns.datePatterns[2];
        expect(pattern.hasMatch('15 Jan 2024'), true);
        expect(pattern.hasMatch('25 December 2023'), true);
      });

      test('pattern 3 matches Mon DD, YYYY', () {
        final pattern = FuzzyMatchRegexPatterns.datePatterns[3];
        expect(pattern.hasMatch('Jan 15, 2024'), true);
        expect(pattern.hasMatch('December 25, 2023'), true);
      });
    });

    group('sumPatterns', () {
      test('has 5 sum patterns', () {
        expect(FuzzyMatchRegexPatterns.sumPatterns.length, 5);
      });

      test('pattern 0 matches total keyword with price', () {
        final pattern = FuzzyMatchRegexPatterns.sumPatterns[0];
        expect(pattern.hasMatch('TOTAL: 12.99'), true);
        expect(pattern.hasMatch('total \$45.00'), true);
        expect(pattern.hasMatch('Amount Due: 100.00'), true);
      });

      test('pattern 1 matches dollar sign prefix', () {
        final pattern = FuzzyMatchRegexPatterns.sumPatterns[1];
        expect(pattern.hasMatch('\$12.99'), true);
        expect(pattern.hasMatch('\$ 45.00'), true);
      });

      test('pattern 3 matches grand total', () {
        final pattern = FuzzyMatchRegexPatterns.sumPatterns[3];
        expect(pattern.hasMatch('GRAND TOTAL: 50.00'), true);
        expect(pattern.hasMatch('Net Total \$100.00'), true);
      });
    });

    group('itemPatterns', () {
      test('has 5 item patterns', () {
        expect(FuzzyMatchRegexPatterns.itemPatterns.length, 5);
      });

      test('pattern 0 matches item -> price', () {
        final pattern = FuzzyMatchRegexPatterns.itemPatterns[0];
        // Pattern matches ITEM -> PRICE or ITEM > PRICE formats
        expect(pattern.hasMatch('ITEM -> 5.99'), true);
        expect(pattern.hasMatch('Product Name -> 12.99 F'), true);
      });

      test('pattern 1 matches quantity format', () {
        final pattern = FuzzyMatchRegexPatterns.itemPatterns[1];
        expect(pattern.hasMatch('2 x ITEM 10.00'), true);
        expect(pattern.hasMatch('3 @ Product 15.00'), true);
      });

      test('pattern 3 matches dollar prefix items', () {
        final pattern = FuzzyMatchRegexPatterns.itemPatterns[3];
        expect(pattern.hasMatch('ITEM NAME \$5.99'), true);
      });
    });

    group('marketIndicators', () {
      test('has common grocery indicators', () {
        expect(FuzzyMatchRegexPatterns.marketIndicators, contains('walmart'));
        expect(FuzzyMatchRegexPatterns.marketIndicators, contains('target'));
        expect(FuzzyMatchRegexPatterns.marketIndicators, contains('costco'));
        expect(FuzzyMatchRegexPatterns.marketIndicators, contains('kroger'));
      });

      test('has specialty store indicators', () {
        expect(FuzzyMatchRegexPatterns.marketIndicators, contains('whole foods'));
        expect(FuzzyMatchRegexPatterns.marketIndicators, contains('trader joe'));
      });

      test('has more than 20 indicators', () {
        expect(FuzzyMatchRegexPatterns.marketIndicators.length, greaterThan(20));
      });
    });
  });
}
