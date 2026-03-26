import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Global utility class for attendance status colors
/// Used consistently across the entire app
class AttendanceColors {
  // Status colors as per requirements
  static const Color absent = AppColors.error; // Red
  static const Color late = AppColors.warning; // Yellow
  static const Color present = AppColors.success; // Green
  static const Color halfDay = AppColors.info; // Blue

  /// Get color for attendance status
  /// Supports various status formats: 'absent', 'late', 'present', 'half_day', 'halfDay', 'completed', etc.
  static Color getStatusColor(String? status) {
    if (status == null) return absent;
    
    final normalizedStatus = status.toLowerCase().trim();
    
    // Absent statuses
    if (normalizedStatus == 'absent' || 
        normalizedStatus == 'on_leave' || 
        normalizedStatus == 'leave') {
      return absent;
    }
    
    // Late status
    if (normalizedStatus == 'late') {
      return late;
    }
    
    // Half day statuses
    if (normalizedStatus == 'half_day' || 
        normalizedStatus == 'halfday' || 
        normalizedStatus == 'half-day' ||
        normalizedStatus == 'half day') {
      return halfDay;
    }
    
    // Present/Completed statuses (default to green)
    if (normalizedStatus == 'present' || 
        normalizedStatus == 'completed' ||
        normalizedStatus == 'checked_in' ||
        normalizedStatus == 'checked_in') {
      return present;
    }
    
    // On break - use warning (yellow/orange)
    if (normalizedStatus == 'on_break' || normalizedStatus == 'onbreak') {
      return late; // Using late color (yellow) for break
    }
    
    // Default to present (green) for unknown statuses
    return present;
  }

  /// Get color for attendance status from attendance record
  /// Checks both status field and check-in/check-out times
  static Color getColorFromRecord(Map<String, dynamic>? attendance) {
    if (attendance == null || attendance.isEmpty) {
      return absent;
    }

    final status = attendance['status']?.toString();
    final checkIn = attendance['checkIn']?['time'];
    final checkOut = attendance['checkOut']?['time'];
    final isOnBreak = attendance['isOnBreak'] == true;

    // If status is explicitly set, use it
    if (status != null) {
      return getStatusColor(status);
    }

    // Fallback logic based on check-in/check-out
    if (checkOut != null) {
      return present; // Completed day
    } else if (isOnBreak) {
      return late; // On break - use yellow
    } else if (checkIn != null) {
      return present; // Checked in
    }

    return absent; // No check-in
  }

  /// Get status text for display
  static String getStatusText(String? status) {
    if (status == null) return 'Absent';
    
    final normalizedStatus = status.toLowerCase().trim();
    
    switch (normalizedStatus) {
      case 'absent':
        return 'Absent';
      case 'late':
        return 'Late';
      case 'half_day':
      case 'halfday':
      case 'half-day':
      case 'half day':
        return 'Half Day';
      case 'present':
      case 'completed':
        return 'Present';
      case 'on_break':
      case 'onbreak':
        return 'On Break';
      case 'on_leave':
      case 'leave':
        return 'On Leave';
      default:
        return status.toUpperCase();
    }
  }
}

