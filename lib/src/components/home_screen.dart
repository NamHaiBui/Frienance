import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  File? _selectedImage;
  final picker = ImagePicker();
  final GeminiService _geminiService = GeminiService();

  Future<void> _pickImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _selectedImage = File(pickedFile.path));
      await _sendToGemini(_selectedImage!);
    }
  }

  Future<void> _sendToGemini(File image) async {
    try {
      final result = await _geminiService.processReceiptImage(image);
      // Handle the result as needed
      print('Receipt data: $result');
    } catch (e) {
      print('Error processing receipt: $e');
      // Show error message to user
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home Screen')),
      body: Center(
        child: ElevatedButton(
          onPressed: _pickImage,
          child: Text('Upload Receipt'),
        ),
      ),
    );
  }
}