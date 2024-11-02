import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';

class EmailSignIn extends StatefulWidget {
  const EmailSignIn({super.key});

  @override
  State<EmailSignIn> createState() => _EmailSignInState();
}

class _EmailSignInState extends State<EmailSignIn>
    implements EmailAuthListener {
  @override
  final auth = FirebaseAuth.instance;
  @override
  late final EmailAuthProvider provider = EmailAuthProvider()
    ..authListener = this;

  late Widget child = EmailForm(onSubmit: (email, password) {
    provider.authenticate(email, password, AuthAction.signIn);
  });

  @override
  Widget build(BuildContext context) {
    return Center(child: child);
  }

  void onBeforeCredentialLinked(AuthCredential credential) {
    setState(() {
      child = const CircularProgressIndicator();
    });
  }

  @override
  void onBeforeProvidersForEmailFetch() {
    setState(() {
      child = const CircularProgressIndicator();
    });
  }

  @override
  void onBeforeSignIn() {
    setState(() {
      child = const CircularProgressIndicator();
    });
  }

  @override
  void onCanceled() {
    setState(() {
      child = EmailForm(onSubmit: (email, password) {
        auth.signInWithEmailAndPassword(email: email, password: password);
      });
    });
  }

  @override
  void onCredentialLinked(AuthCredential credential) {
    Navigator.of(context).pushReplacementNamed('/profile');
  }

  @override
  void onDifferentProvidersFound(
      String email, List<String> providers, AuthCredential? credential) {}

  @override
  void onError(Object error) {
    try {
      // tries default recovery strategy
      defaultOnAuthError(provider, error);
    } catch (err) {
      setState(() {
        defaultOnAuthError(provider, error);
      });
    }
  }

  @override
  void onSignedIn(UserCredential credential) {
    Navigator.of(context).pushReplacementNamed('/profile');
  }

  @override
  void onCredentialReceived(AuthCredential credential) {
    // TODO: implement onCredentialReceived
  }

  @override
  void onMFARequired(MultiFactorResolver resolver) {
    // TODO: implement onMFARequired
  }
}
