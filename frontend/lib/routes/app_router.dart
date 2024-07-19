import 'package:flutter/material.dart';
import 'package:frontend/features/auth/auth_routing.dart';
import 'package:frontend/features/error/error_page.dart';
import 'package:frontend/features/service_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

String initRouterURI = "/";

@Riverpod(keepAlive: true)
class AppGoRouter extends _$AppGoRouter {
  @override
  GoRouter build() {
    final currentUser = ref.watch(authServiceProvider).userChanges();
    currentUser.firstWhere((user) => user != null, orElse: () => null);
    return GoRouter(
        initialLocation: initRouterURI,
        errorBuilder: (context, state) => ErrorPage(state.error),
        routes: appGoRoutes,
        redirect: (context, goRouterState) async {
          return null;
        
          
        });
  }
}

bool matchesDynamicPath(String path, String pattern) {
  final pathSegments = path.split('/');
  final patternSegments = pattern.split('/');

  if (pathSegments.length != patternSegments.length) return false;

  for (int i = 0; i < pathSegments.length; i++) {
    if (patternSegments[i].startsWith(':')) continue;
    if (patternSegments[i] != pathSegments[i]) return false;
  }

  return true;
}

bool isPathProtected(String path) {
  for (String protectedPath in appProtectedPaths) {
    if (path == protectedPath) {
      return true;
    }
    if (matchesDynamicPath(path, protectedPath)) {
      return true;
    }
  }
  return false;
}

List<String> appProtectedPaths = [
  // DashboardPage: '/dashboard',
];
final Map<Type, String> appRoutePaths = {
  ...authFeatureRoutePaths,
};
final List<RouteBase> appGoRoutes = [
  ...authGoRoute,
];
