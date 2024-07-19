import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:frontend/features/auth/service/authorization/account_service.dart';
import 'package:frontend/model/user_model.dart';

class AccountServiceImpl implements AccountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  Future<UserID> createAccount() async {
    // Assuming you have a way to get the current user's ID (e.g., from Firebase Auth)
    final userId = 'your_user_id'; // Replace with actual user ID

    // Create a new user document in Firestore
    final userDoc = _firestore.collection('users').doc(userId);
    await userDoc.set({
      'id': userId,
      'name': 'Your Name', // Replace with actual user name
      'currency': 'USD', // Replace with actual currency
      // Add other initial user data as needed
    });

    return userId;
  }

  @override
  Future<String> deleteUser(String userId) async {
    // Delete the user document from Firestore
    await _firestore.collection('users').doc(userId).delete();

    // Delete any profile picture associated with the user
    try {
      await _storage.ref('profile_pictures/$userId.jpg').delete();
    } catch (e) {
      // Ignore if the profile picture doesn't exist
    }

    return 'User deleted successfully';
  }

  @override
  Future<User> getUserSnapshot(String userId) async {
    // Retrieve the user document from Firestore
    final userDoc = await _firestore.collection('users').doc(userId).get();

    // Get the profile picture URL from Firestore
    final profilePicUrl = userDoc.data()?['profilePicUrl'];

    // Convert the document data to a User object
    final user = User.fromJson(userDoc.data()!);

    // Set the profile picture URL if it exists
    if (profilePicUrl != null) {
      user.profilePicUrl = profilePicUrl;
    }

    return user;
  }

  @override
  Stream<User?> getUserStream(String userId) {
    // Listen for changes to the user document in Firestore
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        // Get the profile picture URL from Firestore
        final profilePicUrl = snapshot.data()?['profilePicUrl'];

        // Convert the document data to a User object
        final user = User.fromJson(snapshot.data()!);

        // Set the profile picture URL if it exists
        if (profilePicUrl != null) {
          user.profilePicUrl = profilePicUrl;
        }

        return user;
      } else {
        return null;
      }
    });
  }

  @override
  Future<User> updateUserData(String userId) async {
    // Assuming you have a way to get the updated user data (e.g., from a form)
    final updatedUserData = {
      'name': 'Updated Name', // Replace with actual updated name
      // Add other updated user data as needed
    };

    // Update the user document in Firestore
    final userDoc = _firestore.collection('users').doc(userId);
    await userDoc.update(updatedUserData);

    // Retrieve the updated user document
    final updatedUserDoc = await userDoc.get();

    // Convert the document data to a User object
    final updatedUser = User.fromJson(updatedUserDoc.data()!);

    return updatedUser;
  }

  // Method to upload a profile picture to Firebase Storage
  Future<String?> uploadProfilePicture(String userId, File file) async {
    try {
      // Create a reference to the profile picture in Firebase Storage
      final ref = _storage.ref('profile_pictures/$userId.jpg');

      // Upload the file to Firebase Storage
      final uploadTask = ref.putFile(file);
      await uploadTask.whenComplete(() => null);

      // Get the download URL of the uploaded profile picture
      final downloadUrl = await ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('Error uploading profile picture: $e');
      return null;
    }
  }

  // Method to update the profile picture URL in Firestore
  Future<void> updateProfilePictureUrl(String userId, String? profilePicUrl) async {
    final userDoc = _firestore.collection('users').doc(userId);
    await userDoc.update({'profilePicUrl': profilePicUrl});
  }
}
