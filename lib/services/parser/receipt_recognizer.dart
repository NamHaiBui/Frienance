import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:frienance/utils/mat_extensions.dart';
import 'package:path/path.dart' as path;
import 'package:opencv_dart/opencv_dart.dart' as cv2;
import 'package:collection/collection.dart';

// Debug mode flag for pure Dart execution
const bool kDebugMode = bool.fromEnvironment('dart.vm.product') == false;

typedef Point2f = cv2.Point2f;

class ReceiptRecognizer {
  String basePath = 'D:\\Side Ultimatum\\Frienance\\lib\\cache';
  final String inputFolder = "1_source_img";
  final String outputFolder = "2_temp_img";

  static Future<ReceiptRecognizer> create() async {
    final instance = ReceiptRecognizer._();
    await instance._init();
    return instance;
  }

  ReceiptRecognizer._();

  Future<void> _init() async {
    // Use current working directory for pure Dart execution
    basePath = path.join(Directory.current.path, 'lib', 'cache');

    await prepareFolders();
  }

  Future<void> copyImagesToSourceDir(List<String> imagePaths) async {
    try {
      final sourceDir = Directory(path.join(basePath, inputFolder));
      await sourceDir.create(recursive: true);

      for (String imagePath in imagePaths) {
        final fileName = path.basename(imagePath);
        final destination = path.join(sourceDir.path, fileName);

        // Read directly from file system
        // Read directly from file system
        final bytes = await File(imagePath).readAsBytes();

        await File(destination).writeAsBytes(bytes);

        if (kDebugMode) {
          print('Copied $fileName to $destination');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error copying images: $e');
      }
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

      if (kDebugMode) {
        print('Cache directory: $basePath');
        print('Input directory: $inputPath');
        print('Output directory: $outputPath');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error preparing folders: $e');
      }
      rethrow;
    }
  }

  Future<List<String>> findImages() async {
    try {
      final inputPath = path.join(basePath, inputFolder);

      if (!Directory(inputPath).existsSync()) {
        if (kDebugMode) {
          print('Input directory not found: $inputPath');
        }
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

      if (kDebugMode) {
        print('Found ${images.length} images in $inputPath');
      }

      return images;
    } catch (e) {
      if (kDebugMode) {
        print('Error finding images: $e');
      }
      return [];
    }
  }

  cv2.Mat opencvResize(cv2.Mat image, double ratio) {
    int width = (image.width * ratio).toInt();
    int height = (image.height * ratio).toInt();
    final dim = (width, height);
    return cv2.resize(image, dim, interpolation: cv2.INTER_AREA);
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
    // Scale points back to original image size
    var scaledRect = cv2.VecPoint.fromList(
      rect.toList().map((p) => cv2.Point(
        (p.x / resizeRatio).round(),
        (p.y / resizeRatio).round()
      )).toList()
    );
    
    // Order the points correctly
    var orderedRect = orderPoints(scaledRect);
    
    // Unpack rectangle points
    var tl = orderedRect[0];
    var tr = orderedRect[1];
    var br = orderedRect[2];
    var bl = orderedRect[3];

    // Calculate width and height using Euclidean distance
    double widthA = sqrt(pow(br.x - bl.x, 2) + pow(br.y - bl.y, 2)); 
    double widthB = sqrt(pow(tr.x - tl.x, 2) + pow(tr.y - tl.y, 2));
    double heightA = sqrt(pow(tr.x - br.x, 2) + pow(tr.y - br.y, 2));
    double heightB = sqrt(pow(tl.x - bl.x, 2) + pow(tl.y - bl.y, 2));

    double maxWidth = max(widthA, widthB);
    double maxHeight = max(heightA, heightB);

    // Create destination points
    List<Point2f> dst = [
      Point2f(0, 0),
      Point2f(maxWidth, 0),
      Point2f(maxWidth, maxHeight),
      Point2f(0, maxHeight),
    ];

    // Perform perspective transformation
    final temp = cv2.getPerspectiveTransform(
        orderedRect,
        cv2.VecPoint.fromList(
            dst.map((p) => cv2.Point(p.x.toInt(), p.y.toInt())).toList()));
    return cv2.warpPerspective(img, temp, (maxWidth.toInt(), maxHeight.toInt()));
  }

  cv2.VecPoint approximateContour(cv2.VecPoint contour) {
    // 1. Get the convex hull to "straighten" the edges
    var hull = cv2.convexHull(contour); 
    // Convert mat to cv2.VecPoint 
    var hullVec = cv2.VecPoint.fromMat(hull);
    // 2. Then approximate from the hull, not the raw contour
    double epsilon = 0.01 * cv2.arcLength(hullVec, true); 
    return cv2.approxPolyDP(hullVec, epsilon, true);
  }

  cv2.VecPoint getReceiptContour(List<cv2.VecPoint> contours) {
    for (var contour in contours) {
      var approx = approximateContour(contour);
      
      if (approx.length == 4) {
        return approx;
      }
    }
    return cv2.VecPoint(); // Return empty VecPoint if none found
  }


  cv2.VecPoint contourToRect(cv2.VecPoint contour, double resizeRatio) {
    final boundingRect = cv2.boundingRect(contour);
    final x = boundingRect.x;
    final y = boundingRect.y;
    final w = boundingRect.width;
    final h = boundingRect.height;

    // Corner points
    List<List<double>> rectPoints = [
      [x.toDouble(), y.toDouble()],
      [x.toDouble() + w, y.toDouble()],
      [x.toDouble() + w, y.toDouble() + h],
      [x.toDouble(), y.toDouble() + h],
    ];

    // Sums for top-left (min) / bottom-right (max)
    List<double> s = rectPoints.map((p) => p[0] + p[1]).toList();
    int minSumIndex = s.indexOf(s.reduce(min));
    int maxSumIndex = s.indexOf(s.reduce(max));

    // Differences for top-right (min) / bottom-left (max)
    List<double> diff = rectPoints.map((p) => p[1] - p[0]).toList();
    int minDiffIndex = diff.indexOf(diff.reduce(min));
    int maxDiffIndex = diff.indexOf(diff.reduce(max));

    // Arrange points
    List<List<double>> rect = List.generate(4, (_) => List.filled(2, 0.0));
    rect[0] = rectPoints[minSumIndex];
    rect[2] = rectPoints[maxSumIndex];
    rect[1] = rectPoints[minDiffIndex];
    rect[3] = rectPoints[maxDiffIndex];

    // Scale by resizeRatio
    List<List<double>> scaled =
        rect.map((p) => [p[0] / resizeRatio, p[1] / resizeRatio]).toList();

    // Convert back to cv2.VecPoint
    return cv2.VecPoint.fromList(
      scaled.map((p) => cv2.Point(p[0].round(), p[1].round())).toList(),
    );
  }

  Future<String> saveToOutput(cv2.Mat image, String originalFileName,
      {String? suffix}) async {
    try {
      final fileName = suffix != null
          ? '${path.basenameWithoutExtension(originalFileName)}_$suffix${path.extension(originalFileName)}'
          : path.basename(originalFileName);

      final outputPath = path.join(basePath, outputFolder, fileName);

      await Directory(path.dirname(outputPath)).create(recursive: true);

      cv2.imwrite(outputPath, image);

      if (kDebugMode) {
        print('Saved image to: $outputPath');
      }

      return outputPath;
    } catch (e) {
      if (kDebugMode) {
        print('Error saving image: $e');
      }
      rethrow;
    }
  }

  double percentile(cv2.Mat data, double p) {
    if (data.isEmpty) {
      throw ArgumentError('Data cannot be empty');
    }
    if (p < 0 || p > 100) {
      throw ArgumentError('Percentile must be between 0 and 100');
    }

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
  // Ensure we are working with Grayscale
  if (result.channels > 1) {
    result = cv2.cvtColor(result, cv2.COLOR_BGR2GRAY);
  }

  double minval = percentile(result, 4.5);
  double maxval = percentile(result, 95);

  // 1. Clip the values using OpenCV's thresholding/clipping
  // Anything below minval becomes minval; anything above maxval becomes maxval
  cv2.Mat clipped = result.clone();
  cv2.threshold(clipped, maxval, maxval, cv2.THRESH_TRUNC); // Cap at max
  cv2.threshold(clipped, minval, minval, cv2.THRESH_TOZERO_INV); // This is complex manually

  // 2. USE NORMALIZE - This replaces your second loop entirely and is more robust
  cv2.Mat normalized = cv2.Mat.empty();
  cv2.normalize(
    clipped, 
    normalized, 
    alpha: 0, 
    beta: 255, 
    normType: cv2.NORM_MINMAX, 
    dtype: cv2.MatType.CV_8U
  );

  return normalized;
}

  Future<void> saveProcessingStep(
      cv2.Mat image, String originalFileName, String step) async {
    await saveToOutput(image, originalFileName, suffix: 'step_$step');
  }

  void processReceipts(String fileName) async {
    var images = await findImages();
    for (var imagePath in images) {
      try {
        var fileName = path.basename(imagePath);
        // Read image
        cv2.Mat image = cv2.imread(imagePath);
        double resizeRatio = 1024 / image.shape[0];
        cv2.Mat original = image.clone();

        // Resize image
        image = opencvResize(image, resizeRatio);

        // Process image
        cv2.Mat gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);
        // await saveProcessingStep(gray, fileName, '1_grayscale');

        // cv2.Mat blurred = cv2.gaussianBlur(gray, (5, 5), 0);
        cv2.Mat filtered = cv2.bilateralFilter(gray, 9, 75, 75);
        // await saveProcessingStep(filtered, fileName, '2_filtered');

        cv2.Mat rectKernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9));


        cv2.Mat dilated = cv2.dilate(filtered, rectKernel);
        // await saveProcessingStep(dilated, fileName, '3_dilated');
        cv2.Mat closing = cv2.morphologyEx(
          dilated,
          cv2.MORPH_CLOSE,
          rectKernel,
          anchor: cv2.Point(-1, -1),
          iterations: 1,
          borderType: cv2.BORDER_REPLICATE,
        );
        // await saveProcessingStep(closing, fileName, '4_closing');

        cv2.Mat edged = cv2.canny(closing, 50, 125);
        // await saveProcessingStep(edged, fileName, '5_edged');

        // Find contours
        var (contours, hierarchy) = cv2.findContours(
          edged,
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

        // cv2.Mat contoursImage = original.clone();
        // cv2.drawContours(
        //   contoursImage,
        //   cv2.VecVecPoint.fromVecPoint(sortedContours.first),
        //   -1,
        //   cv2.Scalar.green,
        //   thickness: 3,
        // );
        // await saveProcessingStep(contoursImage, fileName, '6_largest_contours');
        // Sort contours by area

        var largestContours = sortedContours.take(10).toList(); // Take top 10 largest contours
        
        // // Draw approximated contours for visualization
        // cv2.Mat approxImage = original.clone();
        // for (var contour in largestContours) {
        //   var approx = approximateContour(contour);
        //   cv2.drawContours(
        //     approxImage,
        //     cv2.VecVecPoint.fromVecPoint(approx),
        //     -1,
        //     cv2.Scalar.blue,
        //     thickness: 3,
        //   );
        //   // Draw corner points in red
        //   for (var point in approx.toList()) {
        //     cv2.circle(
        //       approxImage,
        //       point,
        //       5,
        //       cv2.Scalar.red,
        //       thickness: -1,
        //     );
        //   }
        // }
        // await saveProcessingStep(approxImage, fileName, '7_approximated_contours');
        
        var receiptContour = getReceiptContour(largestContours);
        if (receiptContour.length != 4) {
          if (kDebugMode) {
            print('No 4-point receipt contour found in: $imagePath');
          }
          continue;
        }
        // var finalContour = original.clone();
        //   cv2.drawContours(
        //     finalContour,
        //     cv2.VecVecPoint.fromVecPoint(receiptContour),
        //     -1,
        //     cv2.Scalar.green,
        //     thickness: 3,
        //   );
        //   // Draw corner points in red
        //   for (var point in receiptContour.toList()) {
        //     cv2.circle(
        //       finalContour,
        //       point,
        //       5,
        //       cv2.Scalar.red,
        //       thickness: -1,
        //     );
        //   }
        
        // await saveProcessingStep(finalContour, fileName, '7_final_contour');
        var scanned = wrapPerspective(
            original, receiptContour, resizeRatio);
        // await saveProcessingStep(scanned, fileName, '7_scanned');
        var result = processImage(scanned);
        // await saveProcessingStep(result, fileName, '7_scanned');
        final savedPath = await saveToOutput(result, path.basename(imagePath),
            suffix: 'processed');
          print('Saved processed image to: $savedPath');
      } catch (e) {
          print('Error processing $imagePath: $e');
      }
    }
  }

}

Future<void> preworkImage() async {
  final recognizer = await ReceiptRecognizer.create();
  try {
    List<String> imageAssets = [];

    // Load images from assets/images directory (pure Dart approach)
    final assetsDir = Directory(path.join(Directory.current.path, 'assets', 'images'));
    if (assetsDir.existsSync()) {
      imageAssets = assetsDir
          .listSync(recursive: false)
          .whereType<File>()
          .where((f) => ['.jpg', '.jpeg', '.png']
              .contains(path.extension(f.path).toLowerCase()))
          .map((f) => f.path)
          .toList();
    }

    if (imageAssets.isEmpty) {
      throw StateError(
        'No images found to import. Place images in assets/images/ directory.',
      );
    }

    await recognizer.copyImagesToSourceDir(imageAssets);

    if (kDebugMode) {
      print('Imported ${imageAssets.length} images');
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error importing assets: $e');
    }
    rethrow;
  }
  recognizer.processReceipts('');
}

void main() {
  preworkImage();
}
