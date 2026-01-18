import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Self-improving fuzzy matching algorithm for receipt parsing.
/// Learns from user confirmations and persists patterns to config.json
class AdaptiveFuzzyMatcher {
  final String configPath;
  late Map<String, dynamic> _learnedPatterns;
  late Map<String, dynamic> _config;

  // Extraction confidence thresholds
  static const double highConfidence = 0.85;
  static const double mediumConfidence = 0.65;
  static const double lowConfidence = 0.45;

  // Regex pattern collections for different extraction types
  static final List<RegExp> datePatterns = [
    RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b'), // MM/DD/YYYY, DD-MM-YY
    RegExp(r'\b(\d{2,4})[/\-.](\d{1,2})[/\-.](\d{1,2})\b'), // YYYY-MM-DD
    RegExp(r'\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*\s+(\d{2,4})\b', caseSensitive: false),
    RegExp(r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*\s+(\d{1,2}),?\s+(\d{2,4})\b', caseSensitive: false),
    RegExp(r'\b(\d{1,2})\s*/\s*(\d{1,2})\s*/\s*(\d{2,4})\b'), // With spaces around slashes
  ];

  static final List<RegExp> sumPatterns = [
    RegExp(r'(?:total|sum|amount|due|balance)[:\s]*[\$]?\s*(\d+[.,]\d{2})\b', caseSensitive: false),
    RegExp(r'[\$]\s*(\d+[.,]\d{2})\b'),
    RegExp(r'\b(\d+[.,]\d{2})\s*(?:total|sum|amount|due)\b', caseSensitive: false),
    RegExp(r'(?:grand\s*total|net\s*total)[:\s]*[\$]?\s*(\d+[.,]\d{2})\b', caseSensitive: false),
    RegExp(r'\btotal\s*-?>?\s*[\$]?\s*(\d+[.,]\d{2})\b', caseSensitive: false),
  ];

  static final List<RegExp> itemPatterns = [
    // Pattern: ITEM_NAME -> PRICE or ITEM_NAME PRICE
    RegExp(r'^(.+?)\s*-?>\s*(\d+[.,]\d{2})\s*[A-Z]?$'),
    // Pattern: QTY x ITEM_NAME PRICE
    RegExp(r'(\d+)\s*[x@]\s*(.+?)\s+(\d+[.,]\d{2})'),
    // Pattern: ITEM_NAME CODE PRICE
    RegExp(r'^([A-Za-z\s]+)\s+\d+\s+(\d+[.,]\d{2})'),
    // Pattern: ITEM_NAME $PRICE
    RegExp(r'^(.+?)\s+\$(\d+[.,]\d{2})'),
    // Pattern with product codes
    RegExp(r'^([A-Za-z][A-Za-z\s]+)\s+\d{6,}\s+(\d+[.,]\d{2})'),
  ];

  static final List<String> marketIndicators = [
    'walmart', 'target', 'costco', 'kroger', 'safeway', 'whole foods',
    'trader joe', 'aldi', 'publix', 'winco', 'spar', 'metro', 'lidl',
    'meijer', 'heb', 'food lion', 'giant', 'stop & shop', 'wegmans',
    'sprouts', 'fresh market', 'market basket', 'piggly wiggly',
  ];

  AdaptiveFuzzyMatcher(this.configPath) {
    _loadConfig();
    _loadLearnedPatterns();
  }

  void _loadConfig() {
    final file = File(configPath);
    if (file.existsSync()) {
      _config = json.decode(file.readAsStringSync());
    } else {
      _config = _getDefaultConfig();
      _saveConfig();
    }
  }

  void _loadLearnedPatterns() {
    _learnedPatterns = _config['learned_patterns'] as Map<String, dynamic>? ?? {};
    if (!_config.containsKey('learned_patterns')) {
      _config['learned_patterns'] = _learnedPatterns;
    }
  }

  Map<String, dynamic> _getDefaultConfig() {
    return {
      'markets': <String, dynamic>{
        'default': ['store', 'market', 'shop'],
        'walmart': ['walmart', 'wal-mart', 'wal mart'],
        'target': ['target'],
        'costco': ['costco', 'wholesale'],
        'trader_joes': ['trader joe', "trader joe's", 'trader joes'],
        'whole_foods': ['whole foods', 'wholefoods', 'wfm'],
        'winco': ['winco', 'winco foods'],
        'spar': ['spar'],
      },
      'sum_keys': [
        'total', 'subtotal', 'amount', 'due', 'sum', 'grand total',
        'net total', 'balance', 'payment', 'total due',
      ],
      'ignore_keys': [
        'tax', 'tip', 'change', 'cash', 'debit', 'credit', 'visa',
        'mastercard', 'approval', 'ref', 'terminal', 'network',
      ],
      'sum_format': r'\d+[.,]\d{2}',
      'date_format': r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b',
      'item_format': r'^(.+?)\s+(\d+[.,]\d{2})\s*[A-Z]?$',
      'learned_patterns': <String, dynamic>{
        'successful_market_matches': <String, dynamic>{},
        'successful_date_patterns': <String>[],
        'successful_sum_patterns': <String>[],
        'successful_item_patterns': <String>[],
        'user_corrections': <Map<String, dynamic>>[],
        'extraction_stats': <String, dynamic>{
          'total_extractions': 0,
          'successful_markets': 0,
          'successful_dates': 0,
          'successful_sums': 0,
          'successful_items': 0,
        },
      },
      'confidence_thresholds': {
        'high': highConfidence,
        'medium': mediumConfidence,
        'low': lowConfidence,
      },
    };
  }

  void _saveConfig() {
    final file = File(configPath);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_config),
    );
  }

  /// Extract all receipt data with confidence scores
  ExtractionResult extractAll(List<String> lines) {
    final normalizedLines = _normalizeLines(lines);
    
    final marketResult = extractMarket(normalizedLines);
    final dateResult = extractDate(normalizedLines);
    final sumResult = extractSum(normalizedLines);
    final itemsResult = extractItems(normalizedLines);

    _updateExtractionStats(marketResult, dateResult, sumResult, itemsResult);

    return ExtractionResult(
      market: marketResult,
      date: dateResult,
      sum: sumResult,
      items: itemsResult,
      rawLines: lines,
    );
  }

  List<String> _normalizeLines(List<String> lines) {
    return lines
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.trim())
        .toList();
  }

  /// Extract market/store name with confidence
  MatchResult extractMarket(List<String> lines) {
    String? bestMatch;
    double bestConfidence = 0.0;
    String? matchedLine;
    String? patternUsed;

    // First check learned patterns
    final learnedMarkets = _learnedPatterns['successful_market_matches'] as Map<String, dynamic>? ?? {};
    
    for (final line in lines.take(10)) { // Markets usually in first 10 lines
      final lowerLine = line.toLowerCase();
      
      // Check learned patterns first (higher priority)
      for (final entry in learnedMarkets.entries) {
        final patterns = (entry.value as List).cast<String>();
        for (final pattern in patterns) {
          if (lowerLine.contains(pattern.toLowerCase())) {
            final confidence = 0.95; // High confidence for learned patterns
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
      final markets = _config['markets'] as Map<String, dynamic>;
      for (final entry in markets.entries) {
        if (entry.key == 'default') continue;
        final spellings = (entry.value as List).cast<String>();
        for (final spelling in spellings) {
          final similarity = _calculateStringSimilarity(lowerLine, spelling);
          if (similarity > bestConfidence && similarity >= lowConfidence) {
            bestConfidence = similarity;
            bestMatch = entry.key;
            matchedLine = line;
            patternUsed = 'config:$spelling';
          }
          // Direct contains check
          if (lowerLine.contains(spelling.toLowerCase())) {
            final directConfidence = 0.9;
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
      for (final indicator in marketIndicators) {
        if (lowerLine.contains(indicator)) {
          final confidence = 0.85;
          if (confidence > bestConfidence) {
            bestConfidence = confidence;
            bestMatch = _normalizeMarketName(indicator);
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

  /// Extract date with multiple pattern attempts
  MatchResult extractDate(List<String> lines) {
    String? bestMatch;
    double bestConfidence = 0.0;
    String? matchedLine;
    String? patternUsed;

    // Try learned patterns first
    final learnedDatePatterns = (_learnedPatterns['successful_date_patterns'] as List?)?.cast<String>() ?? [];
    
    for (final line in lines) {
      // Try learned patterns
      for (final patternStr in learnedDatePatterns) {
        try {
          final pattern = RegExp(patternStr);
          final match = pattern.firstMatch(line);
          if (match != null) {
            final confidence = 0.95;
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

      // Try built-in patterns
      for (int i = 0; i < datePatterns.length; i++) {
        final match = datePatterns[i].firstMatch(line);
        if (match != null) {
          final confidence = 0.85 - (i * 0.05); // Decrease confidence for later patterns
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
        final configPattern = RegExp(_config['date_format'] as String);
        final match = configPattern.firstMatch(line);
        if (match != null) {
          final confidence = 0.80;
          if (confidence > bestConfidence) {
            bestConfidence = confidence;
            bestMatch = match.group(0);
            matchedLine = line;
            patternUsed = 'config:date_format';
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

  /// Extract total sum with multiple pattern attempts
  MatchResult extractSum(List<String> lines) {
    String? bestMatch;
    double bestConfidence = 0.0;
    String? matchedLine;
    String? patternUsed;

    final sumKeys = (_config['sum_keys'] as List).cast<String>();
    final ignoreKeys = (_config['ignore_keys'] as List).cast<String>();

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
      final learnedSumPatterns = (_learnedPatterns['successful_sum_patterns'] as List?)?.cast<String>() ?? [];
      for (final patternStr in learnedSumPatterns) {
        try {
          final pattern = RegExp(patternStr, caseSensitive: false);
          final match = pattern.firstMatch(line);
          if (match != null) {
            final confidence = hasSumKeyword ? 0.95 : 0.75;
            if (confidence > bestConfidence) {
              bestConfidence = confidence;
              bestMatch = _extractPrice(match.group(0)!);
              matchedLine = line;
              patternUsed = 'learned:$patternStr';
            }
          }
        } catch (_) {}
      }

      // Try built-in patterns
      for (int i = 0; i < sumPatterns.length; i++) {
        final match = sumPatterns[i].firstMatch(line);
        if (match != null) {
          final baseConfidence = 0.85 - (i * 0.05);
          final confidence = hasSumKeyword ? baseConfidence + 0.1 : baseConfidence;
          if (confidence > bestConfidence) {
            bestConfidence = min(confidence, 1.0);
            bestMatch = match.group(1) ?? _extractPrice(match.group(0)!);
            matchedLine = line;
            patternUsed = 'builtin:sum_pattern_$i';
          }
        }
      }

      // Simple price extraction if sum keyword found
      if (hasSumKeyword && bestConfidence < 0.7) {
        final priceMatch = RegExp(r'(\d+[.,]\d{2})').firstMatch(line);
        if (priceMatch != null) {
          final confidence = 0.7;
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

  /// Extract line items with prices
  ItemsResult extractItems(List<String> lines) {
    final items = <ItemMatch>[];
    final ignoreKeys = (_config['ignore_keys'] as List).cast<String>();
    final sumKeys = (_config['sum_keys'] as List).cast<String>();

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
      if (itemMatch != null && itemMatch.confidence >= lowConfidence) {
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
    final learnedItemPatterns = (_learnedPatterns['successful_item_patterns'] as List?)?.cast<String>() ?? [];
    for (final patternStr in learnedItemPatterns) {
      try {
        final pattern = RegExp(patternStr);
        final match = pattern.firstMatch(line);
        if (match != null && match.groupCount >= 2) {
          itemName = match.group(1)?.trim();
          price = _parsePrice(match.group(2) ?? match.group(match.groupCount)!);
          bestConfidence = 0.9;
          patternUsed = 'learned:$patternStr';
          break;
        }
      } catch (_) {}
    }

    // Try built-in patterns
    if (itemName == null) {
      for (int i = 0; i < itemPatterns.length; i++) {
        final match = itemPatterns[i].firstMatch(line);
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
              price = _parsePrice(priceStr);
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
        price = _parsePrice(simpleMatch.group(2)!);
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

  String _extractPrice(String text) {
    final match = RegExp(r'(\d+[.,]\d{2})').firstMatch(text);
    return match?.group(1) ?? text;
  }

  double _parsePrice(String priceStr) {
    return double.tryParse(priceStr.replaceAll(',', '.')) ?? 0.0;
  }

  String _normalizeMarketName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Calculate string similarity using Levenshtein-like algorithm
  double _calculateStringSimilarity(String s1, String s2) {
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

    final distance = _levenshteinDistance(s1Lower, s2Lower);
    return 1.0 - (distance / maxLen);
  }

  int _levenshteinDistance(String s1, String s2) {
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

  void _updateExtractionStats(
    MatchResult market,
    MatchResult date,
    MatchResult sum,
    ItemsResult items,
  ) {
    final stats = _learnedPatterns['extraction_stats'] as Map<String, dynamic>? ?? {};
    stats['total_extractions'] = (stats['total_extractions'] as int? ?? 0) + 1;
    
    if (market.value != null && market.confidence >= mediumConfidence) {
      stats['successful_markets'] = (stats['successful_markets'] as int? ?? 0) + 1;
    }
    if (date.value != null && date.confidence >= mediumConfidence) {
      stats['successful_dates'] = (stats['successful_dates'] as int? ?? 0) + 1;
    }
    if (sum.value != null && sum.confidence >= mediumConfidence) {
      stats['successful_sums'] = (stats['successful_sums'] as int? ?? 0) + 1;
    }
    if (items.items.isNotEmpty) {
      stats['successful_items'] = (stats['successful_items'] as int? ?? 0) + 1;
    }

    _learnedPatterns['extraction_stats'] = stats;
  }

  /// Confirm extraction and learn from it
  void confirmExtraction(ExtractionResult result, {
    String? confirmedMarket,
    String? confirmedDate,
    String? confirmedSum,
    List<ItemMatch>? confirmedItems,
  }) {
    // Learn market pattern
    if (confirmedMarket != null && result.market.matchedLine != null) {
      _learnMarketPattern(confirmedMarket, result.market.matchedLine!);
    }

    // Learn date pattern
    if (confirmedDate != null && result.date.patternUsed != null) {
      _learnDatePattern(result.date.patternUsed!);
    }

    // Learn sum pattern
    if (confirmedSum != null && result.sum.patternUsed != null) {
      _learnSumPattern(result.sum.patternUsed!);
    }

    // Learn item patterns
    if (confirmedItems != null) {
      for (final item in confirmedItems) {
        if (item.patternUsed != null) {
          _learnItemPattern(item.patternUsed!);
        }
      }
    }

    _saveConfig();
  }

  void _learnMarketPattern(String marketName, String matchedLine) {
    final marketMatches = _learnedPatterns['successful_market_matches'] as Map<String, dynamic>? ?? {};
    final normalizedName = _normalizeMarketName(marketName);
    
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
    _learnedPatterns['successful_market_matches'] = marketMatches;

    // Also add to main config markets
    final configMarkets = _config['markets'] as Map<String, dynamic>;
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

  void _learnDatePattern(String patternUsed) {
    if (patternUsed.startsWith('builtin:') || patternUsed.startsWith('config:')) {
      return; // Don't learn built-in patterns
    }

    final datePatterns = (_learnedPatterns['successful_date_patterns'] as List?)?.cast<String>() ?? [];
    
    if (patternUsed.startsWith('learned:')) {
      final pattern = patternUsed.substring(8);
      if (!datePatterns.contains(pattern)) {
        datePatterns.add(pattern);
      }
    }

    _learnedPatterns['successful_date_patterns'] = datePatterns;
  }

  void _learnSumPattern(String patternUsed) {
    if (patternUsed.startsWith('builtin:') || patternUsed.startsWith('config:')) {
      return;
    }

    final sumPatterns = (_learnedPatterns['successful_sum_patterns'] as List?)?.cast<String>() ?? [];
    
    if (patternUsed.startsWith('learned:')) {
      final pattern = patternUsed.substring(8);
      if (!sumPatterns.contains(pattern)) {
        sumPatterns.add(pattern);
      }
    }

    _learnedPatterns['successful_sum_patterns'] = sumPatterns;
  }

  void _learnItemPattern(String patternUsed) {
    if (patternUsed.startsWith('builtin:') || patternUsed.startsWith('simple:')) {
      return;
    }

    final itemPatterns = (_learnedPatterns['successful_item_patterns'] as List?)?.cast<String>() ?? [];
    
    if (patternUsed.startsWith('learned:')) {
      final pattern = patternUsed.substring(8);
      if (!itemPatterns.contains(pattern)) {
        itemPatterns.add(pattern);
      }
    }

    _learnedPatterns['successful_item_patterns'] = itemPatterns;
  }

  /// Record a user correction for future learning
  void recordCorrection({
    required String fieldType,
    required String originalValue,
    required String correctedValue,
    String? originalLine,
  }) {
    final corrections = (_learnedPatterns['user_corrections'] as List?) ?? [];
    
    corrections.add({
      'field_type': fieldType,
      'original_value': originalValue,
      'corrected_value': correctedValue,
      'original_line': originalLine,
      'timestamp': DateTime.now().toIso8601String(),
    });

    _learnedPatterns['user_corrections'] = corrections;
    _saveConfig();
  }

  /// Get extraction statistics
  Map<String, dynamic> getStats() {
    return Map<String, dynamic>.from(
      _learnedPatterns['extraction_stats'] as Map<String, dynamic>? ?? {},
    );
  }

  /// Reset learned patterns (for testing)
  void resetLearnedPatterns() {
    _learnedPatterns = {
      'successful_market_matches': <String, dynamic>{},
      'successful_date_patterns': <String>[],
      'successful_sum_patterns': <String>[],
      'successful_item_patterns': <String>[],
      'user_corrections': <Map<String, dynamic>>[],
      'extraction_stats': <String, dynamic>{
        'total_extractions': 0,
        'successful_markets': 0,
        'successful_dates': 0,
        'successful_sums': 0,
        'successful_items': 0,
      },
    };
    _config['learned_patterns'] = _learnedPatterns;
    _saveConfig();
  }

  /// Export current config
  String exportConfig() {
    return const JsonEncoder.withIndent('  ').convert(_config);
  }

  /// Import config
  void importConfig(String jsonConfig) {
    _config = json.decode(jsonConfig);
    _loadLearnedPatterns();
    _saveConfig();
  }
}

/// Result of a single field extraction
class MatchResult {
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

  bool get isHighConfidence => confidence >= AdaptiveFuzzyMatcher.highConfidence;
  bool get isMediumConfidence => confidence >= AdaptiveFuzzyMatcher.mediumConfidence;
  bool get isLowConfidence => confidence >= AdaptiveFuzzyMatcher.lowConfidence;

  Map<String, dynamic> toJson() => {
    'value': value,
    'confidence': confidence,
    'matched_line': matchedLine,
    'pattern_used': patternUsed,
    'field_type': fieldType,
  };
}

/// Result of item extraction
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

/// Container for items extraction result
class ItemsResult {
  final List<ItemMatch> items;
  final double averageConfidence;

  ItemsResult({
    required this.items,
    required this.averageConfidence,
  });

  Map<String, dynamic> toJson() => {
    'items': items.map((i) => i.toJson()).toList(),
    'average_confidence': averageConfidence,
    'count': items.length,
  };
}

/// Complete extraction result
class ExtractionResult {
  final MatchResult market;
  final MatchResult date;
  final MatchResult sum;
  final ItemsResult items;
  final List<String> rawLines;

  ExtractionResult({
    required this.market,
    required this.date,
    required this.sum,
    required this.items,
    required this.rawLines,
  });

  double get overallConfidence {
    final confidences = [
      market.confidence,
      date.confidence,
      sum.confidence,
      items.averageConfidence,
    ].where((c) => c > 0);
    
    if (confidences.isEmpty) return 0.0;
    return confidences.reduce((a, b) => a + b) / confidences.length;
  }

  Map<String, dynamic> toJson() => {
    'market': market.toJson(),
    'date': date.toJson(),
    'sum': sum.toJson(),
    'items': items.toJson(),
    'overall_confidence': overallConfidence,
  };

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== Extraction Result ===');
    buffer.writeln('Market: ${market.value ?? "N/A"} (${(market.confidence * 100).toStringAsFixed(1)}%)');
    buffer.writeln('Date: ${date.value ?? "N/A"} (${(date.confidence * 100).toStringAsFixed(1)}%)');
    buffer.writeln('Sum: ${sum.value ?? "N/A"} (${(sum.confidence * 100).toStringAsFixed(1)}%)');
    buffer.writeln('Items (${items.items.length}):');
    for (final item in items.items) {
      buffer.writeln('  - ${item.name}: \$${item.price.toStringAsFixed(2)} (${(item.confidence * 100).toStringAsFixed(1)}%)');
    }
    buffer.writeln('Overall Confidence: ${(overallConfidence * 100).toStringAsFixed(1)}%');
    return buffer.toString();
  }
}
