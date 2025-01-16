import 'package:flutter/material.dart';
import 'dart:io' if (dart.library.html) 'dart:html' as html;
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart' if (dart.library.html) 'package:path_provider/path_provider_web.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final int _counter = 0;

  @override
  void initState() {
    super.initState();
    prepareFolders();
  }

  void _parseReceipts() async {
    await processReceipts();
    setState(() {
      // Update UI after parsing
    });
  }

  void prepareFolders() async {
    if (!kIsWeb) {
      html.Directory appDocDir = await getApplicationDocumentsDirectory();
      String appDocPath = appDocDir.path;

      List<String> folders = [
        '$appDocPath/data/origin_img',
        '$appDocPath/data/img',
        '$appDocPath/data/tmp',
        '$appDocPath/data/txt',
      ];

      for (var folder in folders) {
        final directory = html.Directory(folder);
        if (!(await directory.exists())) {
          await directory.create(recursive: true);
        }
      }
    } else {
      // Handle web: Use alternative storage or notify the user
      // Web-specific code here
    }
  }

  List<html.File> findImages(String folderPath) {
    if (!kIsWeb) {
      final directory = html.Directory(folderPath);
      List<html.File> images = [];
      for (var file in directory.listSync()) {
        if (file is html.File &&
            (file.path.endsWith('.png') || file.path.endsWith('.jpg'))) {
          images.add(file);
        }
      }
      return images;
    } else {
      // Handle web case
      // Web-specific code here
      return [];
    }
  }

  Future<void> processReceipts() async {
    if (!kIsWeb) {
      String folderPath = '${(await getApplicationDocumentsDirectory()).path}/data/origin_img';
      List<html.File> images = findImages(folderPath);

      for (var imageFile in images) {
        img.Image? image = img.decodeImage(imageFile.readAsBytesSync());
        if (image == null) continue;
      }
    } else {
      // Handle web case
      // Web-specific code here
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _parseReceipts,
        tooltip: 'Parse Receipts',
        child: const Icon(Icons.scanner),
      ),
    );
  }
}
