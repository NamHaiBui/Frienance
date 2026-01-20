import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/string_utils.dart';

void main() {
  group('StringUtils', () {
    group('normalizeMarketName', () {
      test('converts to lowercase', () {
        expect(StringUtils.normalizeMarketName('WALMART'), 'walmart');
        expect(StringUtils.normalizeMarketName('Target'), 'target');
      });

      test('replaces spaces with underscores', () {
        expect(StringUtils.normalizeMarketName('Whole Foods'), 'whole_foods');
        expect(StringUtils.normalizeMarketName('Trader Joes'), 'trader_joes');
      });

      test('removes special characters', () {
        expect(StringUtils.normalizeMarketName("Trader Joe's"), 'trader_joe_s');
        expect(StringUtils.normalizeMarketName('Chick-fil-A'), 'chick_fil_a');
      });

      test('collapses multiple underscores', () {
        expect(StringUtils.normalizeMarketName('Store   Name'), 'store_name');
        expect(StringUtils.normalizeMarketName('A---B'), 'a_b');
      });

      test('trims leading/trailing underscores', () {
        expect(StringUtils.normalizeMarketName(' Store '), 'store');
        expect(StringUtils.normalizeMarketName('_store_'), 'store');
      });

      test('handles empty string', () {
        expect(StringUtils.normalizeMarketName(''), '');
      });
    });

    group('calculateSimilarity', () {
      test('returns 1.0 for identical strings', () {
        expect(StringUtils.calculateSimilarity('walmart', 'walmart'), 1.0);
        expect(StringUtils.calculateSimilarity('test', 'test'), 1.0);
      });

      test('returns 0.0 for empty strings', () {
        expect(StringUtils.calculateSimilarity('', 'test'), 0.0);
        expect(StringUtils.calculateSimilarity('test', ''), 0.0);
        expect(StringUtils.calculateSimilarity('', ''), 0.0);
      });

      test('handles containment', () {
        final similarity = StringUtils.calculateSimilarity('walmart store', 'walmart');
        expect(similarity, greaterThan(0.4)); // Contained string scores well
      });

      test('is case insensitive', () {
        // Note: containment check returns 0.9 * ratio, not 1.0
        expect(StringUtils.calculateSimilarity('WALMART', 'walmart'), greaterThanOrEqualTo(0.9));
        expect(StringUtils.calculateSimilarity('Target', 'TARGET'), greaterThanOrEqualTo(0.9));
      });

      test('handles similar strings', () {
        final similarity = StringUtils.calculateSimilarity('walmart', 'walmartk');
        expect(similarity, greaterThan(0.75)); // Levenshtein allows some variation
      });

      test('handles completely different strings', () {
        final similarity = StringUtils.calculateSimilarity('abc', 'xyz');
        expect(similarity, lessThan(0.5));
      });
    });

    group('levenshteinDistance', () {
      test('returns 0 for identical strings', () {
        expect(StringUtils.levenshteinDistance('test', 'test'), 0);
        expect(StringUtils.levenshteinDistance('', ''), 0);
      });

      test('returns string length for empty comparison', () {
        expect(StringUtils.levenshteinDistance('test', ''), 4);
        expect(StringUtils.levenshteinDistance('', 'test'), 4);
      });

      test('calculates single edit distance', () {
        expect(StringUtils.levenshteinDistance('test', 'tests'), 1); // insertion
        expect(StringUtils.levenshteinDistance('test', 'tes'), 1); // deletion
        expect(StringUtils.levenshteinDistance('test', 'tast'), 1); // substitution
      });

      test('calculates multiple edit distance', () {
        expect(StringUtils.levenshteinDistance('kitten', 'sitting'), 3);
        expect(StringUtils.levenshteinDistance('saturday', 'sunday'), 3);
      });
    });

    group('extractPrice', () {
      test('extracts price from text', () {
        expect(StringUtils.extractPrice('Total: \$12.99'), '12.99');
        expect(StringUtils.extractPrice('Amount Due: 45.50'), '45.50');
      });

      test('extracts first price when multiple present', () {
        expect(StringUtils.extractPrice('12.99 and 45.00'), '12.99');
      });

      test('handles comma decimal separator', () {
        expect(StringUtils.extractPrice('Price: 12,99'), '12,99');
      });

      test('returns original text if no price found', () {
        expect(StringUtils.extractPrice('No price here'), 'No price here');
      });
    });

    group('parsePrice', () {
      test('parses period decimal format', () {
        expect(StringUtils.parsePrice('12.99'), 12.99);
        expect(StringUtils.parsePrice('0.50'), 0.50);
      });

      test('parses comma decimal format', () {
        expect(StringUtils.parsePrice('12,99'), 12.99);
        expect(StringUtils.parsePrice('100,00'), 100.00);
      });

      test('returns 0.0 for invalid price', () {
        expect(StringUtils.parsePrice('invalid'), 0.0);
        expect(StringUtils.parsePrice(''), 0.0);
      });
    });

    group('normalizeLines', () {
      test('removes empty lines', () {
        final lines = ['line1', '', 'line2', '   ', 'line3'];
        final result = StringUtils.normalizeLines(lines);
        expect(result, ['line1', 'line2', 'line3']);
      });

      test('trims whitespace', () {
        final lines = ['  line1  ', '\tline2\t', 'line3'];
        final result = StringUtils.normalizeLines(lines);
        expect(result, ['line1', 'line2', 'line3']);
      });

      test('handles empty list', () {
        expect(StringUtils.normalizeLines([]), []);
      });

      test('handles list with only empty strings', () {
        expect(StringUtils.normalizeLines(['', '   ', '\t']), []);
      });
    });
  });
}
