import 'dart:convert';
import 'dart:io';
import 'object_config.dart';

ObjectView readConfig({String configPath = 'config.json'}) {
  var content = File(configPath).readAsStringSync();
  Map<String, dynamic> jsonMap = jsonDecode(content);
  return ObjectView(jsonMap);
}

void writeConfig(ObjectView config, {String configPath = 'config.json'}) {
  var jsonString = jsonEncode(config.toMap());
  File(configPath).writeAsStringSync(jsonString);
}
