import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static const String apiKey = 'YOUR_API_KEY_HERE';
  final model = GenerativeModel(
    model: 'gemini-pro-vision',
    apiKey: apiKey,
  );

  Future<Map<String, dynamic>> processReceiptImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final prompt = 'Extract the following information from this receipt: date, merchant name, total amount, items purchased with their individual prices. Format the response as JSON.';
      
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', bytes),
        ])
      ]);

      final responseText = response.text;
      // Parse the JSON response
      return _parseGeminiResponse(responseText);
    } catch (e) {
      throw Exception('Failed to process receipt: $e');
    }
  }

  Map<String, dynamic> _parseGeminiResponse(String response) {
    // Remove any markdown formatting if present
    final jsonStr = response.replaceAll('```json', '').replaceAll('```', '').trim();
    try {
      return json.decode(jsonStr);
    } catch (e) {
      throw Exception('Failed to parse Gemini response: $e');
    }
  }
}
