import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv2;

class ImageConverter {
  static cv2.Mat imageToMat(img.Image image) {
    // Convert to BGR format since OpenCV uses BGR
    final bgr = _convertToBGR(image);

    // Create Mat with correct dimensions and type
    final mat = cv2.Mat.zeros(image.height, image.width, cv2.MatType.CV_8UC3);

    // Copy pixel data
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = bgr.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;
        mat.set(y, x, [b, g, r]);
      }
    }

    return mat;
  }

  static img.Image matToImage(cv2.Mat mat) {
    // Create image with correct dimensions
    final image = img.Image(width: mat.cols, height: mat.rows);

    // Copy pixel data
    for (int y = 0; y < mat.rows; y++) {
      for (int x = 0; x < mat.cols; x++) {
        final pixel = mat.atPixel(x, y);
        final b = pixel[0];
        final g = pixel[1];
        final r = pixel[2];
        image.setPixelRgb(x, y, r, g, b);
      }
    }

    return image;
  }

  static img.Image _convertToBGR(img.Image image) {
    final result = img.Image(width: image.width, height: image.height);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;
        result.setPixelRgb(x, y, b, g, r);
      }
    }

    return result;
  }

  static bool validateConversion(img.Image original, cv2.Mat converted) {
    if (original.width != converted.cols || original.height != converted.rows) {
      return false;
    }

    for (int y = 0; y < original.height; y++) {
      for (int x = 0; x < original.width; x++) {
        final originalPixel = original.getPixel(x, y);
        final convertedPixel = converted.atPixel(x, y);

        final originalR = originalPixel.r;
        final originalG = originalPixel.g;
        final originalB = originalPixel.b;

        final convertedB = convertedPixel[0];
        final convertedG = convertedPixel[1];
        final convertedR = convertedPixel[2];

        if (originalR != convertedR ||
            originalG != convertedG ||
            originalB != convertedB) {
          return false;
        }
      }
    }

    return true;
  }
}

// Update the existing conversion calls:
cv2.Mat imageToMat(img.Image image) {
  return ImageConverter.imageToMat(image);
}

img.Image matToImage(cv2.Mat mat) {
  return ImageConverter.matToImage(mat);
}