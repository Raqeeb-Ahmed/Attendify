// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendenceapp/main.dart';
import 'package:attendenceapp/screens/login_screen.dart';

void main() {
  group('Attendance App Widget Tests', () {
    testWidgets('App should build without errors', (WidgetTester tester) async {
      await tester.pumpWidget(const AttendanceApp());
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('LoginScreen should show Google Sign In button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );
      
      // Verify login screen elements
      expect(find.text('Core Flow HCM'), findsOneWidget);
      expect(find.text('Professional Attendance System'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
    });

    testWidgets('LoginScreen should show app branding', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );
      
      // Check for branding elements
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
      expect(find.text('Professional Attendance System'), findsOneWidget);
    });
  });
}
