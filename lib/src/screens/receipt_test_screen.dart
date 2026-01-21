import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:frienance/services/receipt_parser/receipt_extraction.dart';
import 'package:frienance/utils/logger.dart';

/// A test screen for receipt image processing on mobile devices.
/// 
/// Usage:
/// 1. Pick an image from gallery or capture from camera
/// 2. Watch the processing logs
/// 3. View the processed result
class ReceiptTestScreen extends StatefulWidget {
  const ReceiptTestScreen({super.key});

  @override
  State<ReceiptTestScreen> createState() => _ReceiptTestScreenState();
}

class _ReceiptTestScreenState extends State<ReceiptTestScreen> with Loggable {
  final ImagePicker _picker = ImagePicker();
  
  String? _originalImagePath;
  String? _processedImagePath;
  bool _isProcessing = false;
  String _statusMessage = 'Pick an image to start';
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    logger.i('ReceiptTestScreen initialized');
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      logger.d('Picking image from ${source.name}');
      _addLog('📷 Picking image from ${source.name}...');
      
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
      );

      if (image == null) {
        _addLog('⚠️ No image selected');
        logger.w('No image selected');
        return;
      }

      setState(() {
        _originalImagePath = image.path;
        _processedImagePath = null;
        _statusMessage = 'Image selected: ${image.name}';
      });
      
      _addLog('✅ Image selected: ${image.name}');
      logger.i('Image selected: ${image.path}');

      await _processImage(image.path);
    } catch (e, stackTrace) {
      logger.e('Error picking image', error: e, stackTrace: stackTrace);
      _addLog('❌ Error picking image: $e');
      _showError('Failed to pick image: $e');
    }
  }

  Future<void> _processImage(String imagePath) async {
    if (_isProcessing) {
      logger.w('Already processing an image');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing...';
    });

    _addLog('🔄 Starting receipt extraction...');
    logger.i('Starting receipt extraction for: $imagePath');

    final stopwatch = Stopwatch()..start();

    try {
      final processedPath = await processReceiptImageFromDevice(imagePath);
      stopwatch.stop();

      if (processedPath != null) {
        setState(() {
          _processedImagePath = processedPath;
          _statusMessage = 'Processed in ${stopwatch.elapsedMilliseconds}ms';
        });
        _addLog('✅ Processing complete: ${stopwatch.elapsedMilliseconds}ms');
        _addLog('📁 Output: $processedPath');
        logger.i('Processing complete: $processedPath (${stopwatch.elapsedMilliseconds}ms)');
      } else {
        setState(() {
          _statusMessage = 'Processing failed';
        });
        _addLog('❌ Processing failed - check logs');
        logger.e('Processing returned null');
      }
    } catch (e, stackTrace) {
      stopwatch.stop();
      setState(() {
        _statusMessage = 'Error: $e';
      });
      _addLog('❌ Error: $e');
      logger.e('Processing error', error: e, stackTrace: stackTrace);
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      // Keep only last 50 logs
      if (_logs.length > 50) {
        _logs.removeAt(0);
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
      _originalImagePath = null;
      _processedImagePath = null;
      _statusMessage = 'Pick an image to start';
    });
    logger.d('Logs cleared');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt Processing Test'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearLogs,
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isProcessing 
                ? Colors.orange.shade100 
                : (_processedImagePath != null ? Colors.green.shade100 : Colors.grey.shade100),
            child: Row(
              children: [
                if (_isProcessing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_isProcessing) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          // Image preview section
          Expanded(
            flex: 2,
            child: Row(
              children: [
                // Original image
                Expanded(
                  child: _buildImagePreview(
                    'Original',
                    _originalImagePath,
                    Colors.blue,
                  ),
                ),
                // Processed image
                Expanded(
                  child: _buildImagePreview(
                    'Processed',
                    _processedImagePath,
                    Colors.green,
                  ),
                ),
              ],
            ),
          ),

          // Logs section
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LOGS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[_logs.length - 1 - index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            log,
                            style: TextStyle(
                              color: log.contains('❌') 
                                  ? Colors.red.shade300 
                                  : log.contains('✅') 
                                      ? Colors.green.shade300 
                                      : Colors.white70,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(String label, String? imagePath, Color accentColor) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
          ),
          Expanded(
            child: imagePath != null
                ? ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        logger.e('Error loading image preview', error: error);
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image, color: Colors.grey.shade400),
                              const SizedBox(height: 4),
                              Text(
                                'Failed to load',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  )
                : Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 40,
                      color: Colors.grey.shade300,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
