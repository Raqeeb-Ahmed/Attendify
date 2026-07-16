import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'utils/app_config.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/employee/employee_dashboard.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/push_notification_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Load environment variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: Could not load .env file: $e");
  }

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyDqDCmvqkVXO0sS8eL6gItD-YG4Ho0UEcU",
        authDomain: "attendify-2e534.firebaseapp.com",
        databaseURL: "https://attendify-2e534-default-rtdb.firebaseio.com",
        projectId: "attendify-2e534",
        storageBucket: "attendify-2e534.firebasestorage.app",
        messagingSenderId: "41353583974",
        appId: "1:41353583974:web:e4e3752e534606f2e27c06",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  // Set the background messaging handler early in main (only on non-web)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  runApp(const AttendanceApp());

  // Background initialization
  Future.microtask(_initializeServices);
}

Future<void> _initializeServices() async {
  try {
    await Future.wait([
      GoogleSignIn.instance.initialize(
        serverClientId: AppConfig.googleServerClientId,
      ),
      if (!kIsWeb) PushNotificationService.instance.initialize(),
    ]);

    debugPrint("✅ Background services initialized");
  } catch (e, s) {
    debugPrint("Initialization failed");
    debugPrint(e.toString());
    debugPrint(s.toString());
  }
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendify',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/admin': (context) => const AdminDashboard(),
        '/employee': (context) => const EmployeeDashboard(),
      },
    );
  }
}

/// Auth wrapper that listens to Firebase Auth state and redirects accordingly
/// Firebase Auth persists sessions locally by default on mobile
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),

      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnapshot.data;

        if (user == null) {
          FlutterNativeSplash.remove();
          return const LoginScreen();
        }

        // Logged in - fetch role and redirect to appropriate dashboard
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            FlutterNativeSplash.remove();

            if (userSnapshot.hasError ||
                !userSnapshot.hasData ||
                !userSnapshot.data!.exists) {
              // If the user document does not exist, they are pending approval or profile setup.
              // Once the LoginScreen finishes creating the document, the StreamBuilder will automatically rebuild.
              return const PendingApprovalScreen();
            }

            final data = userSnapshot.data!.data() as Map<String, dynamic>?;
            final role = data?['role'] ?? 'employee';
            final approved = data?['approved'] ?? true;

            if (kIsWeb && role == 'employee') {
              return const WebAccessDeniedScreen();
            }

            if (role == 'admin' || role == 'manager') {
              return const AdminDashboard();
            } else {
              if (approved) {
                return const EmployeeDashboard();
              } else {
                return const PendingApprovalScreen();
              }
            }
          },
        );
      },
    );
  }
}

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  @override
  void initState() {
    super.initState();
    _ensureUserDocExists();
  }

  Future<void> _ensureUserDocExists() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final docSnap = await docRef.get();
      if (!docSnap.exists) {
        await docRef.set({
          'name': user.displayName ?? 'Unknown',
          'email': user.email ?? '',
          'role': 'employee',
          'approved': false,
          'department': '',
          'designation': '',
          'phone': '',
          'baseSalary': 0,
          'allowances': 0,
          'createdAt': DateTime.now().toIso8601String(),
        });
        debugPrint(
          '[PendingApprovalScreen] User document auto-created in Firestore',
        );
      }
    } catch (e) {
      debugPrint('[PendingApprovalScreen] Error ensuring user doc: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.hourglass_empty_rounded,
                  size: 64,
                  color: Color(0xFFD97706),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Approval Pending',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your account has been registered, but it is waiting for approval by the administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              if (user?.email != null)
                Text(
                  'Email: ${user!.email}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6366F1),
                  ),
                ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () async {
                  await AuthService().signOut();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  }
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'Cancel & Sign Out',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WebAccessDeniedScreen extends StatelessWidget {
  const WebAccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF8F9FC),
      body: Center(
        child: Card(
          margin: EdgeInsets.all(24),
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.monitor_rounded, size: 64, color: Color(0xFFEF4444)),
                SizedBox(height: 16),
                Text(
                  'Web Access Restricted',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text(
                  'This Web Portal is only accessible for Admins and Managers.\nEmployees must log in using the mobile application.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
