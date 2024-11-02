import 'package:flutter/material.dart';
import 'package:frienance/screens/home_screen.dart';
import 'package:frienance/services/python_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PythonBridge.initialize();
  runApp(const ReceiptManagerApp());
}

class ReceiptManagerApp extends StatelessWidget {
  const ReceiptManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomeScreen(),
    );
  }
}
