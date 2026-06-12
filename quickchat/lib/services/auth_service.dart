import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Listen to Auth State changes
  Stream<User?> get userStream => _auth.authStateChanges();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Google Sign In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // Persist user to Firestore
        await _saveUserToFirestore(user);
      }

      return userCredential;
    } catch (e) {
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
