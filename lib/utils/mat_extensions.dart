import 'package:opencv_dart/opencv_dart.dart' as cv2;

// extension ConvertMatToNumList on cv2.Mat {
//   List<num> toNumList() {
//     final result = <num>[];
//     for (var value in data) {
//       result.add(value.toDouble());
//     }
//     return result;
//   }
// }
// // extension ConvertNumListToMat on List<num> {
// //   cv2.Mat toMat() {
// //     final mat = cv2.Mat.fromList(1, width: length, type: cv2.CV_64F);
// //     for (var i = 0; i < length; i++) {
// //       mat.data[i] = this[i].toDouble();
// //     }
// //     return mat;
// //   }
// // }
extension PercentileExt on List<num> {
  double percentile(double p) {
    if (isEmpty) {
      throw ArgumentError('Data cannot be empty');
    }
    if (p < 0 || p > 100) {
      throw ArgumentError('Percentile must be between 0 and 100');
    }

    sort(); // Sort the list in place

    final index = (p / 100.0) * (length - 1);

    if (index == index.round()) {
      return this[index.round()].toDouble();
    } else {
      final lower = this[index.floor()];
      final upper = this[index.ceil()];
      return lower + (upper - lower) * (index - index.floor());
    }
  }
}
