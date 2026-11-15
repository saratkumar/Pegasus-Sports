import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_booking/services/class_reschedule_service.dart';

void main() {
  group('nextOnDays (where a booking lands when a whole class moves)', () {
    // 2026-11-16 is a Monday.
    final mon = DateTime(2026, 11, 16);

    test('Monday class moved to Friday → same week\'s Friday', () {
      expect(ClassRescheduleService.nextOnDays(mon, {'Friday'}),
          DateTime(2026, 11, 20));
    });

    test('day unchanged (time-only change) → same date', () {
      expect(ClassRescheduleService.nextOnDays(mon, {'Monday'}), mon);
    });

    test('Friday class moved to Monday → following Monday, never earlier', () {
      expect(ClassRescheduleService.nextOnDays(DateTime(2026, 11, 20), {'Monday'}),
          DateTime(2026, 11, 23));
    });

    test('several new days → the first one on or after the old date', () {
      expect(
          ClassRescheduleService.nextOnDays(
              DateTime(2026, 11, 18), {'Monday', 'Thursday'}),
          DateTime(2026, 11, 19));
    });
  });

  test('minutesBetween handles normal and past-midnight slots', () {
    expect(
        ClassRescheduleService.minutesBetween(
            const TimeOfDay(hour: 19, minute: 0), const TimeOfDay(hour: 20, minute: 30)),
        90);
    expect(
        ClassRescheduleService.minutesBetween(
            const TimeOfDay(hour: 23, minute: 30), const TimeOfDay(hour: 0, minute: 30)),
        60);
  });

  test('formatTime matches how classes store times', () {
    expect(ClassRescheduleService.formatTime(const TimeOfDay(hour: 19, minute: 15)),
        '7:15 PM');
    expect(ClassRescheduleService.formatTime(const TimeOfDay(hour: 0, minute: 5)),
        '12:05 AM');
    expect(ClassRescheduleService.formatTime(const TimeOfDay(hour: 12, minute: 0)),
        '12:00 PM');
  });

  test('duration text round-trips', () {
    for (final m in [45, 60, 90, 120]) {
      expect(
          ClassRescheduleService.parseDuration(
              ClassRescheduleService.formatDuration(m)),
          m);
    }
  });
}
