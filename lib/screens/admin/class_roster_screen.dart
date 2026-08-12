import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/class_model.dart';
import '../../models/user_model.dart';
import '../../services/booking_service.dart';
import '../../services/class_service.dart';
import '../../services/config_service.dart';
import '../../services/email_service.dart';
import '../../services/user_service.dart';
import '../../services/waiting_list_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../widgets/timeline_range_selector.dart' show formatWithWeekday;

/// Google Calendar/Outlook-style month (default) or week view of scheduled
/// classes. Day markers come from the recurring ClassModel templates
/// (loaded once, matched against a date via [ClassModel.occursOn]) — a
/// cheap, purely local computation, not a per-day network call. Tapping a
/// day lists every class scheduled that day; roster membership is
/// reconciled from the ActivityLog Google Sheet mirror (not Firestore) —
/// see ConfigService.logActivityEvent/getActivityLog — a best-effort
/// convenience view, not an audit-proof record. Firestore remains the
/// actual source of truth for booking state and for the "Book for Client"
/// write path (see BookingService).
class ClassRosterScreen extends StatefulWidget {
  const ClassRosterScreen({super.key});

  @override
  State<ClassRosterScreen> createState() => _ClassRosterScreenState();
}

class _ClassRosterScreenState extends State<ClassRosterScreen> {
  DateTime _selectedDay = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  List<ClassModel> _allClasses = [];
  bool _classesLoading = true;

  bool _loading = false;
  bool _loaded = false;
  List<_ClassGroup> _groups = [];

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _load();
  }

  Future<void> _loadClasses() async {
    final classes = await ClassService.getClasses();
    if (!mounted) return;
    setState(() {
      _allClasses = classes;
      _classesLoading = false;
    });
  }

  /// Active, non-cancelled occurrences on [day] — drives both the calendar
  /// day marker and the "how many classes are scheduled today" seed list.
  List<ClassModel> _classesForDay(DateTime day) =>
      _allClasses.where((c) => c.isActive && c.occursOn(day)).toList();

  ClassModel? _findClass(String classId) {
    for (final c in _allClasses) {
      if (c.effectiveId == classId) return c;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loaded = false;
    });
    final scheduled = _classesForDay(_selectedDay);
    final rows = await ConfigService.getActivityLog(date: _selectedDay);
    final groups = _buildRoster(scheduled, rows);

    // Waiting-list count is live state, not history — read straight from
    // Firestore (same source the client/trainer screens use) rather than
    // trying to reconstruct it from the Sheet log, which has no stable way
    // to correlate a "joined" event with its eventual resolution.
    final waitingCounts = await Future.wait(
      groups.map((g) => WaitingListService.getWaitingCount(g.classId, _selectedDay)),
    );
    for (var i = 0; i < groups.length; i++) {
      groups[i].waiting = waitingCounts[i];
    }

    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
      _loaded = true;
    });
  }

  /// Seeds one group per class actually scheduled [scheduled] that day —
  /// so a class with zero bookings still shows up and can be booked into —
  /// then layers on roster membership from the Sheet mirror [rows].
  List<_ClassGroup> _buildRoster(
      List<ClassModel> scheduled, List<Map<String, String>> rows) {
    final cancelledIds = <String>{};
    for (final r in rows) {
      final type = r['eventType'] ?? '';
      final bid = r['bookingId'] ?? '';
      if (bid.isNotEmpty &&
          (type == 'Cancelled by Client' || type == 'Cancelled by Trainer')) {
        cancelledIds.add(bid);
      }
    }

    final groups = <String, _ClassGroup>{};
    for (final cls in scheduled) {
      final key = '${cls.effectiveId}|${cls.startTime}';
      groups[key] = _ClassGroup(
        classId: cls.effectiveId,
        className: cls.mode,
        sessionTime: cls.startTime,
      );
    }

    for (final r in rows) {
      final type = r['eventType'] ?? '';
      if (type != 'Booked' && type != 'Admitted from Waitlist') continue;
      final bid = r['bookingId'] ?? '';
      if (bid.isNotEmpty && cancelledIds.contains(bid)) continue;

      final classId = r['classId'] ?? '';
      final sessionTime = r['sessionTime'] ?? '';
      final key = '$classId|$sessionTime';
      final group = groups.putIfAbsent(
        key,
        () => _ClassGroup(
          classId: classId,
          className: r['className'] ?? '',
          sessionTime: sessionTime,
        ),
      );
      group.members.add(_RosterEntry(
        userName: r['userName']?.isNotEmpty == true ? r['userName']! : 'Unknown',
        eventType: type,
        bookedByRole: r['bookedByRole'] ?? 'client',
      ));
    }

    final list = groups.values.toList()
      ..sort((a, b) => a.sessionTime.compareTo(b.sessionTime));
    return list;
  }

  void _onDaySelected(DateTime selected, DateTime focused) {
    final day = DateTime(selected.year, selected.month, selected.day);
    if (isSameDay(day, _selectedDay)) return;
    setState(() {
      _selectedDay = day;
      _focusedDay = focused;
      _loaded = false;
      _groups = [];
    });
    _load();
  }

  Future<void> _openBookForClient(_ClassGroup group) async {
    final cls = _findClass(group.classId);
    if (cls == null) {
      AppToast.error(context, 'Could not find this class — try refreshing');
      return;
    }
    final booked = await showModalBottomSheet<UserModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BookForClientSheet(cls: cls, date: _selectedDay),
    );
    if (booked == null || !mounted) return;
    // The Sheet mirror isn't reactive and can lag or silently fail — patch
    // the already-rendered group locally rather than re-fetching.
    setState(() {
      group.members.add(_RosterEntry(
        userName: booked.name.isNotEmpty ? booked.name : booked.email,
        eventType: 'Booked',
        bookedByRole: 'admin',
      ));
    });
    AppToast.success(context, 'Booked ${booked.name} into ${group.className}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Roster'),
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.card,
            child: TableCalendar<ClassModel>(
              firstDay: DateTime(DateTime.now().year - 1, 1, 1),
              lastDay: DateTime(DateTime.now().year + 1, 12, 31),
              focusedDay: _focusedDay,
              currentDay: DateTime.now(),
              selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
              calendarFormat: _calendarFormat,
              availableCalendarFormats: const {
                CalendarFormat.month: 'Month',
                CalendarFormat.week: 'Week',
              },
              eventLoader: _classesForDay,
              onDaySelected: _onDaySelected,
              onFormatChanged: (format) =>
                  setState(() => _calendarFormat = format),
              onPageChanged: (focused) =>
                  setState(() => _focusedDay = focused),
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonShowsNext: false,
                // No `intl` package used elsewhere in this app — build the
                // header text from a plain array instead of DateFormat.
                titleTextFormatter: (date, locale) =>
                    '${_months[date.month - 1]} ${date.year}',
                formatButtonDecoration: BoxDecoration(
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(12),
                ),
                formatButtonTextStyle:
                    const TextStyle(color: AppColors.primary, fontSize: 12),
              ),
              daysOfWeekStyle: const DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                weekendStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                selectedDecoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
                todayDecoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    shape: BoxShape.circle),
                markerDecoration: const BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
                markersMaxCount: 1,
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return null;
                  return Positioned(
                    bottom: 4,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${events.length}',
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    formatWithWeekday(_selectedDay),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                ),
                if (_loaded)
                  Text(
                    '${_groups.length} scheduled',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: const Text(
              'Roster read from the Google Sheet activity mirror, not Firestore — '
              'a best-effort convenience view, not an audit-proof record.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 8),
          if (!_loaded)
            const Expanded(
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (_groups.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No classes scheduled for this day',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: _groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _GroupCard(
                  group: _groups[i],
                  onBookForClient: _classesLoading
                      ? null
                      : () => _openBookForClient(_groups[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClassGroup {
  final String classId;
  final String className;
  final String sessionTime;
  final List<_RosterEntry> members = [];
  int waiting = 0;

  _ClassGroup({
    required this.classId,
    required this.className,
    required this.sessionTime,
  });
}

class _RosterEntry {
  final String userName;
  final String eventType;
  final String bookedByRole;

  _RosterEntry({
    required this.userName,
    required this.eventType,
    required this.bookedByRole,
  });
}

class _GroupCard extends StatelessWidget {
  final _ClassGroup group;
  final VoidCallback? onBookForClient;
  const _GroupCard({required this.group, this.onBookForClient});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(group.className,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          subtitle: Text(group.sessionTime,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${group.members.length} enrolled',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
              ),
              if (group.waiting > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFAB40).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${group.waiting} waiting',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFFFAB40),
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          children: [
            if (onBookForClient != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onBookForClient,
                    icon: const Icon(Icons.person_add_alt_1, size: 16),
                    label: const Text('Book for Client'),
                  ),
                ),
              ),
            if (group.members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('No one enrolled yet',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              )
            else
              ...group.members.map((m) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(m.userName,
                              style: const TextStyle(
                                  fontSize: 14, color: AppColors.textPrimary)),
                        ),
                        if (m.bookedByRole != 'client') ...[
                          const SizedBox(width: 6),
                          _chip('by ${m.bookedByRole}', AppColors.primary),
                        ],
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Book for client ──────────────────────────────────────────────────────────

/// Bottom sheet letting an admin pick a client and book them into [cls] on
/// [date], enforcing the exact same guards as client self-booking via
/// [BookingService.bookClass]. Pops with the booked [UserModel] on success
/// so the caller can optimistically patch its roster display.
class _BookForClientSheet extends StatefulWidget {
  final ClassModel cls;
  final DateTime date;
  const _BookForClientSheet({required this.cls, required this.date});

  @override
  State<_BookForClientSheet> createState() => _BookForClientSheetState();
}

class _BookForClientSheetState extends State<_BookForClientSheet> {
  List<UserModel> _clients = [];
  bool _loading = true;
  String _query = '';
  String? _bookingUid;

  @override
  void initState() {
    super.initState();
    UserService.getUsersByRole('client').then((clients) {
      if (!mounted) return;
      setState(() {
        _clients = clients..sort((a, b) => a.name.compareTo(b.name));
        _loading = false;
      });
    });
  }

  Future<void> _confirmAndBook(UserModel client) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Book this client?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Book ${client.name} into ${widget.cls.mode} at ${widget.cls.startTime}? '
          'This uses one of their credits, same as if they booked it themselves.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Book'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _bookingUid = client.uid);
    final result = await BookingService.bookClass(
      cls: widget.cls,
      date: widget.date,
      targetUid: client.uid,
      bookedByUid: FirebaseAuth.instance.currentUser!.uid,
      bookedByRole: 'admin',
      targetUserName: client.name.isNotEmpty ? client.name : client.email,
    );
    if (!mounted) return;
    setState(() => _bookingUid = null);

    if (!result.success) {
      final msg = switch (result.reason!) {
        BookingFailureReason.alreadyBooked =>
          '${client.name} is already booked into this class',
        BookingFailureReason.planNotAllowed =>
          "${client.name}'s plan doesn't cover this class",
        BookingFailureReason.noCredits =>
          '${client.name} has no credits available',
        BookingFailureReason.classFull => 'Class is full',
        BookingFailureReason.unknown =>
          'Booking failed: ${result.errorDetail ?? ''}',
      };
      if (mounted) AppToast.error(context, msg);
      return;
    }

    if (client.email.isNotEmpty) {
      try {
        await EmailService.sendBookingEmail(
          email: client.email,
          className: widget.cls.mode,
          classTime: widget.cls.startTime,
          classDate: widget.date,
          location: widget.cls.location,
        );
      } catch (_) {
        // Best-effort — booking itself already succeeded.
      }
    }

    if (mounted) Navigator.pop(context, client);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _clients
        : _clients
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.email.toLowerCase().contains(q))
            .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Book for Client',
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('${widget.cls.mode} · ${widget.cls.startTime}',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search clients by name or email...',
                    prefixIcon:
                        const Icon(Icons.search, size: 18, color: AppColors.textMuted),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.divider)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppColors.divider)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Expanded(
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary)),
                )
              else if (filtered.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('No matching clients',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final isBooking = _bookingUid == c.uid;
                      return ListTile(
                        title: Text(c.name,
                            style: const TextStyle(color: AppColors.textPrimary)),
                        subtitle: Text(c.email,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        trailing: isBooking
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary),
                              )
                            : const Icon(Icons.chevron_right,
                                color: AppColors.textMuted),
                        onTap: _bookingUid != null ? null : () => _confirmAndBook(c),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
