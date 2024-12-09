import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:opencv_dart/opencv_dart.dart' as cv2;
import 'package:path_provider/path_provider.dart';

class Point {
  final double x;
  final double y;
  Point(this.x, this.y);
  cv2.Point toCvPoint() {
    return cv2.Point(x.toInt(), y.toInt());
  }
}

class ReceiptRecognizer {
  String basePath = 'D:\\Side Ultimatum\\Frienance\\lib\\cache';
  final String inputFolder = "1_source_img";
  final String outputFolder = "2_temp_img";

  static Future<ReceiptRecognizer> create() async {
    WidgetsFlutterBinding.ensureInitialized();
    final instance = ReceiptRecognizer._();
    await instance._init();
    return instance;
  }

  ReceiptRecognizer._();

  Future<void> _init() async {
    // Use application documents directory
    final documentsDirectory = await getApplicationDocumentsDirectory();
    basePath = path.join(documentsDirectory.path, 'cache');

    await prepareFolders();
  }

  Future<void> copyImagesToSourceDir(List<String> imagePaths) async {
    try {
      final sourceDir = Directory(path.join(basePath, inputFolder));
      await sourceDir.create(recursive: true);

      for (String imagePath in imagePaths) {
        final fileName = path.basename(imagePath);
        final destination = path.join(sourceDir.path, fileName);

        // Get asset from app bundle
        final byteData = await rootBundle.load('assets/images/$fileName');
        final buffer = byteData.buffer;

        // Write to emulator storage
        await File(destination).writeAsBytes(
            buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));

        if (kDebugMode) {
          print('Copied $fileName to $destination');
        }
        break;
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

  List<Point> findRectPoints(cv2.VecPoint contour, double resizeRatio) {
    // Get bounding rectangle coordinates
    cv2.Rect rect = cv2.boundingRect(contour);
    int x = rect.x;
    int y = rect.y;
    int w = rect.width;
    int h = rect.height;

    // Create a list of points representing the rectangle
    var rectPoints = [
      Point(x.toDouble(), y.toDouble()),
      Point((x + w).toDouble(), y.toDouble()),
      Point((x + w).toDouble(), (y + h).toDouble()),
      Point(x.toDouble(), (y + h).toDouble()),
    ];

    // Sort the points to ensure correct order (top-left, top-right, bottom-right, bottom-left)
    rectPoints.sort((a, b) {
      // Sort by sum of x and y (top-left has the smallest sum, bottom-right the largest)
      var sumA = a.x + a.y;
      var sumB = b.x + b.y;
      if (sumA != sumB) {
        return sumA.compareTo(sumB);
      }
      // If sums are equal, sort by difference of x and y (top-right has the smallest difference, bottom-left the largest)
      return (a.x - a.y).compareTo(b.x - b.y);
    });

    // Scale the points back using the resize ratio
    return rectPoints
        .map((p) => Point(p.x / resizeRatio, p.y / resizeRatio))
        .toList();
  }

  cv2.Mat wrapPerspective(cv2.Mat img, cv2.VecPoint rect) {
    // Unpack rectangle points
    var tl = rect[0];
    var tr = rect[1];
    var br = rect[2];
    var bl = rect[3];

    // Calculate width and height
    double widthA = sqrt(pow(br.x - bl.x, 2) + pow(br.y - bl.y, 2));
    double widthB = sqrt(pow(tr.x - tl.x, 2) + pow(tr.y - tl.y, 2));
    double heightA = sqrt(pow(tr.x - br.x, 2) + pow(tr.y - br.y, 2));
    double heightB = sqrt(pow(tl.x - bl.x, 2) + pow(tl.y - bl.y, 2));

    int maxWidth = max(widthA.toInt(), widthB.toInt());
    int maxHeight = max(heightA.toInt(), heightB.toInt());

    // Create destination points
    List<Point> dst = [
      Point(0, 0),
      Point(maxWidth - 1, 0),
      Point(maxWidth - 1, maxHeight - 1),
      Point(0, maxHeight - 1),
    ];

    // Perform perspective transforcv2.Mation
    final temp = cv2.getPerspectiveTransform(
        rect, cv2.VecPoint.fromList(dst.map((p) => p.toCvPoint()).toList()));
    return cv2.warpPerspective(img, temp, (maxWidth, maxHeight));
  }

  cv2.VecPoint approximateContour(cv2.VecPoint contour) {
    double epsilon = 0.01 * cv2.arcLength(contour, true);
    return cv2.approxPolyDP(contour, epsilon, true);
  }

  cv2.VecPoint? getReceiptContour(List<cv2.VecPoint> contours) {
    for (var contour in contours) {
      var approx = approximateContour(contour);
      if (approx.length == 4) {
        return contour;
      }
    }
    return null;
  }

  cv2.Mat bwScanner(cv2.Mat image) {
    // Convert to grayscale
    cv2.Mat gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);

    // Create sharpening kernel using proper initialization
    List<List<double>> kernelData = [
      [-1.0, -1.0, -1.0],
      [-1.0, 9.0, -1.0],
      [-1.0, -1.0, -1.0]
    ];
    cv2.Mat kernel =
        cv2.Mat.from2DList(kernelData, cv2.MatType.CV_64F as cv2.MatType);

    // Apply sharpening filter
    cv2.Mat sharpen = cv2.filter2D(gray, -1, kernel);

    // Apply threshold
    final thresh = cv2.threshold(
      sharpen,
      0,
      255,
      cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU,
    );

    return cv2.bitwiseNOT(thresh.$2);
  }

  cv2.VecPoint contourToRect(cv2.VecPoint contour, double resizeRatio) {
    // Calculate the bounding rectangle of the contour
    var boundingRect = cv2.boundingRect(contour);
    int x = boundingRect.x;
    int y = boundingRect.y;
    int w = boundingRect.width;
    int h = boundingRect.height;

    // Create a list of rectangle points
    List<cv2.Point> rectPoints = [
      cv2.Point(x, y),
      cv2.Point(x + w, y),
      cv2.Point(x + w, y + h),
      cv2.Point(x, y + h),
    ];

    // Order the rectangle points: top-left, top-right, bottom-right, bottom-left
    List<cv2.Point> rect = List.filled(4, cv2.Point(0, 0));
    List<int> sums = rectPoints.map((p) => p.x + p.y).toList();
    List<int> diffs = rectPoints.map((p) => p.x - p.y).toList();
    rect[0] = rectPoints[sums.indexOf(sums.reduce((a, b) => a < b ? a : b))];
    rect[2] = rectPoints[sums.indexOf(sums.reduce((a, b) => a > b ? a : b))];
    rect[1] = rectPoints[diffs.indexOf(diffs.reduce((a, b) => a < b ? a : b))];
    rect[3] = rectPoints[diffs.indexOf(diffs.reduce((a, b) => a > b ? a : b))];

    return cv2.VecPoint.fromList(rect
        .map((p) =>
            cv2.Point((p.x / resizeRatio).toInt(), (p.y / resizeRatio).toInt()))
        .toList());
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

  void processReceipts() async {
    var images = await findImages();
    for (var imagePath in images) {
      try {
        // Read image
        cv2.Mat image = cv2.imread(imagePath);
        double resizeRatio = 500 / image.rows;
        cv2.Mat original = image.clone();

        // Resize image
        image = opencvResize(image, resizeRatio);

        // Process image
        cv2.Mat gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);
        cv2.Mat blurred = cv2.gaussianBlur(
          gray,
          (5, 5),
          0,
        );

        // Create rectangular kernel and apply morphological operations
        cv2.Mat rectKernel = cv2.getStructuringElement(
          cv2.MORPH_RECT,
          (9, 9),
        );

        cv2.Mat dilated = cv2.dilate(blurred, rectKernel);
        cv2.Mat closing = cv2.morphologyEx(
          dilated,
          cv2.MORPH_CLOSE,
          rectKernel,
        );

        cv2.Mat edged = cv2.canny(closing, 50, 200);

        // Find contours
        var (contours, hierarchy) = cv2.findContours(
          edged,
          cv2.RETR_EXTERNAL,
          cv2.CHAIN_APPROX_SIMPLE,
        );

        // Sort contours by area
        contours.toList().sort((a, b) {
          double areaA = cv2.contourArea(a);
          double areaB = cv2.contourArea(b);
          return areaB.compareTo(areaA);
        });

        var largestContours = contours.take(10).toList();

        var receiptContour = getReceiptContour(largestContours);

        if (receiptContour == null) {
          if (kDebugMode) {
            print('No receipt found in: $imagePath');
            continue;
          }
        }

        // Transform perspective
        var scanned = wrapPerspective(
            original, contourToRect(receiptContour!, resizeRatio));

        // Apply black and white scanner effect
        var result = cv2.rotate(
            cv2.flip(bwScanner(scanned), 1), cv2.ROTATE_90_COUNTERCLOCKWISE);

        final savedPath = await saveToOutput(result, path.basename(imagePath),
            suffix: 'processed');
        if (kDebugMode) {
          print('Saved processed image to: $savedPath');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error processing $imagePath: $e');
        }
      }
    }
  }
}

Future<void> preworkImage() async {
  final recognizer = await ReceiptRecognizer.create();
  try {
    // List all assets from pubspec.yaml
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);

    // Filter image files from assets
    final imageAssets = manifestMap.keys
        .where((String key) =>
            key.startsWith('assets/images/') &&
            ['.jpg', '.jpeg', '.png']
                .contains(path.extension(key).toLowerCase()))
        .toList();

    // Copy all found images
    await recognizer.copyImagesToSourceDir(imageAssets);

    if (kDebugMode) {
      print('Imported ${imageAssets.length} images from assets');
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error importing assets: $e');
    }
    rethrow;
  }
  recognizer.processReceipts();
}
