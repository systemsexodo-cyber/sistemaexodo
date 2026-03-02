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
    apiKey: 'AIzaSyBWvs6jCOFXZ3wN-5gwlvSDhfDR-bv-h_k',
    appId: '1:54918146922:web:8c26f3e66135f17bf8d313',
    messagingSenderId: '54918146922',
    projectId: 'exodosystems-1541d',
    authDomain: 'exodosystems-1541d.firebaseapp.com',
    storageBucket: 'exodosystems-1541d.firebasestorage.app',
    databaseURL: 'https://exodosystems-1541d-default-rtdb.firebaseio.com',
    measurementId: 'G-P5Z93JCW1F',
  );
}
