import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frienance/utils/mat_extensions.dart';
import 'package:path/path.dart' as path;
import 'package:opencv_dart/opencv_dart.dart' as cv2;
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart';

typedef Point2f = cv2.Point2f;

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
          // break;
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
    List<Point2f> dst = [
      Point2f(0, 0),
      Point2f(maxWidth - 1, 0),
      Point2f(maxWidth - 1, maxHeight - 1),
      Point2f(0, maxHeight - 1),
    ];

    // Perform perspective transforcv2.Mation
    final temp = cv2.getPerspectiveTransform(
        rect,
        cv2.VecPoint.fromList(
            dst.map((p) => cv2.Point(p.x.toInt(), p.y.toInt())).toList()));
    return cv2.warpPerspective(img, temp, (maxWidth, maxHeight));
  }

  cv2.VecPoint approximateContour(cv2.VecPoint contour) {
    double epsilon = 0.01 * cv2.arcLength(contour, true);
    return cv2.approxPolyDP(contour, epsilon, true);
  }

  cv2.VecPoint getReceiptContour(List<cv2.VecPoint> contours) {
    for (var contour in contours) {
      var approx = approximateContour(contour);
      if (approx.length == 4) {
        return approx;
      } else {
        var rect = cv2.minAreaRect(contour);
        var box = cv2.boxPoints(rect);

        // box = cv2.VecPoint.fromList(
        //   box.map((p) => cv2.Point(p.x.toInt(), p.y.toInt())).toList(),
        // );
        return approx;
      }
    }

    return cv2.VecPoint();
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
    double minval = percentile(result, 4.5);
    double maxval = percentile(result, 95);

    cv2.Mat pixvals = result.clone();

    pixvals = result;

    for (int i = 0; i < pixvals.rows; i++) {
      for (int j = 0; j < pixvals.cols; j++) {
        num val = pixvals.at(i, j);
        val = max(minval, min(maxval, val)); // Clip
        pixvals.set(i, j, val); // Assuming you have a put method
      }
    }

    // Normalize the pixel values (example using manual looping)
    for (int i = 0; i < pixvals.rows; i++) {
      for (int j = 0; j < pixvals.cols; j++) {
        num val = pixvals.at(i, j);
        val = (val - minval) / (maxval - minval) * 255;
        pixvals.set(i, j, val);
      }
    }
    cv2.Mat rotatedResult = cv2.rotate(pixvals, cv2.ROTATE_180);

    return pixvals;
  }

  Future<void> saveProcessingStep(
      cv2.Mat image, String originalFileName, String step) async {
    await saveToOutput(image, originalFileName, suffix: 'step_$step');
  }

  void processReceipts() async {
    var images = await findImages();
    for (var imagePath in images) {
      try {
        // Read image
        cv2.Mat image = cv2.imread(imagePath);
        String fileName = path.basename(imagePath);
        double resizeRatio = 1024 / image.shape[0];
        cv2.Mat original = image.clone();

        // Resize image
        image = opencvResize(image, resizeRatio);

        // Process image
        cv2.Mat gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);
        // await saveProcessingStep(gray, fileName, '1_grayscale');

        cv2.Mat blurred = cv2.gaussianBlur(gray, (5, 5), 0);
        // await saveProcessingStep(blurred, fileName, '2_blurred');

        cv2.Mat rectKernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9));

        cv2.Mat dilated = cv2.dilate(blurred, rectKernel);
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

        cv2.Mat contoursImage = original.clone();
        cv2.drawContours(
          contoursImage,
          cv2.VecVecPoint.fromVecPoint(sortedContours.first),
          -1,
          cv2.Scalar.green,
          thickness: 3,
        );
        // await saveProcessingStep(contoursImage, fileName, '6_largest_contours');
        // Sort contours by area

        var largestContours = sortedContours.take(5).toList();

        var receiptContour = getReceiptContour(largestContours);

        if (receiptContour == null) {
          if (kDebugMode) {
            print('No receipt found in: $imagePath');
            continue;
          }
        }

        var scanned = wrapPerspective(
            original, contourToRect(receiptContour, resizeRatio));
        // await saveProcessingStep(scanned, fileName, '7_largest_contours');
        var result = processImage(scanned);
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

  Future<void> processIndividualImage(String srcImagePath) async {
    try {
      // Read image
      cv2.Mat image = cv2.imread(srcImagePath);
      String fileName = path.basename(srcImagePath);
      double resizeRatio = 1024 / image.shape[0];
      cv2.Mat original = image.clone();

      // Resize image
      image = opencvResize(image, resizeRatio);

      // Process image
      cv2.Mat gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);
      await saveProcessingStep(gray, fileName, '1_grayscale');

      cv2.Mat blurred = cv2.gaussianBlur(gray, (5, 5), 0);
      await saveProcessingStep(blurred, fileName, '2_blurred');

      cv2.Mat rectKernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9));

      cv2.Mat dilated = cv2.dilate(blurred, rectKernel);
      await saveProcessingStep(dilated, fileName, '3_dilated');

      cv2.Mat closing = cv2.morphologyEx(
        dilated,
        cv2.MORPH_CLOSE,
        rectKernel,
        anchor: cv2.Point(-1, -1),
        iterations: 1,
        borderType: cv2.BORDER_REPLICATE,
      );
      cv2.Mat kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2));
      closing = cv2.erode(closing, kernel);
      await saveProcessingStep(closing, fileName, '4_closing');

      cv2.Mat edged = cv2.canny(dilated, 50, 125);
      await saveProcessingStep(edged, fileName, '5_edged');

      // Find contours
      var (contours, hierarchy) = cv2.findContours(
        edged,
        cv2.RETR_EXTERNAL,
        cv2.CHAIN_APPROX_SIMPLE,
      );
      cv2.Mat contoursImage = original.clone();
      cv2.drawContours(
        contoursImage,
        contours,
        -1,
        cv2.Scalar.green,
        thickness: 3,
      );
      cv2.Mat cropRegion(cv2.Mat src, int offset) {
        int croppedWidth = src.width - offset * 2;
        int croppedHeight = src.height - offset * 2;
        cv2.Mat output = cv2.Mat.zeros(croppedHeight, croppedWidth, src.type);
        for (int y = 0; y < croppedHeight; y++) {
          for (int x = 0; x < croppedWidth; x++) {
            output.set(y, x, src.at(y + offset, x + offset));
          }
        }
        return output;
      }

      // After closing/erosion steps:
      int offset = 5;
      cv2.Mat cropped = cropRegion(closing, offset);
      await saveProcessingStep(closing, fileName, '6_largest_contours');
      // Sort contours by area
      contours.toList().sort((a, b) {
        double areaA = cv2.contourArea(a);
        double areaB = cv2.contourArea(b);
        return areaB.compareTo(areaA);
      });

      var largestContours = contours.take(10).toList();
      // if (largestContours.isNotEmpty) {
      //   largestContours.removeAt(0);
      // }
      var receiptContour = getReceiptContour(largestContours);

      var scanned =
          wrapPerspective(original, contourToRect(receiptContour, resizeRatio));

      var result = processImage(scanned);
      final savedPath = await saveToOutput(result, path.basename(srcImagePath),
          suffix: 'processed');
      if (kDebugMode) {
        print('Saved processed image to: $savedPath');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error processing $srcImagePath: $e');
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

void main() {
  preworkImage();
}
