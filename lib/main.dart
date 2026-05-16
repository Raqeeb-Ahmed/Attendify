import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'utils/app_config.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/employee/employee_dashboard.dart';
import 'screens/login_screen.dart';
import 'services/work_manager_service.dart';
import 'services/foreground_tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  await GoogleSignIn.instance.initialize(
    serverClientId: AppConfig.googleServerClientId,
  );

  // Initialize WorkManager for true Android background execution
  await WorkManagerService.initialize();

  // Initialize foreground tracking service (must be called before runApp)
  ForegroundTrackingService.initialize();

  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Core Flow HCM',
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
      builder: (context, snapshot) {
        // Show loading while determining auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          // Not logged in - show login screen
          return const LoginScreen();
        }

        // Logged in - fetch role and redirect to appropriate dashboard
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (userSnapshot.hasError || !userSnapshot.hasData || !userSnapshot.data!.exists) {
              // Error or user doc missing - sign out and go to login
              FirebaseAuth.instance.signOut();
              return const LoginScreen();
            }

            final data = userSnapshot.data!.data() as Map<String, dynamic>?;
            final role = data?['role'] ?? 'employee';
            if (role == 'admin') {
              return const AdminDashboard();
            } else {
              return const EmployeeDashboard();
            }
          },
        );
      },
    );
  }
}
