import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:frontend/features/auth/screens/widgets/email_password/handle_error_authentication.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
// import 'package:openknect_app/features/account/presentation/routing/auth_feature_router.dart';

class HandleErrorAuthenticationWidget extends HookConsumerWidget {
  final String errorCode;
  const HandleErrorAuthenticationWidget({
    super.key,
    required this.errorCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String value;
    if (errorCode == HandleErrorAuthentication.emailAlreadyExistError) {
      value = HandleErrorAuthentication.emailAlreadyExistErrorMessage;
    } else {
      value = HandleErrorAuthentication.defaultErrorMessage;
    }
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            text: value,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            children: [
              if (errorCode == HandleErrorAuthentication.emailAlreadyExistError)
                TextSpan(
                  text: HandleErrorAuthentication.loginHere,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      context.go("/login");
                    },
                ),
            ],
          ),
        ));
  }
}
