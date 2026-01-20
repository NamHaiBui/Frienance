import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/base_configs.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/regex_patterns.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/config_manager.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/core/string_utils.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/extraction_results.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/match_result.dart';

/// Extracts line items (products with prices) from receipt text.
class ItemsExtractor {
  final ConfigManager configManager;

  const ItemsExtractor(this.configManager);

  /// Extract line items with prices.
  /// 
  /// Processes lines until reaching the total section, skipping ignored lines.
  ItemsResult extract(List<String> lines) {
    final items = <ItemMatch>[];
    final ignoreKeys = configManager.ignoreKeys;
    final sumKeys = configManager.sumKeys;

    bool reachedTotal = false;
    
    for (final line in lines) {
      final lowerLine = line.toLowerCase();
      
      // Check if we've reached the total section
      for (final sumKey in sumKeys) {
        if (lowerLine.contains(sumKey.toLowerCase()) && 
            (lowerLine.contains('total') || lowerLine.contains('sum'))) {
          reachedTotal = true;
          break;
        }
      }
      
      if (reachedTotal) break;

      // Skip ignored lines
      bool shouldSkip = false;
      for (final ignoreKey in ignoreKeys) {
        if (lowerLine.startsWith(ignoreKey.toLowerCase())) {
          shouldSkip = true;
          break;
        }
      }
      if (shouldSkip) continue;

      // Try to extract item
      final itemMatch = _extractItem(line);
      if (itemMatch != null && itemMatch.confidence >= FuzzyMatchingConfidence.low.value) {
        items.add(itemMatch);
      }
    }

    final avgConfidence = items.isEmpty 
        ? 0.0 
        : items.map((i) => i.confidence).reduce((a, b) => a + b) / items.length;

    return ItemsResult(
      items: items,
      averageConfidence: avgConfidence,
    );
  }

  ItemMatch? _extractItem(String line) {
    String? itemName;
    double? price;
    double bestConfidence = 0.0;
    String? patternUsed;

    // Try learned patterns first
    final learnedItemPatterns = configManager.learnedItemPatterns;
    for (final patternStr in learnedItemPatterns) {
      try {
        final pattern = RegExp(patternStr);
        final match = pattern.firstMatch(line);
        if (match != null && match.groupCount >= 2) {
          itemName = match.group(1)?.trim();
          price = StringUtils.parsePrice(match.group(2) ?? match.group(match.groupCount)!);
          bestConfidence = 0.9;
          patternUsed = 'learned:$patternStr';
          break;
        }
      } catch (_) {}
    }

    // Try built-in patterns
    if (itemName == null) {
      for (int i = 0; i < FuzzyMatchRegexPatterns.itemPatterns.length; i++) {
        final match = FuzzyMatchRegexPatterns.itemPatterns[i].firstMatch(line);
        if (match != null) {
          final groups = <String>[];
          for (int g = 1; g <= match.groupCount; g++) {
            final group = match.group(g);
            if (group != null) groups.add(group);
          }
          
          if (groups.length >= 2) {
            // Find the price (numeric value with decimal)
            String? name;
            String? priceStr;
            
            for (final group in groups) {
              if (RegExp(r'^\d+[.,]\d{2}$').hasMatch(group)) {
                priceStr = group;
              } else if (group.length > 1 && !RegExp(r'^\d+$').hasMatch(group)) {
                name = group;
              }
            }

            if (name != null && priceStr != null) {
              itemName = name.trim();
              price = StringUtils.parsePrice(priceStr);
              bestConfidence = 0.8 - (i * 0.05);
              patternUsed = 'builtin:item_pattern_$i';
              break;
            }
          }
        }
      }
    }

    // Fallback: simple name + price extraction
    if (itemName == null) {
      final simpleMatch = RegExp(r'^([A-Za-z][A-Za-z\s\-/]+?)\s+[\$]?(\d+[.,]\d{2})\s*[A-Z]?$').firstMatch(line);
      if (simpleMatch != null) {
        itemName = simpleMatch.group(1)?.trim();
        price = StringUtils.parsePrice(simpleMatch.group(2)!);
        bestConfidence = 0.6;
        patternUsed = 'simple:name_price';
      }
    }

    if (itemName != null && price != null && itemName.length > 1) {
      return ItemMatch(
        name: itemName,
        price: price,
        confidence: bestConfidence,
        originalLine: line,
        patternUsed: patternUsed,
      );
    }

    return null;
  }
}
