import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// A utility class for handling Firebase Authentication.
///
/// This class supports email/password sign-in, Google sign-in,
/// user registration, password reset, and sign-out functionality.
class Auth {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final GoogleSignIn googleSignIn = GoogleSignIn();

  /// Signs in a user with email and password.
  ///
  /// - [email]: The user's email address.
  /// - [password]: The user's password.
  ///
  /// Returns the [User] object on success, or `null` on failure.
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      UserCredential userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      // Log specific error messages based on the Firebase error codes
      switch (e.code) {
        case 'user-not-found':
          print('No user found for the provided email.');
          break;
        case 'wrong-password':
          print('Incorrect password provided.');
          break;
        default:
          print('Error signing in with email: ${e.message}');
      }
      return null;
    } catch (e) {
      print('Unexpected error signing in with email: $e');
      return null;
    }
  }

  /// Registers a new user with email and password.
  ///
  /// - [email]: The user's email address.
  /// - [password]: The user's password.
  ///
  /// Returns the [User] object on success, or `null` on failure.
  Future<User?> registerWithEmail(String email, String password) async {
    try {
      UserCredential userCredential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      // Handle registration-specific errors
      switch (e.code) {
        case 'email-already-in-use':
          print('The email address is already in use.');
          break;
        case 'weak-password':
          print('The provided password is too weak.');
          break;
        default:
          print('Error registering with email: ${e.message}');
      }
      return null;
    } catch (e) {
      print('Unexpected error registering with email: $e');
      return null;
    }
  }

  /// Signs in a user with Google.
  ///
  /// Returns the [User] object on success, or `null` on failure.
  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled the sign-in
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
      await auth.signInWithCredential(credential);
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      // Log Google-specific authentication errors
      print('Error signing in with Google: ${e.message}');
      return null;
    } catch (e) {
      print('Unexpected error signing in with Google: $e');
      return null;
    }
  }

  /// Signs out the user from all accounts.
  ///
  /// This method signs the user out of Firebase and Google (if signed in).
  Future<void> signOut() async {
    try {
      await auth.signOut();
      await googleSignIn.signOut();
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  /// Retrieves the currently signed-in user, if any.
  ///
  /// Returns the [User] object if a user is signed in, or `null` if no user is signed in.
  User? getCurrentUser() {
    return auth.currentUser;
  }

  /// Sends a password reset email to the provided email address.
  ///
  /// - [email]: The user's email address.
  ///
  /// Returns `true` if the email was sent successfully, or `false` if an error occurred.
  Future<bool> sendResetEmail(String email) async {
    try {
      await auth.sendPasswordResetEmail(email: email);
      return true;
    } on FirebaseAuthException catch (e) {
      // Log specific error messages
      switch (e.code) {
        case 'invalid-email':
          print('The email address is not valid.');
          break;
        case 'user-not-found':
          print('No user found for the provided email.');
          break;
        default:
          print('Error sending password reset email: ${e.message}');
      }
      return false;
    } catch (e) {
      print('Unexpected error sending password reset email: $e');
      return false;
    }
  }
}
