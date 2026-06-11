import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream of users, excluding the current logged-in user
  Stream<List<AppUser>> getOtherUsers(String currentUid) {
    return _db.collection('users').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => AppUser.fromMap(doc.data()))
          .where((user) => user.uid != currentUid)
          .toList();
    });
  }

  // Consistently generate a Room ID by sorting UIDs
  String getRoomId(String uidA, String uidB) {
    final list = [uidA, uidB]..sort();
    return list.join("_");
  }

  // Create chat room document if it does not exist
  Future<void> createChatRoom(String roomId, String uidA, String uidB) async {
    final roomDoc = _db.collection('chat_rooms').doc(roomId);
    final docSnapshot = await roomDoc.get();

    if (!docSnapshot.exists) {
      await roomDoc.set({
        'roomId': roomId,
        'participants': [uidA, uidB],
      });
    }
  }

  // Get chat messages in real-time
  Stream<List<ChatMessage>> getMessages(String roomId) {
    return _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => ChatMessage.fromMap(doc.id, doc.data()))
              .toList();
        });
  }

  // Send a message inside the chat room
  Future<void> sendMessage({
    required String roomId,
    required String senderId,
    required String receiverId,
    required String message,
  }) async {
    if (message.trim().isEmpty) return;

    // Ensure chat room document exists before adding a message
    await createChatRoom(roomId, senderId, receiverId);

    await _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .add({
          'senderId': senderId,
          'receiverId': receiverId,
          'message': message.trim(),
          'timestamp': FieldValue.serverTimestamp(),
        });
  }
}
