import 'package:flutter/material.dart';
import 'dart:async';

class HeroWidget extends StatefulWidget {
  const HeroWidget({super.key});

  @override
  State<HeroWidget> createState() => _HeroWidgetState();
}

class _HeroWidgetState extends State<HeroWidget> {
  final List<IconData> icons = [
    Icons.home,
    Icons.favorite,
    Icons.settings,
    Icons.person,
  ];
  final List<Color> colors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
  ];
  int currentIndex = 0;
  bool isExpanded = false;

  @override
  void initState() {
    super.initState();
    Timer.periodic(const Duration(seconds: 3), (timer) {
      setState(() {
        currentIndex = (currentIndex + 1) % icons.length;
      });
    });
  }

  void toggleExpansion() {
    setState(() {
      isExpanded = !isExpanded;
    });
  }

  void changeIcon(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Hero(
          tag: 'icon-hero',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: toggleExpansion,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                padding: EdgeInsets.all(isExpanded ? 40 : 20),
                decoration: BoxDecoration(
                  color: colors[currentIndex],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icons[currentIndex],
                  size: isExpanded ? 100 : 50,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Tap to expand/shrink',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 20),
        Text(
          'Current Icon: ${icons[currentIndex].toString().split('.').last}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        // Navigator dot bar
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: icons.asMap().entries.map((entry) {
            final index = entry.key;
            final icon = entry.value;
            return GestureDetector(
              onTap: () => changeIcon(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(
                  icon,
                  size: 24,
                  color: index == currentIndex ? Colors.blue : Colors.grey,
                ),
              ),
            );
          }).toList(),
        ),
      ],   );
  }
}
