// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCe1oXWjs3a_-ANa5CNQ6-zA-_qZK0uGSU',
    appId: '1:299162737168:web:cfd177ff17d27664958895',
    messagingSenderId: '299162737168',
    projectId: 'frienance-325b0',
    authDomain: 'frienance-325b0.firebaseapp.com',
    storageBucket: 'frienance-325b0.appspot.com',
    measurementId: 'G-HK9LGWDJT9',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA1Q5LjBgasv2fxQA_Fkp0LP4-PHIeZoto',
    appId: '1:299162737168:android:17fb27baf45bb005958895',
    messagingSenderId: '299162737168',
    projectId: 'frienance-325b0',
    storageBucket: 'frienance-325b0.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB5mpTDEL_mw_5xxR1yVbkG4y-dFZl6udw',
    appId: '1:299162737168:ios:475fa439ad16a8f8958895',
    messagingSenderId: '299162737168',
    projectId: 'frienance-325b0',
    storageBucket: 'frienance-325b0.appspot.com',
    iosClientId: '299162737168-tsoql7prjlidhid5nimofv5f9jtl5t0o.apps.googleusercontent.com',
    iosBundleId: 'com.example.frontend',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyB5mpTDEL_mw_5xxR1yVbkG4y-dFZl6udw',
    appId: '1:299162737168:ios:475fa439ad16a8f8958895',
    messagingSenderId: '299162737168',
    projectId: 'frienance-325b0',
    storageBucket: 'frienance-325b0.appspot.com',
    iosClientId: '299162737168-tsoql7prjlidhid5nimofv5f9jtl5t0o.apps.googleusercontent.com',
    iosBundleId: 'com.example.frontend',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCe1oXWjs3a_-ANa5CNQ6-zA-_qZK0uGSU',
    appId: '1:299162737168:web:e6cd8f80a6816400958895',
    messagingSenderId: '299162737168',
    projectId: 'frienance-325b0',
    authDomain: 'frienance-325b0.firebaseapp.com',
    storageBucket: 'frienance-325b0.appspot.com',
    measurementId: 'G-DQH73ZC0BK',
  );

}