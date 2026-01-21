import 'dart:io';
import 'dart:math';

import 'package:frienance/utils/logger.dart';
import 'package:frienance/services/receipt_parser/utils/open_cv_utils/mat_extensions.dart';
import 'package:path/path.dart' as path;
import 'package:opencv_dart/opencv_dart.dart' as cv2;
import 'package:collection/collection.dart';

// Lazy import
import 'package:flutter/material.dart' deferred as flutter_material show WidgetsFlutterBinding;
import 'package:path_provider/path_provider.dart' deferred as path_provider;

typedef Point2f = cv2.Point2f;

class ReceiptExtraction with Loggable {
  
  String basePath = '';
  final String inputFolder = "1_source_img";
  final String outputFolder = "2_temp_img";
  late String imagesOutputPath; // Output to assets/images for easy viewing

  /// When true, dumps intermediate images and extra logs.
  final bool saveDebugImages;

  ReceiptExtraction._({this.saveDebugImages = false});

  static Future<ReceiptExtraction> create({bool saveDebugImages = false}) async {
    final instance = ReceiptExtraction._(saveDebugImages: saveDebugImages);
    await instance._init();
    return instance;
  }

  Future<void> _init() async {
    final resolvedBasePath = await _resolveBasePath();
    basePath = resolvedBasePath;
    imagesOutputPath = await _resolveImagesOutputPath(resolvedBasePath);

    await prepareFolders();
  }

  Future<String> _resolveBasePath() async {
    try {
      await flutter_material.loadLibrary();
      flutter_material.WidgetsFlutterBinding.ensureInitialized();
      await path_provider.loadLibrary();
      final appDir = await path_provider.getApplicationDocumentsDirectory();
      return path.join(appDir.path, 'cache');
    } catch (_) {
      // Fallback for CLI or when plugins are unavailable
      return path.join(Directory.current.path, 'lib', 'cache');
    }
  }

  Future<String> _resolveImagesOutputPath(String resolvedBasePath) async {
    try {
      await flutter_material.loadLibrary();
      flutter_material.WidgetsFlutterBinding.ensureInitialized();
      await path_provider.loadLibrary();
      final appDir = await path_provider.getApplicationDocumentsDirectory();
      return path.join(appDir.path, 'cache', outputFolder);
    } catch (_) {
      // Default to assets/images for CLI usage
      return path.join(Directory.current.path, 'assets', 'images');
    }
  }

  Future<void> copyImagesToSourceDir(List<String> imagePaths) async {
    try {
      final sourceDir = Directory(path.join(basePath, inputFolder));
      await sourceDir.create(recursive: true);

      for (String imagePath in imagePaths) {
        final fileName = path.basename(imagePath);
        final destination = path.join(sourceDir.path, fileName);

        // Read directly from file system
        final bytes = await File(imagePath).readAsBytes();

        await File(destination).writeAsBytes(bytes);
        logger.d('Copied $fileName to $destination');
      }
    } catch (e, stackTrace) {
      logger.e('Error copying images', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> prepareFolders() async {
    try {
      // Create base cache directory
      await Directory(basePath).create(recursive: true);

      // Create input and output directories
      final inputPath = path.join(basePath, inputFolder);
      final outputPath = path.join(basePath, outputFolder);

      await Future.wait([
        Directory(inputPath).create(recursive: true),
        Directory(outputPath).create(recursive: true),
      ]);

      logger.i('Cache directory: $basePath');
      logger.d('Input directory: $inputPath');
      logger.d('Output directory: $outputPath');
    } catch (e, stackTrace) {
      logger.e('Error preparing folders', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  cv2.VecPoint getReceiptContour(List<cv2.VecPoint> contours) {
    for (var contour in contours) {
      var approx = approximateContour(contour);

      if (approx.length == 4) {
        return approx;
      }
    }
    return cv2.VecPoint(); 
  }

  Future<List<String>> findImages() async {
    try {
      final inputPath = path.join(basePath, inputFolder);

      if (!Directory(inputPath).existsSync()) {
        logger.w('Input directory not found: $inputPath');
        return [];
      }

      final images = Directory(inputPath)
          .listSync()
          .where((entity) =>
              entity is File &&
              ['.jpg', '.jpeg', '.png']
                  .contains(path.extension(entity.path).toLowerCase()))
          .map((entity) => entity.path)
          .toList();

      logger.i('Found ${images.length} images in $inputPath');

      return images;
    } catch (e, stackTrace) {
      logger.e('Error finding images', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  cv2.Mat opencvResize(cv2.Mat image, double ratio) {
    int width = (image.width * ratio).toInt();
    int height = (image.height * ratio).toInt();
    final dim = (width, height);
    return cv2.resize(image, dim, interpolation: cv2.INTER_AREA);
  }

  /// Find the optimal seed point using Distance Transform.
  /// This finds the "deepest white" point near the center - a point that is
  /// maximally far from any black pixels, ensuring a robust flood-fill start.
  cv2.Point _findOptimalSeedPoint(
    cv2.Mat binary,
    int centerX,
    int centerY, {
    int searchRadius = 100,
  }) {
    // Compute distance transform - each white pixel gets a value equal to
    // its distance from the nearest black pixel
    // distanceTransform returns (distImage, labels)
    var (distTransform, _) = cv2.distanceTransform(
      binary,
      cv2.DIST_L2,
      cv2.DIST_MASK_5,
      cv2.DIST_LABEL_CCOMP, // labelType for connected components
    );

    // Search in a region around the center for the point with max distance
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

    logger.v('Distance Transform: max distance = $maxDist at (${bestPoint.x}, ${bestPoint.y})');

    // Fallback to center if no good point found
    if (maxDist < 5) {
      return cv2.Point(centerX, centerY);
    }

    return bestPoint;
  }

  cv2.VecPoint orderPoints(cv2.VecPoint points) {
    // Order points as: top-left, top-right, bottom-right, bottom-left
    var pts = points.toList();

    // Sort by sum (x + y) - smallest is top-left, largest is bottom-right
    var sums = pts.map((p) => p.x + p.y).toList();
    var topLeft = pts[sums.indexOf(sums.reduce(min))];
    var bottomRight = pts[sums.indexOf(sums.reduce(max))];

    // Sort by difference (y - x) - smallest is top-right, largest is bottom-left
    var diffs = pts.map((p) => p.y - p.x).toList();
    var topRight = pts[diffs.indexOf(diffs.reduce(min))];
    var bottomLeft = pts[diffs.indexOf(diffs.reduce(max))];

    return cv2.VecPoint.fromList([topLeft, topRight, bottomRight, bottomLeft]);
  }

  cv2.Mat wrapPerspective(cv2.Mat img, cv2.VecPoint rect, double resizeRatio) {
    final padding = 20;
    // Scale points back to original image size
    var scaledRect = cv2.VecPoint.fromList(rect
        .toList()
        .map((p) =>
            cv2.Point((p.x / resizeRatio).round(), (p.y / resizeRatio).round()))
        .toList());

    // Order the points correctly
    var orderedRect = orderPoints(scaledRect);

    // Unpack rectangle points
    var tl = orderedRect[0];
    var tr = orderedRect[1];
    var br = orderedRect[2];
    var bl = orderedRect[3];

    // Compute centroid
    final cx = (tl.x + tr.x + br.x + bl.x) / 4.0;
    final cy = (tl.y + tr.y + br.y + bl.y) / 4.0;

    // Expand each corner outward from centroid by `padding` pixels so the
    // perspective warp includes extra margin from the original image.
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

    // Calculate width and height using Euclidean distance on expanded rect
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

    // Destination points start at origin and use computed dimensions
    List<Point2f> dst = [
      Point2f(0.0, 0.0),
      Point2f(maxWidth, 0.0),
      Point2f(maxWidth, maxHeight),
      Point2f(0.0, maxHeight),
    ];

    // Perform perspective transformation using expanded source points
    final temp = cv2.getPerspectiveTransform(
      expandedRect,
      cv2.VecPoint.fromList(
        dst.map((p) => cv2.Point(p.x.toInt(), p.y.toInt())).toList()));
    return cv2
      .warpPerspective(img, temp, (maxWidth.toInt(), maxHeight.toInt()));
  }

  cv2.VecPoint approximateContour(cv2.VecPoint contour) {
    // 1. Get the convex hull to "straighten" the edges
    var hull = cv2.convexHull(contour);
    // Convert mat to cv2.VecPoint
    var hullVec = cv2.VecPoint.fromMat(hull);
    // 2. Then approximate from the hull, not the raw contour
    double epsilon = 0.02 * cv2.arcLength(hullVec, true);
    return cv2.approxPolyDP(hullVec, epsilon, true);
  }

  Future<String> saveToOutput(cv2.Mat image, String originalFileName,
      {String? suffix, bool toAssetsImages = false}) async {
    try {
      final fileName = suffix != null
          ? '${path.basenameWithoutExtension(originalFileName)}_$suffix${path.extension(originalFileName)}'
          : path.basename(originalFileName);

      // Save to assets/images if requested, otherwise to cache output folder
      final outputPath = toAssetsImages
          ? path.join(imagesOutputPath, fileName)
          : path.join(basePath, outputFolder, fileName);

      await Directory(path.dirname(outputPath)).create(recursive: true);

      cv2.imwrite(outputPath, image);
      logger.d('Saved image to: $outputPath');

      return outputPath;
    } catch (e, stackTrace) {
      logger.e('Error saving image', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  double getPercentile(cv2.Mat data, double p) {
    // Flatten the cv2.Mat to a List<num>
    List<num> dataList = [];
    for (int i = 0; i < data.rows; i++) {
      for (int j = 0; j < data.cols; j++) {
        dataList.add(data.atNum(i, j));
      }
    }
    return dataList.sorted().percentile(p);
  }

  cv2.Mat processImage(cv2.Mat result) {
    double minval = getPercentile(result, 4.5);
    double maxval = getPercentile(result, 95);

    // 1. Clip the values using OpenCV's thresholding/clipping
    cv2.Mat clipped = result.clone();
    cv2.threshold(clipped, maxval, maxval, cv2.THRESH_TRUNC); // Cap at max
    cv2.threshold(clipped, minval, minval,
        cv2.THRESH_TOZERO_INV); 

    // 2.  Normalize the clipped image to full 0-255 range
    cv2.Mat normalized = cv2.Mat.empty();
    cv2.normalize(clipped, normalized,
        alpha: 0,
        beta: 255,
        normType: cv2.NORM_MINMAX,
        dtype: cv2.MatType.CV_8U);

    return normalized;
  }

  
/// Process a single image from device storage (camera/gallery) on mobile.
  /// Returns the path to the processed image file.
  /// 
  /// [imagePath] - Absolute path to the image file on the device
  /// Returns the path to the processed output image, or null if processing failed.
  Future<String?> processImageFromDevice(String imagePath) async {
    try {
      // Validate input file exists
      final inputFile = File(imagePath);
      if (!await inputFile.exists()) {
        logger.w('Input image not found: $imagePath');
        return null;
      }

      // Copy to source directory first
      await copyImagesToSourceDir([imagePath]);

      final fileName = path.basename(imagePath);
      final sourceFilePath = path.join(basePath, inputFolder, fileName);

      // Process the single image
      return await _processSingleImage(sourceFilePath);
    } catch (e, stackTrace) {
      logger.e('Error processing image from device', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Internal method to process a single image file.
  /// Returns the path to the processed output image, or null if processing failed.
  Future<String?> _processSingleImage(String imagePath) async {
    try {
      cv2.Mat image = cv2.imread(imagePath);

      double resizeRatio = 2048 / image.shape[0];
      cv2.Mat original1 = image.clone();
      image = opencvResize(image, resizeRatio);

      // --- PHASE 1 SHADOW REMOVAL ---
      cv2.Mat gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);

      cv2.Mat bgKernel = cv2.getStructuringElement(cv2.MORPH_RECT, (25, 25));
      cv2.Mat dilated = cv2.dilate(gray, bgKernel);
      cv2.Mat bg = cv2.medianBlur(dilated, 25);

      cv2.Mat diff = cv2.Mat.zeros(gray.rows, gray.cols, gray.type);
      cv2.absDiff(gray, bg, dst: diff);
      gray = cv2.bitwiseNOT(diff);

      // --- PHASE 2 ENHANCED CONTRAST ---
      cv2.Mat claheImg =
          cv2.createCLAHE(clipLimit: 3.0, tileGridSize: (8, 8)).apply(gray);
      cv2.Mat edgePreserved = cv2.bilateralFilter(claheImg, 9, 75, 75);

      cv2.Mat gradientBlurKernel =
          cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3));
      cv2.Mat gradient =
          cv2.morphologyEx(edgePreserved, cv2.MORPH_GRADIENT, gradientBlurKernel);

      cv2.Mat thresholded = cv2.adaptiveThreshold(
        gradient,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31,
        10,
      );

      cv2.Mat thresholdClosingKernel =
          cv2.getStructuringElement(cv2.MORPH_RECT, (11, 11));
      cv2.Mat adaptiveThresInverted = cv2.bitwiseNOT(thresholded);
      cv2.Mat adaptiveThresClosed = cv2.morphologyEx(
        adaptiveThresInverted,
        cv2.MORPH_CLOSE,
        thresholdClosingKernel,
      );

      thresholded = cv2.bitwiseNOT(adaptiveThresClosed);

      // --- BORDER RECTANGLE ---
      const int borderThickness = 10;
      final int inset = (borderThickness / 2).ceil();
      final int innerW = thresholded.cols - (2 * inset);
      final int innerH = thresholded.rows - (2 * inset);
      if (innerW > 0 && innerH > 0) {
        cv2.rectangle(
          thresholded,
          cv2.Rect(inset, inset, innerW, innerH),
          cv2.Scalar.all(0),
          thickness: borderThickness,
        );
      }

      // Create flood fill mask
      cv2.Mat floodMask = cv2.Mat.zeros(
          thresholded.rows + 2, thresholded.cols + 2, cv2.MatType.CV_8UC1);

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

      cv2.Mat receiptMask = filledMask
          .rowRange(1, filledMask.rows - 2)
          .colRange(1, filledMask.cols - 2)
          .clone();

      var (contours, _) = cv2.findContours(
        receiptMask,
        cv2.RETR_EXTERNAL,
        cv2.CHAIN_APPROX_SIMPLE,
      );

      var temp = (contours.toList().sorted((a, b) {
        double areaA = cv2.contourArea(a);
        double areaB = cv2.contourArea(b);
        return areaB.compareTo(areaA);
      }));
      cv2.VecVecPoint sortedContours = cv2.VecVecPoint.fromList(temp
          .map((e) =>
              e.map((e2) => cv2.Point(e2.x.toInt(), e2.y.toInt())).toList())
          .toList());

      var largestContours = sortedContours.take(10).toList();

      var receiptContour = getReceiptContour(largestContours);
      if (receiptContour.length != 4) {
        logger.w('No 4-point receipt contour found in: $imagePath');
        // Fall back to processing without perspective correction
        var result = processImage(original1);
        return await saveToOutput(result, path.basename(imagePath),
            suffix: 'processed');
      }

      var scanned = wrapPerspective(original1, receiptContour, resizeRatio);
      var result = processImage(scanned);
      final savedPath = await saveToOutput(result, path.basename(imagePath),
          suffix: 'processed');
      
      logger.i('Saved processed image to: $savedPath');
      
      return savedPath;
    } catch (e, stackTrace) {
      logger.e('Error processing $imagePath', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> processReceipts() async {
    final images = await findImages();
    for (var imagePath in images) {
      try {
        await _processSingleImage(imagePath);
      } catch (e, stackTrace) {
        logger.e('Error processing $imagePath', error: e, stackTrace: stackTrace);
      }
    }
  }
}


/// Convenience function to process a single image from device storage on mobile.
/// Use this when the user picks an image from gallery or captures from camera.
/// 
/// [imagePath] - Absolute path to the image file on the device
/// Returns the path to the processed output image, or null if processing failed.
Future<String?> processReceiptImageFromDevice(String imagePath) async {
  final recognizer = await ReceiptExtraction.create();
  return recognizer.processImageFromDevice(imagePath);
}

/// Convenience function to process multiple images from device storage on mobile.
/// 
/// [imagePaths] - List of absolute paths to image files on the device
/// Returns a map of input path -> processed output path (null if failed)
Future<Map<String, String?>> processMultipleReceiptImages(List<String> imagePaths) async {
  final recognizer = await ReceiptExtraction.create();
  final results = <String, String?>{};
  
  for (final imagePath in imagePaths) {
    results[imagePath] = await recognizer.processImageFromDevice(imagePath);
  }
  
  return results;
}
