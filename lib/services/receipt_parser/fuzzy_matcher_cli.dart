import 'dart:convert';
import 'dart:io';
import 'adaptive_fuzzy_matcher.dart';

/// Interactive CLI for running the adaptive fuzzy matcher
/// with user confirmation for self-improvement
class FuzzyMatcherCLI {
  final AdaptiveFuzzyMatcher matcher;
  final bool interactive;

  FuzzyMatcherCLI({
    required String configPath,
    this.interactive = true,
  }) : matcher = AdaptiveFuzzyMatcher(configPath);

  /// Process a single receipt file
  Future<ExtractionResult> processReceipt(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }

    final lines = file.readAsLinesSync();
    final result = matcher.extractAll(lines);

    if (interactive) {
      await _confirmWithUser(result, filePath);
    }

    return result;
  }

  /// Process multiple receipt files
  Future<List<ExtractionResult>> processReceipts(List<String> filePaths) async {
    final results = <ExtractionResult>[];

    for (final filePath in filePaths) {
      try {
        print('\n${'=' * 60}');
        print('Processing: $filePath');
        print('=' * 60);

        final result = await processReceipt(filePath);
        results.add(result);

        // Save individual result as JSON
        final jsonPath = '$filePath.extraction.json';
        File(jsonPath).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
        );
        print('Saved extraction to: $jsonPath');
      } catch (e) {
        print('Error processing $filePath: $e');
      }
    }

    // Print summary statistics
    _printSummary(results);

    return results;
  }

  Future<void> _confirmWithUser(ExtractionResult result, String filePath) async {
    print('\n${result.toString()}');

    if (result.overallConfidence >= AdaptiveFuzzyMatcher.highConfidence) {
      print('\n✅ High confidence extraction. Auto-confirming...');
      matcher.confirmExtraction(result,
        confirmedMarket: result.market.value,
        confirmedDate: result.date.value,
        confirmedSum: result.sum.value,
        confirmedItems: result.items.items,
      );
      return;
    }

    print('\n📝 Please confirm or correct the extraction:');
    
    // Confirm market
    final confirmedMarket = await _confirmField(
      'Market',
      result.market.value,
      result.market.matchedLine,
    );

    // Confirm date
    final confirmedDate = await _confirmField(
      'Date',
      result.date.value,
      result.date.matchedLine,
    );

    // Confirm sum
    final confirmedSum = await _confirmField(
      'Sum/Total',
      result.sum.value,
      result.sum.matchedLine,
    );

    // Confirm items (simplified - just ask for overall confirmation)
    final itemsConfirmed = await _confirmItems(result.items);

    // Record confirmations and corrections
    if (confirmedMarket != null && confirmedMarket != result.market.value) {
      matcher.recordCorrection(
        fieldType: 'market',
        originalValue: result.market.value ?? '',
        correctedValue: confirmedMarket,
        originalLine: result.market.matchedLine,
      );
    }

    if (confirmedDate != null && confirmedDate != result.date.value) {
      matcher.recordCorrection(
        fieldType: 'date',
        originalValue: result.date.value ?? '',
        correctedValue: confirmedDate,
        originalLine: result.date.matchedLine,
      );
    }

    if (confirmedSum != null && confirmedSum != result.sum.value) {
      matcher.recordCorrection(
        fieldType: 'sum',
        originalValue: result.sum.value ?? '',
        correctedValue: confirmedSum,
        originalLine: result.sum.matchedLine,
      );
    }

    // Confirm extraction to learn patterns
    matcher.confirmExtraction(
      result,
      confirmedMarket: confirmedMarket ?? result.market.value,
      confirmedDate: confirmedDate ?? result.date.value,
      confirmedSum: confirmedSum ?? result.sum.value,
      confirmedItems: itemsConfirmed ? result.items.items : null,
    );

    print('\n✅ Extraction confirmed and patterns learned!');
  }

  Future<String?> _confirmField(
    String fieldName,
    String? currentValue,
    String? matchedLine,
  ) async {
    print('\n$fieldName: ${currentValue ?? "Not found"}');
    if (matchedLine != null) {
      print('  (from line: "$matchedLine")');
    }

    stdout.write('Press Enter to accept, or type correction: ');
    final input = stdin.readLineSync()?.trim();

    if (input == null || input.isEmpty) {
      return currentValue;
    }

    return input;
  }

  Future<bool> _confirmItems(ItemsResult items) async {
    print('\nItems found: ${items.items.length}');
    for (int i = 0; i < items.items.length && i < 5; i++) {
      final item = items.items[i];
      print('  ${i + 1}. ${item.name}: \$${item.price.toStringAsFixed(2)}');
    }
    if (items.items.length > 5) {
      print('  ... and ${items.items.length - 5} more items');
    }

    stdout.write('Are the items correct? (y/n, default: y): ');
    final input = stdin.readLineSync()?.trim().toLowerCase();

    return input != 'n';
  }

  void _printSummary(List<ExtractionResult> results) {
    print('\n${'=' * 60}');
    print('EXTRACTION SUMMARY');
    print('=' * 60);

    int totalReceipts = results.length;
    int successfulMarkets = results.where((r) => r.market.value != null).length;
    int successfulDates = results.where((r) => r.date.value != null).length;
    int successfulSums = results.where((r) => r.sum.value != null).length;
    int receiptsWithItems = results.where((r) => r.items.items.isNotEmpty).length;

    double avgConfidence = results.isEmpty
        ? 0.0
        : results.map((r) => r.overallConfidence).reduce((a, b) => a + b) / results.length;

    print('Total receipts processed: $totalReceipts');
    print('Successful market extractions: $successfulMarkets (${(successfulMarkets / totalReceipts * 100).toStringAsFixed(1)}%)');
    print('Successful date extractions: $successfulDates (${(successfulDates / totalReceipts * 100).toStringAsFixed(1)}%)');
    print('Successful sum extractions: $successfulSums (${(successfulSums / totalReceipts * 100).toStringAsFixed(1)}%)');
    print('Receipts with items: $receiptsWithItems (${(receiptsWithItems / totalReceipts * 100).toStringAsFixed(1)}%)');
    print('Average confidence: ${(avgConfidence * 100).toStringAsFixed(1)}%');

    // Print learned patterns stats
    final stats = matcher.getStats();
    print('\nLearned Patterns Statistics:');
    print('  Total extractions (all time): ${stats['total_extractions'] ?? 0}');
    print('  Successful markets: ${stats['successful_markets'] ?? 0}');
    print('  Successful dates: ${stats['successful_dates'] ?? 0}');
    print('  Successful sums: ${stats['successful_sums'] ?? 0}');
    print('  Successful items: ${stats['successful_items'] ?? 0}');
  }

  /// Batch process receipts non-interactively
  Future<List<ExtractionResult>> batchProcess(String folderPath) async {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      throw FileSystemException('Directory not found', folderPath);
    }

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.txt'))
        .map((f) => f.path)
        .toList();

    print('Found ${files.length} receipt files to process');

    // Use non-interactive mode for batch processing
    final batchCLI = FuzzyMatcherCLI(
      configPath: matcher.exportConfig(),
      interactive: false,
    );

    return batchCLI.processReceipts(files);
  }
}

/// Command-line entry point
void main(List<String> args) async {
  final configPath = args.isNotEmpty
      ? args[0]
      : 'lib/cache/fuzzy_matcher_config.json';

  final cli = FuzzyMatcherCLI(
    configPath: configPath,
    interactive: args.contains('--interactive') || args.contains('-i'),
  );

  // Determine input
  String? inputPath;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--input' || args[i] == '-f') {
      if (i + 1 < args.length) {
        inputPath = args[i + 1];
      }
    }
  }

  // Check for batch mode
  if (args.contains('--batch') || args.contains('-b')) {
    final folderPath = inputPath ?? 'lib/cache/output/cache/output';
    await cli.batchProcess(folderPath);
  } else if (inputPath != null) {
    await cli.processReceipt(inputPath);
  } else {
    // Default: process sample receipts
    final sampleFolder = 'lib/cache/output/cache/output';
    if (Directory(sampleFolder).existsSync()) {
      await cli.batchProcess(sampleFolder);
    } else {
      print('Usage:');
      print('  dart run fuzzy_matcher_cli.dart [config_path] [options]');
      print('');
      print('Options:');
      print('  -i, --interactive  Enable interactive confirmation');
      print('  -b, --batch        Batch process folder');
      print('  -f, --input PATH   Input file or folder path');
    }
  }
}
