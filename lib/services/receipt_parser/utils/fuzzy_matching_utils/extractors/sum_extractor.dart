import 'dart:math';

import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/regex_patterns.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/string_utils.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/match_result.dart';

/// Extracts total sum from receipt text.
class SumExtractor {
  final ConfigManager configManager;

  const SumExtractor(this.configManager);

  /// Extract total sum with multiple pattern attempts.
  /// 
  /// Processes lines in reverse (totals often at bottom), checks for sum
  /// keywords, tries learned patterns, then built-in patterns.
  MatchResult extract(List<String> lines) {
    String? bestMatch;
    double bestConfidence = 0.0;
    String? matchedLine;
    String? patternUsed;

    final sumKeys = configManager.sumKeys;
    final ignoreKeys = configManager.ignoreKeys;

    // Process lines in reverse (totals often at bottom)
    final reversedLines = lines.reversed.toList();

    for (final line in reversedLines) {
      final lowerLine = line.toLowerCase();
      
      // Skip ignored lines
      bool shouldSkip = false;
      for (final ignoreKey in ignoreKeys) {
        if (lowerLine.contains(ignoreKey.toLowerCase()) && 
            !lowerLine.contains('total')) {
          shouldSkip = true;
          break;
        }
      }
      if (shouldSkip) continue;

      // Check for sum keywords
      bool hasSumKeyword = false;
      for (final sumKey in sumKeys) {
        if (lowerLine.contains(sumKey.toLowerCase())) {
          hasSumKeyword = true;
          break;
        }
      }

      // Try learned patterns
      final learnedSumPatterns = configManager.learnedSumPatterns;
      for (final patternStr in learnedSumPatterns) {
        try {
          final pattern = RegExp(patternStr, caseSensitive: false);
          final match = pattern.firstMatch(line);
          if (match != null) {
            final confidence = hasSumKeyword ? 0.95 : 0.75;
            if (confidence > bestConfidence) {
              bestConfidence = confidence;
              bestMatch = StringUtils.extractPrice(match.group(0)!);
              matchedLine = line;
              patternUsed = 'learned:$patternStr';
            }
          }
        } catch (_) {}
      }

      // Try built-in patterns
      for (int i = 0; i < FuzzyMatchRegexPatterns.sumPatterns.length; i++) {
        final match = FuzzyMatchRegexPatterns.sumPatterns[i].firstMatch(line);
        if (match != null) {
          final baseConfidence = 0.85 - (i * 0.05);
          final confidence = hasSumKeyword ? baseConfidence + 0.1 : baseConfidence;
          if (confidence > bestConfidence) {
            bestConfidence = min(confidence, 1.0);
            bestMatch = match.group(1) ?? StringUtils.extractPrice(match.group(0)!);
            matchedLine = line;
            patternUsed = 'builtin:sum_pattern_$i';
          }
        }
      }

      // Simple price extraction if sum keyword found
      if (hasSumKeyword && bestConfidence < 0.7) {
        final priceMatch = RegExp(r'(\d+[.,]\d{2})').firstMatch(line);
        if (priceMatch != null) {
          const confidence = 0.7;
          if (confidence > bestConfidence) {
            bestConfidence = confidence;
            bestMatch = priceMatch.group(1);
            matchedLine = line;
            patternUsed = 'simple:price_with_keyword';
          }
        }
      }
    }

    return MatchResult(
      value: bestMatch,
      confidence: bestConfidence,
      matchedLine: matchedLine,
      patternUsed: patternUsed,
      fieldType: 'sum',
    );
  }
}
