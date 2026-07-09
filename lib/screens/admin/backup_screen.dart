import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/backup_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

/// Lets an admin export all booking/waiting-list logs and admin requests to
/// CSV (opens straight in Excel/Sheets) and records when the backup was
/// taken, so [BackupService.isOverdue] can nudge them if it's been a while.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  DateTime? _lastBackupAt;
  bool _loadingStatus = true;
  bool _backingUp = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final last = await BackupService.getLastBackupAt();
    if (!mounted) return;
    setState(() {
      _lastBackupAt = last;
      _loadingStatus = false;
    });
  }

  int? get _daysSinceBackup =>
      _lastBackupAt == null ? null : DateTime.now().difference(_lastBackupAt!).inDays;

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day.toString().padLeft(2,'0')} ${m[d.month-1]} ${d.year}, '
        '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  String _csvCell(dynamic v) => '"${v?.toString().replaceAll('"', '""') ?? ''}"';

  String _fmtTimestamp(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    return _fmtDate(d);
  }

  Future<File> _writeCsv(String fileName, String csv) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csv);
    return file;
  }

  Future<void> _runBackup() async {
    setState(() => _backingUp = true);
    try {
      final today =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';

      // ── Logs: bookings + waiting list (all time) ─────────────────────────
      final bookings =
          await FirebaseFirestore.instance.collection('bookings').get();
      final waitingList =
          await FirebaseFirestore.instance.collection('waitingList').get();

      final logHeader =
          'Source,Date/Time,User,Class,Status,Booked By,Credits\n';
      final logLines = <String>[];
      for (final doc in bookings.docs) {
        final d = doc.data();
        logLines.add([
          'Booking',
          _fmtTimestamp(d['bookingDate']),
          d['userId'],
          d['displayName'],
          d['status'] ?? 'booked',
          d['bookedByRole'] ?? 'client',
          d['creditsUsed'],
        ].map(_csvCell).join(','));
      }
      for (final doc in waitingList.docs) {
        final d = doc.data();
        logLines.add([
          'Waitlist',
          _fmtTimestamp(d['bookingDate']),
          d['userName'],
          d['className'],
          d['status'] ?? 'waiting',
          'client',
          '1',
        ].map(_csvCell).join(','));
      }
      final logCsv = '$logHeader${logLines.join('\n')}';

      // ── Requests: adminRequests (all time) ────────────────────────────────
      final requests = await FirebaseFirestore.instance
          .collection('adminRequests')
          .orderBy('createdAt', descending: true)
          .get();
      final reqHeader =
          'Type,Requested By,Target User,Class,Amount,Status,Note,Created At\n';
      final reqLines = requests.docs.map((doc) {
        final d = doc.data();
        return [
          d['type'],
          d['requestedByName'],
          d['targetUserName'],
          d['className'],
          d['amount'],
          d['status'],
          d['note'],
          _fmtTimestamp(d['createdAt']),
        ].map(_csvCell).join(',');
      }).join('\n');
      final reqCsv = '$reqHeader$reqLines';

      final logFile = await _writeCsv('PSAS_Logs_$today.csv', logCsv);
      final reqFile = await _writeCsv('PSAS_Requests_$today.csv', reqCsv);

      await Share.shareXFiles(
        [
          XFile(logFile.path, mimeType: 'text/csv'),
          XFile(reqFile.path, mimeType: 'text/csv'),
        ],
        subject: 'PSAS Backup – $today',
      );

      await BackupService.recordBackup();
      if (!mounted) return;
      setState(() => _lastBackupAt = DateTime.now());
      AppToast.success(context, 'Backup exported and saved');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Backup failed: $e');
    }
    if (mounted) setState(() => _backingUp = false);
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysSinceBackup;
    final overdue = days == null || days >= 30;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: overdue
                  ? AppColors.error.withValues(alpha: 0.08)
                  : AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: overdue ? AppColors.error : AppColors.divider),
            ),
            child: Row(
              children: [
                Icon(
                  overdue ? Icons.warning_amber_rounded : Icons.check_circle,
                  color: overdue ? AppColors.error : const Color(0xFF00D4AA),
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loadingStatus
                            ? 'Checking last backup…'
                            : (_lastBackupAt == null
                                ? 'No backup has ever been taken'
                                : 'Last backup: ${_fmtDate(_lastBackupAt!)}'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                      ),
                      if (!_loadingStatus && days != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          '$days day${days == 1 ? '' : 's'} ago'
                          '${overdue ? ' — backup is overdue' : ''}',
                          style: TextStyle(
                              fontSize: 12,
                              color: overdue
                                  ? AppColors.error
                                  : AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Exports all booking/waiting-list logs and admin requests as CSV '
            'files (opens directly in Excel or Google Sheets) and shares them '
            'so you can save a copy.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _backingUp ? null : _runBackup,
            icon: _backingUp
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.backup_outlined),
            label: Text(_backingUp ? 'Exporting…' : 'Back Up Now'),
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48)),
          ),
        ],
      ),
    );
  }
}
