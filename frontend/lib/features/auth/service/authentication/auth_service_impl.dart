import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:frontend/features/auth/service/authentication/auth_service.dart';

class AuthServiceImpl implements AuthService {
  final firebase.FirebaseAuth auth = firebase.FirebaseAuth.instance;

  @override
  Stream<firebase.User?> authStateChanges() {
    return auth.authStateChanges();
  }

  @override
  Future<void> signOut() async {
    await FirebaseUIAuth.signOut();
  }

  @override
  UserId? getCurrentUserId() {
    return auth.currentUser?.uid;
  }

  @override
  Stream<firebase.User?> userChanges() {
    return auth.userChanges();
  }

  @override
  firebase.FirebaseAuth? getFirebaseAuth() {
    return auth;
  }

}
