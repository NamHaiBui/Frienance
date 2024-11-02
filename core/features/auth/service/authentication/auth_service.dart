import 'package:firebase_auth/firebase_auth.dart' as firebase;

typedef UserId = String;
typedef Email = String;

abstract class AuthService {
  /// Provides a continuous stream of authentication state changes.
  ///
  /// Whenever the authentication state changes (e.g., user logs in or out),
  /// this stream emits the current `firebase.User` object, or `null` if
  /// there is no authenticated user.
  Stream<firebase.User?> authStateChanges();

  /// Retrieves the unique ID of the currently authenticated user.
  /// If the value is null then there is no current user (the user is currently not logged in)
  ///
  /// Returns:
  /// - The user's unique ID as a `UserId` string if a user is currently logged in.
  /// - `null` if no user is authenticated.
  UserId? getCurrentUserId();

  /// Signs out the current user from Firebase.
  ///
  /// This operation is asynchronous and completes when the user has been
  /// successfully signed out.
  Future<void> signOut();

  /// Provides a continuous stream of user changes.
  ///
  /// This stream returns the current `firebase.User` object whenever a change occurs,
  /// such as when the user's profile is updated or when the authentication token
  /// is refreshed.
  Stream<firebase.User?> userChanges();

  /// Accesses the underlying `FirebaseAuth` instance.
  ///
  /// Returns:
  /// - The `FirebaseAuth` instance used for authentication operations.
  firebase.FirebaseAuth? getFirebaseAuth();
}
