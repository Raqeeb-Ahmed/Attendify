import 'package:firebase_auth/firebase_auth.dart';

/// Clean exception that prints only the message (no "Exception:" prefix).
class AppException implements Exception {
  final String message;
  AppException(this.message);

  @override
  String toString() => message;
}

/// Maps Firebase and common exceptions to user-friendly messages.
String getFirebaseErrorMessage(dynamic error) {
  if (error is FirebaseAuthException) {
    return _mapAuthError(error);
  }

  if (error is FirebaseException) {
    return _mapFirebaseException(error);
  }

  // Strip "Exception: " prefix for cleaner UI
  final raw = error?.toString() ?? 'Something went wrong.';
  return raw.replaceFirst('Exception: ', '');
}

String _mapAuthError(FirebaseAuthException error) {
  switch (error.code) {
    case 'user-disabled':
      return 'This account has been disabled. Please contact support.';
    case 'user-not-found':
      return 'No account found for this user.';
    case 'account-exists-with-different-credential':
      return 'An account already exists with a different sign-in method.';
    case 'invalid-credential':
      return 'The sign-in credential is invalid or expired. Please try again.';
    case 'operation-not-allowed':
      return 'This sign-in method is not enabled. Please contact support.';
    case 'network-request-failed':
      return 'Network error. Please check your internet connection and try again.';
    case 'popup-closed-by-user':
    case 'cancelled':
    case 'aborted':
      return 'Sign-in was cancelled.';
    case 'timeout':
      return 'The request timed out. Please try again.';
    case 'invalid-email':
      return 'The email address is not valid.';
    case 'email-already-in-use':
      return 'An account already exists with this email address.';
    case 'weak-password':
      return 'The password provided is too weak.';
    case 'wrong-password':
      return 'Incorrect password. Please try again.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again later.';
    default:
      return 'Authentication failed. Please try again.';
  }
}

String _mapFirebaseException(FirebaseException error) {
  // Firestore errors
  if (error.plugin == 'cloud_firestore') {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to perform this action.';
      case 'not-found':
        return 'The requested data was not found.';
      case 'already-exists':
        return 'This record already exists.';
      case 'resource-exhausted':
        return 'Service is temporarily unavailable. Please try again later.';
      case 'unauthenticated':
        return 'Please sign in again to continue.';
      case 'unavailable':
        return 'Firestore service is currently unavailable. Please check your connection.';
      case 'deadline-exceeded':
        return 'The request took too long. Please try again.';
      case 'cancelled':
        return 'The request was cancelled.';
      case 'data-loss':
        return 'Data was lost. Please contact support.';
      case 'internal':
        return 'An internal error occurred. Please try again later.';
      default:
        return 'Database error. Please try again.';
    }
  }

  // Realtime Database errors
  if (error.plugin == 'firebase_database') {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to access this data.';
      case 'disconnected':
        return 'Lost connection to the server. Please check your internet.';
      case 'expired-token':
        return 'Your session has expired. Please sign in again.';
      case 'invalid-token':
        return 'Invalid session. Please sign in again.';
      case 'unavailable':
        return 'Realtime database is unavailable. Please try again later.';
      case 'network-error':
        return 'Network error. Please check your connection.';
      default:
        return 'Database sync error. Please try again.';
    }
  }

  // Storage or other Firebase plugins
  return 'A server error occurred. Please try again later.';
}
