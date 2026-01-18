import 'dart:convert';
import 'dart:io';
import 'package:frienance/services/receipt_parser/object_config.dart' show ObjectView;
import 'package:frienance/services/receipt_parser/receipt.dart' show Receipt;
import 'package:path/path.dart' as path;

void outputStatistics(Map<String, int> stats, String filePath) {
  if (stats.isEmpty || filePath.isEmpty) return;

  try {
    final file = File(filePath);
    final statsString =
        '${DateTime.now().millisecondsSinceEpoch},${stats['total'] ?? 0},${stats['market'] ?? 0},${stats['date'] ?? 0},${stats['sum'] ?? 0}\n';
    file.writeAsStringSync(statsString, mode: FileMode.append);
  } on IOException catch (e) {
    print('Error writing statistics: $e');
  }
}

List<String> getFilesInFolder(String folder, {bool includeHidden = false}) {
  if (folder.isEmpty) return [];

  try {
    final dir = Directory(folder);
    if (!dir.existsSync()) return [];

    final files = dir
        .listSync(recursive: false)
        .where((f) => includeHidden || !path.basename(f.path).startsWith('.'))
        .whereType<File>()
        .map((f) => f.path)
        .toList();

    return files;
  } on FileSystemException catch (e) {
    print('Error reading folder: $e');
    return [];
  }
}

void ocrReceipts(ObjectView config, List<String> receiptFiles) {
  if (receiptFiles.isEmpty) return;

  final stats = <String, int>{
    'total': 0,
    'market': 0,
    'date': 0,
    'sum': 0,
  };

  final tableData = [
    ['Path', 'Market', 'Date', 'Items', 'SUM'],
  ];

  try {
    if (config.resultsAsJson) {
      resultsToJson(config, receiptFiles);
    }

    for (final receiptPath in receiptFiles) {
      try {
        final lines = File(receiptPath).readAsLinesSync();
        final receipt = Receipt(config, lines);

        final itemList = receipt.items?.join('\n') ?? '';

        tableData.add([
          receiptPath,
          receipt.market ?? '',
          receipt.date ?? '',
          itemList,
          receipt.sum ?? '',
        ]);

        _updateStats(stats, receipt);
      } on FileSystemException catch (e) {
        print('Error reading receipt $receiptPath: $e');
      }
    }

    printTable(tableData);
    outputStatistics(stats, 'stats.csv');
  } catch (e) {
    print('Error processing receipts: $e');
  }
}

void _updateStats(Map<String, int> stats, Receipt receipt) {
  stats['total'] = (stats['total'] ?? 0) + 1;

  if (receipt.market?.isNotEmpty == true) {
    stats['market'] = (stats['market'] ?? 0) + 1;
  }
  if (receipt.date?.isNotEmpty == true) {
    stats['date'] = (stats['date'] ?? 0) + 1;
  }
  if (receipt.sum?.isNotEmpty == true) {
    stats['sum'] = (stats['sum'] ?? 0) + 1;
  }
}

void resultsToJson(ObjectView config, List<String> receiptFiles) {
  for (final receiptPath in receiptFiles) {
    try {
      final lines = File(receiptPath).readAsLinesSync();
      final receipt = Receipt(config, lines);
      final outPath = '$receiptPath.json';
      File(outPath).writeAsStringSync(json.encode(receipt.toJson()));
    } on FileSystemException catch (e) {
      print('Error processing JSON for $receiptPath: $e');
    }
  }
}

void printTable(List<List<String>> tableData) {
  if (tableData.isEmpty) return;

  for (final row in tableData) {
    print(row.join('\t'));
  }
}
