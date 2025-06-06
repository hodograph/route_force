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
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
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
    apiKey: 'AIzaSyA4yTNaZ1y_1PSuDudyH3igws59QU5tRPk',
    appId: '1:922250209867:web:12475858155488dba07bce',
    messagingSenderId: '922250209867',
    projectId: 'route-force',
    authDomain: 'route-force.firebaseapp.com',
    storageBucket: 'route-force.firebasestorage.app',
    measurementId: 'G-P6RCY64HNW',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD9taoRxfxFPtYe-j1TnT4QysJrP9mrRuU',
    appId: '1:922250209867:android:aefcf89296b38a26a07bce',
    messagingSenderId: '922250209867',
    projectId: 'route-force',
    storageBucket: 'route-force.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAssOhYvM4e7LlZcNN6Ip7uyS6Z3atT-t0',
    appId: '1:922250209867:ios:879dff97cca8a4fba07bce',
    messagingSenderId: '922250209867',
    projectId: 'route-force',
    storageBucket: 'route-force.firebasestorage.app',
    iosClientId: '922250209867-jncq8oepqh4q584hgijf9v3bljqrktdc.apps.googleusercontent.com',
    iosBundleId: 'com.example.routeForce',
  );
}
