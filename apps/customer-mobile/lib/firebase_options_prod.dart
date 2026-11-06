// PRODUCTION config — Firebase project washpro-prod (created Oct 22, 2026).
// Used when building with --dart-define=ENV=prod. Default (no ENV) stays on
// the pilot project wash-pro-7f3b1. Regenerate: flutterfire configure --project=washpro-prod
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class ProdFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return android;
      default: return web;
    }
  }
  static const web = FirebaseOptions(apiKey: 'AIzaSyC5AfgHhnL_SmUbU7whhcKPraJPp14pwXg', appId: '1:848454299025:web:8324b67b73356e3e08be30', messagingSenderId: '848454299025', projectId: 'washpro-prod', authDomain: 'washpro-prod.firebaseapp.com', storageBucket: 'washpro-prod.firebasestorage.app');
  static const android = FirebaseOptions(apiKey: 'AIzaSyA7TA5l_TQeT26HD_D_qcDjRgYXVuWTyz0', appId: '1:848454299025:android:e1d4d01efa39aa8a08be30', messagingSenderId: '848454299025', projectId: 'washpro-prod', storageBucket: 'washpro-prod.firebasestorage.app');
}
