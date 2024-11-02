import 'package:flutter/material.dart';

class RadialHeroDemo extends StatelessWidget {
  const RadialHeroDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radial Hero Animation'),
      ),
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(
            3,
            (index) => GestureDetector(
              onTap: () => Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      RadialHeroDetail(index: index),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                ),
              ),
              child: Hero(
                tag: 'hero-circle-$index', // Unique tag for each hero
                createRectTween: (begin, end) {
                  return MaterialRectCenterArcTween(begin: begin, end: end);
                },
                child: ClipOval(
                  child: Container(
                    width: 50,
                    height: 50,
                    color: Colors.primaries[index],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RadialHeroDetail extends StatelessWidget {
  final int index;

  const RadialHeroDetail({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Hero(
          tag: 'hero-circle-$index',
          child: Container(
            width: 200,
            height: 200,
            color: Colors.primaries[index],
          ),
        ),
      ),
    );
  }
}
