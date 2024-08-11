// Create a provider to keep track of what groupByCondition the use4 is using ("Week", "Month", "Year")
import 'package:hooks_riverpod/hooks_riverpod.dart';

final timeFrameProvider = StateProvider<String>((ref) => 'Month');
