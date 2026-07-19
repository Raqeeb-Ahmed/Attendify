import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import '../utils/service_account.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background notifications here if necessary.
  debugPrint("Handling a background message: ${message.messageId}");
}

class PushNotificationService {
  PushNotificationService._privateConstructor();
  static final PushNotificationService instance =
      PushNotificationService._privateConstructor();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Cache FCM V1 OAuth2 Access Token
  String? _cachedToken;
  DateTime? _tokenExpiry;

  Future<void> initialize() async {
    if (_initialized) return;

    // 1. Request notification permissions
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted push notification permission');
    } else {
      debugPrint(
        'User declined or has not accepted push notification permission',
      );
    }

    // 2. Initialize local notifications for foreground alerts
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification clicked: ${response.payload}');
      },
    );

    // 3. Create high importance notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important push notifications.',
      importance: Importance.high,
      playSound: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(channel);
    }

    // 4. Setup foreground message listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Received foreground push: ${message.notification?.title}');
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: android?.smallIcon ?? '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: message.data.toString(),
        );
      }
    });

    // 5. Setup interaction message listeners
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('FCM opened app from notification: ${message.data}');
    });

    // 6. Automatically register/refresh token if user is already signed in
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await registerUserToken(currentUser.uid);
    }

    _initialized = true;
  }

  /// Saves the device FCM token to the user document in Firestore.
  Future<void> registerUserToken(String userId) async {
    try {
      String? token = await _fcm.getToken();
      if (token == null) return;

      debugPrint('FCM Device Token: $token');

      // Add the token to fcmTokens array in Firestore
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });

      // Handle token refreshes
      _fcm.onTokenRefresh.listen((newToken) async {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid == userId) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
                'fcmTokens': FieldValue.arrayUnion([newToken]),
              });
        }
      });
    } catch (e) {
      debugPrint('Error registering user FCM token: $e');
    }
  }

  /// Removes the device FCM token from the user document in Firestore on logout.
  Future<void> removeUserToken(String userId) async {
    try {
      String? token = await _fcm.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
      debugPrint('Successfully removed FCM token on logout');
    } catch (e) {
      debugPrint('Error removing FCM token: $e');
    }
  }

  /// Subscribes the device to a global notification topic.
  Future<void> subscribeToTopic(String topic) async {
    await _fcm.subscribeToTopic(topic);
    debugPrint('Subscribed to topic: $topic');
  }

  /// Unsubscribes the device from a global notification topic.
  Future<void> unsubscribeFromTopic(String topic) async {
    await _fcm.unsubscribeFromTopic(topic);
    debugPrint('Unsubscribed from topic: $topic');
  }

  /// Sends a push notification directly from the app using the modern Firebase FCM V1 API.
  /// Works on the free Spark plan without requiring Cloud Functions.
  Future<void> sendPushNotification({
    required List<String> recipientTokens,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (recipientTokens.isEmpty) {
      debugPrint('No recipient tokens provided for push notification.');
      return;
    }

    if (ServiceAccountConfig.jsonCredentials['project_id'] ==
        dotenv.env['FCM_PROJECT_ID']) {
      debugPrint(
        'FCM Service Account not configured in service_account.dart. Please set your credentials.',
      );
      return;
    }

    try {
      final projectId = ServiceAccountConfig.jsonCredentials['project_id'];
      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
      );

      // 1. Get OAuth2 access token (use cache if valid)
      String accessToken;
      if (_cachedToken != null &&
          _tokenExpiry != null &&
          _tokenExpiry!.isAfter(
            DateTime.now().add(const Duration(minutes: 2)),
          )) {
        accessToken = _cachedToken!;
        debugPrint(
          'Using cached FCM V1 Access Token (expires in: ${_tokenExpiry!.difference(DateTime.now()).inMinutes} mins)',
        );
      } else {
        debugPrint(
          'Fetching new FCM V1 Access Token (cache expired or empty)...',
        );
        final credentials = ServiceAccountCredentials.fromJson(
          ServiceAccountConfig.jsonCredentials,
        );
        final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

        final client = await clientViaServiceAccount(credentials, scopes);
        _cachedToken = client.credentials.accessToken.data;
        _tokenExpiry = client.credentials.accessToken.expiry;
        accessToken = _cachedToken!;
        client.close();
        debugPrint('Successfully retrieved and cached new FCM V1 token');
      }

      // 2. Send notifications in parallel to all recipient tokens
      final sendRequests = recipientTokens.map((token) async {
        try {
          final response = await http.post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({
              'message': {
                'token': token,
                'notification': {'title': title, 'body': body},
                'data': data ?? {},
                'android': {
                  'priority': 'high',
                  'notification': {
                    'channel_id': 'high_importance_channel',
                    'sound': 'default',
                  },
                },
                'apns': {
                  'headers': {'apns-priority': '10'},
                  'payload': {
                    'aps': {
                      'sound': 'default',
                      'badge': 1,
                      'content-available': 1,
                    },
                  },
                },
              },
            }),
          );

          if (response.statusCode == 200) {
            debugPrint(
              'Push notification sent successfully via FCM V1 to: ${token.substring(0, min(10, token.length))}...',
            );
          } else {
            debugPrint(
              'Failed to send push notification to token. Status: ${response.statusCode}, Body: ${response.body}',
            );
            // If the token is unregistered or not found, remove it from Firestore automatically
            if (response.statusCode == 404 ||
                response.body.contains('UNREGISTERED')) {
              _removeInvalidToken(token);
            }
          }
        } catch (e) {
          debugPrint('Error sending single push request: $e');
        }
      });

      await Future.wait(sendRequests);
    } catch (e) {
      debugPrint('Error sending FCM V1 push notification: $e');
    }
  }

  /// Removes an invalid/unregistered FCM token from any user document in Firestore.
  Future<void> _removeInvalidToken(String token) async {
    try {
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('fcmTokens', arrayContains: token)
          .get();

      for (var doc in userQuery.docs) {
        await doc.reference.update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
      }
      debugPrint(
        'Successfully cleaned up unregistered FCM token from Firestore: ${token.substring(0, min(10, token.length))}...',
      );
    } catch (e) {
      debugPrint('Error cleaning up unregistered FCM token: $e');
    }
  }

  // Helper helper to get min value safely without dart:math import
  int min(int a, int b) => a < b ? a : b;
}
