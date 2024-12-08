// ignore_for_file: constant_identifier_names, non_constant_identifier_names, avoid_print

import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:frienance/utils/image_btw_mat_converter.dart';
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

String BASE_PATH = Directory.current.path;
String INPUT_FOLDER = path.join(BASE_PATH, 'lib', 'cache', '1_source_img');
String TMP_FOLDER = path.join(BASE_PATH, 'lib', 'cache', '2_temp_img');
String OUTPUT_FOLDER = path.join(BASE_PATH, 'lib', 'cache', '3_results');

void prepareFolders() {
  for (var folder in [INPUT_FOLDER, TMP_FOLDER, OUTPUT_FOLDER]) {
    if (!Directory(folder).existsSync()) {
      Directory(folder).createSync(recursive: true);
    }
  }
}

Iterable<String> findImages(String folder) {
  return Directory(folder)
      .listSync()
      .where((entity) =>
          entity is File &&
          ['.jpg', '.jpeg', '.png', '.bmp', '.tiff']
              .contains(path.extension(entity.path).toLowerCase()))
      .map((entity) => path.basename(entity.path));
}

void rotateImage(String inputFile, String outputFile, {double angle = 90}) {
  var imageBytes = File(inputFile).readAsBytesSync();
  img.Image? image = img.decodeImage(imageBytes);

  if (image == null) {
    print('Error: Could not decode image.');
    return;
  }

  int width = image.width;
  int height = image.height;

  if (width < height) {
    angle = 0;
  }

  print('$ORANGE\t~: $RESET Rotate image by: $angle° $RESET');

  img.Image rotatedImage = img.copyRotate(image, angle: angle);

  File(outputFile).writeAsBytesSync(img.encodePng(rotatedImage));
}

Mat deskewImage(Mat image, {double delta = 0.5, double limit = 5}) {
  // Convert the image to grayscale
  Mat gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY);

  // Apply Otsu's thresholding to create a binary image
  Mat thresh =
      cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU).$2;

  List<double> scores = [];
  List<double> angles = [];
  for (double angle = -limit; angle <= limit + delta; angle += delta) {
    angles.add(angle);
    Mat rotated = imageToMat(img.copyRotate(matToImage(thresh), angle: angle));
    List<int> histogram = List.filled(rotated.rows, 0);
    for (int y = 0; y < rotated.rows; y++) {
      for (int x = 0; x < rotated.cols; x++) {
        if (rotated.atPixel(x, y)[0] > 0) {
          histogram[y]++;
        }
      }
    }
    double score = 0;
    for (int i = 1; i < histogram.length; i++) {
      score += pow(histogram[i] - histogram[i - 1], 2);
    }
    scores.add(score);
  }

  // Find the angle with the highest score
  double bestAngle = angles[scores.indexOf(scores.reduce(max))];

  // Rotate the image by the best angle
  var center = cv2.Point2f(image.cols / 2, image.rows / 2);
  var rotationMatrix = cv2.getRotationMatrix2D(center, bestAngle, 1.0);
  Mat rotated = cv2.warpAffine(image, rotationMatrix, (image.cols, image.rows),
      flags: cv2.INTER_CUBIC, borderMode: cv2.BORDER_REPLICATE);

  return rotated;
}

Future<void> runMLKitTextRecognition(
    String inputFile, String outputFile) async {
  print('$ORANGE\t~: $RESET Parse image using ML Kit Text Recognition $RESET');
  print('$ORANGE\t~: $RESET Parse image at: $inputFile $RESET');
  print('$ORANGE\t~: $RESET Write result to: $outputFile $RESET');

  try {
    final inputImage = InputImage.fromFilePath(inputFile);
    final textRecognizer = TextRecognizer();
    final RecognizedText recognizedText =
        await textRecognizer.processImage(inputImage);

    String text = recognizedText.text;
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        text += '${line.text}\n';
      }
    }

    await File(outputFile).writeAsString(text, encoding: utf8);
    textRecognizer.close();
  } catch (e) {
    print('$ORANGE\t~: $RESET Error during text recognition: $e $RESET');
    rethrow;
  }
}

img.Image rescaleImage(img.Image image) {
  print('$ORANGE\t~: $RESET Rescale image $RESET');
  int newWidth = (image.width * 1.2).toInt();
  int newHeight = (image.height * 1.2).toInt();
  return img.copyResize(image, width: newWidth, height: newHeight);
}

img.Image grayscaleImage(img.Image image) {
  print('$ORANGE\t~: $RESET Grayscale image $RESET');
  return img.grayscale(image);
}

Mat removeNoise(cv2.Mat img) {
  var kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, 1));
  img = cv2.dilate(img, kernel);
  img = cv2.erode(img, kernel);

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
    31,
    2,
  );

  return img;
}

cv2.Mat removeShadows(cv2.Mat img) {
  cv2.VecMat rgbPlanes = cv2.split(img);
  List<cv2.Mat> resultPlanes = [];

  for (var plane in rgbPlanes) {
    var dilatedImg =
        cv2.dilate(plane, cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7)));
    var bgImg = cv2.medianBlur(dilatedImg, 21);
    var diffImg = cv2.absDiff(plane, bgImg);
    diffImg = cv2.subtract(
      cv2.Mat.fromScalar(
          diffImg.cols, diffImg.rows, diffImg.type, cv2.Scalar.all(255)),
      cv2.absDiff(plane, bgImg),
    );
    resultPlanes.add(diffImg);
  }

  final result = cv2.merge(cv2.VecMat.fromList(resultPlanes));
  return result;
}

img.Image enhanceImage(img.Image image, String tmpPath,
    {bool highContrast = true, bool gaussianBlur = true, bool rotate = true}) {
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
  String inputPath = path.join(INPUT_FOLDER, filename);
  String outputPath =
      path.join(OUTPUT_FOLDER, '${filename.split('.').first}.txt');

  print('$ORANGE~: $RESET Process image: $ORANGE$inputPath$RESET');
  prepareFolders();

  img.Image? image = img.decodeImage(File(inputPath).readAsBytesSync());
  if (image == null) {
    print('Error: Unable to read image $inputPath');
    return;
  }

  String tmpPath = path.join(TMP_FOLDER, filename);
  image = enhanceImage(image, tmpPath,
      highContrast: grayscale, gaussianBlur: gaussianBlur);

  print('$ORANGE~: $RESET Temporary store image at: $ORANGE$tmpPath$RESET');
  File(tmpPath).writeAsBytesSync(img.encodePng(image));

  await runMLKitTextRecognition(tmpPath, outputPath);

  print('$ORANGE~: $RESET Store parsed text at: $ORANGE$outputPath$RESET');
}

Future<void> main() async {
  prepareFolders();
  var images = findImages(INPUT_FOLDER);
  print(
      '$ORANGE~: $RESET Found: $ORANGE${images.length}$RESET images in: $ORANGE$INPUT_FOLDER$RESET');

  int i = 1;
  for (var filename in images) {
    if (i != 1) {
      print('');
    }
    print(
        '$ORANGE~: $RESET Process image ($ORANGE$i/${images.length}$RESET): $filename$RESET');

    await processReceipt(filename);
    i += 1;
  }
}
