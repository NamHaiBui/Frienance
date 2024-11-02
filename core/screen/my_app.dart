import 'package:flutter/material.dart';
import 'package:frontend/routes/app_router.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter appRouter = ref.watch(appGoRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Test App',
      routerConfig: appRouter,
    );
  }
}
