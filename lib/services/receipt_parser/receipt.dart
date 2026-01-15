import 'dart:convert';
import 'object_config.dart';

class Receipt {
  ObjectView config;
  String? market;
  String? date;
  String? sum;
  List<Item>? items;
  List<String> lines;

  Receipt(this.config, this.lines) {
    normalize();
    parse();
  }

  // Factory constructor from JSON config
  factory Receipt.fromJson(String jsonConfig, List<String> lines) {
    return Receipt(ObjectView.fromJson(jsonConfig), lines);
  }

  void normalize() {
    lines = lines
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.toLowerCase())
        .toList();
  }

  void parse() {
    market = parseMarket();
    date = parseDate();
    sum = parseSum();
    items = parseItems();
  }

  String? fuzzyFind(String keyword, [double accuracy = 0.6]) {
    for (var line in lines) {
      List<String> words = line.split(' ');
      List<String> matches = getCloseMatches(keyword, words, 1, accuracy);
      if (matches.isNotEmpty) {
        return line;
      }
    }
    return null;
  }

  List<String> getCloseMatches(
      String word, List<String> possibilities, int n, double cutoff) {
    List<_Match> matches = [];

    for (String candidate in possibilities) {
      double ratio =
          _calculateSimilarity(word.toLowerCase(), candidate.toLowerCase());
      if (ratio >= cutoff) {
        matches.add(_Match(candidate, ratio));
      }
    }

    matches.sort((a, b) => b.ratio.compareTo(a.ratio));
    return matches.take(n).map((m) => m.word).toList();
  }

  String? parseMarket() {
    for (int intAccuracy = 10; intAccuracy > 6; intAccuracy--) {
      double accuracy = intAccuracy / 10.0;
      double minAccuracy = -1;
      String? marketMatch;

      config.markets.forEach((market, spellings) {
        for (String spelling in spellings) {
          String? line = fuzzyFind(spelling, accuracy);
          if (line != null && (accuracy < minAccuracy || minAccuracy == -1)) {
            minAccuracy = accuracy;
            marketMatch = market;
          }
        }
      });

      if (marketMatch != null) return marketMatch;
    }
    return '';
  }

  String? parseDate() {
    for (String line in lines) {
      RegExpMatch? match = RegExp(config.dateFormat).firstMatch(line);
      if (match != null) {
        return match.group(0)?.replaceAll(' ', '');
      }
    }
    return null;
  }

  List<Item> parseItems() {
    List<Item> items = [];
    List<String> ignoredWords =
        config.getConfigList('ignore_keys', market ?? '');
    List<String> stopWords = config.getConfigList('sum_keys', market ?? '');
    String itemFormat = config.getConfigString('item_format', market ?? '');

    for (String line in lines) {
      bool parseStop = false;

      for (String ignoreWord in ignoredWords) {
        if (_matchPattern(line, '*$ignoreWord*')) {
          parseStop = true;
          break;
        }
      }

      if (parseStop) continue;

      if (market != 'LanThai') {
        for (String stopWord in stopWords) {
          if (_matchPattern(line, '*$stopWord*')) {
            return items;
          }
        }
      }

      RegExpMatch? match = RegExp(itemFormat).firstMatch(line);
      if (match != null) {
        String itemWithP = match.group(0)!;
        List<String> parts = itemWithP.split(' ');
        String itemP = parts.last;
        String itemName = parts.sublist(0, parts.length - 2).join(' ');
        items.add(Item(itemName, double.parse(itemP)));
      }
    }

    return items;
  }

  String? parseSum() {
    for (String sumKey in config.sumKeys) {
      String? sumLine = fuzzyFind(sumKey);
      if (sumLine != null) {
        sumLine = sumLine.replaceAll(',', '.');
        RegExpMatch? sumFloat = RegExp(config.sumFormat).firstMatch(sumLine);
        if (sumFloat != null) {
          return sumFloat.group(0);
        }
      }
    }
    return null;
  }

  // Convert receipt to JSON
  Map<String, dynamic> toJson() {
    return {
      'market': market,
      'date': date,
      'sum': sum,
      'items': items?.map((item) => item.toJson()).toList(),
      'config': json.decode(config.toJson())
    };
  }

  double _calculateSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1 == s2) return 1.0;

    int matches = 0;
    int length = s1.length < s2.length ? s1.length : s2.length;

    for (int i = 0; i < length; i++) {
      if (s1[i] == s2[i]) matches++;
    }

    return matches / s1.length;
  }

  bool _matchPattern(String text, String pattern) {
    pattern = pattern.replaceAll('*', '.*');
    return RegExp(pattern).hasMatch(text);
  }
}

class Item {
  final String name;
  final double price;

  Item(this.name, this.price);

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
}

class _Match {
  final String word;
  final double ratio;

  _Match(this.word, this.ratio);
}

class ReceiptParseException implements Exception {
  final String message;
  ReceiptParseException(this.message);

  @override
  String toString() => 'ReceiptParseException: $message';
}

class ParseResult {
  final bool success;
  final String? error;
  final Receipt? receipt;

  ParseResult({
    required this.success,
    this.error,
    this.receipt,
  });

  factory ParseResult.success(Receipt receipt) {
    return ParseResult(success: true, receipt: receipt);
  }

  factory ParseResult.failure(String error) {
    return ParseResult(success: false, error: error);
  }
}
