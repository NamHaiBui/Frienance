import 'package:flutter/material.dart';
import 'package:frontend/core/initialization.dart';
import 'package:frontend/screen/my_app.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appInit();
  runApp(const ProviderScope(child: MyApp()));
}
