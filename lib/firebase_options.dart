import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA4Lxv1UKfibT84ap71hd0RgYXXwvHqvWE',
    appId: '1:992451732443:android:10ab816408089e58857dfe',
    messagingSenderId: '992451732443',
    projectId: 'chat-free--8783',
    storageBucket: 'chat-free--8783.firebasestorage.app',
  );
}