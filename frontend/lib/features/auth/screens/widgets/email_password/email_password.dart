import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart' as firebase
    hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:frontend/features/auth/screens/widgets/email_password/auth_field.dart';
import 'package:frontend/features/auth/screens/widgets/email_password/handle_error_authentication_widget.dart';
import 'package:frontend/features/auth/screens/widgets/constants/strings_for_auth.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';

final hasAgreedToTermsProvider =
    StateNotifierProvider<BoolNotifier, bool?>((ref) => BoolNotifier());

class BoolNotifier extends StateNotifier<bool?> {
  BoolNotifier() : super(null);

  void setValue(bool value) {
    state = value;
  }
}

bool rememberMe = false;

/// This will be the universal email login screen
class EmailPasswordWidget extends HookConsumerWidget {
  final bool isLogin;
  final double w;
  final double h;

  final Future<void> Function(WidgetRef ref)? handleNewUser;
  const EmailPasswordWidget(
      {required this.w,
      required this.h,
      super.key,
      required this.isLogin,
      required this.handleNewUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AuthFlowBuilder<EmailAuthController>(
        auth: firebase.FirebaseAuth.instance,
        action: isLogin ? AuthAction.signIn : AuthAction.signUp,
        listener: (oldState, newState, ctrl) async {
          if (newState is UserCreated && handleNewUser != null) {
            await handleNewUser!(ref);
            if (context.mounted) {}
          }
        },
        provider: EmailAuthProvider(),
        child: _SignInFormWidget(isLogin: isLogin, height: h, width: w));
  }
}

class _SignInFormWidget extends HookConsumerWidget {
  final bool isLogin;
  final double height;
  final double width;
  _SignInFormWidget({
    required this.isLogin,
    required this.height,
    required this.width,
  });

  final _formKey = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // final padding = widget.width * 0.0703125;

    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final passwordConfirmCtrl = TextEditingController();

    final textTheme = Theme.of(context).textTheme;
    final emailFocusNode = FocusNode();
    final passwordFocusNode = FocusNode();
    final confirmPasswordFocusNode = FocusNode();
    void submit([String? password]) {
      FocusManager.instance.primaryFocus?.unfocus();

      final ctrl = AuthController.ofType<EmailAuthController>(context);

      final email = (emailCtrl.text).trim();

      if (_formKey.currentState!.validate()) {
        if (!rememberMe) {
          ctrl.auth.setPersistence(firebase.Persistence.SESSION);
        } else if (rememberMe) {
          ctrl.auth.setPersistence(firebase.Persistence.INDEXED_DB);
        }

        var encodePassword = utf8.encode(passwordCtrl.text);
        var hash256Password = sha256.convert(encodePassword);

        ctrl.setEmailAndPassword(
          email,
          password ?? hash256Password.toString(),
        );
      }
    }

    final padding = width * 0.0703125;
    final double fontSize = min(16, width / 30);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Form(
        key: _formKey,
        child: SizedBox(
          height: height * 0.6,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                AuthTextField(
                  width: width,
                  height: height,
                  padding: padding,
                  controller: emailCtrl,
                  focusNode: emailFocusNode,
                  autofocus: true,
                  fieldName: StringsForAuth.fieldNameEmail,
                  hintText: StringsForAuth.hintTextEmail,
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty ||
                        !StringsForAuth.emailRegex.hasMatch(value.trim())) {
                      return StringsForAuth.invalidEmailMessage;
                    }
                    return null;
                  },
                  onSubmitted: (v) {
                    FocusScope.of(context).requestFocus(passwordFocusNode);
                  },
                ),
                AuthTextField(
                  width: width,
                  height: height,
                  padding: padding,
                  controller: passwordCtrl,
                  focusNode: passwordFocusNode,
                  fieldName: 'Password',
                  hintText: isLogin
                      ? StringsForAuth.hintTextPasswordLogin
                      : StringsForAuth.hintTextPasswordOther,
                  obscure: true,
                  validator: isLogin
                      ? (value) => value == null
                          ? StringsForAuth.requiredPasswordMessage
                          : null
                      : (value) {
                          if (value == null ||
                              value.trim().length <
                                  StringsForAuth.minPasswordLength) {
                            return StringsForAuth.shortPasswordMessage;
                          }
                          return null;
                        },
                  onSubmitted: submit,
                ),
                if (isLogin) ...[
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      RememberWidget(
                        fontSize: fontSize,
                        textTheme: textTheme,
                      ),
                      TextButton(
                        onPressed: () {},
                        child: Text(
                          StringsForAuth.forgotYourPassword,
                          style: textTheme.bodyMedium!.copyWith(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      )
                    ],
                  ),
                ] else ...[
                  AuthTextField(
                    width: width,
                    height: height,
                    padding: padding,
                    controller: passwordConfirmCtrl,
                    onSubmitted: submit,
                    focusNode: confirmPasswordFocusNode,
                    fieldName: StringsForAuth.fieldNameConfirmPassword,
                    hintText: StringsForAuth.hintTextConfirmPassword,
                    obscure: true,
                    validator: (value) {
                      if (value == null ||
                          passwordConfirmCtrl.text
                                  .compareTo(passwordCtrl.text) !=
                              0) {
                        return StringsForAuth.passwordMismatchMessage;
                      }
                      return null;
                    },
                  ),
                ],
                Builder(
                  builder: (context) {
                    final authState = AuthState.of(context);
                    if (authState is AuthFailed) {
                      return HandleErrorAuthenticationWidget(
                          errorCode: (authState.exception
                                  as firebase.FirebaseAuthException)
                              .code);
                    }
                    return const SizedBox.shrink();
                  },
                ),
                ElevatedButton(
                  onPressed: isLogin
                      ? () {
                          submit(passwordCtrl.text);
                        }
                      : () {
                          final agreedToTermsProvider =
                              ref.read(hasAgreedToTermsProvider);
                          final agreedToTermsProviderNotifier =
                              ref.read(hasAgreedToTermsProvider.notifier);
                          if (agreedToTermsProvider != null &&
                              agreedToTermsProvider == true) {
                            submit(passwordCtrl.text);
                          } else {
                            agreedToTermsProviderNotifier.setValue(false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F52BA),
                      minimumSize: Size(width, height / 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100))),
                  child: Padding(
                    padding: EdgeInsets.all(width * 0.8 / 96),
                    child: Text(
                      isLogin ? StringsForAuth.signIn : StringsForAuth.signUp,
                      style: Theme.of(context).textTheme.labelLarge!.copyWith(
                            color: Theme.of(context).colorScheme.surface,
                            fontSize: width * 0.8 / 24,
                          ),
                    ),
                  ),
                ),
                // SizedBox(height: widget.height / 12),
              ]),
        ),
      ),
    );
  }
}

class RememberWidget extends HookWidget {
  final double fontSize;
  final TextTheme textTheme;
  const RememberWidget(
      {super.key, required this.fontSize, required this.textTheme});

  @override
  Widget build(BuildContext context) {
    final remember = useState(false);
    return SingleChildScrollView(
      child: Row(
        children: [
          Checkbox(
              side: const BorderSide(width: 2, color: Color(0xFF0F52BA)),
              value: remember.value,
              onChanged: (val) {
                remember.value = val!;
                rememberMe = remember.value;
              }),
          Text(
            'Remember me',
            style: textTheme.bodyMedium!.copyWith(fontSize: fontSize),
          ),
        ],
      ),
    );
  }
}
