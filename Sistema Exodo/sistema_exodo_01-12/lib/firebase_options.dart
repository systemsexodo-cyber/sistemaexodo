// Arquivo gerado manualmente com base na configuração JS fornecida pelo usuário.
// Apenas a configuração Web está disponível.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for android - '
          'you can re-run this command with, for example, '
          'flutterfire configure --platforms=android',
        );
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can re-run this command with, for example, '
          'flutterfire configure --platforms=ios',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can re-run this command with, for example, '
          'flutterfire configure --platforms=macos',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can re-run this command with, for example, '
          'flutterfire configure --platforms=windows',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can re-run this command with, for example, '
          'flutterfire configure --platforms=linux',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyALiVxc5XXMbVDFQP7ZIIckIatcvGHuIYs',
    appId: '1:959755913630:web:297d86a78c681f66c56e8f',
    messagingSenderId: '959755913630',
    projectId: 'exodo-system',
    authDomain: 'exodo-system.firebaseapp.com',
    storageBucket: 'exodo-system.firebasestorage.app',
    measurementId: 'G-Z7QWN2054D',
  );
}
