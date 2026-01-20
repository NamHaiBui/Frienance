import 'dart:math';

/// String manipulation and similarity utilities for fuzzy matching.
class StringUtils {
  const StringUtils._();

  /// Normalize a market/store name to a consistent format.
  /// 
  /// Converts to lowercase, replaces non-alphanumeric chars with underscores,
  /// collapses multiple underscores, and trims leading/trailing underscores.
  static String normalizeMarketName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Calculate string similarity using containment and Levenshtein distance.
  /// 
  /// Returns a value between 0.0 (completely different) and 1.0 (identical).
  static double calculateSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    final s1Lower = s1.toLowerCase();
    final s2Lower = s2.toLowerCase();

    // Check for containment
    if (s1Lower.contains(s2Lower)) {
      return 0.9 * (s2Lower.length / s1Lower.length);
    }
    if (s2Lower.contains(s1Lower)) {
      return 0.9 * (s1Lower.length / s2Lower.length);
    }

    // Levenshtein distance
    final len1 = s1Lower.length;
    final len2 = s2Lower.length;
    final maxLen = max(len1, len2);

    if (maxLen == 0) return 1.0;

    final distance = levenshteinDistance(s1Lower, s2Lower);
    return 1.0 - (distance / maxLen);
  }

  /// Calculate the Levenshtein (edit) distance between two strings.
  /// 
  /// Returns the minimum number of single-character edits (insertions,
  /// deletions, or substitutions) required to change one string into the other.
  static int levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List.generate(s2.length + 1, (i) => i);
    List<int> v1 = List.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < s2.length; j++) {
        final cost = s1[i] == s2[j] ? 0 : 1;
        v1[j + 1] = min(min(v1[j] + 1, v0[j + 1] + 1), v0[j] + cost);
      }

      final temp = v0;
      v0 = v1;
      v1 = temp;
    }

    return v0[s2.length];
  }

  /// Extract a price string from text.
  /// 
  /// Finds the first occurrence of a price pattern (digits with 2 decimal places).
  static String extractPrice(String text) {
    final match = RegExp(r'(\d+[.,]\d{2})').firstMatch(text);
    return match?.group(1) ?? text;
  }

  /// Parse a price string to double.
  /// 
  /// Handles both period and comma as decimal separators.
  static double parsePrice(String priceStr) {
    return double.tryParse(priceStr.replaceAll(',', '.')) ?? 0.0;
  }

  /// Normalize lines by trimming whitespace and removing empty lines.
  static List<String> normalizeLines(List<String> lines) {
    return lines
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.trim())
        .toList();
  }
}
