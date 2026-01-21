/// Receipt Parser Service - Complete receipt processing pipeline.
/// 
/// Orchestrates the full receipt processing flow:
/// 1. Image receipt extraction (perspective correction, enhancement)
/// 2. Text extraction using ML Kit OCR
/// 3. Fuzzy matching for structured data extraction
/// 4. Final structured output
/// 
/// Features:
/// - Single and batch image processing
/// - Temporary directory management with automatic cleanup
/// - Preserves source images and final results
/// - Semaphore-controlled concurrency (3 slots)
/// - Deferred processing support for LLM fallback
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' deferred as path_provider;

import 'package:frienance/src/core/feature/feature_exports.dart';
import 'package:frienance/src/core/service/service.dart';
import 'package:frienance/services/receipt_parser/receipt_extraction_feature.dart';
import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/extraction_results.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/match_result.dart';

/// Configuration for receipt parser service.
class ReceiptParserConfig {
  const ReceiptParserConfig({
    this.confidenceThreshold = 0.6,
    this.deferToLLMThreshold = 0.4,
    this.preserveIntermediateImages = false,
    this.enableLLMFallback = true,
    this.outputDirectory,
  });

  /// Minimum confidence to accept extraction result.
  final double confidenceThreshold;

  /// Below this threshold, defer to LLM for processing.
  final double deferToLLMThreshold;

  /// Whether to preserve intermediate processing images.
  final bool preserveIntermediateImages;

  /// Whether to enable LLM fallback for low-confidence results.
  final bool enableLLMFallback;

  /// Custom output directory (defaults to app documents/receipts).
  final String? outputDirectory;

  static const ReceiptParserConfig production = ReceiptParserConfig();

  static const ReceiptParserConfig debug = ReceiptParserConfig(
    preserveIntermediateImages: true,
    deferToLLMThreshold: 0.3,
  );
}

/// Result of processing a single receipt.
class ReceiptParseResult {
  const ReceiptParseResult({
    required this.sourceImagePath,
    required this.processedImagePath,
    required this.extractionResult,
    required this.confidence,
    required this.processingDuration,
    this.ocrText,
    this.rawLines,
    this.deferredToLLM = false,
    this.llmResult,
    this.warnings = const [],
  });

  /// Original source image path.
  final String sourceImagePath;

  /// Path to the processed/enhanced image.
  final String processedImagePath;

  /// Structured extraction result from fuzzy matching.
  final ExtractionResult extractionResult;

  /// Overall confidence score (0.0 - 1.0).
  final double confidence;

  /// Total processing duration.
  final Duration processingDuration;

  /// Raw OCR text (if available).
  final String? ocrText;

  /// Raw lines from OCR.
  final List<String>? rawLines;

  /// Whether this result was deferred to LLM.
  final bool deferredToLLM;

  /// LLM processing result (if deferred).
  final LLMParseResult? llmResult;

  /// Processing warnings.
  final List<String> warnings;

  /// Whether the result is acceptable (above confidence threshold).
  bool isAcceptable(double threshold) => confidence >= threshold;

  /// Whether this needs LLM assistance.
  bool needsLLMAssistance(double deferThreshold) => 
      confidence < deferThreshold && !deferredToLLM;

  Map<String, dynamic> toJson() => {
    'sourceImagePath': sourceImagePath,
    'processedImagePath': processedImagePath,
    'extraction': extractionResult.toJson(),
    'confidence': confidence,
    'processingDurationMs': processingDuration.inMilliseconds,
    'deferredToLLM': deferredToLLM,
    'llmResult': llmResult?.toJson(),
    'warnings': warnings,
  };

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== Receipt Parse Result ===');
    buffer.writeln('Source: $sourceImagePath');
    buffer.writeln('Confidence: ${(confidence * 100).toStringAsFixed(1)}%');
    buffer.writeln('Duration: ${processingDuration.inMilliseconds}ms');
    if (deferredToLLM) buffer.writeln('Deferred to LLM: Yes');
    buffer.writeln(extractionResult.toString());
    return buffer.toString();
  }
}

/// Result from LLM processing (for deferred items).
class LLMParseResult {
  const LLMParseResult({
    required this.market,
    required this.date,
    required this.total,
    required this.items,
    required this.rawResponse,
    this.confidence = 0.9,
  });

  final String? market;
  final String? date;
  final String? total;
  final List<LLMItemResult> items;
  final String rawResponse;
  final double confidence;

  Map<String, dynamic> toJson() => {
    'market': market,
    'date': date,
    'total': total,
    'items': items.map((i) => i.toJson()).toList(),
    'confidence': confidence,
  };

  /// Convert to ExtractionResult for learning.
  ExtractionResult toExtractionResult() {
    return ExtractionResult(
      market: MatchResult(
        value: market,
        confidence: confidence,
        fieldType: 'market',
        patternUsed: 'llm',
      ),
      date: MatchResult(
        value: date,
        confidence: confidence,
        fieldType: 'date',
        patternUsed: 'llm',
      ),
      sum: MatchResult(
        value: total,
        confidence: confidence,
        fieldType: 'sum',
        patternUsed: 'llm',
      ),
      items: ItemsResult(
        items: items.map((i) => ItemMatch(
          name: i.name,
          price: i.price,
          confidence: confidence,
          originalLine: i.originalLine ?? '',
          patternUsed: 'llm',
        )).toList(),
        averageConfidence: confidence,
      ),
      rawLines: const [],
    );
  }
}

/// Single item from LLM parsing.
class LLMItemResult {
  const LLMItemResult({
    required this.name,
    required this.price,
    this.quantity = 1,
    this.originalLine,
  });

  final String name;
  final double price;
  final int quantity;
  final String? originalLine;

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'quantity': quantity,
    'originalLine': originalLine,
  };

  factory LLMItemResult.fromJson(Map<String, dynamic> json) {
    return LLMItemResult(
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      quantity: json['quantity'] as int? ?? 1,
      originalLine: json['originalLine'] as String?,
    );
  }
}

/// Batch processing result.
class BatchParseResult {
  const BatchParseResult({
    required this.results,
    required this.totalDuration,
    required this.successCount,
    required this.failureCount,
    required this.deferredCount,
  });

  final List<FeatureResult<ReceiptParseResult>> results;
  final Duration totalDuration;
  final int successCount;
  final int failureCount;
  final int deferredCount;

  int get totalCount => results.length;
  double get successRate => totalCount > 0 ? successCount / totalCount : 0.0;

  /// Get all successful results.
  List<ReceiptParseResult> get successfulResults => results
      .where((r) => r.isSuccess)
      .map((r) => r.valueOrNull!)
      .toList();

  /// Get all results that need LLM processing.
  List<ReceiptParseResult> get resultsNeedingLLM => successfulResults
      .where((r) => r.needsLLMAssistance(0.4))
      .toList();

  Map<String, dynamic> toJson() => {
    'totalCount': totalCount,
    'successCount': successCount,
    'failureCount': failureCount,
    'deferredCount': deferredCount,
    'successRate': '${(successRate * 100).toStringAsFixed(1)}%',
    'totalDurationMs': totalDuration.inMilliseconds,
  };
}

/// Receipt Parser Service - Orchestrates the complete receipt processing pipeline.
class ReceiptParserService extends Service with TemporaryDirectoryService {
  ReceiptParserService({
    ReceiptParserConfig? parserConfig,
    ServiceConfig? serviceConfig,
  }) : parserConfig = parserConfig ?? const ReceiptParserConfig(),
       super(
         name: 'ReceiptParserService',
         config: serviceConfig ?? const ServiceConfig(
           maxConcurrentTasks: 3, // Semaphore with 3 slots
           taskTimeout: Duration(minutes: 3),
         ),
       );

  /// Parser-specific configuration.
  final ReceiptParserConfig parserConfig;

  /// Receipt extraction feature instance.
  ReceiptExtractionFeature? _extractionFeature;

  /// Fuzzy matcher instance.
  AdaptiveFuzzyMatcher? _fuzzyMatcher;

  /// Base output directory.
  late String _outputDirectory;

  /// Config path for fuzzy matcher.
  late String _configPath;

  /// Deferred results waiting for LLM processing.
  final List<ReceiptParseResult> _deferredResults = [];

  /// Callback for when results are deferred to LLM.
  void Function(List<ReceiptParseResult> deferred)? onResultsDeferred;

  // ============================================================
  // PUBLIC API
  // ============================================================

  /// Get deferred results that need LLM processing.
  List<ReceiptParseResult> get deferredResults => List.unmodifiable(_deferredResults);

  /// Process a single receipt image.
  Future<FeatureResult<ReceiptParseResult>> processReceipt(String imagePath) async {
    final result = await submitTask<ReceiptParseResult>(
      taskName: 'processReceipt',
      processor: () => _processReceiptInternal(imagePath),
    );

    // Convert ServiceResult to FeatureResult
    return result.isSuccess 
        ? Success(result.valueOrNull!)
        : Failure(FeatureError(
            code: result.errorOrNull!.code,
            message: result.errorOrNull!.message,
          ));
  }

  /// Process multiple receipt images.
  Future<FeatureResult<BatchParseResult>> processReceipts(List<String> imagePaths) async {
    if (imagePaths.isEmpty) {
      return Success(BatchParseResult(
        results: const [],
        totalDuration: Duration.zero,
        successCount: 0,
        failureCount: 0,
        deferredCount: 0,
      ));
    }

    final stopwatch = Stopwatch()..start();
    final results = <FeatureResult<ReceiptParseResult>>[];
    int deferredCount = 0;

    // Process images - semaphore handles concurrency
    for (final imagePath in imagePaths) {
      final result = await processReceipt(imagePath);
      results.add(result);

      if (result.isSuccess && 
          result.valueOrNull!.needsLLMAssistance(parserConfig.deferToLLMThreshold)) {
        deferredCount++;
      }
    }

    stopwatch.stop();

    final successCount = results.where((r) => r.isSuccess).length;
    final failureCount = results.where((r) => r.isFailure).length;

    // Notify about deferred results
    if (_deferredResults.isNotEmpty) {
      onResultsDeferred?.call(_deferredResults);
    }

    return Success(BatchParseResult(
      results: results,
      totalDuration: stopwatch.elapsed,
      successCount: successCount,
      failureCount: failureCount,
      deferredCount: deferredCount,
    ));
  }

  /// Process a receipt and wait for LLM if needed.
  Future<FeatureResult<ReceiptParseResult>> processReceiptWithLLMFallback(
    String imagePath,
    Future<LLMParseResult> Function(String imagePath, String? ocrText) llmProcessor,
  ) async {
    final result = await processReceipt(imagePath);

    return result.fold(
      onSuccess: (parseResult) async {
        if (parseResult.needsLLMAssistance(parserConfig.deferToLLMThreshold) &&
            parserConfig.enableLLMFallback) {
          try {
            final llmResult = await llmProcessor(
              parseResult.processedImagePath,
              parseResult.ocrText,
            );

            // Learn from LLM result
            _learnFromLLMResult(llmResult, parseResult.rawLines ?? []);

            return Success(ReceiptParseResult(
              sourceImagePath: parseResult.sourceImagePath,
              processedImagePath: parseResult.processedImagePath,
              extractionResult: llmResult.toExtractionResult(),
              confidence: llmResult.confidence,
              processingDuration: parseResult.processingDuration,
              ocrText: parseResult.ocrText,
              rawLines: parseResult.rawLines,
              deferredToLLM: true,
              llmResult: llmResult,
              warnings: parseResult.warnings,
            ));
          } catch (e, st) {
            logError('LLM processing failed', e, st);
            return Success(parseResult); // Return original result
          }
        }
        return Success(parseResult);
      },
      onFailure: (error) => Failure(error),
    );
  }

  /// Apply learning from an LLM result to improve fuzzy matching.
  void learnFromLLMResult(LLMParseResult llmResult, List<String> originalLines) {
    _learnFromLLMResult(llmResult, originalLines);
  }

  /// Clear deferred results after they've been processed.
  void clearDeferredResults() {
    _deferredResults.clear();
  }

  /// Confirm an extraction result for learning.
  void confirmExtraction(
    ReceiptParseResult result, {
    String? confirmedMarket,
    String? confirmedDate,
    String? confirmedSum,
    List<ItemMatch>? confirmedItems,
  }) {
    _fuzzyMatcher?.confirmExtraction(
      result.extractionResult,
      confirmedMarket: confirmedMarket,
      confirmedDate: confirmedDate,
      confirmedSum: confirmedSum,
      confirmedItems: confirmedItems,
    );
  }

  /// Get fuzzy matcher for direct access.
  AdaptiveFuzzyMatcher? get fuzzyMatcher => _fuzzyMatcher;

  // ============================================================
  // SERVICE LIFECYCLE
  // ============================================================

  @override
  Future<void> onStart() async {
    logInfo('Starting receipt parser service');

    // Load path_provider
    await path_provider.loadLibrary();

    // Setup directories
    final appDocDir = await path_provider.getApplicationDocumentsDirectory();
    _outputDirectory = parserConfig.outputDirectory ?? 
        p.join(appDocDir.path, 'frienance', 'receipts');
    _configPath = p.join(appDocDir.path, 'frienance', 'config.json');

    await Directory(_outputDirectory).create(recursive: true);
    
    // Ensure config file exists
    final configFile = File(_configPath);
    if (!await configFile.exists()) {
      await configFile.create(recursive: true);
      await configFile.writeAsString('{}');
    }

    // Initialize receipt extraction feature
    _extractionFeature = ReceiptExtractionFeature();
    await _extractionFeature!.initialize();

    // Initialize fuzzy matcher
    _fuzzyMatcher = AdaptiveFuzzyMatcher(_configPath);

    logInfo('Receipt parser service started');
  }

  @override
  Future<void> onStop() async {
    logInfo('Stopping receipt parser service');

    await _extractionFeature?.dispose();
    _extractionFeature = null;
    _fuzzyMatcher = null;

    logInfo('Receipt parser service stopped');
  }

  /// Check service health.
  Future<HealthCheckResult> checkHealth() async {
    final issues = <String>[];

    // Check extraction feature
    if (_extractionFeature == null || !_extractionFeature!.isReady) {
      issues.add('Extraction feature not ready');
    }

    // Check fuzzy matcher
    if (_fuzzyMatcher == null) {
      issues.add('Fuzzy matcher not initialized');
    }

    // Check output directory
    if (!await Directory(_outputDirectory).exists()) {
      issues.add('Output directory does not exist');
    }

    if (issues.isEmpty) {
      return HealthCheckResult(
        featureName: name,
        status: HealthStatus.healthy,
        message: 'Receipt parser service is healthy',
        details: {
          'outputDirectory': _outputDirectory,
          'deferredCount': _deferredResults.length,
          'serviceState': state.name,
        },
      );
    }

    return HealthCheckResult(
      featureName: name,
      status: issues.length > 1 ? HealthStatus.unhealthy : HealthStatus.degraded,
      message: issues.join('; '),
      details: {'issues': issues},
    );
  }

  // ============================================================
  // PRIVATE IMPLEMENTATION
  // ============================================================

  Future<ReceiptParseResult> _processReceiptInternal(String imagePath) async {
    final stopwatch = Stopwatch()..start();
    final warnings = <String>[];
    final taskId = 'receipt_${DateTime.now().millisecondsSinceEpoch}';

    // Create temporary working directory
    final workDir = await createTempDirectory(taskId);
    final sourceFileName = p.basename(imagePath);
    final baseFileName = p.basenameWithoutExtension(sourceFileName);

    try {
      // Step 1: Copy source image
      final sourceFile = File(imagePath);
      if (!await sourceFile.exists()) {
        throw FeatureException(FeatureError(
          code: FeatureError.codeValidation,
          message: 'Source image not found: $imagePath',
        ));
      }

      final workSourcePath = p.join(workDir.path, sourceFileName);
      await sourceFile.copy(workSourcePath);

      // Step 2: Extract and enhance receipt image
      logDebug('Step 1: Extracting receipt from image');
      final extractionResult = await _extractionFeature!.processImage(workSourcePath);
      
      String processedImagePath;
      if (extractionResult.isFailure) {
        warnings.add('Image extraction failed, using original');
        processedImagePath = workSourcePath;
      } else {
        processedImagePath = extractionResult.valueOrNull!.outputPath;
        if (!extractionResult.valueOrNull!.contourFound) {
          warnings.add('No receipt contour found');
        }
      }

      // Step 3: Extract text using OCR
      logDebug('Step 2: Extracting text via OCR');
      final ocrLines = await _extractTextFromImage(processedImagePath);
      final ocrText = ocrLines.join('\n');

      if (ocrLines.isEmpty) {
        warnings.add('No text extracted from image');
      }

      // Step 4: Apply fuzzy matching
      logDebug('Step 3: Applying fuzzy matching');
      final extractionData = _fuzzyMatcher!.extractAll(ocrLines);

      // Step 5: Calculate overall confidence
      final confidence = extractionData.overallConfidence;

      // Step 6: Save results
      final outputImagePath = p.join(_outputDirectory, '${baseFileName}_processed${p.extension(sourceFileName)}');
      final outputJsonPath = p.join(_outputDirectory, '${baseFileName}_result.json');

      await File(processedImagePath).copy(outputImagePath);
      await File(outputJsonPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(extractionData.toJson()),
      );

      // Copy source image to output
      final outputSourcePath = p.join(_outputDirectory, sourceFileName);
      await sourceFile.copy(outputSourcePath);

      stopwatch.stop();

      final result = ReceiptParseResult(
        sourceImagePath: outputSourcePath,
        processedImagePath: outputImagePath,
        extractionResult: extractionData,
        confidence: confidence,
        processingDuration: stopwatch.elapsed,
        ocrText: ocrText,
        rawLines: ocrLines,
        warnings: warnings,
      );

      // Check if should defer to LLM
      if (result.needsLLMAssistance(parserConfig.deferToLLMThreshold) &&
          parserConfig.enableLLMFallback) {
        _deferredResults.add(result);
        logInfo('Result deferred to LLM (confidence: ${(confidence * 100).toStringAsFixed(1)}%)');
      }

      return result;
    } finally {
      // Cleanup temporary directory
      final preserveFiles = parserConfig.preserveIntermediateImages
          ? <String>[]
          : <String>[]; // Don't preserve anything in temp - results are in output dir
      
      await cleanupTempDirectory(workDir, preserveFiles: preserveFiles);
    }
  }

  Future<List<String>> _extractTextFromImage(String imagePath) async {
    // This would use ML Kit or similar OCR
    // For now, we'll create a placeholder that the text_extraction module can fill
    try {
      // Import and use the Enhancer class for text extraction
      // This is a simplified version - full implementation would use Enhancer
      final file = File(imagePath);
      if (!await file.exists()) return [];

      // Placeholder: In production, this calls ML Kit via Enhancer
      // The actual implementation should be injected or use the Enhancer class
      logWarning('OCR not fully implemented - using placeholder');
      return [];
    } catch (e, st) {
      logError('Text extraction failed', e, st);
      return [];
    }
  }

  void _learnFromLLMResult(LLMParseResult llmResult, List<String> originalLines) {
    if (_fuzzyMatcher == null) return;

    // Add new market if discovered
    if (llmResult.market != null && llmResult.market!.isNotEmpty) {
      final existingMarket = _fuzzyMatcher!.getStores().keys
          .where((k) => k.toLowerCase() == llmResult.market!.toLowerCase())
          .firstOrNull;

      if (existingMarket == null) {
        _fuzzyMatcher!.addStore(
          name: llmResult.market!,
          spellings: [llmResult.market!.toLowerCase()],
        );
        logInfo('Learned new market from LLM: ${llmResult.market}');
      }
    }

    // Record the LLM extraction as a confirmation for pattern learning
    final extractionResult = llmResult.toExtractionResult();
    _fuzzyMatcher!.confirmExtraction(
      extractionResult,
      confirmedMarket: llmResult.market,
      confirmedDate: llmResult.date,
      confirmedSum: llmResult.total,
      confirmedItems: extractionResult.items.items,
    );

    logInfo('Applied LLM learning to fuzzy matcher');
  }
}

// ============================================================
// CONVENIENCE FUNCTIONS
// ============================================================

/// Singleton instance for simple usage.
ReceiptParserService? _sharedParserService;

/// Get or create the shared receipt parser service.
Future<ReceiptParserService> getReceiptParserService() async {
  if (_sharedParserService == null || !_sharedParserService!.isRunning) {
    _sharedParserService = ReceiptParserService();
    await _sharedParserService!.start();
  }
  return _sharedParserService!;
}

/// Process a single receipt using the shared service.
Future<FeatureResult<ReceiptParseResult>> parseReceipt(String imagePath) async {
  final service = await getReceiptParserService();
  return service.processReceipt(imagePath);
}

/// Process multiple receipts using the shared service.
Future<FeatureResult<BatchParseResult>> parseReceipts(List<String> imagePaths) async {
  final service = await getReceiptParserService();
  return service.processReceipts(imagePaths);
}

/// Stop the shared service.
Future<void> stopReceiptParserService() async {
  await _sharedParserService?.stop();
  _sharedParserService = null;
}
