import 'dart:convert';

class ObjectView {
  final Map<String, dynamic> _map;

  ObjectView(this._map) {
    _validateConfig();
  }

  factory ObjectView.fromJson(String jsonString) {
    return ObjectView(json.decode(jsonString));
  }

  void _validateConfig() {
    final requiredFields = ['markets', 'date_format', 'sum_format', 'sum_keys'];
    final missingFields = requiredFields.where((field) => !_map.containsKey(field));
    
    if (missingFields.isNotEmpty) {
      throw FormatException(
          'Invalid config format: missing required fields: ${missingFields.join(", ")}');
    }

    if (_map['markets'] is! Map) {
      throw FormatException('Invalid config format: markets must be a Map');
    }
  }

  Map<String, List<String>> get markets {
    try {
      final markets = _map['markets'] as Map<String, dynamic>;
      return Map.fromEntries(
        markets.entries.map((e) => MapEntry(
          e.key,
          (e.value as List).cast<String>(),
        )),
      );
    } catch (e) {
      throw FormatException('Invalid markets format: $e');
    }
  }

  String get dateFormat => _map['date_format'] as String;
  String get sumFormat => _map['sum_format'] as String;
  List<String> get sumKeys => (_map['sum_keys'] as List).cast<String>();

  bool get resultsAsJson => _map['results_as_json'] as bool? ?? false;

  List<String> getConfigList(String key, String market) {
    try {
      final customKey = '${key}_${market.toLowerCase()}';
      final value = _map[customKey] ?? _map[key];
      if (value == null) return [];
      return (value as List).cast<String>();
    } catch (e) {
      print('Error getting config list for $key: $e');
      return [];
    }
  }

  String getConfigString(String key, String market) {
    try {
      final customKey = '${key}_${market.toLowerCase()}';
      final value = _map[customKey] ?? _map[key];
      return value?.toString() ?? '';
    } catch (e) {
      print('Error getting config string for $key: $e');
      return '';
    }
  }

  String toJson() => json.encode(_map);
  Map<String, dynamic> toMap() => Map<String, dynamic>.from(_map);
}
