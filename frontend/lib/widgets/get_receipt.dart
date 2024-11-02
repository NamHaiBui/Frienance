import 'package:flutter/material.dart';
import 'package:frienance/services/python_bridge.dart';
import 'package:image_picker_web/image_picker_web.dart';
import 'dart:convert';

class CaptureReceipt extends StatefulWidget {
  final Function(Map<String, dynamic>) addReceipt;

  const CaptureReceipt({super.key, required this.addReceipt});

  @override
  _CaptureReceiptState createState() => _CaptureReceiptState();
}

class _CaptureReceiptState extends State<CaptureReceipt> {
  String _ocrResult = '';
  bool _isProcessing = false;

  Future<void> _captureAndProcessReceipt() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final pickedFile = await ImagePickerWeb.getImageAsBytes();
      if (pickedFile == null) return;

      final base64Image = base64Encode(pickedFile);

      final parsedReceipt = await PythonBridge.parseReceipt(base64Image);
      widget.addReceipt(parsedReceipt);
      setState(() {
        _ocrResult = 'Receipt parsed successfully!';
      });
    } catch (e) {
      print('OCR Error: $e');
      setState(() {
        _ocrResult = 'Error processing image';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Capture Receipt',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _captureAndProcessReceipt,
          child: const Text('Upload Receipt Image'),
        ),
        if (_isProcessing) ...[
          const SizedBox(height: 16),
          const CircularProgressIndicator(),
        ],
        if (_ocrResult.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Result:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(_ocrResult),
        ],
      ],
    );
  }
}