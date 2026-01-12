// ignore_for_file: constant_identifier_names, non_constant_identifier_names, avoid_print

import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:frienance/services/parser/receipt_recognizer.dart';
import 'package:frienance/utils/image_btw_mat_converter.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv2;
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:exif/exif.dart';

//
typedef Image = img.Image;
typedef Mat = cv2.Mat;
//

const String ORANGE = '\x1B[33m';
const String RESET = '\x1B[0m';
//

// Enum for EXIF orientation values
enum ExifOrientation {
  normal(1),
  flipHorizontal(2),
  rotate180(3),
  flipVertical(4),
  transpose(5),
  rotate90(6),
  transverse(7),
  rotate270(8);

  const ExifOrientation(this.value);
  final int value;

  factory ExifOrientation.fromInt(int value) {
    return ExifOrientation.values.firstWhere((e) => e.value == value);
  }
}

//
class Enhancer {
  late String basePath;
  final String INPUT_FOLDER =
      "2_temp_img"; 
  final String OUTPUT_FOLDER = "output";
  final String TMP_FOLDER = "temp";

  static Future<Enhancer> create({required String sharedBasePath}) async {
    WidgetsFlutterBinding.ensureInitialized();
    final instance = Enhancer._();
    instance.basePath = sharedBasePath; // Use shared basePath
    await instance._init();
    return instance;
  }

  Enhancer._();

  Future<void> _init() async {
    await prepareFolders();
  }

  Future<void> prepareFolders() async {
    await Future.wait([
      // Do not recreate INPUT_FOLDER
      Directory(path.join(basePath, OUTPUT_FOLDER)).create(recursive: true),
      Directory(path.join(basePath, TMP_FOLDER)).create(recursive: true),
    ]);
  }

  Future<List<String>> findImages(String folder) async {
    final inputPath = path.join(basePath, folder);
    if (!Directory(inputPath).existsSync()) {
      print('Input directory not found: $inputPath');
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

    print('Found ${images.length} images in $inputPath');
    return images;
  }

  void rotateImage(String inputFile, String outputFile, {double angle = 90}) {
    final file = File(inputFile);
    if (!file.existsSync()) {
      print('Error: Input file not found.');
      return;
    }

    final imageBytes = file.readAsBytesSync();
    img.Image? image = img.decodeImage(imageBytes);

    if (image == null) {
      print('Error: Could not decode image.');
      return;
    }

    // Check orientation based on EXIF data if available
    final orientation = getExifOrientation(imageBytes);
    switch (orientation) {
      // ignore: constant_pattern_never_matches_value_type
      case ExifOrientation.rotate90:
        angle = 90;
        break;
      // ignore: constant_pattern_never_matches_value_type
      case ExifOrientation.rotate180:
        angle = 180;
        break;
      // ignore: constant_pattern_never_matches_value_type
      case ExifOrientation.rotate270:
        angle = 270;
        break;
      default:
        angle = 0; // Or keep the original angle if needed
    }

    print('$ORANGE\t~: $RESET Rotate image by: $angle° $RESET');

    final rotatedImage = img.copyRotate(image, angle: angle);
    File(outputFile).writeAsBytesSync(img.encodePng(rotatedImage));
  }

// Helper function to get orientation from EXIF data (if available)
  Future<ExifOrientation?> getExifOrientation(List<int> imageBytes) async {
    try {
      final exifData = await readExifFromBytes(imageBytes);
      final orientationTag = exifData['Orientation'];
      if (orientationTag != null) {
        return ExifOrientation.fromInt(int.parse(orientationTag.printable));
      }
    } catch (e) {
      print('Error reading EXIF data: $e');
    }
    return null;
  }

  cv2.Mat deskewImage(cv2.Mat image) {
    cv2.Mat gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);

    // Invert colors (optional, if needed)
    if (cv2.mean(gray).val[0] > 127) {
      gray = cv2.bitwiseNOT(gray);
    }

    cv2.Mat thresh = cv2
        .threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        .$2; // Note: [1] for the thresholded image

    // 1. Morphological closing to fill small gaps
    var closeKernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 1));
    thresh = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, closeKernel);

    // 2. Adjust minLineLength and maxLineGap
    cv2.Mat lines = cv2.HoughLinesP(thresh, 1, cv2.CV_PI / 180,
        50, // Lower threshold to detect lines with fewer votes
        minLineLength: 20,
        maxLineGap: 50 // Increase to allow larger breaks
        );

    double angle = 0;
    int count = 0;
    for (var line in lines.toList()) {
      double angleTemp =
          atan2(line[3] - line[1], line[2] - line[0]) * 180 / cv2.CV_PI;
      if (angleTemp.abs() < 45) {
        // Consider lines close to horizontal
        angle += angleTemp;
        count++;
      }
    }

    if (count > 0) {
      angle /= count;
    }

    cv2.Point2f center =
        cv2.Point2f(image.cols / 2, image.rows / 2); // Integer division
    cv2.Mat rotationMatrix = cv2.getRotationMatrix2D(center, angle, 1.0);
    cv2.Mat rotated = cv2.Mat.zeros(image.rows, image.cols,
        cv2.MatType.CV_8UC3); // Create a destination Mat
    cv2.warpAffine(
        image, // The input image you want to rotate.
        rotationMatrix, // The transformation matrix calculated by getRotationMatrix2D.
        (
          image.cols,
          image.rows
        ), // The size of the output image (width, height).
        dst:
            rotated, // The output image (destination) where the rotated image will be stored.
        flags: cv2
            .INTER_CUBIC, // Interpolation method (INTER_CUBIC for high-quality resizing).
        borderMode: cv2
            .BORDER_REPLICATE // How to handle borders (REPLICATE to repeat edge pixels).
        );

    return rotated;
  }

  Future<void> runMLKitTextRecognition(
      String inputFile, String outputFile) async {
    print(
        '$ORANGE\t~: $RESET Parse image using ML Kit Text Recognition $RESET');
    print('$ORANGE\t~: $RESET Parse image at: $inputFile $RESET');
    print('$ORANGE\t~: $RESET Write result to: $outputFile $RESET');

    try {
      final inputImage = InputImage.fromFilePath(inputFile);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      String text = "";

      for (var block in clusterVerticalLines(recognizedText.blocks)) {
        String temp = "";
        for (TextBlock j in block) {
          for (TextLine line in j.lines) {
            temp += '${line.text} , ';
          }
        }
        text += '$temp\n';
      }

      await File(outputFile).writeAsString(text, encoding: utf8);

      // Create contours folder and save contoured image
      final contoursFolder = Directory(path.join(basePath, 'with_contours'));
      contoursFolder.createSync(recursive: true);
      final contourOutput =
          path.join(contoursFolder.path, path.basename(inputFile));
      await drawContoursForTextBlocks(inputFile, recognizedText.blocks, contourOutput);

      textRecognizer.close();
    } catch (e) {
      print('$ORANGE\t~: $RESET Error during text recognition: $e $RESET');
      rethrow;
    }
  }
List<List<TextBlock>> clusterVerticalLines(List<TextBlock> blocks, {int k = 10}) {
  // 1. Extract horizontal center points of each block
  List<cv2.Point2f> points = blocks
      .map((block) => cv2.Point2f(block.boundingBox.center.dx, 0))
      .toList();

  // 2. Prepare data for K-means
  cv2.Mat data = cv2.Mat.fromList(
    points.length,
    1,
    cv2.MatType.CV_32F as cv2.MatType,
    points.map((p) => p.x.toDouble()).toList(),
  );

  // 3. Apply K-means clustering
  cv2.Mat labels =
      cv2.Mat.zeros(points.length, 1, cv2.MatType.CV_32F as cv2.MatType);
  cv2.Mat centers =
      cv2.Mat.zeros(k, 1, cv2.MatType.CV_32F as cv2.MatType);

  cv2.kmeans(
    data,
    k,
    labels,
    (cv2.TERM_EPS + cv2.TERM_MAX_ITER, 30, 0.1),
    10,
    cv2.KMEANS_PP_CENTERS,
    centers: centers,
  );

  // 4. Group blocks based on clusters
  List<List<TextBlock>> clusteredLines = List.generate(k, (_) => []);
  for (int i = 0; i < blocks.length; i++) {
    int clusterIndex = labels.atNum(i, 0).toInt();
    clusteredLines[clusterIndex].add(blocks[i]);
  }

  clusteredLines = mergeCloseClusters(clusteredLines, centers, threshold: 5);
  return clusteredLines;
}
List<List<TextBlock>> mergeCloseClusters(
    List<List<TextBlock>> clusteredLines, cv2.Mat centers,
    {double threshold = 20}) {
  for (int i = 0; i < centers.rows - 1; i++) {
    for (int j = i + 1; j < centers.rows; j++) {
      double distance =
          (centers.atNum(i, 0).toDouble() - centers.atNum(j, 0).toDouble())
              .abs();
      if (distance < threshold) {
        clusteredLines[i].addAll(clusteredLines[j]);
        clusteredLines[j].clear();
      }
    }
  }
  clusteredLines.removeWhere((cluster) => cluster.isEmpty);
  return clusteredLines;
}

  img.Image rescaleImage(img.Image image) {
    print('$ORANGE\t~: $RESET Rescale image $RESET');
    int newWidth = (image.width * 1.5).toInt();
    int newHeight = (image.height * 1.5).toInt();
    return img.copyResize(image,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.cubic);
  }

  img.Image grayscaleImage(img.Image image) {
    print('$ORANGE\t~: $RESET Grayscale image $RESET');
    img.Image grayscale = img.grayscale(image);
    img.Image lightened = img.adjustColor(grayscale);
    return lightened;
  }

  Mat removeNoise(cv2.Mat img) {
    var kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, 1));

    img = cv2.dilate(img, kernel);
    img = cv2.erode(img, kernel);

    img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY);
    img = cv2
        .threshold(cv2.gaussianBlur(img, (5, 5), 0), 150, 255,
            cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        .$2;
    img = cv2
        .threshold(cv2.bilateralFilter(img, 5, 75, 75), 0, 255,
            cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        .$2;
    img = cv2.adaptiveThreshold(
      cv2.bilateralFilter(img, 9, 75, 75),
      255,
      cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv2.THRESH_BINARY,
      11,
      1,
    );
    //  var kernel2 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2, 2));
    // img = cv2.erode(img, kernel2, iterations: 1);
    return img;
  }

  cv2.Mat removeShadows(cv2.Mat img) {
    cv2.VecMat rgbPlanes = cv2.split(img);
    List<cv2.Mat> resultPlanes = [];

    for (var plane in rgbPlanes) {
      var dilatedImg = cv2.dilate(
        plane,
        cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7)),
      );
      var bgImg = cv2.medianBlur(dilatedImg, 21);
      var absDiff = cv2.absDiff(plane, bgImg);

      // Create a scalar matrix with the same size and type as absDiff
      var scalarMat = cv2.Mat.create(
        rows: absDiff.rows,
        cols: absDiff.cols,
        type: absDiff.type,
      );
      scalarMat.setTo(cv2.Scalar.all(255));
      // Perform the subtraction
      var resultImg = cv2.subtract(scalarMat, absDiff);
      resultPlanes.add(resultImg);
    }

    final result = cv2.merge(cv2.VecMat.fromList(resultPlanes));
    return result;
  }

  img.Image enhanceImage(img.Image image, String tmpPath,
      {bool highContrast = true,
      bool gaussianBlur = true,
      bool rotate = true}) {
    image = rescaleImage(image);
    if (rotate) {
      File(tmpPath).writeAsBytesSync(img.encodePng(image));
      rotateImage(tmpPath, tmpPath);
      var imageBytes = File(tmpPath).readAsBytesSync();
      image = img.decodeImage(imageBytes)!;
    }
    var temp_image = imageToMat(image);

    temp_image = deskewImage(temp_image);

    temp_image = removeShadows(temp_image);
    if (highContrast) {
      temp_image = imageToMat(grayscaleImage(matToImage(temp_image)));
    }

    if (gaussianBlur) {
      temp_image = removeNoise(temp_image);
    }

    return matToImage(temp_image);
  }

  Future<void> processReceipt(String filename,
      {bool rotate = true,
      bool grayscale = true,
      bool gaussianBlur = true}) async {
    String inputPath = path.join(basePath, INPUT_FOLDER, filename);
    String outputPath =
        path.join(basePath, OUTPUT_FOLDER, '${filename.split('.').first}.txt');

    print('Processing image: $inputPath');

    img.Image? image = img.decodeImage(File(inputPath).readAsBytesSync());
    if (image == null) {
      print('Error: Unable to read image $inputPath');
      return;
    }

    String tmpPath = path.join(basePath, TMP_FOLDER, filename);
    image = enhanceImage(image, tmpPath,
        highContrast: grayscale, gaussianBlur: gaussianBlur);

    print('Temporary image stored at: $tmpPath');
    File(tmpPath).writeAsBytesSync(img.encodePng(image));

    await runMLKitTextRecognition(tmpPath, outputPath);

    print('Parsed text saved at: $outputPath');
  }

  Future<void> drawContoursForTextBlocks(
    String inputFile,
    List<TextBlock> recognizedTextBlocks,
    String outputFile,
  ) async {
    final file = File(inputFile);
    if (!file.existsSync()) return;
    img.Image? image = img.decodeImage(file.readAsBytesSync());
    if (image == null) return;

    for (final block in recognizedTextBlocks) {
      final rect = block.boundingBox;
      img.drawRect(
        image,
        x1: rect.left.toInt(),
        y1: rect.top.toInt(),
        x2: (rect.left + rect.width).toInt(),
        y2: (rect.top + rect.height).toInt(),
        color: img.ColorRgb8(255, 0, 0),
        thickness: 2,
      );
    }
    File(outputFile).writeAsBytesSync(img.encodePng(image));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Run ReceiptRecognizer
  final recognizer = await ReceiptRecognizer.create();
  await preworkImage();
  // Run Enhancer using the output from ReceiptRecognizer
  final enhancer = await Enhancer.create(sharedBasePath: recognizer.basePath);
  await enhancer.prepareFolders();
  var images = await enhancer.findImages(enhancer.INPUT_FOLDER);
  for (var imagePath in images) {
    final fileName = path.basename(imagePath);
    await enhancer.processReceipt(fileName);
  }
}
