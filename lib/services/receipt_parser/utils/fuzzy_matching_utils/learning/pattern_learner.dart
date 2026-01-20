import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/base_configs.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/string_utils.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/extraction_results.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/match_result.dart';

/// Handles pattern learning from user confirmations.
class PatternLearner {
  final ConfigManager configManager;

  PatternLearner(this.configManager);

  /// Update extraction statistics based on results.
  void updateExtractionStats(
    MatchResult market,
    MatchResult date,
    MatchResult sum,
    ItemsResult items,
  ) {
    final stats = configManager.learnedPatterns['extraction_stats'] as Map<String, dynamic>? ?? {};
    stats['total_extractions'] = (stats['total_extractions'] as int? ?? 0) + 1;
    
    if (market.value != null && market.confidence >= FuzzyMatchingConfidence.medium.value) {
      stats['successful_markets'] = (stats['successful_markets'] as int? ?? 0) + 1;
    }
    if (date.value != null && date.confidence >= FuzzyMatchingConfidence.medium.value) {
      stats['successful_dates'] = (stats['successful_dates'] as int? ?? 0) + 1;
    }
    if (sum.value != null && sum.confidence >= FuzzyMatchingConfidence.medium.value) {
      stats['successful_sums'] = (stats['successful_sums'] as int? ?? 0) + 1;
    }
    if (items.items.isNotEmpty) {
      stats['successful_items'] = (stats['successful_items'] as int? ?? 0) + 1;
    }

    configManager.learnedPatterns['extraction_stats'] = stats;
  }

  /// Confirm extraction and learn from it.
  void confirmExtraction(ExtractionResult result, {
    String? confirmedMarket,
    String? confirmedDate,
    String? confirmedSum,
    List<ItemMatch>? confirmedItems,
  }) {
    // Learn market pattern
    if (confirmedMarket != null && result.market.matchedLine != null) {
      learnMarketPattern(confirmedMarket, result.market.matchedLine!);
    }

    // Learn date pattern
    if (confirmedDate != null && result.date.patternUsed != null) {
      learnDatePattern(result.date.patternUsed!);
    }

    // Learn sum pattern
    if (confirmedSum != null && result.sum.patternUsed != null) {
      learnSumPattern(result.sum.patternUsed!);
    }

    // Learn item patterns
    if (confirmedItems != null) {
      for (final item in confirmedItems) {
        if (item.patternUsed != null) {
          learnItemPattern(item.patternUsed!);
        }
      }
    }

    configManager.saveConfig();
  }

  /// Learn a market pattern from a confirmed match.
  void learnMarketPattern(String marketName, String matchedLine) {
    final marketMatches = configManager.learnedMarketMatches;
    final normalizedName = StringUtils.normalizeMarketName(marketName);
    
    if (!marketMatches.containsKey(normalizedName)) {
      marketMatches[normalizedName] = <String>[];
    }
    
    final patterns = (marketMatches[normalizedName] as List).cast<String>();
    final lowerLine = matchedLine.toLowerCase();
    
    // Extract meaningful tokens from the line
    final tokens = lowerLine.split(RegExp(r'\s+')).where((t) => t.length > 2).toList();
    for (final token in tokens) {
      if (!patterns.contains(token) && !RegExp(r'^\d+$').hasMatch(token)) {
        patterns.add(token);
      }
    }

    marketMatches[normalizedName] = patterns;
    configManager.updateLearnedMarketMatches(marketMatches);

    // Also add to main config markets
    final configMarkets = configManager.markets;
    if (!configMarkets.containsKey(normalizedName)) {
      configMarkets[normalizedName] = patterns;
    } else {
      final existingPatterns = (configMarkets[normalizedName] as List).cast<String>();
      for (final pattern in patterns) {
        if (!existingPatterns.contains(pattern)) {
          existingPatterns.add(pattern);
        }
      }
    }
  }

  /// Learn a date pattern from a confirmed match.
  void learnDatePattern(String patternUsed) {
    if (patternUsed.startsWith('builtin:') || patternUsed.startsWith('config:')) {
      return; // Don't learn built-in patterns
    }

    if (patternUsed.startsWith('learned:')) {
      final pattern = patternUsed.substring(8);
      configManager.addLearnedDatePattern(pattern);
    }
  }

  /// Learn a sum pattern from a confirmed match.
  void learnSumPattern(String patternUsed) {
    if (patternUsed.startsWith('builtin:') || patternUsed.startsWith('config:')) {
      return;
    }

    if (patternUsed.startsWith('learned:')) {
      final pattern = patternUsed.substring(8);
      configManager.addLearnedSumPattern(pattern);
    }
  }

  /// Learn an item pattern from a confirmed match.
  void learnItemPattern(String patternUsed) {
    if (patternUsed.startsWith('builtin:') || patternUsed.startsWith('simple:')) {
      return;
    }

    if (patternUsed.startsWith('learned:')) {
      final pattern = patternUsed.substring(8);
      configManager.addLearnedItemPattern(pattern);
    }
  }

  /// Record a user correction for future learning.
  void recordCorrection({
    required String fieldType,
    required String originalValue,
    required String correctedValue,
    String? originalLine,
  }) {
    configManager.addUserCorrection(
      fieldType: fieldType,
      originalValue: originalValue,
      correctedValue: correctedValue,
      originalLine: originalLine,
    );
    configManager.saveConfig();
  }
}
