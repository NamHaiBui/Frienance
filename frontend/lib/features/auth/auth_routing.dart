import 'package:frontend/features/auth/screens/widgets/sign_in_page.dart';
import 'package:frontend/features/auth/screens/widgets/sign_up_page.dart';
import 'package:go_router/go_router.dart';

const Map<Type, String> authFeatureRoutePaths = {
  SignInPage: '/sign-in',
  SignUpPage: '/sign-up',
};
final List<RouteBase> authGoRoute = [
  GoRoute(
      path: authFeatureRoutePaths[SignInPage]!,
      builder: (context, state) => const SignInPage()),
  GoRoute(
      path: authFeatureRoutePaths[SignUpPage]!,
      builder: (context, state) => const SignUpPage()),
];
