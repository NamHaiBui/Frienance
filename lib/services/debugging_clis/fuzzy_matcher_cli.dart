// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/constants/base_configs.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/extraction_results.dart';
import 'package:frienance/utils/logger.dart';

import '../receipt_parser/adaptive_fuzzy_matcher.dart';

/// Interactive CLI for running the adaptive fuzzy matcher
/// with user confirmation for self-improvement
class FuzzyMatcherCLI with Loggable{
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
        ('\n${'=' * 60}');
        logger.v('Processing: $filePath');
        logger.v('=' * 60);

        final result = await processReceipt(filePath);
        results.add(result);

        // Save individual result as JSON
        final jsonPath = '$filePath.extraction.json';
        File(jsonPath).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
        );
        logger.v('Saved extraction to: $jsonPath');
      } catch (e) {
        logger.v('Error processing $filePath: $e');
      }
    }

    // Print summary statistics
    _printSummary(results);

    return results;
  }

  Future<void> _confirmWithUser(ExtractionResult result, String filePath) async {
    logger.v('\n${result.toString()}');

    if (result.overallConfidence >= FuzzyMatchingConfidence.high.value) {
      logger.v('\n✅ High confidence extraction. Auto-confirming...');
      matcher.confirmExtraction(result,
        confirmedMarket: result.market.value,
        confirmedDate: result.date.value,
        confirmedSum: result.sum.value,
        confirmedItems: result.items.items,
      );
      return;
    }

    logger.v('\n📝 Please confirm or correct the extraction:');
    
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

    logger.v('\n✅ Extraction confirmed and patterns learned!');
  }

  Future<String?> _confirmField(
    String fieldName,
    String? currentValue,
    String? matchedLine,
  ) async {
    logger.v('\n$fieldName: ${currentValue ?? "Not found"}');
    if (matchedLine != null) {
      logger.v('  (from line: "$matchedLine")');
    }

    stdout.write('Press Enter to accept, or type correction: ');
    final input = stdin.readLineSync()?.trim();

    if (input == null || input.isEmpty) {
      return currentValue;
    }

    return input;
  }

  Future<bool> _confirmItems(ItemsResult items) async {
    logger.v('\nItems found: ${items.items.length}');
    for (int i = 0; i < items.items.length && i < 5; i++) {
      final item = items.items[i];
      logger.v('  ${i + 1}. ${item.name}: \$${item.price.toStringAsFixed(2)}');
    }
    if (items.items.length > 5) {
      logger.v('  ... and ${items.items.length - 5} more items');
    }

    stdout.write('Are the items correct? (y/n, default: y): ');
    final input = stdin.readLineSync()?.trim().toLowerCase();

    return input != 'n';
  }

  void _printSummary(List<ExtractionResult> results) {
    logger.v('\n${'=' * 60}');
    logger.v('EXTRACTION SUMMARY');
    logger.v('=' * 60);

    int totalReceipts = results.length;
    int successfulMarkets = results.where((r) => r.market.value != null).length;
    int successfulDates = results.where((r) => r.date.value != null).length;
    int successfulSums = results.where((r) => r.sum.value != null).length;
    int receiptsWithItems = results.where((r) => r.items.items.isNotEmpty).length;

    double avgConfidence = results.isEmpty
        ? 0.0
        : results.map((r) => r.overallConfidence).reduce((a, b) => a + b) / results.length;

    logger.v('Total receipts processed: $totalReceipts');
    logger.v('Successful market extractions: $successfulMarkets (${(successfulMarkets / totalReceipts * 100).toStringAsFixed(1)}%)');
    logger.v('Successful date extractions: $successfulDates (${(successfulDates / totalReceipts * 100).toStringAsFixed(1)}%)');
    logger.v('Successful sum extractions: $successfulSums (${(successfulSums / totalReceipts * 100).toStringAsFixed(1)}%)');
    logger.v('Receipts with items: $receiptsWithItems (${(receiptsWithItems / totalReceipts * 100).toStringAsFixed(1)}%)');
    logger.v('Average confidence: ${(avgConfidence * 100).toStringAsFixed(1)}%');

    // Print learned patterns stats
    final stats = matcher.getStats();
    logger.v('\nLearned Patterns Statistics:');
    logger.v('  Total extractions (all time): ${stats['total_extractions'] ?? 0}');
    logger.v('  Successful markets: ${stats['successful_markets'] ?? 0}');
    logger.v('  Successful dates: ${stats['successful_dates'] ?? 0}');
    logger.v('  Successful sums: ${stats['successful_sums'] ?? 0}');
    logger.v('  Successful items: ${stats['successful_items'] ?? 0}');
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

    logger.v('Found ${files.length} receipt files to process');

    // Use non-interactive mode for batch processing
    final batchCLI = FuzzyMatcherCLI(
      configPath: matcher.exportConfig(),
      interactive: false,
    );

    return batchCLI.processReceipts(files);
  }

  // ==========================================
  // STORE/RESTAURANT MANAGEMENT CLI
  // ==========================================

  /// Interactive prompt to add a new store/restaurant.
  Future<bool> addStoreInteractive() async {
    logger.v('\n${'=' * 60}');
    logger.v('ADD NEW STORE/RESTAURANT');
    logger.v('=' * 60);

    stdout.write('\nEnter store/restaurant name: ');
    final name = stdin.readLineSync()?.trim();
    if (name == null || name.isEmpty) {
      logger.v('❌ Name cannot be empty.');
      return false;
    }

    // Check if already exists
    if (matcher.hasStore(name)) {
      logger.v('⚠️  Store "$name" already exists. Do you want to add more spellings? (y/n): ');
      final addMore = stdin.readLineSync()?.trim().toLowerCase();
      if (addMore != 'y') return false;
    }

    logger.v('\nEnter spelling variations (comma-separated, or press Enter to skip):');
    logger.v('  Example: chipotle mexican grill, chipolte, chipotles');
    stdout.write('> ');
    final spellingsInput = stdin.readLineSync()?.trim() ?? '';
    
    final spellings = spellingsInput.isEmpty
        ? <String>[]
        : spellingsInput.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    // Always include the name itself
    if (!spellings.any((s) => s.toLowerCase() == name.toLowerCase())) {
      spellings.insert(0, name.toLowerCase());
    }

    logger.v('\nSelect category (or press Enter to skip):');
    logger.v('  1. fast_food');
    logger.v('  2. casual_dining');
    logger.v('  3. coffee_shop');
    logger.v('  4. grocery');
    logger.v('  5. Other (specify)');
    stdout.write('> ');
    final categoryChoice = stdin.readLineSync()?.trim() ?? '';

    String? category;
    switch (categoryChoice) {
      case '1':
        category = 'fast_food';
        break;
      case '2':
        category = 'casual_dining';
        break;
      case '3':
        category = 'coffee_shop';
        break;
      case '4':
        category = 'grocery';
        break;
      case '5':
        stdout.write('Enter category name: ');
        category = stdin.readLineSync()?.trim();
        break;
    }

    final success = matcher.addStore(
      name: name,
      spellings: spellings,
      category: category,
    );

    if (success) {
      logger.v('\n✅ Store "$name" added successfully with ${spellings.length} spelling(s).');
      if (category != null) logger.v('   Category: $category');
    } else {
      logger.v('\n❌ Failed to add store.');
    }

    return success;
  }

  /// Interactive prompt to add multiple stores at once.
  Future<int> addStoresBulkInteractive() async {
    logger.v('\n${'=' * 60}');
    logger.v('BULK ADD STORES/RESTAURANTS');
    logger.v('=' * 60);

    logger.v('\nEnter stores in the format: name:spelling1,spelling2,spelling3');
    logger.v('One store per line. Enter an empty line when done.');
    logger.v('Example:');
    logger.v('  chipotle:chipotle mexican grill,chipolte');
    logger.v('  subway:sub way,subs');
    logger.v('');

    final stores = <String, List<String>>{};
    
    while (true) {
      stdout.write('> ');
      final line = stdin.readLineSync()?.trim() ?? '';
      if (line.isEmpty) break;

      final parts = line.split(':');
      if (parts.length < 2) {
        // No spellings provided, use name as only spelling
        stores[parts[0].trim()] = [parts[0].trim().toLowerCase()];
      } else {
        final name = parts[0].trim();
        final spellings = parts[1].split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        if (!spellings.any((s) => s.toLowerCase() == name.toLowerCase())) {
          spellings.insert(0, name.toLowerCase());
        }
        stores[name] = spellings;
      }
    }

    if (stores.isEmpty) {
      logger.v('No stores to add.');
      return 0;
    }

    logger.v('\nSelect category for all stores (or press Enter to skip):');
    logger.v('  1. fast_food');
    logger.v('  2. casual_dining');
    logger.v('  3. coffee_shop');
    logger.v('  4. grocery');
    logger.v('  5. Other (specify)');
    stdout.write('> ');
    final categoryChoice = stdin.readLineSync()?.trim() ?? '';

    String? category;
    switch (categoryChoice) {
      case '1':
        category = 'fast_food';
        break;
      case '2':
        category = 'casual_dining';
        break;
      case '3':
        category = 'coffee_shop';
        break;
      case '4':
        category = 'grocery';
        break;
      case '5':
        stdout.write('Enter category name: ');
        category = stdin.readLineSync()?.trim();
        break;
    }

    final added = matcher.addStores(stores, category: category);
    logger.v('\n✅ Added $added store(s) successfully.');
    return added;
  }

  /// Interactive prompt to load preset stores.
  Future<int> loadPresetsInteractive() async {
    logger.v('\n${'=' * 60}');
    logger.v('LOAD PRESET STORES');
    logger.v('=' * 60);

    logger.v('\nSelect which presets to load:');
    logger.v('  1. Fast Food Restaurants');
    logger.v('  2. Casual Dining Restaurants');
    logger.v('  3. Coffee Shops');
    logger.v('  4. Grocery Stores');
    logger.v('  5. All of the above');
    logger.v('  0. Cancel');
    stdout.write('> ');
    
    final choice = stdin.readLineSync()?.trim() ?? '';
    int added = 0;

    switch (choice) {
      case '1':
        added = matcher.addFastFoodRestaurants();
        logger.v('✅ Added $added fast food restaurants.');
        break;
      case '2':
        added = matcher.addCasualDiningRestaurants();
        logger.v('✅ Added $added casual dining restaurants.');
        break;
      case '3':
        added = matcher.addCoffeeShops();
        logger.v('✅ Added $added coffee shops.');
        break;
      case '4':
        added = matcher.addGroceryStores();
        logger.v('✅ Added $added grocery stores.');
        break;
      case '5':
        added = matcher.addAllPresets();
        logger.v('✅ Added $added total stores from all presets.');
        break;
      default:
        logger.v('Cancelled.');
    }

    return added;
  }

  /// Interactive prompt to search and view stores.
  Future<void> searchStoresInteractive() async {
    logger.v('\n${'=' * 60}');
    logger.v('SEARCH STORES');
    logger.v('=' * 60);

    stdout.write('\nEnter search query: ');
    final query = stdin.readLineSync()?.trim() ?? '';
    if (query.isEmpty) {
      logger.v('No query provided.');
      return;
    }

    final matches = matcher.searchStores(query, threshold: 0.3);

    if (matches.isEmpty) {
      logger.v('No stores found matching "$query".');
      return;
    }

    logger.v('\nFound ${matches.length} matching store(s):');
    for (int i = 0; i < matches.length && i < 10; i++) {
      final match = matches[i];
      final spellings = matcher.getSpellings(match.key) ?? [];
      final category = matcher.getStoreCategory(match.key);
      
      logger.v('  ${i + 1}. ${match.key} (${(match.value * 100).toStringAsFixed(1)}% match)');
      logger.v('     Spellings: ${spellings.take(5).join(", ")}${spellings.length > 5 ? "..." : ""}');
      if (category != null) logger.v('     Category: $category');
    }

    if (matches.length > 10) {
      logger.v('  ... and ${matches.length - 10} more');
    }
  }

  /// Interactive prompt to view all stores.
  Future<void> listStoresInteractive() async {
    logger.v('\n${'=' * 60}');
    logger.v('ALL STORES/RESTAURANTS');
    logger.v('=' * 60);

    final stores = matcher.getStores();
    final categories = matcher.getCategories();

    if (stores.isEmpty) {
      logger.v('\nNo stores configured.');
      return;
    }

    // Group by category
    if (categories.isNotEmpty) {
      for (final category in categories) {
        final categoryStores = matcher.getStoresInCategory(category);
        if (categoryStores.isEmpty) continue;

        logger.v('\n📁 $category (${categoryStores.length} stores):');
        for (final store in categoryStores) {
          final spellings = stores[store] ?? [];
          logger.v('   • $store: ${spellings.take(3).join(", ")}${spellings.length > 3 ? "..." : ""}');
        }
      }

      // Uncategorized stores
      final categorizedStores = categories.expand((c) => matcher.getStoresInCategory(c)).toSet();
      final uncategorized = stores.keys.where((s) => s != 'default' && !categorizedStores.contains(s)).toList();
      if (uncategorized.isNotEmpty) {
        logger.v('\n📁 Uncategorized (${uncategorized.length} stores):');
        for (final store in uncategorized) {
          final spellings = stores[store] ?? [];
          logger.v('   • $store: ${spellings.take(3).join(", ")}${spellings.length > 3 ? "..." : ""}');
        }
      }
    } else {
      logger.v('\nTotal: ${stores.length - 1} stores (excluding default)');
      for (final entry in stores.entries) {
        if (entry.key == 'default') continue;
        logger.v('   • ${entry.key}: ${entry.value.take(3).join(", ")}${entry.value.length > 3 ? "..." : ""}');
      }
    }

    logger.v('\nTotal stores: ${stores.length - 1}');
  }

  /// Interactive prompt to remove a store.
  Future<bool> removeStoreInteractive() async {
    logger.v('\n${'=' * 60}');
    logger.v('REMOVE STORE');
    logger.v('=' * 60);

    stdout.write('\nEnter store name to remove: ');
    final name = stdin.readLineSync()?.trim() ?? '';
    if (name.isEmpty) {
      logger.v('No name provided.');
      return false;
    }

    if (!matcher.hasStore(name)) {
      logger.v('❌ Store "$name" not found.');
      
      // Suggest similar stores
      final suggestions = matcher.searchStores(name, threshold: 0.4);
      if (suggestions.isNotEmpty) {
        logger.v('Did you mean: ${suggestions.take(3).map((e) => e.key).join(", ")}?');
      }
      return false;
    }

    stdout.write('Are you sure you want to remove "$name"? (y/n): ');
    final confirm = stdin.readLineSync()?.trim().toLowerCase();
    if (confirm != 'y') {
      logger.v('Cancelled.');
      return false;
    }

    stdout.write('Also remove learned patterns for this store? (y/n): ');
    final removePatterns = stdin.readLineSync()?.trim().toLowerCase() == 'y';

    final success = matcher.removeStore(name, removeLearnedPatterns: removePatterns);
    if (success) {
      logger.v('✅ Store "$name" removed successfully.');
    } else {
      logger.v('❌ Failed to remove store.');
    }
    return success;
  }

  /// Main interactive menu for store management.
  Future<void> storeManagementMenu() async {
    while (true) {
      logger.v('\n${'=' * 60}');
      logger.v('STORE/RESTAURANT MANAGEMENT');
      logger.v('=' * 60);
      logger.v('  1. Add new store/restaurant');
      logger.v('  2. Bulk add stores');
      logger.v('  3. Load preset stores');
      logger.v('  4. Search stores');
      logger.v('  5. List all stores');
      logger.v('  6. Remove a store');
      logger.v('  0. Back to main menu');
      stdout.write('\nSelect option: ');

      final choice = stdin.readLineSync()?.trim() ?? '';

      switch (choice) {
        case '1':
          await addStoreInteractive();
          break;
        case '2':
          await addStoresBulkInteractive();
          break;
        case '3':
          await loadPresetsInteractive();
          break;
        case '4':
          await searchStoresInteractive();
          break;
        case '5':
          await listStoresInteractive();
          break;
        case '6':
          await removeStoreInteractive();
          break;
        case '0':
          return;
        default:
          logger.v('Invalid option.');
      }
    }
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

  // Check for store management mode
  if (args.contains('--stores') || args.contains('-s')) {
    await cli.storeManagementMenu();
    return;
  }

  // Check for add-store mode
  if (args.contains('--add-store')) {
    await cli.addStoreInteractive();
    return;
  }

  // Check for list-stores mode
  if (args.contains('--list-stores')) {
    await cli.listStoresInteractive();
    return;
  }

  // Check for load-presets mode
  if (args.contains('--load-presets')) {
    final added = cli.matcher.addAllPresets();
    print('✅ Loaded $added preset stores.');
    return;
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
      print('  -s, --stores       Store/restaurant management menu');
      print('  --add-store        Add a new store interactively');
      print('  --list-stores      List all configured stores');
      print('  --load-presets     Load all preset stores (fast food, restaurants, etc.)');
    }
  }
}
