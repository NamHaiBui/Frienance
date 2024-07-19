import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MyAppBar extends StatelessWidget implements PreferredSizeWidget {
  // final String userImageUrl; // URL of the user's image

  const MyAppBar({
    super.key,
  });

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight); // Standard AppBar height

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('My App'), // Replace with your app's title
      actions: [
        FloatingActionButton(
            child: const Icon(Icons.login),
            onPressed: () {
              context.push('/login');
            }),
      ],
    );
  }
}
