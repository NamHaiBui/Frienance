import 'dart:io';

import 'package:frienance/services/parser/config.dart';
import 'package:frienance/services/parser/parse.dart';

void main() {
  var config = readConfig();
  var receiptFiles = getFilesInFolder("./lib/cache/1_source_img");
  ocrReceipts(config, receiptFiles);
  
}

List<String> getFilesInFolder(String folderPath) {
  return Directory(folderPath)
      .listSync()
      .where((entity) => entity is File && !(entity).path.startsWith('.'))
      .map((entity) => entity.path)
      .toList();
}
