import 'package:firebase_auth/firebase_auth.dart';

final ActionCodeSettings acs = ActionCodeSettings(
    url: '', // Push back to home page
    // This must be true
    handleCodeInApp: true,
    iOSBundleId: 'com.example.ios',
    androidPackageName: 'com.dev.frienance',
    // installIfNotAvailable
    androidInstallApp: true,
    // minimumVersion
    androidMinimumVersion: '21');
