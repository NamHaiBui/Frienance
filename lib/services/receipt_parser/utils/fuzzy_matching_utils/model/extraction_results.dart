import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/match_result.dart';

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