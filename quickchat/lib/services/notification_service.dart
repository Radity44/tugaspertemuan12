import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Initialize notifications setup (Phase 2 extension point)
  Future<void> init(String userId) async {
    // Phase 2: Set up firebase messaging listeners, background handlers, and local notifications
    // ignore: avoid_print
    print('NotificationService: Inisialisasi notifikasi untuk user $userId (Phase 2)');
    await requestPermissions();
    final token = await getToken();
    if (token != null) {
      await saveTokenToFirestore(userId, token);
    }
  }

  // Request notification permissions (Phase 2 extension point)
  Future<void> requestPermissions() async {
    // Phase 2: Request permissions using FirebaseMessaging or Local Notifications
    // ignore: avoid_print
    print('NotificationService: Meminta izin notifikasi (Phase 2)');
  }

  // Get FCM token (Phase 2 extension point)
  Future<String?> getToken() async {
    // Phase 2: Retrieve actual token using FirebaseMessaging.instance.getToken()
    return null;
  }

  // Save FCM token to user document in Firestore (Phase 2 extension point)
  Future<void> saveTokenToFirestore(String userId, String token) async {
    try {
      await _db.collection('users').doc(userId).update({
        'fcmToken': token,
      });
      // ignore: avoid_print
      print('NotificationService: Token berhasil disimpan ke Firestore.');
    } catch (e) {
      // ignore: avoid_print
      print('NotificationService: Gagal menyimpan token ke Firestore: $e');
    }
  }
}
