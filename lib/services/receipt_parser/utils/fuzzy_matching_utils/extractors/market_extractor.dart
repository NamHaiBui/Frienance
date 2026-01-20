import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/base_configs.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/regex_patterns.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/string_utils.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/match_result.dart';

/// Extracts market/store names from receipt text.
class MarketExtractor {
  final ConfigManager configManager;

  const MarketExtractor(this.configManager);

  /// Extract market/store name with confidence.
  /// 
  /// Checks learned patterns first (highest priority), then configured markets,
  /// then common market indicators.
  MatchResult extract(List<String> lines) {
    String? bestMatch;
    double bestConfidence = 0.0;
    String? matchedLine;
    String? patternUsed;

    // First check learned patterns
    final learnedMarkets = configManager.learnedMarketMatches;
    
    for (final line in lines.take(10)) { // Markets usually in first 10 lines
      final lowerLine = line.toLowerCase();
      
      // Check learned patterns first (higher priority)
      for (final entry in learnedMarkets.entries) {
        final patterns = (entry.value as List).cast<String>();
        for (final pattern in patterns) {
          if (lowerLine.contains(pattern.toLowerCase())) {
            const confidence = 0.95; // High confidence for learned patterns
            if (confidence > bestConfidence) {
              bestConfidence = confidence;
              bestMatch = entry.key;
              matchedLine = line;
              patternUsed = 'learned:$pattern';
            }
          }
        }
      }

      // Check configured markets
      final markets = configManager.markets;
      for (final entry in markets.entries) {
        if (entry.key == 'default') continue;
        final spellings = (entry.value as List).cast<String>();
        for (final spelling in spellings) {
          final similarity = StringUtils.calculateSimilarity(lowerLine, spelling);
          if (similarity > bestConfidence && similarity >= FuzzyMatchingConfidence.low.value) {
            bestConfidence = similarity;
            bestMatch = entry.key;
            matchedLine = line;
            patternUsed = 'config:$spelling';
          }
          // Direct contains check
          if (lowerLine.contains(spelling.toLowerCase())) {
            const directConfidence = 0.9;
            if (directConfidence > bestConfidence) {
              bestConfidence = directConfidence;
              bestMatch = entry.key;
              matchedLine = line;
              patternUsed = 'contains:$spelling';
            }
          }
        }
      }

      // Check common market indicators
      for (final indicator in FuzzyMatchRegexPatterns.marketIndicators) {
        if (lowerLine.contains(indicator)) {
          const confidence = 0.85;
          if (confidence > bestConfidence) {
            bestConfidence = confidence;
            bestMatch = StringUtils.normalizeMarketName(indicator);
            matchedLine = line;
            patternUsed = 'indicator:$indicator';
          }
        }
      }
    }

    return MatchResult(
      value: bestMatch,
      confidence: bestConfidence,
      matchedLine: matchedLine,
      patternUsed: patternUsed,
      fieldType: 'market',
    );
  }
}
