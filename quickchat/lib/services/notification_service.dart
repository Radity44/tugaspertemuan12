// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';

// Top-level background message handler annotated with @pragma('vm:entry-point')
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling background message: ${message.messageId}");
}

class NotificationService {
  // Private constructor for Singleton pattern
  NotificationService._internal();

  // Singleton instance
  static final NotificationService _instance = NotificationService._internal();

  // Factory constructor to return the same instance
  factory NotificationService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'high_importance_channel';
  static const String _channelName = 'High Importance Notifications';
  static const String _channelDesc = 'This channel is used for important notifications.';

  // In-memory cache to prevent duplicate notifications during the app run
  final Set<String> _processedMessageIds = {};
  
  // Track rooms we are currently listening to
  final Set<String> _activeListeningRooms = {};
  
  // Subscriptions to cancel on logout
  final List<StreamSubscription> _messageSubscriptions = [];
  StreamSubscription? _roomsSubscription;
  DateTime? _appStartTime;

  // Initialize notifications setup and register Firestore listeners
  Future<void> init(String userId) async {
    try {
      print('FCM STEP 1: init called');
      print('NotificationService: Inisialisasi notifikasi berbasis Firestore Listener untuk user $userId');

      // Record app start time to filter out old chat history
      _appStartTime = DateTime.now();

      // 1. Request Notification Permission
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );
      print('FCM STEP 2: permission status = ${settings.authorizationStatus}');

      // 2. Initialize Local Notifications
      await _initLocalNotifications();

      // 3. Register Firestore Real-Time Message Listener
      _startFirestoreListener(userId);

      // 4. Fetch and save FCM token (retained for compatibility)
      final token = await getToken();
      if (token != null) {
        print('FCM STEP 4: saving token to firestore');
        await saveTokenToFirestore(userId, token);
        print('FCM STEP 5: token saved');
      } else {
        print('FCM STEP 4: token is null, skipping Firestore save');
      }

      // 5. Setup Token Refresh Listener
      _fcm.onTokenRefresh.listen((newToken) async {
        print('FCM Token refreshed: $newToken');
        try {
          await saveTokenToFirestore(userId, newToken);
        } catch (e, stackTrace) {
          print('FCM REFRESH ERROR: $e');
          print(stackTrace);
        }
      });
    } catch (e, stackTrace) {
      print('FCM ERROR during init: $e');
      print(stackTrace);
      rethrow;
    }
  }

  // Request permissions (legacy/fallback helper)
  Future<void> requestPermissions() async {
    try {
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      print('User granted permission: ${settings.authorizationStatus}');
    } catch (e, stackTrace) {
      print('Error requesting notification permissions: $e');
      print(stackTrace);
      rethrow;
    }
  }

  // Initialize Local Notifications configuration
  Future<void> _initLocalNotifications() async {
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );

      await _localNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          print('Notification tapped: ${details.payload}');
        },
      );

      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
    } catch (e, stackTrace) {
      print('Error initializing local notifications: $e');
      print(stackTrace);
      rethrow;
    }
  }

  // Real-time Firestore Listener: Listen to all rooms the user participates in
  void _startFirestoreListener(String currentUid) {
    // Cancel previous listeners to prevent duplicates/leaks
    _roomsSubscription?.cancel();
    for (var sub in _messageSubscriptions) {
      sub.cancel();
    }
    _messageSubscriptions.clear();
    _activeListeningRooms.clear();

    _roomsSubscription = _db
        .collection('chat_rooms')
        .where('participants', arrayContains: currentUid)
        .snapshots()
        .listen((roomsSnapshot) {
      for (var doc in roomsSnapshot.docs) {
        final roomId = doc.id;
        _subscribeToRoomMessages(roomId, currentUid);
      }
    }, onError: (e, stackTrace) {
      print("Error listening to chat rooms: $e");
      print(stackTrace);
    });
  }

  // Subscribe to the messages subcollection of a specific room
  void _subscribeToRoomMessages(String roomId, String currentUid) {
    if (_activeListeningRooms.contains(roomId)) return;
    _activeListeningRooms.add(roomId);

    final sub = _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('messages')
        .snapshots()
        .listen((messagesSnapshot) {
      for (var change in messagesSnapshot.docChanges) {
        // Only trigger on newly added documents in the stream
        if (change.type == DocumentChangeType.added) {
          final doc = change.doc;
          final messageId = doc.id;
          final data = doc.data();

          if (data != null) {
            final senderId = data['senderId'] as String?;
            final messageText = data['message'] as String?;
            final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

            // Conditions for showing local notifications:
            // 1. Sent by another user (senderId != currentUid)
            // 2. Not processed/shown in this session yet
            if (senderId != null &&
                senderId != currentUid &&
                messageText != null &&
                !_processedMessageIds.contains(messageId)) {
              
              // Register as processed immediately
              _processedMessageIds.add(messageId);

              // 3. Ensure the message was sent after app started (or timestamp is null while write resolves)
              if (timestamp == null || timestamp.isAfter(_appStartTime!)) {
                _showNotification(messageId, messageText);
              }
            }
          }
        }
      }
    }, onError: (e, stackTrace) {
      print("Error listening to messages in room $roomId: $e");
      print(stackTrace);
    });

    _messageSubscriptions.add(sub);
  }

  // Display the local notification
  Future<void> _showNotification(String messageId, String messageBody) async {
    try {
      await _localNotificationsPlugin.show(
        id: messageId.hashCode,
        title: 'Pesan Baru',
        body: messageBody,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
      print("Local Notification Triggered for Message: $messageBody");
    } catch (e, stackTrace) {
      print("Error showing local notification: $e");
      print(stackTrace);
    }
  }

  // Get FCM token (retained for compatibility)
  Future<String?> getToken() async {
    try {
      final token = await _fcm.getToken();
      print('FCM STEP 3: token = $token');
      return token;
    } catch (e, stackTrace) {
      print('Error getting FCM token: $e');
      print(stackTrace);
      rethrow;
    }
  }

  // Save FCM token to Firestore (retained for compatibility)
  Future<void> saveTokenToFirestore(String userId, String token) async {
    try {
      await _db.collection('users').doc(userId).update({
        'fcmToken': token,
      });
      print('NotificationService: Token berhasil disimpan/diperbarui ke Firestore.');
    } catch (e, stackTrace) {
      print('NotificationService: Gagal menyimpan token ke Firestore: $e');
      print(stackTrace);
      rethrow;
    }
  }

  // Static background message handler getter for main.dart registration compatibility
  static Future<void> Function(RemoteMessage) get backgroundHandler =>
      _firebaseMessagingBackgroundHandler;

  // Unsubscribe listeners and reset state on logout
  void dispose() {
    _roomsSubscription?.cancel();
    for (var sub in _messageSubscriptions) {
      sub.cancel();
    }
    _messageSubscriptions.clear();
    _activeListeningRooms.clear();
    _processedMessageIds.clear();
    print('NotificationService: Firestore subscriptions and caches disposed.');
  }
}
