// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Listen to Auth State changes
  Stream<User?> get userStream => _auth.authStateChanges();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Google Sign In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      print("STEP 1");
      // Trigger the Google authentication flow (version 7.2.0+)
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();
      print("STEP 2");
      
      // Obtain the auth details (getter in 7.2.0+, not a Future, no await needed)
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      print("STEP 3");

      // Create a new credential using the ID token
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      print("STEP 4");

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      print("STEP 5");
      final User? user = userCredential.user;

      if (user != null) {
        // Persist user to Firestore
        await _saveUserToFirestore(user);
      }

      return userCredential;
    } on GoogleSignInException catch (e, stackTrace) {
      print("LOGIN ERROR: $e");
      print(stackTrace);
      // If the user cancels the sign-in flow
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    } catch (e, stackTrace) {
      print("LOGIN ERROR: $e");
      print(stackTrace);
      rethrow;
    }
  }

  // Save/Update user in Firestore users collection
  Future<void> _saveUserToFirestore(User user) async {
    final docRef = _db.collection('users').doc(user.uid);
    final docSnap = await docRef.get();

    if (!docSnap.exists) {
      // Create new user record
      await docRef.set({
        'uid': user.uid,
        'name': user.displayName ?? 'No Name',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'fcmToken': null, // Placeholder for Phase 2
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Update existing user details (name, email, photoUrl) but keep createdAt
      await docRef.update({
        'name': user.displayName ?? 'No Name',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
      });
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
