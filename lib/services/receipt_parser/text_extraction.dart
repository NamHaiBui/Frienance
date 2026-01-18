// ignore_for_file: constant_identifier_names, non_constant_identifier_names, avoid_print

import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:frienance/services/receipt_parser/object_extraction.dart';
import 'package:frienance/services/receipt_parser/utils/image_btw_mat_converter.dart';
import 'package:frienance/services/receipt_parser/utils/line_list.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv2;
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:google_ml_kit/google_ml_kit.dart';
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

  /// Last line-sweep grouping results (each inner list is a line of text).
  List<List<String>> lastLineSweepResults = [];

  /// Last line-sweep linked list heads (one per line).
  List<LineNode?> lastLineSweepNodes = [];
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

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

  Future<void> runMLKitTextRecognition(
      String inputFile, String outputFile) async {
    print(
        '$ORANGE\t~: $RESET Parse image using ML Kit Text Recognition $RESET');
    print('$ORANGE\t~: $RESET Parse image at: $inputFile $RESET');
    print('$ORANGE\t~: $RESET Write result to: $outputFile $RESET');

    try {
      final inputImage = InputImage.fromFilePath(inputFile);

      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      final groupedLines = _groupTextLinesByLineSweep(recognizedText.blocks);

      lastLineSweepResults = groupedLines
          .map((line) => line.map((entry) => entry.text).toList())
          .toList();

      lastLineSweepNodes = groupedLines.map(_buildLineList).toList();

      String text = "";
      for (final head in lastLineSweepNodes) {
        text += _lineListToText(head);
        text += '\n';
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
    int newWidth = (image.width * 1.25).toInt();
    int newHeight = (image.height *1.25).toInt();
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

    // final scannedPath = await scanDocument();
    final sourcePath =  inputPath;

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

  void cleanupAfterImage() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
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

  List<List<_LineEntry>> _groupTextLinesByLineSweep(
    List<TextBlock> blocks, {
    double lineGapThresholdPx = 1,
    double overlapPaddingPx = 2,
  }) {
    final entries = <_LineEntry>[];
    for (final block in blocks) {
      for (final line in block.lines) {
        final rect = line.boundingBox;
        entries.add(_LineEntry(
          text: line.text,
          rect: rect,
          left: rect.left.toDouble(),
          right: (rect.left + rect.width).toDouble(),
          top: rect.top.toDouble(),
          bottom: (rect.top + rect.height).toDouble(),
        ));
      }
    }
    if (entries.isEmpty) return [];

    entries.sort((a, b) {
      final centerCompare = a.centroidY.compareTo(b.centroidY);
      if (centerCompare != 0) return centerCompare;
      return a.left.compareTo(b.left);
    });

    final results = <List<_LineEntry>>[];
    final currentLineStack = <_LineEntry>[];
    double currentMinTop = entries.first.top;
    double currentMaxBottom = entries.first.bottom;
    double currentAvgCenter = entries.first.centroidY;
    double currentAvgHeight = entries.first.height;

    void flushCurrentLine() {
      if (currentLineStack.isEmpty) return;
      currentLineStack.sort((a, b) => a.left.compareTo(b.left));
      results.add(List<_LineEntry>.from(currentLineStack));
      currentLineStack.clear();
    }

    void startNewLine(_LineEntry entry) {
      currentLineStack.add(entry);
      currentMinTop = entry.top;
      currentMaxBottom = entry.bottom;
      currentAvgCenter = entry.centroidY;
      currentAvgHeight = entry.height;
    }

    startNewLine(entries.first);

    for (var i = 1; i < entries.length; i++) {
      final entry = entries[i];

      final dynamicThreshold =
          (currentAvgHeight * 0.4).clamp(lineGapThresholdPx, double.infinity);

        final centerAligned =
          (entry.centroidY - currentAvgCenter).abs() <= dynamicThreshold;

      final tooFarDown = entry.top > currentMaxBottom + dynamicThreshold;

      if (tooFarDown) {
        flushCurrentLine();
        startNewLine(entry);
        continue;
      }

      if (centerAligned) {
        currentLineStack.add(entry);
        final count = currentLineStack.length;
        currentMinTop = currentMinTop < entry.top ? currentMinTop : entry.top;
        currentMaxBottom =
            currentMaxBottom > entry.bottom ? currentMaxBottom : entry.bottom;
        currentAvgCenter =
            ((currentAvgCenter * (count - 1)) + entry.centroidY) / count;
        currentAvgHeight =
            ((currentAvgHeight * (count - 1)) + entry.height) / count;
      } else {
        flushCurrentLine();
        startNewLine(entry);
      }
    }

    flushCurrentLine();
    results.sort((a, b) {
      final aCenter = a.isEmpty
          ? 0.0
          : a.map((entry) => entry.centroidY).reduce((x, y) => x + y) /
              a.length;
      final bCenter = b.isEmpty
          ? 0.0
          : b.map((entry) => entry.centroidY).reduce((x, y) => x + y) /
              b.length;
      return aCenter.compareTo(bCenter);
    });
    return results;
  }

  LineNode? _buildLineList(List<_LineEntry> lineEntries) {
    if (lineEntries.isEmpty) return null;

    final sorted = [...lineEntries]..sort((a, b) => a.left.compareTo(b.left));
    final head = LineNode(sorted.first.text, sorted.first.rect);
    LineNode? current = head;

    for (var i = 1; i < sorted.length; i++) {
      final entry = sorted[i];
      final next = LineNode(entry.text, entry.rect);
      current!.next = next;
      current = next;
    }

    return head;
  }

  String _lineListToText(LineNode? head) {
    if (head == null) return '';
    final parts = <String>[];
    LineNode? current = head;
    while (current != null) {
      parts.add(current.text);
      current = current.next;
    }
    return parts.join(' -> ');
  }
}

class _LineEntry {
  // Line entry is a plain debuggable class for line-sweep grouping.
  _LineEntry({
    required this.text,
    required this.rect,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  final String text;
  final Rect rect;
  final double left;
  final double right;
  final double top;
  final double bottom;

  Offset get topLeft => Offset(left, top);
  Offset get topRight => Offset(right, top);
  Offset get bottomLeft => Offset(left, bottom);
  Offset get bottomRight => Offset(right, bottom);

  double get centroidX =>
      (topLeft.dx + topRight.dx + bottomLeft.dx + bottomRight.dx) / 4;
  double get centroidY =>
      (topLeft.dy + topRight.dy + bottomLeft.dy + bottomRight.dy) / 4;
  double get height => (bottom - top).abs();
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
    enhancer.cleanupAfterImage();
  }
}
