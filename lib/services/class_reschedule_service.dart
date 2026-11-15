import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import '../models/class_model.dart';
import '../utils/time_utils.dart';
import 'booking_service.dart';
import 'config_service.dart';
import 'email_service.dart';

/// Result of a reschedule — how many bookings / waiting-list entries moved.
typedef RescheduleResult = ({int bookingsMoved, int waitlistMoved});

/// Admin-only "move this class to a different date/time" actions — the
/// alternative to cancelling. Built alongside ClassCancellationService (and
/// deliberately independent of it): nothing is refunded, every booking and
/// waiting-list entry simply moves with the session, and affected clients
/// are emailed the new time.
///
/// Activity Log: each moved booking gets a "Session Rescheduled by Admin"
/// row on the old session and a "Booked" row (note: "Rescheduled from …")
/// on the new one, same booking id — so the Class Roster, which rebuilds
/// rosters from the Sheet, shows the person on the new session only.
class ClassRescheduleService {
  static final _db = FirebaseFirestore.instance;
  static final _bookingsCol = _db.collection('bookings');
  static final _classesCol = _db.collection('classes');
  static final _waitlistCol = _db.collection('waitingList');
  static final _usersCol = _db.collection('users');

  static const dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  // ── Single session ──────────────────────────────────────────────────────

  /// Moves one session of [cls] — the one on [fromDate] — to [toDate] at
  /// [newStart]–[newEnd]. The moved session becomes its own one-off class
  /// (same details, coach, capacity and plan rules), and [fromDate] is
  /// taken off the original class's schedule, so the rest of the series is
  /// untouched.
  static Future<RescheduleResult> rescheduleSession({
    required ClassModel cls,
    required DateTime fromDate,
    required DateTime toDate,
    required TimeOfDay newStart,
    required TimeOfDay newEnd,
  }) async {
    final from = _day(fromDate);
    final to = _day(toDate);
    final newStartText = formatTime(newStart);
    final durationText = formatDuration(minutesBetween(newStart, newEnd));

    // 1. The moved session, as a one-off class.
    final newRef = _classesCol.doc();
    final capacity = cls.effectiveCapacity(from);
    await newRef.set({
      ...cls.toFirestore(),
      'day': dayNames[to.weekday - 1],
      'occurrence': 'once',
      'specificDate': _dateKey(to),
      'startTime': newStartText,
      'duration': durationText,
      'groupSize': capacity > 0 ? capacity.toString() : cls.groupSize,
      'isActive': true,
      'rescheduledFrom': {
        'classId': cls.effectiveId,
        'date': _dateKey(from),
        'startTime': cls.startTime,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Take the old date off the original class.
    if (cls.occurrence == 'once') {
      await _classesCol.doc(cls.id).update(
          {'isActive': false, 'updatedAt': FieldValue.serverTimestamp()});
    } else {
      await _classesCol.doc(cls.id).update({
        'cancelledDates': FieldValue.arrayUnion([_dateKey(from)]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // 3. Move bookings + waiting list.
    final bookings = await _activeBookingsOn(cls.effectiveId, from);
    final moves = [
      for (final b in bookings)
        _Move(b, newClassId: newRef.id, newDate: to, newTime: newStartText),
    ];
    await _applyMoves(moves);
    final waitlist = await _waitingOn(cls.effectiveId, from);
    await _moveWaitlist(waitlist,
        newClassId: newRef.id, newDate: to, newTime: newStartText);

    await _db.collection('sessionLogs').add({
      'type': 'session_rescheduled',
      'classId': cls.effectiveId,
      'newClassId': newRef.id,
      'className': cls.mode,
      'fromDate': _dateKey(from),
      'fromTime': cls.startTime,
      'toDate': _dateKey(to),
      'toTime': newStartText,
      'bookingsMoved': moves.length,
      'rescheduledAt': Timestamp.now(),
      'reason': 'admin_direct',
    });

    unawaited(_notify(moves,
        oldClassId: cls.effectiveId,
        className: cls.mode,
        location: cls.location,
        durationMinutes: minutesBetween(newStart, newEnd)));

    return (bookingsMoved: moves.length, waitlistMoved: waitlist.length);
  }

  // ── Whole class ─────────────────────────────────────────────────────────

  /// Moves the whole series of [cls] to [newDays] (weekly classes only;
  /// ignored for other recurrences) at [newStart]–[newEnd]. Every upcoming
  /// booking moves to the first session on the new schedule on or after
  /// its original date (same date when only the time changes).
  static Future<RescheduleResult> rescheduleWholeClass({
    required ClassModel cls,
    required Set<String> newDays,
    required TimeOfDay newStart,
    required TimeOfDay newEnd,
  }) async {
    final weekly = _isWeekly(cls);
    final days = weekly ? _orderedDays(newDays) : cls.day;
    final newStartText = formatTime(newStart);
    final durationText = formatDuration(minutesBetween(newStart, newEnd));

    await _classesCol.doc(cls.id).update({
      if (weekly) 'day': days,
      'startTime': newStartText,
      'duration': durationText,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final today = _day(DateTime.now());
    final bookings = await _activeBookingsFrom(cls.effectiveId, today);
    final moves = <_Move>[];
    for (final b in bookings) {
      final oldDate = _day((b.data()['bookingDate'] as Timestamp).toDate());
      final move = _Move(b,
          newClassId: cls.effectiveId,
          newDate: weekly ? nextOnDays(oldDate, newDays) : oldDate,
          newTime: newStartText);
      // e.g. only a day was added: this booking keeps its date and time.
      if (move.newDate == oldDate && move.newTime == move.oldTime) continue;
      moves.add(move);
    }
    await _applyMoves(moves);

    final waitlist = await _waitingFrom(cls.effectiveId, today);
    for (final w in waitlist) {
      final oldDate = _day((w.data()['bookingDate'] as Timestamp).toDate());
      await _moveWaitlist([w],
          newClassId: cls.effectiveId,
          newDate: weekly ? nextOnDays(oldDate, newDays) : oldDate,
          newTime: newStartText);
    }

    await _db.collection('sessionLogs').add({
      'type': 'class_rescheduled',
      'classId': cls.effectiveId,
      'className': cls.mode,
      'fromDays': cls.day,
      'fromTime': cls.startTime,
      'toDays': days,
      'toTime': newStartText,
      'bookingsMoved': moves.length,
      'rescheduledAt': Timestamp.now(),
      'reason': 'admin_direct',
    });

    unawaited(_notify(moves,
        oldClassId: cls.effectiveId,
        className: cls.mode,
        location: cls.location,
        durationMinutes: minutesBetween(newStart, newEnd)));

    return (bookingsMoved: moves.length, waitlistMoved: waitlist.length);
  }

  /// For the confirmation dialog: upcoming bookings a whole-class move
  /// would affect, and the new sessions that would end up over capacity.
  static Future<({int bookings, List<String> overCapacity})> previewWholeClass({
    required ClassModel cls,
    required Set<String> newDays,
  }) async {
    final today = _day(DateTime.now());
    final bookings = await _activeBookingsFrom(cls.effectiveId, today);
    final perDate = <DateTime, int>{};
    for (final b in bookings) {
      final old = _day((b.data()['bookingDate'] as Timestamp).toDate());
      final target = _isWeekly(cls) ? nextOnDays(old, newDays) : old;
      perDate[target] = (perDate[target] ?? 0) + 1;
    }
    final over = <String>[
      for (final e in perDate.entries)
        if (cls.effectiveCapacity(e.key) > 0 &&
            e.value > cls.effectiveCapacity(e.key))
          '${_dateKey(e.key)}: ${e.value} booked, capacity ${cls.effectiveCapacity(e.key)}',
    ];
    return (bookings: bookings.length, overCapacity: over);
  }

  /// Bookings currently on [cls]'s session on [date] — for the dialog.
  static Future<int> bookingsOn(ClassModel cls, DateTime date) async =>
      (await _activeBookingsOn(cls.effectiveId, _day(date))).length;

  // ── Helpers ─────────────────────────────────────────────────────────────

  static bool _isWeekly(ClassModel cls) =>
      cls.occurrence == 'weekly' || cls.occurrence.isEmpty;

  /// First date on or after [from] whose weekday is in [days].
  static DateTime nextOnDays(DateTime from, Set<String> days) {
    for (var i = 0; i < 7; i++) {
      final d = from.add(Duration(days: i));
      if (days.contains(dayNames[d.weekday - 1])) return _day(d);
    }
    return _day(from);
  }

  static String _orderedDays(Set<String> days) =>
      dayNames.where(days.contains).join(',');

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int minutesBetween(TimeOfDay start, TimeOfDay end) {
    final diff = (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute);
    return diff > 0 ? diff : diff + 24 * 60;
  }

  static String formatTime(TimeOfDay t) {
    final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final period = t.period.name == 'am' ? 'AM' : 'PM';
    return '$hour12:${t.minute.toString().padLeft(2, '0')} $period';
  }

  static String formatDuration(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    if (h > 0 && m > 0) return '$h hr $m mins';
    if (h > 0) return '$h hr';
    return '$m mins';
  }

  /// Parses a class's stored duration ("1 hr", "45 mins", "1 hr 30 mins").
  static int? parseDuration(String text) {
    final lower = text.toLowerCase();
    final h = RegExp(r'(\d+)\s*hr').firstMatch(lower);
    final m = RegExp(r'(\d+)\s*min').firstMatch(lower);
    if (h == null && m == null) return null;
    final total = (h != null ? int.parse(h.group(1)!) : 0) * 60 +
        (m != null ? int.parse(m.group(1)!) : 0);
    return total == 0 ? null : total;
  }

  static TimeOfDay? parseTime(String text) => parseTimeString(text);

  static bool _isActive(Map<String, dynamic> data) =>
      data['status'] != 'cancelled_by_trainer';

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _activeBookingsOn(String classId, DateTime day) async {
    final end = day.add(const Duration(days: 1));
    final snap = await _bookingsCol.where('classId', isEqualTo: classId).get();
    return snap.docs.where((d) {
      final bd = d.data()['bookingDate'];
      if (bd is! Timestamp || !_isActive(d.data())) return false;
      final t = bd.toDate();
      return !t.isBefore(day) && t.isBefore(end);
    }).toList();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _activeBookingsFrom(String classId, DateTime from) async {
    final snap = await _bookingsCol.where('classId', isEqualTo: classId).get();
    return snap.docs.where((d) {
      final bd = d.data()['bookingDate'];
      return bd is Timestamp && _isActive(d.data()) && !bd.toDate().isBefore(from);
    }).toList();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _waitingOn(
      String classId, DateTime day) async {
    final snap = await _waitlistCol
        .where('classId', isEqualTo: classId)
        .where('status', isEqualTo: 'waiting')
        .get();
    return snap.docs.where((d) {
      final bd = d.data()['bookingDate'];
      return bd is Timestamp && _day(bd.toDate()) == day;
    }).toList();
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _waitingFrom(
      String classId, DateTime from) async {
    final snap = await _waitlistCol
        .where('classId', isEqualTo: classId)
        .where('status', isEqualTo: 'waiting')
        .get();
    return snap.docs.where((d) {
      final bd = d.data()['bookingDate'];
      return bd is Timestamp && !bd.toDate().isBefore(from);
    }).toList();
  }

  static Future<void> _applyMoves(List<_Move> moves) async {
    // Firestore batches cap at 500 writes.
    for (var i = 0; i < moves.length; i += 400) {
      final batch = _db.batch();
      for (final m in moves.skip(i).take(400)) {
        batch.update(m.doc.reference, {
          'classId': m.newClassId,
          'bookingDate': Timestamp.fromDate(m.newDate),
          'bookingDay': dayNames[m.newDate.weekday - 1],
          'bookingTime': m.newTime,
          'rescheduledFrom': {
            'classId': m.doc.data()['classId'],
            'date': _dateKey(m.oldDate),
            'time': m.oldTime,
          },
        });
      }
      await batch.commit();
    }
  }

  static Future<void> _moveWaitlist(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> entries, {
    required String newClassId,
    required DateTime newDate,
    required String newTime,
  }) async {
    if (entries.isEmpty) return;
    final batch = _db.batch();
    for (final e in entries) {
      batch.update(e.reference, {
        'classId': newClassId,
        'bookingDate': Timestamp.fromDate(newDate),
        'bookingDay': dayNames[newDate.weekday - 1],
        'bookingTime': newTime,
      });
    }
    await batch.commit();
  }

  /// Activity Log rows + reschedule email for each moved booking. Runs
  /// after the moves are committed; best-effort, like the cancellation
  /// emails — a failed email never undoes a move.
  static Future<void> _notify(
    List<_Move> moves, {
    required String oldClassId,
    required String className,
    required String location,
    required int durationMinutes,
  }) async {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    for (final m in moves) {
      final data = m.doc.data();
      final uid = data['userId']?.toString() ?? '';
      if (uid.isEmpty) continue;
      try {
        final user = (await _usersCol.doc(uid).get()).data() ?? {};
        final userName = user['name']?.toString() ?? uid;
        final email = user['email']?.toString() ?? '';
        final attendeeName = data['attendeeName'] as String?;
        final guestName = data['guestName'] as String?;
        final logName = BookingService.attendeeLogName(attendeeName, userName,
            guestName: guestName);
        final forName = guestName ?? attendeeName;
        final credits = (data['creditsUsed'] as int?) ?? 1;
        final role = data['bookedByRole']?.toString() ?? 'client';
        final moveNote =
            '${fmt(m.oldDate)} ${m.oldTime} → ${fmt(m.newDate)} ${m.newTime}';

        await ConfigService.logActivityEvent(
          eventType: 'Session Rescheduled by Admin',
          classId: oldClassId,
          className: className,
          sessionDate: m.oldDate,
          sessionTime: m.oldTime,
          userId: uid,
          userName: logName,
          bookedByRole: role,
          creditsUsed: 0,
          bookingId: m.doc.id,
          note: 'Moved $moveNote',
        );
        await ConfigService.logActivityEvent(
          eventType: 'Booked',
          classId: m.newClassId,
          className: className,
          sessionDate: m.newDate,
          sessionTime: m.newTime,
          userId: uid,
          userName: logName,
          bookedByRole: role,
          creditsUsed: credits,
          bookingId: m.doc.id,
          note: 'Rescheduled by admin from ${fmt(m.oldDate)} ${m.oldTime}',
        );

        if (email.isNotEmpty) {
          await EmailService.sendRescheduleEmail(
            email: email,
            clientName: userName,
            className:
                forName == null ? className : '$className (for $forName)',
            oldDate: m.oldDate,
            oldTime: m.oldTime,
            newDate: m.newDate,
            newTime: m.newTime,
            location: location,
            durationMinutes: durationMinutes,
          );
        }
      } catch (_) {
        // Best-effort per client — the move itself already succeeded.
      }
    }
  }
}

class _Move {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String newClassId;
  final DateTime newDate;
  final String newTime;

  _Move(this.doc,
      {required this.newClassId, required this.newDate, required this.newTime});

  DateTime get oldDate {
    final t = (doc.data()['bookingDate'] as Timestamp).toDate();
    return DateTime(t.year, t.month, t.day);
  }

  String get oldTime => doc.data()['bookingTime']?.toString() ?? '';
}
