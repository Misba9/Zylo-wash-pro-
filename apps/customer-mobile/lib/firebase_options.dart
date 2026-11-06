// Config for Firebase project wash-pro-7f3b1 (firebase-basics skill: apps:sdkconfig).
// Regenerate with: flutterfire configure --project=wash-pro-7f3b1
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return android;
      case TargetPlatform.iOS: return ios;
      default: return web;
    }
  }
  static const web = FirebaseOptions(apiKey: 'AIzaSyDEzeaD5PsnSJDCsLcI-_J2UHkYxZErLro', appId: '1:832079032419:web:ba8ba43729059d22f5c856', messagingSenderId: '832079032419', projectId: 'wash-pro-7f3b1', authDomain: 'wash-pro-7f3b1.firebaseapp.com', storageBucket: 'wash-pro-7f3b1.firebasestorage.app');
  static const android = FirebaseOptions(apiKey: 'AIzaSyBktkLj8jHVgeJb9XIeNxm8tbjNBj2N3yY', appId: '1:832079032419:android:db186e57ff6db912f5c856', messagingSenderId: '832079032419', projectId: 'wash-pro-7f3b1', storageBucket: 'wash-pro-7f3b1.firebasestorage.app');
  static const ios = FirebaseOptions(apiKey: 'AIzaSyC7-S2zMekQHJaLJVv2ReIFpRFpnr6LLAk', appId: '1:832079032419:ios:9a3edf7344b37d42f5c856', messagingSenderId: '832079032419', projectId: 'wash-pro-7f3b1', storageBucket: 'wash-pro-7f3b1.firebasestorage.app', iosBundleId: 'com.washpro.customer');
}
