import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_ui_oauth_google/firebase_ui_oauth_google.dart';
import 'package:flutter/material.dart';
import 'package:frontend/features/auth/screens/widgets/oauth/button_style/google_oauth_style.dart';
import 'package:frontend/features/auth/screens/widgets/oauth/oauth_button_base.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../constants/strings_for_auth.dart';

class _ErrorListener extends StatelessWidget {
  const _ErrorListener();

  @override
  Widget build(BuildContext context) {
    final state = AuthState.of(context);
    if (state is AuthFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          style: TextStyle(color: Theme.of(context).colorScheme.error),
          textAlign: TextAlign.center,
          state.exception
              .toString()
              .split(' ')
              .last
              .split('/')
              .last
              .split('-')
              .map((e) {
            if (e.endsWith(').')) {
              return e.substring(0, e.length - 2);
            }
            return e;
          }).join(' '),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class GoogleLoginBtn extends ConsumerWidget {
  final double width;

  final double height;
  final auth = FirebaseAuth.instance;
  final bool isLogin;
  final GoogleProvider googleProvider;
  final Future<void> Function(WidgetRef ref)? handleNewUser;
  GoogleLoginBtn(
      {super.key,
      required this.googleProvider,
      required this.height,
      required this.width,
      required this.isLogin,
      required this.handleNewUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    return AuthFlowBuilder<OAuthController>(
      listener: (oldState, newState, controller) async {
        if (newState is UserCreated && handleNewUser != null) {
          await handleNewUser!(ref);
        }
      },
      provider: googleProvider,
      action: AuthAction.signIn,
      auth: auth,
      builder: (context, state, ctrl, child) {
        final button = OAuthButtonBase(
          height: height,
          width: width,
          style: const GoogleOAuthButtonStyle(),
          fontSize: width / 24,
          auth: auth,
          loadingIndicator: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
                googleProvider.style.color.getValue(brightness)),
          ),
          label: isLogin
              ? StringsForAuth.signInWithGoogle
              : StringsForAuth.signUpWithGoogle,
          provider: googleProvider,
          action: isLogin ? AuthAction.signIn : AuthAction.signUp,
          isLoading: state is SigningIn || state is CredentialReceived,
          onTap: () => ctrl.signIn(Theme.of(context).platform),
          overrideDefaultTapAction: true,
          fontFamily: 'Roboto',
        );

        return Column(children: [button, const _ErrorListener()]);
      },
    );
  }
}
