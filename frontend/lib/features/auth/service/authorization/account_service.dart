import 'package:frontend/model/user_model.dart';

typedef UserID = String;

abstract class AccountService {
  /// Creates a new user account.
  ///
  /// Returns:
  /// - The unique ID of the newly created user account.
  Future<UserID> createAccount();

  /// Retrieves a snapshot of the current user's data.
  ///
  /// Returns:
  /// - A `User` object containing the user's information.
  Future<User> getUserSnapshot(String userId);

  /// Provides a stream of user data updates.
  ///
  /// Returns:
  /// - A stream that emits `User` objects whenever the user's data changes.
  Stream<User?> getUserStream(String userId);

  /// Deletes the current user's account.
  ///
  /// Returns:
  /// - A string indicating the result of the deletion operation.
  Future<String> deleteUser(String userId);

  /// Updates the current user's data.
  ///
  /// Returns:
  /// - A `User` object containing the updated user information.
  Future<User> updateUserData(String userId);
}
