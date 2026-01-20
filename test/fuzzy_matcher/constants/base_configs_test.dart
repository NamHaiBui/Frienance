import 'package:flutter_test/flutter_test.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/base_configs.dart';

void main() {
  group('FuzzyMatchingConfidence', () {
    test('high confidence value is 0.85', () {
      expect(FuzzyMatchingConfidence.high.value, 0.85);
    });

    test('medium confidence value is 0.65', () {
      expect(FuzzyMatchingConfidence.medium.value, 0.65);
    });

    test('low confidence value is 0.45', () {
      expect(FuzzyMatchingConfidence.low.value, 0.45);
    });

    test('values are properly ordered', () {
      expect(FuzzyMatchingConfidence.high.value, greaterThan(FuzzyMatchingConfidence.medium.value));
      expect(FuzzyMatchingConfidence.medium.value, greaterThan(FuzzyMatchingConfidence.low.value));
    });
  });
}
