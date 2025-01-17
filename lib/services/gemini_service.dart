import 'dart:convert';
import 'dart:io';
import 'package:frienance/services/parser/receipt.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static const String apiKey = 'YOUR_API_KEY_HERE';
  final model = GenerativeModel(
    model: 'gemini-2.0-flash-exp',
    apiKey: apiKey,
    generationConfig: GenerationConfig(
      temperature: 1,
      topK: 40,
      topP: 0.95,
      maxOutputTokens: 8192,
      // responseMimeType: 'text/plain',
    ),
  );

  Future<Map<String, dynamic>> processReceiptImage(File imageFile) async {
    try {
      final apiKey = Platform.environment['GEMINI_API_KEY'];
      if (apiKey == null) {
        stderr.writeln(r'No $GEMINI_API_KEY environment variable');
        exit(1);
      }

      final prompt =
          'Confirm that the image is a receipt and then, else, return an error JSON.\nExtract all information from the image.\nReturn the extracted information in a JSON modelling:\nstore_name            STRING\nstore_address         STRING\nstore_phone           STRING (###) ###-#### \nstore_number          INTEGER\nopen_hours            STRING\nitems                 ARRAY of OBJECTS\n  description          STRING\n  price               DECIMAL (2 decimal places)\nsubtotal              DECIMAL (2 decimal places) \ntotal                 DECIMAL (2 decimal places)\ncash                  DECIMAL (2 decimal places)\nchange                DECIMAL (2 decimal places)\nitems_count           INTEGER\ndate                  DATE (MM-DD-YYYY)\ntime                  TIME (HH:MM AM/PM) \nemployee              STRING\nwebsite               STRING (URL)';

      final bytes = await imageFile.readAsBytes();
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', bytes),
        ])
      ]);

      final responseText = response.text ?? "";
      // Parse the JSON response
      return _parseGeminiResponse(responseText);
    } catch (e) {
      throw Exception('Failed to process receipt: $e');
    }
  }

  Map<String, dynamic> _parseGeminiResponse(String response) {
    // Remove any markdown formatting if present
    final jsonStr =
        response.replaceAll('```json', '').replaceAll('```', '').trim();
    try {
      return jsonDecode(jsonStr);
    } catch (e) {
      throw Exception('Failed to parse Gemini response: $e');
    }
  }
}
