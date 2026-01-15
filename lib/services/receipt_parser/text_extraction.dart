// ignore_for_file: constant_identifier_names, non_constant_identifier_names, avoid_print

import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:frienance/services/receipt_parser/object_extraction.dart';
import 'package:frienance/utils/image_btw_mat_converter.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv2;
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
//
typedef Image = img.Image;
typedef Mat = cv2.Mat;
//

const String ORANGE = '\x1B[33m';
const String RESET = '\x1B[0m';
//


class Enhancer {
  late String basePath;
  final String INPUT_FOLDER =
      "2_temp_img"; 
  final String OUTPUT_FOLDER = "output";
  final String TMP_FOLDER = "temp";

  static Future<Enhancer> create({required String sharedBasePath}) async {
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

  Future<String?> scanDocument() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        pageLimit: 1,
        isGalleryImport: true,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      if (result.images.isEmpty) {
        return null;
      }
      final uriString = result.images.first;
      if (uriString.startsWith('file://')) {
        return Uri.parse(uriString).toFilePath();
      }
      return uriString;
    } catch (_) {
      return null;
    } finally {
      await scanner.close();
    }
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
      );
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      String text = "";

      for (var block in (recognizedText.blocks)) {
        String temp = "";
          for (TextLine line in block.lines) {
            temp += '${line.text} , ';
          }
        
        text += '$temp\n';
      }

      await File(outputFile).writeAsString(text, encoding: utf8);

      // Create contours folder and save contoured image
      final contoursFolder = Directory(path.join(basePath, 'with_contours'));
      contoursFolder.createSync(recursive: true);
      final contourOutput =
          path.join(contoursFolder.path, path.basename(inputFile));
        await drawContoursForTextBlocks(
          inputFile, recognizedText.blocks, contourOutput);

      textRecognizer.close();
    } catch (e) {
      print('$ORANGE\t~: $RESET Error during text recognition: $e $RESET');
      rethrow;
    }
  }

  img.Image rescaleImage(img.Image image) {
    print('$ORANGE\t~: $RESET Rescale image $RESET');
    int newWidth = (image.width * 2).toInt();
    int newHeight = (image.height * 2).toInt();
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
    img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY);

    img = cv2.morphologyEx(img,cv2.MORPH_CLOSE, kernel);

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

  Future<img.Image> enhanceImage(img.Image image, String tmpPath,
      {bool highContrast = true,
      bool gaussianBlur = true,
      bool rotate = true}) async {
    image = rescaleImage(image);
    if (rotate) {
      File(tmpPath).writeAsBytesSync(img.encodePng(image));
      var imageBytes = File(tmpPath).readAsBytesSync();
      image = img.decodeImage(imageBytes)!;
    }
    var temp_image = imageToMat(image);

    temp_image = removeShadows(temp_image);
    if (highContrast) {
      temp_image = imageToMat(grayscaleImage(matToImage(temp_image)));
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

    final scannedPath = await scanDocument();
    final sourcePath = scannedPath ?? inputPath;

    img.Image? image = img.decodeImage(File(sourcePath).readAsBytesSync());
    if (image == null) {
      print('Error: Unable to read image $sourcePath');
      return;
    }

    String tmpPath = path.join(basePath, TMP_FOLDER, filename);
    image = await enhanceImage(image, tmpPath,
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
      for (final lines in block.lines) {
        final rect = lines.boundingBox;
        img.drawRect(
          image,
          x1: rect.left.toInt(),
          y1: rect.top.toInt(),
          x2: (rect.left + rect.width).toInt(),
          y2: (rect.top + rect.height).toInt(),
          color: img.ColorRgb8(0, 102, 0),
          thickness: 2,
        );
      }
     
    }
    File(outputFile).writeAsBytesSync(img.encodePng(image));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Run ReceiptRecognizer
  final recognizer = await ReceiptRecognizer.create();
  await preworkImagesonEmulator();
  // Run Enhancer using the output from ReceiptRecognizer
  final enhancer = await Enhancer.create(sharedBasePath: recognizer.basePath);
  await enhancer.prepareFolders();
  var images = await enhancer.findImages(enhancer.INPUT_FOLDER);
  for (var imagePath in images) {
    final fileName = path.basename(imagePath);
    await enhancer.processReceipt(fileName);
  }
}
