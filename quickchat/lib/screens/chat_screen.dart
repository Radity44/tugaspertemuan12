import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../services/firestore_service.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final AppUser receiver;

  const ChatScreen({
    super.key,
    required this.receiver,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _messageController = TextEditingController();
  late final String _roomId;
  late final String _currentUid;

  @override
  void initState() {
    super.initState();
    _currentUid = _auth.currentUser?.uid ?? '';
    // Generate Room ID consistently using: [uidA, uidB]..sort().join("_")
    _roomId = _firestoreService.getRoomId(_currentUid, widget.receiver.uid);
    // Pre-create the chat room document in Firestore
    _firestoreService.createChatRoom(_roomId, _currentUid, widget.receiver.uid);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _handleSend() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await _firestoreService.sendMessage(
        roomId: _roomId,
        senderId: _currentUid,
        receiverId: widget.receiver.uid,
        message: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengirim pesan: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.receiver.photoUrl.isNotEmpty
                  ? NetworkImage(widget.receiver.photoUrl)
                  : null,
              child: widget.receiver.photoUrl.isEmpty
                  ? const Icon(Icons.person, size: 20)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.receiver.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages Feed
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _firestoreService.getMessages(_roomId),
              builder: (context, snapshot) {
                // Loading State
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                // Error State
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 40),
                          const SizedBox(height: 12),
                          Text('Gagal memuat pesan: ${snapshot.error}'),
                        ],
                      ),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];

                // Empty State
                if (messages.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Belum ada pesan. Mulai obrolan sekarang!',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                // Normal Chat List (reversed for automatic bottom scroll anchoring)
                final reversedMessages = messages.reversed.toList();

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: reversedMessages.length,
                  itemBuilder: (context, index) {
                    final message = reversedMessages[index];
                    final isMe = message.senderId == _currentUid;
                    return MessageBubble(
                      message: message,
                      isMe: isMe,
                    );
                  },
                );
              },
            ),
          ),

          // Message Input Field
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Ketik pesan...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _handleSend,
                  icon: const Icon(Icons.send),
                  tooltip: 'Kirim',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
