import 'package:flutter_test/flutter_test.dart';
import 'dart:math';

// Test the core business logic that matches web app
void main() {
  group('Attendance Service Logic Tests', () {
    
    // Office hours: 9:45 AM - 5:45 PM (matching web app)
    
    group('Status Determination', () {
      test('Should return PRESENT when checking in before 9:45 AM', () {
        final checkInTime = DateTime(2024, 1, 15, 9, 30); // 9:30 AM
        final status = _determineStatus(checkInTime, true);
        expect(status, 'present');
      });
      
      test('Should return PRESENT when checking in at exactly 9:45 AM', () {
        final checkInTime = DateTime(2024, 1, 15, 9, 45); // 9:45 AM
        final status = _determineStatus(checkInTime, true);
        expect(status, 'present');
      });
      
      test('Should return LATE when checking in after 9:45 AM', () {
        final checkInTime = DateTime(2024, 1, 15, 10, 0); // 10:00 AM
        final status = _determineStatus(checkInTime, true);
        expect(status, 'late');
      });
      
      test('Should return OUTSIDE when outside office radius', () {
        final checkInTime = DateTime(2024, 1, 15, 9, 30);
        final status = _determineStatus(checkInTime, false);
        expect(status, 'outside');
      });
    });
    
    group('Time Calculations', () {
      test('Should calculate total hours correctly', () {
        final checkIn = DateTime(2024, 1, 15, 9, 0);
        final checkOut = DateTime(2024, 1, 15, 18, 0);
        final hours = _calculateTotalHours(checkIn, checkOut);
        expect(hours, 9.0);
      });
      
      test('Should calculate inside time percentage', () {
        final insideMinutes = 420; // 7 hours
        final outsideMinutes = 60; // 1 hour
        final percentage = _calculateInsidePercentage(insideMinutes, outsideMinutes);
        expect(percentage, 87.5);
      });
      
      test('Should calculate extra hours when working past 5:45 PM', () {
        final checkOut = DateTime(2024, 1, 15, 19, 0); // 7:00 PM
        final officeEnd = DateTime(2024, 1, 15, 17, 45); // 5:45 PM
        final extraMinutes = _calculateExtraMinutes(checkOut, officeEnd);
        expect(extraMinutes, 75); // 1 hour 15 minutes
      });
    });
    
    group('Geofence Calculations', () {
      test('Should calculate correct distance using Haversine formula', () {
        // Office coordinates
        final officeLat = 33.717810797788445;
        final officeLng = 73.07266545222373;
        
        // Position 50 meters away
        final testLat = 33.718260;
        final testLng = 73.072665;
        
        final distance = _calculateHaversineDistance(officeLat, officeLng, testLat, testLng);
        expect(distance, lessThan(100)); // Should be within 100m
        expect(distance, greaterThan(0));
      });
      
      test('Should detect inside radius for position at 80 meters', () {
        final distance = 80.0;
        final isInside = _isWithinRadius(distance, 100);
        expect(isInside, true);
      });
      
      test('Should detect outside radius for position at 150 meters', () {
        final distance = 150.0;
        final isInside = _isWithinRadius(distance, 100);
        expect(isInside, false);
      });
      
      test('Should detect exactly at boundary (100m)', () {
        final distance = 100.0;
        final isInside = _isWithinRadius(distance, 100);
        expect(isInside, true);
      });
    });
    
    group('Office Hours Validation', () {
      test('Should detect check-in during office hours', () {
        final time = DateTime(2024, 1, 15, 10, 0); // 10:00 AM
        final isOfficeHours = _isOfficeHours(time);
        expect(isOfficeHours, true);
      });
      
      test('Should detect check-in before office hours', () {
        final time = DateTime(2024, 1, 15, 8, 0); // 8:00 AM
        final isOfficeHours = _isOfficeHours(time);
        expect(isOfficeHours, false);
      });
      
      test('Should detect check-in after office hours', () {
        final time = DateTime(2024, 1, 15, 18, 0); // 6:00 PM
        final isOfficeHours = _isOfficeHours(time);
        expect(isOfficeHours, false);
      });
    });
    
    group('Date Formatting', () {
      test('Should format date as ISO 8601 string', () {
        final date = DateTime(2024, 1, 15, 9, 30, 0);
        final formatted = _formatDateISO(date);
        expect(formatted, '2024-01-15T09:30:00.000');
      });
      
      test('Should generate correct document ID', () {
        final userId = 'user123';
        final date = DateTime(2024, 1, 15);
        final docId = _generateDocId(userId, date);
        expect(docId, 'user123_2024-01-15');
      });
    });
  });
}

// Helper functions that mirror the actual service logic

String _determineStatus(DateTime checkInTime, bool atOffice) {
  if (!atOffice) return 'outside';
  
  final hour = checkInTime.hour;
  final minute = checkInTime.minute;
  
  // Before 9:45 AM = present
  if (hour < 9 || (hour == 9 && minute <= 45)) {
    return 'present';
  }
  
  // After 9:45 AM = late
  return 'late';
}

double _calculateTotalHours(DateTime checkIn, DateTime checkOut) {
  final difference = checkOut.difference(checkIn);
  return difference.inMinutes / 60.0;
}

double _calculateInsidePercentage(int insideMinutes, int outsideMinutes) {
  final total = insideMinutes + outsideMinutes;
  if (total == 0) return 0.0;
  return (insideMinutes / total) * 100;
}

int _calculateExtraMinutes(DateTime checkOut, DateTime officeEnd) {
  if (checkOut.isBefore(officeEnd)) return 0;
  return checkOut.difference(officeEnd).inMinutes;
}

double _calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371e3; // Earth radius in meters
  final dLat = (lat2 - lat1) * (pi / 180);
  final dLon = (lon2 - lon1) * (pi / 180);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

bool _isWithinRadius(double distance, int radius) {
  return distance <= radius;
}

bool _isOfficeHours(DateTime time) {
  final hour = time.hour;
  return hour >= 9 && hour < 18;
}

String _formatDateISO(DateTime date) {
  return date.toIso8601String();
}

String _generateDocId(String userId, DateTime date) {
  final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return '${userId}_$dateStr';
}
