import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() =>
      _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _exporting = false;
  List<_LogRow> _rows = [];
  bool _loaded = false;

  static const _monthNames = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];

  String get _monthLabel => '${_monthNames[_month.month - 1]} ${_month.year}';

  Future<void> _load() async {
    setState(() { _loaded = false; _rows = []; });

    final startOfMonth = DateTime(_month.year, _month.month, 1);
    final endOfMonth = DateTime(_month.year, _month.month + 1, 1);

    // ── Bookings ──────────────────────────────────────────────────────────
    final bookSnap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('bookingDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('bookingDate', isLessThan: Timestamp.fromDate(endOfMonth))
        .get();

    final rows = <_LogRow>[];

    for (final doc in bookSnap.docs) {
      final d = doc.data();
      final status = d['status']?.toString();
      String eventType;
      if (status == 'cancelled_by_trainer') {
        eventType = 'Cancelled by Trainer';
      } else {
        eventType = 'Booked';
      }

      rows.add(_LogRow(
        date: _fmtDate((d['bookingDate'] as Timestamp).toDate()),
        time: d['bookingTime']?.toString() ?? '',
        userName: await _resolveUserName(d['userId']?.toString()),
        className: d['displayName']?.toString() ?? '',
        bookingType: d['bookingType']?.toString() ?? '',
        eventType: eventType,
        bookedBy: d['bookedByRole']?.toString() ?? 'client',
        creditsUsed: (d['creditsUsed'] as int?)?.toString() ?? '1',
        createdAt: _fmtTs(d['createdAt']),
      ));
    }

    // ── Booking cancellations by clients ─────────────────────────────────
    // (already captured above via status field; also pull deletions by checking
    //  the waitingList admitted entries which represent last-minute cancellation
    //  openings)

    // ── Waiting list events ───────────────────────────────────────────────
    final wlSnap = await FirebaseFirestore.instance
        .collection('waitingList')
        .where('bookingDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('bookingDate', isLessThan: Timestamp.fromDate(endOfMonth))
        .get();

    for (final doc in wlSnap.docs) {
      final d = doc.data();
      final status = d['status']?.toString() ?? 'waiting';
      String eventType;
      switch (status) {
        case 'admitted':
          eventType = 'Admitted from Waitlist';
        case 'expired':
          eventType = 'Waitlist Expired (Credit Refunded)';
        default:
          eventType = 'Joined Waitlist';
      }
      rows.add(_LogRow(
        date: _fmtDate((d['bookingDate'] as Timestamp).toDate()),
        time: d['bookingTime']?.toString() ?? '',
        userName: d['userName']?.toString() ?? '',
        className: d['className']?.toString() ?? '',
        bookingType: 'class',
        eventType: eventType,
        bookedBy: 'client',
        creditsUsed: '1',
        createdAt: _fmtTs(d['requestedAt']),
      ));
    }

    rows.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    setState(() { _rows = rows; _loaded = true; });
  }

  final _nameCache = <String, String>{};

  Future<String> _resolveUserName(String? uid) async {
    if (uid == null || uid.isEmpty) return 'Unknown';
    if (_nameCache.containsKey(uid)) return _nameCache[uid]!;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final name = doc.data()?['name']?.toString() ?? uid;
    _nameCache[uid] = name;
    return name;
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day.toString().padLeft(2,'0')} ${m[d.month-1]} ${d.year}';
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    try {
      final d = (ts as Timestamp).toDate();
      return '${_fmtDate(d)} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _export() async {
    if (_rows.isEmpty) {
      AppToast.warning(context, 'No data to export');
      return;
    }
    setState(() => _exporting = true);

    final header =
        'Date,Time,Member,Class/Appointment,Type,Event,Booked By,Credits,Timestamp\n';
    final lines = _rows.map((r) =>
        '"${r.date}","${r.time}","${r.userName}","${r.className}",'
        '"${r.bookingType}","${r.eventType}","${r.bookedBy}",'
        '"${r.creditsUsed}","${r.createdAt}"').join('\n');

    final csv = '$header$lines';
    final fileName =
        'PSAS_Attendance_${_month.year}_${_month.month.toString().padLeft(2,'0')}.csv';

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csv);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'PSAS Attendance – $_monthLabel',
      );
    } catch (e) {
      if (mounted) AppToast.error(context, 'Export failed: $e');
    }
    if (mounted) setState(() => _exporting = false);
  }

  void _prevMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month - 1);
      _loaded = false;
      _rows = [];
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_month.year == now.year && _month.month == now.month) return;
    setState(() {
      _month = DateTime(_month.year, _month.month + 1);
      _loaded = false;
      _rows = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentMonth = _month.year == DateTime.now().year &&
        _month.month == DateTime.now().month;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Report'),
        actions: [
          if (_loaded && _rows.isNotEmpty)
            _exporting
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary)),
                  )
                : IconButton(
                    icon: const Icon(Icons.download_outlined),
                    tooltip: 'Export CSV',
                    onPressed: _export,
                  ),
        ],
      ),
      body: Column(
        children: [
          // Month picker
          Container(
            color: AppColors.bg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _prevMonth,
                ),
                Expanded(
                  child: Text(
                    _monthLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right,
                      color: isCurrentMonth
                          ? AppColors.divider
                          : AppColors.textPrimary),
                  onPressed: isCurrentMonth ? null : _nextMonth,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('Load $_monthLabel'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ),
          const Divider(height: 1),
          if (!_loaded)
            const Expanded(
              child: Center(
                child: Text(
                  'Select a month and tap Load',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else if (_rows.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'No events found for this month',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else ...[
            // Summary chips
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _summaryChip('Total Events', _rows.length,
                      AppColors.primary),
                  _summaryChip(
                      'Booked',
                      _rows.where((r) => r.eventType == 'Booked').length,
                      const Color(0xFF00D4AA)),
                  _summaryChip(
                      'Cancelled',
                      _rows
                          .where((r) =>
                              r.eventType.toLowerCase().contains('cancel'))
                          .length,
                      AppColors.error),
                  _summaryChip(
                      'Waitlist',
                      _rows
                          .where((r) =>
                              r.eventType.toLowerCase().contains('wait'))
                          .length,
                      const Color(0xFFFFAB40)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _RowCard(row: _rows[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          Text('$count',
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _LogRow {
  final String date;
  final String time;
  final String userName;
  final String className;
  final String bookingType;
  final String eventType;
  final String bookedBy;
  final String creditsUsed;
  final String createdAt;

  _LogRow({
    required this.date,
    required this.time,
    required this.userName,
    required this.className,
    required this.bookingType,
    required this.eventType,
    required this.bookedBy,
    required this.creditsUsed,
    required this.createdAt,
  });
}

class _RowCard extends StatelessWidget {
  final _LogRow row;
  const _RowCard({required this.row});

  Color get _eventColor {
    final e = row.eventType.toLowerCase();
    if (e.contains('cancel')) return AppColors.error;
    if (e.contains('wait') && e.contains('expire')) {
      return const Color(0xFFFFAB40);
    }
    if (e.contains('wait')) return const Color(0xFFFFAB40);
    if (e.contains('admitted')) return const Color(0xFF00D4AA);
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 60,
            decoration: BoxDecoration(
              color: _eventColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(row.userName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _eventColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(row.eventType,
                          style: TextStyle(
                              fontSize: 10,
                              color: _eventColor,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(row.className,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  children: [
                    _info(Icons.calendar_today_outlined, row.date),
                    _info(Icons.schedule, row.time),
                    _info(Icons.toll_rounded, '${row.creditsUsed} cr'),
                    if (row.bookedBy != 'client')
                      _info(Icons.manage_accounts_outlined,
                          'by ${row.bookedBy}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textMuted),
        const SizedBox(width: 3),
        Text(text,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
