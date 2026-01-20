import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/regex_patterns.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/match_result.dart';

/// Extracts dates from receipt text.
class DateExtractor {
  final ConfigManager configManager;

  const DateExtractor(this.configManager);

  /// Extract date with multiple pattern attempts.
  /// 
  /// Tries learned patterns first, then built-in patterns with cascading
  /// confidence levels, then config pattern.
  MatchResult extract(List<String> lines) {
    String? bestMatch;
    double bestConfidence = 0.0;
    String? matchedLine;
    String? patternUsed;

    // Try learned patterns first
    final learnedDatePatterns = configManager.learnedDatePatterns;
    
    for (final line in lines) {
      // Try learned patterns
      for (final patternStr in learnedDatePatterns) {
        try {
          final pattern = RegExp(patternStr);
          final match = pattern.firstMatch(line);
          if (match != null) {
            const confidence = 0.95;
            if (confidence > bestConfidence) {
              bestConfidence = confidence;
              bestMatch = match.group(0);
              matchedLine = line;
              patternUsed = 'learned:$patternStr';
            }
          }
        } catch (_) {
          // Invalid regex, skip
        }
      }

      // Try built-in patterns; cascade confidence level upon each failure
      for (int i = 0; i < FuzzyMatchRegexPatterns.datePatterns.length; i++) {
        final match = FuzzyMatchRegexPatterns.datePatterns[i].firstMatch(line);
        if (match != null) {
          final confidence = 0.85 - (i * 0.05); 
          if (confidence > bestConfidence) {
            bestConfidence = confidence;
            bestMatch = match.group(0);
            matchedLine = line;
            patternUsed = 'builtin:date_pattern_$i';
          }
        }
      }

      // Try config pattern
      try {
        final dateFormat = configManager.config['date_format'] as String?;
        if (dateFormat != null) {
          final configPattern = RegExp(dateFormat);
          final match = configPattern.firstMatch(line);
          if (match != null) {
            const confidence = 0.80;
            if (confidence > bestConfidence) {
              bestConfidence = confidence;
              bestMatch = match.group(0);
              matchedLine = line;
              patternUsed = 'config:date_format';
            }
          }
        }
      } catch (_) {}
    }

    return MatchResult(
      value: bestMatch,
      confidence: bestConfidence,
      matchedLine: matchedLine,
      patternUsed: patternUsed,
      fieldType: 'date',
    );
  }
}
