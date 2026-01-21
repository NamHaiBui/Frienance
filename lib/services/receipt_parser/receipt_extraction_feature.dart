/// Receipt Extraction Feature - Production-ready image processing for receipts.
/// 
/// This feature provides robust receipt image processing with:
/// - Automatic perspective correction
/// - Shadow removal and contrast enhancement
/// - Contour detection and extraction
/// - Production-grade error handling and resiliency
/// 
/// ## Usage
/// ```dart
/// final feature = ReceiptExtractionFeature();
/// await feature.initialize();
/// 
/// final result = await feature.processImage('/path/to/receipt.jpg');
/// result.fold(
///   onSuccess: (outputPath) => print('Processed: $outputPath'),
///   onFailure: (error) => print('Failed: $error'),
/// );
/// ```
library;

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv2;
import 'package:path/path.dart' as p;

import 'package:frienance/src/core/feature/feature_exports.dart';
import 'package:frienance/services/receipt_parser/utils/open_cv_utils/mat_extensions.dart';

// Lazy imports for Flutter-specific dependencies
import 'package:path_provider/path_provider.dart' deferred as path_provider;

typedef Point2f = cv2.Point2f;

/// Configuration specific to receipt extraction.
class ReceiptExtractionConfig {
  const ReceiptExtractionConfig({
    this.targetResizeHeight = 2048,
    this.perspectivePadding = 20,
    this.contrastClipLow = 4.5,
    this.contrastClipHigh = 95.0,
    this.borderThickness = 10,
    this.distanceTransformSearchRadius = 100,
    this.maxContourCandidates = 10,
    this.outputSuffix = 'processed',
    this.supportedExtensions = const ['.jpg', '.jpeg', '.png'],
  });

  /// Target height for image resizing during processing.
  final int targetResizeHeight;

  /// Padding applied during perspective correction.
  final int perspectivePadding;

  /// Lower percentile for contrast clipping.
  final double contrastClipLow;

  /// Upper percentile for contrast clipping.
  final double contrastClipHigh;

  /// Border thickness for flood fill boundary.
  final int borderThickness;

  /// Search radius for distance transform seed point.
  final int distanceTransformSearchRadius;

  /// Maximum number of contour candidates to consider.
  final int maxContourCandidates;

  /// Suffix appended to processed image filenames.
  final String outputSuffix;

  /// Supported image file extensions.
  final List<String> supportedExtensions;

  /// Default configuration for production use.
  static const ReceiptExtractionConfig production = ReceiptExtractionConfig();

  /// Configuration optimized for speed over quality.
  static const ReceiptExtractionConfig fast = ReceiptExtractionConfig(
    targetResizeHeight: 1024,
    maxContourCandidates: 5,
  );

  /// Configuration optimized for quality over speed.
  static const ReceiptExtractionConfig highQuality = ReceiptExtractionConfig(
    targetResizeHeight: 4096,
    maxContourCandidates: 20,
  );
}

/// Result of processing a single receipt image.
class ReceiptExtractionResult {
  const ReceiptExtractionResult({
    required this.inputPath,
    required this.outputPath,
    required this.processingDuration,
    this.contourFound = true,
    this.warnings = const [],
  });

  /// Original input image path.
  final String inputPath;

  /// Path to the processed output image.
  final String outputPath;

  /// Time taken to process the image.
  final Duration processingDuration;

  /// Whether a valid 4-point contour was detected.
  final bool contourFound;

  /// Any warnings during processing.
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
    'inputPath': inputPath,
    'outputPath': outputPath,
    'processingDurationMs': processingDuration.inMilliseconds,
    'contourFound': contourFound,
    'warnings': warnings,
  };
}

/// Production-ready receipt extraction feature.
/// 
/// Extends the base [Feature] class with receipt-specific processing
/// capabilities including perspective correction and contrast enhancement.
class ReceiptExtractionFeature extends Feature 
    with FileSystemFeature, ImageProcessingFeature {
  
  ReceiptExtractionFeature({
    FeatureConfig? featureConfig,
    ReceiptExtractionConfig? extractionConfig,
  }) : extractionConfig = extractionConfig ?? const ReceiptExtractionConfig(),
       super(
         name: 'ReceiptExtraction',
         config: featureConfig ?? _defaultFeatureConfig,
       );

  /// Receipt-specific configuration.
  final ReceiptExtractionConfig extractionConfig;

  /// Folder names for organization.
  static const String _inputFolder = '1_source_img';
  static const String _tempFolder = '2_temp_img';
  static const String _outputFolder = '3_output';

  /// Default feature configuration for receipt processing.
  static const _defaultFeatureConfig = FeatureConfig(
    retry: RetryConfig(
      maxAttempts: 3,
      initialDelay: Duration(milliseconds: 500),
      maxDelay: Duration(seconds: 10),
    ),
    circuitBreaker: CircuitBreakerConfig(
      failureThreshold: 5,
      successThreshold: 2,
      timeout: Duration(seconds: 30),
    ),
    timeout: TimeoutConfig(
      operationTimeout: Duration(seconds: 60),
      initializationTimeout: Duration(seconds: 30),
    ),
  );

  // ============================================================
  // PUBLIC API
  // ============================================================

  /// Process a single receipt image.
  /// 
  /// Takes an image from device storage (camera/gallery) and processes it
  /// through the receipt extraction pipeline.
  /// 
  /// Returns a [FeatureResult] containing the path to the processed image
  /// on success, or an error on failure.
  Future<FeatureResult<ReceiptExtractionResult>> processImage(String imagePath) {
    return execute(
      () => _processImageInternal(imagePath),
      operationName: 'processImage',
    );
  }

  /// Process multiple receipt images.
  /// 
  /// Processes images sequentially to manage memory usage.
  /// Returns results for all images, including partial successes.
  Future<FeatureResult<List<ReceiptExtractionResult>>> processMultipleImages(
    List<String> imagePaths,
  ) {
    return execute(
      () => _processMultipleImagesInternal(imagePaths),
      operationName: 'processMultipleImages',
      timeout: Duration(minutes: imagePaths.length * 2), // 2 min per image max
    );
  }

  /// Find all images in the input directory.
  Future<FeatureResult<List<String>>> findInputImages() {
    return execute(
      () => _findInputImagesInternal(),
      operationName: 'findInputImages',
    );
  }

  /// Process all images in the input directory.
  Future<FeatureResult<List<ReceiptExtractionResult>>> processAllInputImages() async {
    final findResult = await findInputImages();
    
    return findResult.fold(
      onSuccess: (images) => processMultipleImages(images),
      onFailure: (error) => Failure(error),
    );
  }

  // ============================================================
  // FEATURE LIFECYCLE
  // ============================================================

  @override
  Future<void> onInitialize() async {
    logInfo('Initializing receipt extraction feature');
    
    // Load path_provider
    await path_provider.loadLibrary();
    
    // Get application documents directory
    final appDocDir = await path_provider.getApplicationDocumentsDirectory();
    final cacheDir = p.join(appDocDir.path, 'frienance_cache');
    
    setBaseDirectory(cacheDir);
    logDebug('Cache directory: $cacheDir');
    
    // Create directory structure
    await Future.wait([
      ensureDirectory(p.join(cacheDir, _inputFolder)),
      ensureDirectory(p.join(cacheDir, _tempFolder)),
      ensureDirectory(p.join(cacheDir, _outputFolder)),
    ]);
    
    logInfo('Directory structure initialized');
  }

  @override
  Future<void> onWarmUp() async {
    logInfo('Warming up receipt extraction feature');
    
    // Pre-create common OpenCV structures to warm up native libraries
    final testMat = cv2.Mat.zeros(100, 100, cv2.MatType.CV_8UC1);
    cv2.cvtColor(testMat, cv2.COLOR_GRAY2BGR);
    // Clean up
    testMat.dispose();
    
    logInfo('OpenCV warm-up complete');
  }

  @override
  Future<HealthCheckResult> performHealthCheck() async {
    final issues = <String>[];
    
    // Check directory access
    try {
      final inputDir = Directory(p.join(baseDirectory, _inputFolder));
      if (!await inputDir.exists()) {
        issues.add('Input directory missing');
      }
    } catch (e) {
      issues.add('Cannot access input directory: $e');
    }
    
    // Check OpenCV availability
    try {
      final testMat = cv2.Mat.zeros(10, 10, cv2.MatType.CV_8UC1);
      testMat.dispose();
    } catch (e) {
      issues.add('OpenCV not available: $e');
    }
    
    if (issues.isEmpty) {
      return HealthCheckResult(
        featureName: name,
        status: HealthStatus.healthy,
        message: 'Receipt extraction feature is healthy',
      );
    } else if (issues.length == 1) {
      return HealthCheckResult(
        featureName: name,
        status: HealthStatus.degraded,
        message: issues.first,
      );
    } else {
      return HealthCheckResult(
        featureName: name,
        status: HealthStatus.unhealthy,
        message: 'Multiple issues detected',
        details: {'issues': issues},
      );
    }
  }

  @override
  Future<void> onDispose() async {
    logInfo('Disposing receipt extraction feature');
    // OpenCV handles its own cleanup
  }

  @override
  Future<(int width, int height)?> getImageDimensions(String path) async {
    try {
      final mat = cv2.imread(path);
      final dims = (mat.cols, mat.rows);
      mat.dispose();
      return dims;
    } catch (e) {
      logWarning('Failed to get image dimensions: $path', e);
      return null;
    }
  }

  // ============================================================
  // PRIVATE IMPLEMENTATION
  // ============================================================

  Future<ReceiptExtractionResult> _processImageInternal(String imagePath) async {
    final stopwatch = Stopwatch()..start();
    final warnings = <String>[];

    logDebug('Processing image: $imagePath');

    // Validate input
    final validationResult = await validateImage(imagePath);
    if (validationResult.isFailure) {
      throw validationResult.errorOrNull!.toException();
    }

    // Copy to source directory
    final inputFile = File(imagePath);
    final fileName = p.basename(imagePath);
    final sourceFilePath = p.join(baseDirectory, _inputFolder, fileName);
    
    await inputFile.copy(sourceFilePath);
    logDebug('Copied to source: $sourceFilePath');

    // Process the image
    cv2.Mat image = cv2.imread(sourceFilePath);
    
    try {
      double resizeRatio = extractionConfig.targetResizeHeight / image.shape[0];
      cv2.Mat original = image.clone();
      cv2.Mat resized = _opencvResize(image, resizeRatio);

      // Phase 1: Shadow removal
      cv2.Mat processed = _removeShadows(resized);
      
      // Phase 2: Enhanced contrast and edge detection
      processed = _enhanceContrast(processed);
      
      // Phase 3: Morphological operations
      processed = _applyMorphology(processed);
      
      // Phase 4: Flood fill to isolate receipt
      cv2.Mat receiptMask = _floodFillReceipt(processed);
      
      // Phase 5: Find contours
      var contour = _findReceiptContour(receiptMask);
      
      cv2.Mat result;
      bool contourFound = contour.length == 4;
      
      if (contourFound) {
        // Apply perspective transformation
        var warped = _wrapPerspective(original, contour, resizeRatio);
        result = _normalizeContrast(warped);
        warped.dispose();
      } else {
        // Fallback: process without perspective correction
        warnings.add('No valid receipt contour found - processing without perspective correction');
        logWarning('No 4-point receipt contour found in: $imagePath');
        result = _normalizeContrast(original);
      }

      // Save output
      final outputPath = await _saveOutput(result, fileName);
      
      // Cleanup
      image.dispose();
      original.dispose();
      resized.dispose();
      processed.dispose();
      receiptMask.dispose();
      result.dispose();

      stopwatch.stop();
      logInfo('Processed image in ${stopwatch.elapsedMilliseconds}ms: $outputPath');

      return ReceiptExtractionResult(
        inputPath: imagePath,
        outputPath: outputPath,
        processingDuration: stopwatch.elapsed,
        contourFound: contourFound,
        warnings: warnings,
      );
    } catch (e) {
      image.dispose();
      rethrow;
    }
  }

  Future<List<ReceiptExtractionResult>> _processMultipleImagesInternal(
    List<String> imagePaths,
  ) async {
    final results = <ReceiptExtractionResult>[];
    
    for (final path in imagePaths) {
      try {
        final result = await _processImageInternal(path);
        results.add(result);
      } catch (e, st) {
        logError('Failed to process image: $path', e, st);
        // Continue processing other images
      }
    }
    
    return results;
  }

  Future<List<String>> _findInputImagesInternal() async {
    final inputPath = p.join(baseDirectory, _inputFolder);
    final files = await listFiles(
      inputPath,
      extensions: extractionConfig.supportedExtensions,
    );
    
    return files.map((f) => f.path).toList();
  }

  // ============================================================
  // IMAGE PROCESSING HELPERS
  // ============================================================

  cv2.Mat _opencvResize(cv2.Mat image, double ratio) {
    int width = (image.width * ratio).toInt();
    int height = (image.height * ratio).toInt();
    return cv2.resize(image, (width, height), interpolation: cv2.INTER_AREA);
  }

  cv2.Mat _removeShadows(cv2.Mat image) {
    cv2.Mat gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);
    cv2.Mat bgKernel = cv2.getStructuringElement(cv2.MORPH_RECT, (25, 25));
    cv2.Mat dilated = cv2.dilate(gray, bgKernel);
    cv2.Mat bg = cv2.medianBlur(dilated, 25);
    
    cv2.Mat diff = cv2.Mat.zeros(gray.rows, gray.cols, gray.type);
    cv2.absDiff(gray, bg, dst: diff);
    cv2.Mat result = cv2.bitwiseNOT(diff);
    
    // Cleanup intermediate mats
    gray.dispose();
    bgKernel.dispose();
    dilated.dispose();
    bg.dispose();
    diff.dispose();
    
    return result;
  }

  cv2.Mat _enhanceContrast(cv2.Mat gray) {
    cv2.Mat claheImg = cv2.createCLAHE(clipLimit: 3.0, tileGridSize: (8, 8)).apply(gray);
    cv2.Mat edgePreserved = cv2.bilateralFilter(claheImg, 9, 75, 75);
    
    cv2.Mat gradientKernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3));
    cv2.Mat gradient = cv2.morphologyEx(edgePreserved, cv2.MORPH_GRADIENT, gradientKernel);
    
    cv2.Mat result = cv2.adaptiveThreshold(
      gradient,
      255,
      cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv2.THRESH_BINARY,
      31,
      10,
    );
    
    // Cleanup
    claheImg.dispose();
    edgePreserved.dispose();
    gradientKernel.dispose();
    gradient.dispose();
    
    return result;
  }

  cv2.Mat _applyMorphology(cv2.Mat thresholded) {
    cv2.Mat kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (11, 11));
    cv2.Mat inverted = cv2.bitwiseNOT(thresholded);
    cv2.Mat closed = cv2.morphologyEx(inverted, cv2.MORPH_CLOSE, kernel);
    cv2.Mat result = cv2.bitwiseNOT(closed);
    
    // Add border rectangle
    final borderThickness = extractionConfig.borderThickness;
    final inset = (borderThickness / 2).ceil();
    final innerW = result.cols - (2 * inset);
    final innerH = result.rows - (2 * inset);
    
    if (innerW > 0 && innerH > 0) {
      cv2.rectangle(
        result,
        cv2.Rect(inset, inset, innerW, innerH),
        cv2.Scalar.all(0),
        thickness: borderThickness,
      );
    }
    
    // Cleanup
    kernel.dispose();
    inverted.dispose();
    closed.dispose();
    
    return result;
  }

  cv2.Mat _floodFillReceipt(cv2.Mat thresholded) {
    cv2.Mat floodMask = cv2.Mat.zeros(
      thresholded.rows + 2,
      thresholded.cols + 2,
      cv2.MatType.CV_8UC1,
    );

    int centerX = thresholded.cols ~/ 2;
    int centerY = thresholded.rows ~/ 2;

    cv2.Point seedPoint = _findOptimalSeedPoint(
      thresholded,
      centerX,
      centerY,
      searchRadius: min(thresholded.cols, thresholded.rows) ~/ 4,
    );

    cv2.Mat floodImage = thresholded.clone();

    var (_, _, filledMask, _) = cv2.floodFill(
      floodImage,
      seedPoint,
      cv2.Scalar.all(255),
      mask: floodMask,
      loDiff: cv2.Scalar.all(0),
      upDiff: cv2.Scalar.all(0),
      flags: 4 | (255 << 8) | cv2.FLOODFILL_MASK_ONLY,
    );

    cv2.Mat result = filledMask
        .rowRange(1, filledMask.rows - 2)
        .colRange(1, filledMask.cols - 2)
        .clone();

    // Cleanup
    floodMask.dispose();
    floodImage.dispose();
    filledMask.dispose();

    return result;
  }

  cv2.Point _findOptimalSeedPoint(
    cv2.Mat binary,
    int centerX,
    int centerY, {
    int searchRadius = 100,
  }) {
    var (distTransform, _) = cv2.distanceTransform(
      binary,
      cv2.DIST_L2,
      cv2.DIST_MASK_5,
      cv2.DIST_LABEL_CCOMP,
    );

    int startX = max(0, centerX - searchRadius);
    int startY = max(0, centerY - searchRadius);
    int endX = min(binary.cols, centerX + searchRadius);
    int endY = min(binary.rows, centerY + searchRadius);

    double maxDist = 0;
    cv2.Point bestPoint = cv2.Point(centerX, centerY);

    for (int y = startY; y < endY; y++) {
      for (int x = startX; x < endX; x++) {
        double dist = distTransform.at<double>(y, x);
        if (dist > maxDist) {
          maxDist = dist;
          bestPoint = cv2.Point(x, y);
        }
      }
    }

    distTransform.dispose();

    logDebug('Distance Transform: max distance = $maxDist at (${bestPoint.x}, ${bestPoint.y})');

    if (maxDist < 5) {
      return cv2.Point(centerX, centerY);
    }

    return bestPoint;
  }

  cv2.VecPoint _findReceiptContour(cv2.Mat mask) {
    var (contours, _) = cv2.findContours(
      mask,
      cv2.RETR_EXTERNAL,
      cv2.CHAIN_APPROX_SIMPLE,
    );

    var sortedContours = contours.toList()
      ..sort((a, b) {
        double areaA = cv2.contourArea(a);
        double areaB = cv2.contourArea(b);
        return areaB.compareTo(areaA);
      });

    var candidates = sortedContours.take(extractionConfig.maxContourCandidates);

    for (var contour in candidates) {
      var approx = _approximateContour(contour);
      if (approx.length == 4) {
        return approx;
      }
    }

    return cv2.VecPoint();
  }

  cv2.VecPoint _approximateContour(cv2.VecPoint contour) {
    var hull = cv2.convexHull(contour);
    var hullVec = cv2.VecPoint.fromMat(hull);
    double epsilon = 0.02 * cv2.arcLength(hullVec, true);
    return cv2.approxPolyDP(hullVec, epsilon, true);
  }

  cv2.VecPoint _orderPoints(cv2.VecPoint points) {
    var pts = points.toList();

    var sums = pts.map((p) => p.x + p.y).toList();
    var topLeft = pts[sums.indexOf(sums.reduce(min))];
    var bottomRight = pts[sums.indexOf(sums.reduce(max))];

    var diffs = pts.map((p) => p.y - p.x).toList();
    var topRight = pts[diffs.indexOf(diffs.reduce(min))];
    var bottomLeft = pts[diffs.indexOf(diffs.reduce(max))];

    return cv2.VecPoint.fromList([topLeft, topRight, bottomRight, bottomLeft]);
  }

  cv2.Mat _wrapPerspective(cv2.Mat img, cv2.VecPoint rect, double resizeRatio) {
    final padding = extractionConfig.perspectivePadding;
    
    var scaledRect = cv2.VecPoint.fromList(rect
        .toList()
        .map((p) =>
            cv2.Point((p.x / resizeRatio).round(), (p.y / resizeRatio).round()))
        .toList());

    var orderedRect = _orderPoints(scaledRect);

    var tl = orderedRect[0];
    var tr = orderedRect[1];
    var br = orderedRect[2];
    var bl = orderedRect[3];

    final cx = (tl.x + tr.x + br.x + bl.x) / 4.0;
    final cy = (tl.y + tr.y + br.y + bl.y) / 4.0;

    List<cv2.Point> expanded = [];
    for (var p in [tl, tr, br, bl]) {
      double dx = p.x - cx;
      double dy = p.y - cy;
      double len = sqrt(dx * dx + dy * dy);
      if (len == 0) len = 1.0;
      double nx = dx / len;
      double ny = dy / len;
      final ex = (p.x + nx * padding).round();
      final ey = (p.y + ny * padding).round();
      expanded.add(cv2.Point(ex, ey));
    }

    var expandedRect = cv2.VecPoint.fromList(expanded);

    double widthA = sqrt(pow(expandedRect[2].x - expandedRect[3].x, 2) +
        pow(expandedRect[2].y - expandedRect[3].y, 2));
    double widthB = sqrt(pow(expandedRect[1].x - expandedRect[0].x, 2) +
        pow(expandedRect[1].y - expandedRect[0].y, 2));
    double heightA = sqrt(pow(expandedRect[1].x - expandedRect[2].x, 2) +
        pow(expandedRect[1].y - expandedRect[2].y, 2));
    double heightB = sqrt(pow(expandedRect[0].x - expandedRect[3].x, 2) +
        pow(expandedRect[0].y - expandedRect[3].y, 2));

    double maxWidth = max(widthA, widthB);
    double maxHeight = max(heightA, heightB);

    List<Point2f> dst = [
      Point2f(0.0, 0.0),
      Point2f(maxWidth, 0.0),
      Point2f(maxWidth, maxHeight),
      Point2f(0.0, maxHeight),
    ];

    final transform = cv2.getPerspectiveTransform(
      expandedRect,
      cv2.VecPoint.fromList(
          dst.map((p) => cv2.Point(p.x.toInt(), p.y.toInt())).toList()),
    );
    
    return cv2.warpPerspective(
      img,
      transform,
      (maxWidth.toInt(), maxHeight.toInt()),
    );
  }

  cv2.Mat _normalizeContrast(cv2.Mat image) {
    // Get percentiles for contrast clipping
    List<num> dataList = [];
    for (int i = 0; i < image.rows; i++) {
      for (int j = 0; j < image.cols; j++) {
        dataList.add(image.atNum(i, j));
      }
    }
    
    double minval = dataList.sorted().percentile(extractionConfig.contrastClipLow);
    double maxval = dataList.sorted().percentile(extractionConfig.contrastClipHigh);

    cv2.Mat clipped = image.clone();
    cv2.threshold(clipped, maxval, maxval, cv2.THRESH_TRUNC);
    cv2.threshold(clipped, minval, minval, cv2.THRESH_TOZERO_INV);

    cv2.Mat normalized = cv2.Mat.empty();
    cv2.normalize(
      clipped,
      normalized,
      alpha: 0,
      beta: 255,
      normType: cv2.NORM_MINMAX,
      dtype: cv2.MatType.CV_8U,
    );

    clipped.dispose();
    return normalized;
  }

  Future<String> _saveOutput(cv2.Mat image, String originalFileName) async {
    final baseName = p.basenameWithoutExtension(originalFileName);
    final ext = p.extension(originalFileName);
    final outputFileName = '${baseName}_${extractionConfig.outputSuffix}$ext';
    final outputPath = p.join(baseDirectory, _outputFolder, outputFileName);

    await ensureDirectory(p.dirname(outputPath));
    cv2.imwrite(outputPath, image);
    
    logDebug('Saved output: $outputPath');
    return outputPath;
  }
}

// ============================================================
// CONVENIENCE FUNCTIONS
// ============================================================

/// Singleton instance for simple usage.
ReceiptExtractionFeature? _sharedInstance;

/// Get or create the shared receipt extraction feature instance.
Future<ReceiptExtractionFeature> getReceiptExtractionFeature() async {
  if (_sharedInstance == null || _sharedInstance!.isDisposed) {
    _sharedInstance = ReceiptExtractionFeature();
    await _sharedInstance!.initialize();
  }
  return _sharedInstance!;
}

/// Process a single receipt image using the shared instance.
/// 
/// Convenience function for simple use cases.
Future<FeatureResult<ReceiptExtractionResult>> processReceiptImage(
  String imagePath,
) async {
  final feature = await getReceiptExtractionFeature();
  return feature.processImage(imagePath);
}

/// Process multiple receipt images using the shared instance.
Future<FeatureResult<List<ReceiptExtractionResult>>> processReceiptImages(
  List<String> imagePaths,
) async {
  final feature = await getReceiptExtractionFeature();
  return feature.processMultipleImages(imagePaths);
}

/// Dispose the shared instance to free resources.
Future<void> disposeReceiptExtractionFeature() async {
  await _sharedInstance?.dispose();
  _sharedInstance = null;
}
