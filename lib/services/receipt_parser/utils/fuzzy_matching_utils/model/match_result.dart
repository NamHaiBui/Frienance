import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/base_configs.dart';

class MatchResult{
final String? value;
final double confidence;
final String? matchedLine;
final String? patternUsed;
final String fieldType;

MatchResult({
  required this.value,
  required this.confidence,
  this.matchedLine,
  this.patternUsed,
  required this.fieldType,
});

bool get isHighConfidence => confidence >= FuzzyMatchingConfidence.high.value;
bool get isMediumConfidence => confidence >= FuzzyMatchingConfidence.medium.value && confidence < FuzzyMatchingConfidence.high.value;
bool get isLowConfidence => confidence >= FuzzyMatchingConfidence.low.value && confidence < FuzzyMatchingConfidence.medium.value;
  Map<String, dynamic> toJson() => {
    'value': value,
    'confidence': confidence,
    'matched_line': matchedLine,
    'pattern_used': patternUsed,
    'field_type': fieldType,
  };
}

class ItemMatch {
  final String name;
  final double price;
  final double confidence;
  final String originalLine;
  final String? patternUsed;

  ItemMatch({
    required this.name,
    required this.price,
    required this.confidence,
    required this.originalLine,
    this.patternUsed,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'confidence': confidence,
    'original_line': originalLine,
    'pattern_used': patternUsed,
  };
}

