import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../utils/app_config.dart';
import '../utils/firebase_exception_handler.dart';
import 'work_manager_service.dart';
import 'foreground_tracking_service.dart';
import 'push_notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final GoogleSignIn _googleSignIn;

  AuthService() {
    _googleSignIn = GoogleSignIn.instance;
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      debugPrint("Starting Google Sign-In...");

      if (kIsWeb) {
        debugPrint("Running on Web. Triggering Firebase signInWithPopup...");
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.setCustomParameters({
          'prompt': 'select_account'
        });
        final UserCredential userCredential = await _auth.signInWithPopup(googleProvider);
        debugPrint("Firebase Web Sign-In Successful");
        return userCredential;
      }

      // On non-Web, check if authenticate is supported
      if (!_googleSignIn.supportsAuthenticate()) {
        debugPrint("Google Sign-In authentication not supported on this device.");
        return null;
      }

      // Trigger Google Sign-In flow (this is the only method in v7)
      final googleUser = await _googleSignIn.authenticate();

      debugPrint("Getting authentication tokens...");

      final GoogleSignInAuthentication authentication =
          googleUser.authentication;
      final String? idToken = authentication.idToken;

      if (idToken == null) {
        debugPrint("Missing Google Auth ID Token");
        return null;
      }

      // Create Firebase credential using idToken (accessToken is optional/deprecated in v7)
      final credential = GoogleAuthProvider.credential(idToken: idToken);

      // Sign in to Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      debugPrint("Firebase Sign-In Successful");

      // Register Push Notification Token (Skip on Web)
      await PushNotificationService.instance.registerUserToken(
        userCredential.user!.uid,
      );

      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint("FirebaseAuthException: ${e.code} - ${e.message}");
      throw AppException(getFirebaseErrorMessage(e));
    } catch (e) {
      debugPrint("Google Sign-In Error: $e");
      throw AppException(getFirebaseErrorMessage(e));
    }
  }

  /// Sign out from both Firebase + Google and cancel background tasks
  Future<void> signOut() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        // Remove push notification token before signing out (Skip on Web)
        if (!kIsWeb) {
          await PushNotificationService.instance.removeUserToken(currentUser.uid);
        }
      }

      if (!kIsWeb) {
        await WorkManagerService.cancelAll();
        await ForegroundTrackingService.stop();
      }
      await _googleSignIn.signOut();
      await _auth.signOut();

      debugPrint("User signed out");
    } catch (e) {
      debugPrint("Sign out error: $e");
    }
  }

  /// Get current user
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  bool isEmailAllowed(String? email) {
    const allowedDomain = AppConfig.allowedDomain;
    if (allowedDomain.isEmpty) return true;
    if (email == null) return false;
    return email.endsWith('@$allowedDomain');
  }
}
