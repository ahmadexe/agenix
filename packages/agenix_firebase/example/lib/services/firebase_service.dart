import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FirebaseService {
  static final _auth = FirebaseAuth.instance;

  static Future<void> init() async {
    try {
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }
      debugPrint("Dummy user authenticated");
    } catch (e) {
      debugPrint(
        'Error initializing Firebase (Failed while trying to authenticate dummy uesr): $e',
      );
    }
  }
}
