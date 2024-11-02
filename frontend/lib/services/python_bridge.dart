import 'dart:js' as js;
import 'dart:convert';

class PythonBridge {
  static bool _initialized = false;
  static const int _maxRetries = 10;
  static const Duration _retryDelay = Duration(milliseconds: 1000);

  static js.JsObject? get _pyodide {
    final context = js.context;
    if (!context.hasProperty('pyodideReady') || context['pyodideReady'] != true) {
      return null;
    }
    return context.hasProperty('pyodide') ? js.JsObject.fromBrowserObject(context['pyodide']) : null;
  }

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      int retries = 0;
      while (_pyodide == null) {
        if (retries >= _maxRetries) {
          throw Exception('Pyodide not available after $_maxRetries retries');
        }
        await Future.delayed(_retryDelay);
        retries++;
      }

      // Install dependencies and verify Python environment
      final result = await _pyodide!.callMethod('runPythonAsync', ['''
      import json
      import micropip
      await micropip.install('fuzzywuzzy')
      from fuzzywuzzy import process
      from PIL import Image
      import io
      import base64

      def verify_imports():
          return json.dumps({"status": "ready"})

      print(verify_imports())
      ''']);

      // Convert JsObject to String properly
      final resultStr = js.context['JSON'].callMethod('stringify', [result]);
      final status = json.decode(resultStr);
      
      if (status['status'] != 'ready') {
        throw Exception('Python environment verification failed');
      }

      _initialized = true;
    } catch (e) {
      print('Failed to initialize Python bridge: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> parseReceipt(String imageData) async {
    if (!_initialized) await initialize();
    
    final pythonCode = '''
try:
    result = parse_receipt('$imageData')
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
''';
    
    final result = await _pyodide!.callMethod('runPythonAsync', [pythonCode]);
    final resultStr = js.context['JSON'].callMethod('stringify', [result]);
    final decoded = json.decode(resultStr);
    
    if (decoded is Map && decoded.containsKey('error')) {
      throw Exception(decoded['error']);
    }
    return decoded;
  }

  static Future<List<Map<String, dynamic>>> fuzzySearch(String query, List<Map<String, dynamic>> receipts) async {
    if (!_initialized) await initialize();
    
    final pythonCode = '''
try:
    receipts = ${json.encode(receipts)}
    results = fuzzy_search('$query', receipts)
    json.dumps(results)
except Exception as e:
    json.dumps({"error": str(e)})
''';
    
    final result = await _pyodide!.callMethod('runPython', [pythonCode]);
    final decoded = json.decode(result.toString());
    if (decoded is Map && decoded.containsKey('error')) {
      throw Exception(decoded['error']);
    }
    return List<Map<String, dynamic>>.from(decoded);
  }
}