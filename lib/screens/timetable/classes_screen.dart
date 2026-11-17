import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/class_model.dart';
import '../../models/dependent_model.dart';
import '../../services/booking_service.dart';
import '../../services/class_service.dart';
import '../../services/dependent_service.dart';
import '../../services/user_service.dart';
import '../../services/waiting_list_service.dart';
import '../../services/email_service.dart';
import '../../services/notifications.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../utils/require_login.dart';
import '../../utils/time_utils.dart';
import '../../widgets/attendee_picker.dart';
import '../../widgets/coach_profile.dart';
import '../../widgets/guest_picker.dart';
import '../../models/user_model.dart';

class ClassesScreen extends StatefulWidget {
  /// A child's own junior account ([UserModel.isJunior]): books only
  /// themselves, under their parent's account, paying only with their own
  /// junior credits — no attendee picker, no guests.
  final UserModel? junior;
  const ClassesScreen({super.key, this.junior});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  DateTime _selectedDate = DateTime.now();

  // The signed-in parent's active child profiles — drives the attendee
  // picker and per-person "already booked" state. Re-subscribed on auth
  // changes since the web shop starts anonymous and signs in mid-session.
  List<DependentModel> _children = [];
  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<DependentModel>>? _childrenSub;

  StreamSubscription<DependentModel?>? _selfSub;

  UserModel? get _junior =>
      widget.junior?.isJunior == true ? widget.junior : null;

  /// Whose account bookings go under: the signed-in member, or — for a
  /// junior account — their parent's.
  String get _ownerUid =>
      _junior?.parentUid ?? FirebaseAuth.instance.currentUser!.uid;

  /// A junior account's own child profile (live).
  DependentModel? get _self => _junior == null || _children.isEmpty
      ? null
      : _children.first;

  @override
  void initState() {
    super.initState();
    final junior = _junior;
    if (junior != null) {
      _selfSub = DependentService.streamOne(junior.parentUid!, junior.dependentId!)
          .listen((c) {
        if (mounted) setState(() => _children = c == null ? [] : [c]);
      }, onError: (_) {});
      return;
    }
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _childrenSub?.cancel();
      _childrenSub = null;
      if (user == null || user.isAnonymous) {
        if (mounted) setState(() => _children = []);
        return;
      }
      _childrenSub = DependentService.streamActive(user.uid).listen(
        (list) {
          if (mounted) setState(() => _children = list);
        },
        onError: (_) {},
      );
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _childrenSub?.cancel();
    _selfSub?.cancel();
    super.dispose();
  }

  /// Keys identifying everyone this account can book for on the selected
  /// date: '' for the account holder, plus each age-eligible child's id —
  /// matched against bookings' `attendeeId` (absent = account holder).
  Set<String> get _familyKeys => _junior != null
      ? {if (_self != null) _self!.id!}
      : {
          '',
          ..._children
              .where((c) => c.isEligibleJuniorOn(_selectedDate))
              .map((c) => c.id!),
        };

  /// Why a junior account can't book [cls]: no package at all, used up, or
  /// a package that this class doesn't accept — each needs a different ask
  /// of the parent.
  String _juniorNoPackageText(DependentModel? child, ClassModel cls) {
    final plans = [
      ...?child?.activeMemberships,
      ...?child?.queuedMemberships,
    ];
    if (plans.isEmpty) {
      return "You don't have a junior package yet — ask your parent or guardian to buy one for you";
    }
    if (plans.every((m) => m.creditsRemaining <= 0)) {
      return 'Your junior package has no credits left — ask your parent or guardian to buy a new one';
    }
    return "Your junior package doesn't cover ${cls.mode} — ask your parent or guardian";
  }

  /// Who gets the booking confirmation email: the booker, plus — when a
  /// child attends — the parent and the child's own login, so both always
  /// know what's booked.
  Future<List<String>> _bookingEmails(DependentModel? child) async {
    final emails = <String>{};
    final me = FirebaseAuth.instance.currentUser?.email ?? '';
    if (me.isNotEmpty) emails.add(me.toLowerCase());
    if (child != null) {
      if (child.hasLogin && child.loginEmail.isNotEmpty) {
        emails.add(child.loginEmail.toLowerCase());
      }
      if (_junior != null) {
        try {
          final parent = await FirebaseFirestore.instance
              .collection('users')
              .doc(_ownerUid)
              .get();
          final pe = parent.data()?['email']?.toString() ?? '';
          if (pe.isNotEmpty) emails.add(pe.toLowerCase());
        } catch (_) {}
      }
    }
    return emails.toList();
  }

  Future<AttendeeChoice?> _pickAttendee(
    BuildContext context, {
    required String action,
    Set<String> takenKeys = const {},
  }) =>
      pickAttendee(context,
          children: _children,
          date: _selectedDate,
          action: action,
          takenKeys: takenKeys);

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  String get _selectedDayName => _dayNames[_selectedDate.weekday - 1];

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  // Returns true if the class should appear on the given date based on occurrence.
  bool _matchesDate(ClassModel cls, DateTime date) {
    final dayName = _dayNames[date.weekday - 1];
    // day field may be comma-separated for weekly: "Monday,Wednesday,Friday"
    final classDays = cls.day.split(',').map((d) => d.trim()).toSet();
    switch (cls.occurrence) {
      case 'daily':
        return true;
      case 'once':
        if (cls.specificDate == null) return false;
        final parts = cls.specificDate!.split('-');
        if (parts.length < 3) return false;
        final d = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        return d.year == date.year &&
            d.month == date.month &&
            d.day == date.day;
      case 'monthly':
        // Matches if same day-of-week AND same week-of-month as specificDate.
        if (cls.specificDate == null) {
          return classDays.contains(dayName) && date.day <= 7;
        }
        final parts = cls.specificDate!.split('-');
        if (parts.length < 3) return false;
        final ref = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final refWeek = ((ref.day - 1) ~/ 7) + 1;
        final selWeek = ((date.day - 1) ~/ 7) + 1;
        return classDays.contains(dayName) && selWeek == refWeek;
      case 'weekly':
      default:
        return classDays.contains(dayName);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            surface: AppColors.bg,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _book(
      BuildContext context, ClassModel cls, Set<String> takenKeys) async {
    // Public web-embed visitors can browse the timetable signed out —
    // booking is the action that actually needs a real identity. No-ops
    // (returns true immediately) for anyone already properly signed in,
    // mobile included. Guarded here rather than per-button since this is
    // the single funnel every "Book"/"Book Now" path calls into.
    if (!await requireRealSignIn(context)) return;
    if (!context.mounted) return;
    final uid = _ownerUid;
    final isJunior = _junior != null;

    final DependentModel? child;
    if (isJunior) {
      child = _self;
      if (child == null) return;
    } else {
      final choice = await _pickAttendee(context,
          action: 'booking', takenKeys: takenKeys);
      if (choice == null || !context.mounted) return;
      child = choice.child;
    }
    final forLabel = child == null || isJunior ? '' : ' for ${child.name}';

    // Friends come along on the member's own credits — offered only when
    // the member attends and has a credit and a spot to spare.
    var guests = const <String>[];
    if (child == null) {
      final max = await BookingService.maxGuests(
          cls: cls, date: _selectedDate, uid: uid, memberAlreadyBooked: false);
      if (max > 0) {
        if (!context.mounted) return;
        final picked = await pickGuests(context,
            className: cls.mode, maxGuests: max, memberAlreadyBooked: false);
        if (picked == null) return;
        guests = picked;
      }
    }

    final result = await BookingService.bookClass(
      cls: cls,
      date: _selectedDate,
      targetUid: uid,
      bookedByUid: FirebaseAuth.instance.currentUser!.uid,
      bookedByRole: isJunior ? 'junior' : 'client',
      targetUserName: isJunior
          ? (_junior!.name.isNotEmpty ? _junior!.name : uid)
          : FirebaseAuth.instance.currentUser?.displayName ?? uid,
      attendee: child,
      // A child booking themselves may only spend their own junior credits.
      parentCreditsAllowed: !isJunior,
    );

    if (!result.success) {
      if (!context.mounted) return;
      switch (result.reason!) {
        case BookingFailureReason.alreadyBooked:
          AppToast.warning(
              context, "Already registered$forLabel for ${cls.mode}");
          break;
        case BookingFailureReason.attendeeIneligible:
          AppToast.error(context,
              "${child?.name ?? 'This person'} must be ${DependentModel.minAge}–${DependentModel.maxAgeExclusive - 1} on the session date");
          break;
        case BookingFailureReason.planNotAllowed:
          AppToast.error(
              context,
              isJunior
                  ? _juniorNoPackageText(child, cls)
                  : "Your current plan doesn't cover ${cls.mode} — purchase an eligible plan to book it");
          break;
        case BookingFailureReason.noCredits:
          AppToast.error(
              context,
              isJunior
                  ? _juniorNoPackageText(child, cls)
                  : "No credits — purchase a membership plan first");
          break;
        case BookingFailureReason.classFull:
          AppToast.error(context, "Class is full");
          break;
        case BookingFailureReason.unknown:
          AppToast.error(
              context, 'Booking failed: ${result.errorDetail ?? ''}');
          break;
      }
      return;
    }

    var guestLabel = '';
    if (guests.isNotEmpty) {
      final guestResult = await _bookGuests(cls, uid, guests);
      if (guestResult.success) {
        guestLabel = ' + ${guests.join(', ')}';
      } else if (context.mounted) {
        AppToast.warning(context,
            "You're booked, but your friends couldn't be added: ${_guestFailureText(guestResult)}");
      }
    }

    final emailFor = child == null ? '' : ' for ${child.name}';
    for (final email in await _bookingEmails(child)) {
      try {
        await EmailService.sendBookingEmail(
          email: email,
          className: '${cls.mode}$emailFor$guestLabel',
          classTime: cls.startTime,
          classDate: _selectedDate,
          location: cls.location,
        );
      } catch (e) {
        debugPrint('Booking email failed: $e');
        if (context.mounted) {
          AppToast.warning(
              context, 'Booked, but confirmation email failed: $e');
        }
      }
    }

    await NotificationService.showBookingConfirmed(cls.mode);
    await NotificationService.scheduleClassNotifications(
        cls.mode, _selectedDate, cls.startTime);

    if (context.mounted) {
      AppToast.success(context,
          '${cls.mode} booked$forLabel$guestLabel for ${_formatDate(_selectedDate)}');
    }
  }

  Future<BookingResult> _bookGuests(
          ClassModel cls, String uid, List<String> guests) =>
      BookingService.bookGuests(
        cls: cls,
        date: _selectedDate,
        targetUid: uid,
        bookedByUid: uid,
        bookedByRole: 'client',
        guestNames: guests,
        targetUserName: FirebaseAuth.instance.currentUser?.displayName ?? uid,
      );

  String _guestFailureText(BookingResult result) => switch (result.reason) {
        BookingFailureReason.noCredits => 'not enough credits',
        BookingFailureReason.classFull => 'not enough spots left',
        BookingFailureReason.planNotAllowed =>
          "your plan doesn't cover this class",
        _ => result.errorDetail ?? 'please try again',
      };

  /// Adds friends to a session the member is already booked into.
  Future<void> _addGuests(BuildContext context, ClassModel cls) async {
    if (!await requireRealSignIn(context)) return;
    if (!context.mounted) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final max = await BookingService.maxGuests(
        cls: cls, date: _selectedDate, uid: uid, memberAlreadyBooked: true);
    if (!context.mounted) return;
    if (max == 0) {
      AppToast.warning(context,
          'You need a free credit and a spot left to bring a friend');
      return;
    }
    final guests = await pickGuests(context,
        className: cls.mode, maxGuests: max, memberAlreadyBooked: true);
    if (guests == null || guests.isEmpty) return;

    final result = await _bookGuests(cls, uid, guests);
    if (!context.mounted) return;
    if (!result.success) {
      AppToast.error(context,
          "Couldn't add your friends: ${_guestFailureText(result)}");
      return;
    }

    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (email.isNotEmpty) {
      try {
        await EmailService.sendBookingEmail(
          email: email,
          className: '${cls.mode} (guests: ${guests.join(', ')})',
          classTime: cls.startTime,
          classDate: _selectedDate,
          location: cls.location,
        );
      } catch (e) {
        debugPrint('Guest booking email failed: $e');
      }
    }
    if (context.mounted) {
      AppToast.success(context,
          '${guests.join(', ')} added to ${cls.mode} · ${guests.length} credit${guests.length == 1 ? '' : 's'} used');
    }
  }

  Future<void> _joinWaitingList(BuildContext context, ClassModel cls) async {
    if (!await requireRealSignIn(context)) return;
    if (!context.mounted) return;
    final uid = _ownerUid;
    final classId = cls.effectiveId;
    final isJunior = _junior != null;

    final DependentModel? child;
    if (isJunior) {
      child = _self;
      if (child == null) return;
    } else {
      final choice =
          await _pickAttendee(context, action: 'waiting list spot');
      if (choice == null || !context.mounted) return;
      child = choice.child;
    }
    final forLabel = child == null || isJunior ? '' : ' for ${child.name}';

    // Check if already on waiting list
    final alreadyWaiting = await WaitingListService.isOnWaitingList(
        classId, uid, _selectedDate,
        attendeeId: child?.id);
    if (alreadyWaiting) {
      if (context.mounted) {
        AppToast.warning(
            context, "Already on the waiting list$forLabel for ${cls.mode}");
      }
      return;
    }

    final rules = await BookingService.creditRulesFor(child);
    if (!await BookingService.canBookClass(cls, uid,
        excludedPlanNames: rules.excluded,
        child: child,
        parentFallback: !isJunior)) {
      if (context.mounted) {
        AppToast.error(
            context,
            isJunior
                ? _juniorNoPackageText(child, cls)
                : "Your current plan doesn't cover ${cls.mode} — purchase an eligible plan to join the waiting list");
      }
      return;
    }

    // 6-hour cutoff check
    final sessionStart = _parseSessionStart(cls.startTime, _selectedDate);
    if (sessionStart != null &&
        DateTime.now()
            .isAfter(sessionStart.subtract(const Duration(hours: 6)))) {
      if (context.mounted) {
        AppToast.error(context,
            "Waiting list closed — less than 6 hours before session");
      }
      return;
    }

    // Check credits
    final hasCredits = await UserService.hasEnoughCredits(uid,
        allowedPlanNames: cls.allowedPlanNames,
        excludedPlanNames: rules.excluded,
        childId: child?.id,
        parentFallback: !isJunior);
    if (!hasCredits) {
      if (context.mounted) {
        AppToast.error(context,
            "No credits — 1 credit is held when joining the waiting list");
      }
      return;
    }

    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Join Waiting List?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          '1 credit will be held. If you get a spot, you\'re in. If not, your credit is refunded automatically.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Join Waiting List'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final userName =
        userDoc.data()?['name']?.toString() ?? 'Unknown';

    await WaitingListService.joinWaitingList(
      classId: classId,
      userId: uid,
      userName: userName,
      bookingDate: _selectedDate,
      bookingTime: cls.startTime,
      className: cls.mode,
      allowedPlanNames: cls.allowedPlanNames,
      attendee: child,
      parentCreditsAllowed: !isJunior,
    );

    if (context.mounted) {
      AppToast.success(context,
          "Added to waiting list$forLabel for ${cls.mode}. 1 credit held.");
    }
  }

  DateTime? _parseSessionStart(String timeStr, DateTime date) {
    try {
      final cleaned = timeStr.toUpperCase().replaceAll(' ', '');
      final isPM = cleaned.contains('PM');
      final isAM = cleaned.contains('AM');
      final digits = cleaned.replaceAll('AM', '').replaceAll('PM', '');
      final parts = digits.split(':');
      int hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      if (isPM && hour != 12) hour += 12;
      if (isAM && hour == 12) hour = 0;
      return DateTime(date.year, date.month, date.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Classes")),
      body: Column(
        children: [
          _DateBar(label: _formatDate(_selectedDate), onTap: _pickDate),
          _DateCarousel(
            selectedDate: _selectedDate,
            onSelect: (d) => setState(() => _selectedDate = d),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<ClassModel>>(
              stream: ClassService.streamClasses(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary));
                }
                final all = snapshot.data ?? [];
                final classes = all
                    .where((c) =>
                        c.isActive &&
                        _matchesDate(c, _selectedDate) &&
                        !c.isCancelledOn(_selectedDate))
                    .toList()
                  // By start time, so a class run several times a day
                  // lists each session in order.
                  ..sort((a, b) {
                    int minutes(ClassModel c) {
                      final t = parseTimeString(c.startTime);
                      return t == null ? 24 * 60 : t.hour * 60 + t.minute;
                    }

                    final byTime = minutes(a).compareTo(minutes(b));
                    return byTime != 0 ? byTime : a.mode.compareTo(b.mode);
                  });

                if (classes.isEmpty) {
                  return _emptyState(all.isEmpty
                      ? 'No classes available'
                      : 'No classes on $_selectedDayName');
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: classes.length,
                  itemBuilder: (context, index) {
                    final cls = classes[index];
                    return _ClassCard(
                      item: cls,
                      selectedDate: _selectedDate,
                      familyKeys: _familyKeys,
                      ownerUid: _junior?.parentUid,
                      onBook: (ctx, taken) => _book(ctx, cls, taken),
                      onJoinWaitingList: (ctx) =>
                          _joinWaitingList(ctx, cls),
                      onAddGuests: _junior != null
                          ? null
                          : (ctx) => _addGuests(ctx, cls),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.event_busy, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(msg,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 15)),
        ],
      ),
    );
  }
}

// ── Date bar ─────────────────────────────────────────────────────────────────

class _DateBar extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateBar({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 12),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.keyboard_arrow_down,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Date carousel ────────────────────────────────────────────────────────────

class _DateCarousel extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelect;
  const _DateCarousel({required this.selectedDate, required this.onSelect});

  @override
  State<_DateCarousel> createState() => _DateCarouselState();
}

class _DateCarouselState extends State<_DateCarousel> {
  static const _dayCount = 60;
  static const _tileWidth = 60.0;
  static const _abbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final _controller = ScrollController();
  late final DateTime _baseDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _baseDate = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(covariant _DateCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameDay(oldWidget.selectedDate, widget.selectedDate)) {
      _scrollToSelected();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _scrollToSelected() {
    if (!_controller.hasClients) return;
    final index = widget.selectedDate.difference(_baseDate).inDays;
    if (index < 0 || index >= _dayCount) return;
    final target = (index * _tileWidth) - 100;
    _controller.animateTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _dayCount,
        itemBuilder: (context, i) {
          final date = _baseDate.add(Duration(days: i));
          final selected = _isSameDay(date, widget.selectedDate);
          return GestureDetector(
            onTap: () => widget.onSelect(date),
            child: Container(
              width: _tileWidth - 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : AppColors.divider,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _abbr[date.weekday - 1],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Class card ────────────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  final ClassModel item;
  final DateTime selectedDate;
  final Set<String> familyKeys;
  /// Whose bookings count as "mine" — null = the signed-in member.
  final String? ownerUid;
  final Future<void> Function(BuildContext, Set<String> takenKeys) onBook;
  final Future<void> Function(BuildContext) onJoinWaitingList;
  /// Null hides "Bring a friend" (junior accounts can't bring guests).
  final Future<void> Function(BuildContext)? onAddGuests;

  const _ClassCard({
    required this.item,
    required this.selectedDate,
    required this.familyKeys,
    this.ownerUid,
    required this.onBook,
    required this.onJoinWaitingList,
    required this.onAddGuests,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 190,
            width: double.infinity,
            child: item.image.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: item.image,
                    fit: BoxFit.cover,
                    memCacheHeight: 380,
                    placeholder: (_, __) => _imgPlaceholder(),
                    errorWidget: (_, __, ___) => _imgPlaceholder(),
                  )
                : _imgPlaceholder(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.mode,
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: Text(item.type,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(item.description,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 12),
                _coachRow(context),
                const SizedBox(height: 5),
                _row(Icons.location_on_outlined,
                    '${item.location} · ${item.detailLocation}'),
                const SizedBox(height: 5),
                _row(Icons.schedule,
                    '${item.startTime} · ${item.duration}'),
                const SizedBox(height: 14),
                _CapacitySection(
                  classId: item.effectiveId,
                  groupSize: item.effectiveCapacity(selectedDate).toString(),
                  selectedDate: selectedDate,
                  familyKeys: familyKeys,
                  ownerUid: ownerUid,
                  onBook: onBook,
                  onJoinWaitingList: onJoinWaitingList,
                  onAddGuests: onAddGuests,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imgPlaceholder() {
    return Container(
      color: AppColors.surface,
      child: Center(
        child: Icon(Icons.fitness_center,
            size: 42,
            color: AppColors.primary.withValues(alpha: 0.4)),
      ),
    );
  }

  /// Coach with their photo — tap for their profile.
  Widget _coachRow(BuildContext context) {
    if (item.coach.trim().isEmpty) return _row(Icons.person_outline, 'Coach TBA');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showCoachProfile(context, item.coach),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            FutureBuilder<UserModel?>(
              future: CoachDirectory.find(item.coach),
              builder: (_, snap) =>
                  CoachAvatar(photoUrl: snap.data?.coachPhotoUrl, radius: 11),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(item.coach,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.chevron_right,
                size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

// ── Capacity section — streams booking count live ────────────────────────────

class _CapacitySection extends StatefulWidget {
  final String classId;
  final String groupSize;
  final DateTime selectedDate;
  final Set<String> familyKeys;
  final String? ownerUid;
  final Future<void> Function(BuildContext, Set<String> takenKeys) onBook;
  final Future<void> Function(BuildContext) onJoinWaitingList;
  final Future<void> Function(BuildContext)? onAddGuests;

  const _CapacitySection({
    required this.classId,
    required this.groupSize,
    required this.selectedDate,
    required this.familyKeys,
    this.ownerUid,
    required this.onBook,
    required this.onJoinWaitingList,
    required this.onAddGuests,
  });

  @override
  State<_CapacitySection> createState() => _CapacitySectionState();
}

class _CapacitySectionState extends State<_CapacitySection> {
  bool _booking = false;

  Future<void> _handleBook(Set<String> takenKeys) async {
    if (_booking) return;
    setState(() => _booking = true);
    try {
      await widget.onBook(context, takenKeys);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final startOfDay = DateTime(
        widget.selectedDate.year, widget.selectedDate.month, widget.selectedDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Query by classId only — Dart-side date filter avoids composite index requirement
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('classId', isEqualTo: widget.classId)
          .snapshots(),
      builder: (context, snap) {
        final allDocs = snap.data?.docs ?? [];
        final currentUid =
            widget.ownerUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
        final todayDocs = allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          if (data['status'] == 'cancelled_by_trainer') return false;
          final bd = data['bookingDate'];
          if (bd == null) return false;
          final dt = (bd as Timestamp).toDate();
          return !dt.isBefore(startOfDay) && dt.isBefore(endOfDay);
        }).toList();
        final booked = todayDocs.length;
        // Who in this family is booked ('' = account holder, else child id)
        // — only "Already Booked" once everyone is.
        final mine = todayDocs
            .map((d) => d.data() as Map<String, dynamic>)
            .where((data) => data['userId'] == currentUid)
            .toList();
        // Guests brought on this member's credits don't book the member.
        final takenKeys = mine
            .where((data) => data['guestName'] == null)
            .map((data) => (data['attendeeId'] as String?) ?? '')
            .toSet();
        final myGuests = mine
            .map((data) => data['guestName'] as String?)
            .whereType<String>()
            .toList();
        final alreadyBooked = widget.familyKeys.every(takenKeys.contains);
        final hasFamily = widget.familyKeys.length > 1;
        final capacity = int.tryParse(widget.groupSize) ?? 0;
        final isFull = capacity > 0 && booked >= capacity;
        final pct = capacity > 0 ? (booked / capacity).clamp(0.0, 1.0) : 0.0;

        return FutureBuilder<List<Object>>(
          future: Future.wait([
            WaitingListService.getWaitingCount(
                widget.classId, widget.selectedDate),
            WaitingListService.isOnWaitingList(
                widget.classId, currentUid, widget.selectedDate),
          ]),
          builder: (context, waitSnap) {
            final waiting = waitSnap.data?[0] as int? ?? 0;
            // Per-child waiting-list status is checked when joining — with
            // a family, keep the button available for the others.
            final onWaitingList =
                !hasFamily && (waitSnap.data?[1] as bool? ?? false);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isFull
                          ? 'Class full'
                          : '$booked / $capacity spots taken',
                      style: TextStyle(
                        fontSize: 12,
                        color: isFull
                            ? AppColors.error
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (!isFull && snap.hasData)
                      Text(
                        '${capacity - booked} left',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    if (isFull && waiting > 0)
                      Text(
                        '$waiting waiting',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFFFAB40),
                            fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: AppColors.divider,
                    color: isFull ? AppColors.error : AppColors.primary,
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 14),
                if (alreadyBooked)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Already Booked'),
                      style: ElevatedButton.styleFrom(
                        disabledBackgroundColor:
                            const Color(0xFF00D4AA).withValues(alpha: 0.15),
                        disabledForegroundColor: const Color(0xFF00D4AA),
                      ),
                    ),
                  )
                else if (!isFull)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          _booking ? null : () => _handleBook(takenKeys),
                      child: _booking
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Book Now'),
                    ),
                  )
                else if (onWaitingList)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.hourglass_top, size: 18),
                      label: Text(waiting > 0
                          ? 'Already in Waiting List · $waiting waiting'
                          : 'Already in Waiting List'),
                      style: ElevatedButton.styleFrom(
                        disabledBackgroundColor:
                            const Color(0xFFFFAB40).withValues(alpha: 0.15),
                        disabledForegroundColor: const Color(0xFFFFAB40),
                      ),
                    ),
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => widget.onJoinWaitingList(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFFFFAB40).withValues(alpha: 0.15),
                        foregroundColor: const Color(0xFFFFAB40),
                        side: const BorderSide(
                            color: Color(0xFFFFAB40), width: 1),
                        elevation: 0,
                      ),
                      child: Text(waiting > 0
                          ? 'Join Waiting List · $waiting waiting'
                          : 'Join Waiting List'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      'Waiting list closes 6 hours before session',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                  ),
                ],
                if (myGuests.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Your guests: ${myGuests.join(', ')}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
                if (widget.onAddGuests != null &&
                    takenKeys.contains('') &&
                    !isFull)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => widget.onAddGuests!(context),
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const Text('Bring a friend'),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
