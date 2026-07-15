import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/backup_service.dart';
import '../../services/cleanup_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

/// Lets an admin export a snapshot of current Firestore config/live data
/// (classes, facilities, types, bookings) to CSV — a disaster-recovery copy
/// of what's live right now, not a history log. Full event history already
/// lives in the Google Sheet ActivityLog mirror (see ConfigService), which
/// this does not duplicate.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupModule {
  final String id;
  final String label;
  final String fileName;
  final Future<String> Function() buildCsv;
  bool selected = true;

  _BackupModule({
    required this.id,
    required this.label,
    required this.fileName,
    required this.buildCsv,
  });
}

class _BackupScreenState extends State<BackupScreen> {
  DateTime? _lastBackupAt;
  DateTime? _lastCleanupAt;
  bool _loadingStatus = true;
  bool _backingUp = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final results = await Future.wait([
      BackupService.getLastBackupAt(),
      CleanupService.getLastRunAt(),
    ]);
    if (!mounted) return;
    setState(() {
      _lastBackupAt = results[0];
      _lastCleanupAt = results[1];
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
    return _fmtDate(ts.toDate());
  }

  Future<File> _writeCsv(String fileName, String csv) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csv);
    return file;
  }

  // ── Module CSV builders ─────────────────────────────────────────────────

  Future<String> _buildClassesCsv() async {
    final snap = await FirebaseFirestore.instance.collection('classes').get();
    final header = 'ID,Day,Mode,Coach,Location,Group Size,Duration,'
        'Detail Location,Start Time,Type,Occurrence,Specific Date,Active\n';
    final lines = snap.docs.map((doc) {
      final d = doc.data();
      return [
        doc.id, d['day'], d['mode'], d['coach'], d['location'],
        d['groupSize'], d['duration'], d['detailLocation'], d['startTime'],
        d['type'], d['occurrence'], d['specificDate'], d['isActive'],
      ].map(_csvCell).join(',');
    }).join('\n');
    return '$header$lines';
  }

  Future<String> _buildFacilitiesCsv() async {
    final snap = await FirebaseFirestore.instance.collection('facilities').get();
    final header = 'ID,Name,Address\n';
    final lines = snap.docs.map((doc) {
      final d = doc.data();
      return [doc.id, d['name'], d['address']].map(_csvCell).join(',');
    }).join('\n');
    return '$header$lines';
  }

  Future<String> _buildTypesCsv() async {
    final snap = await FirebaseFirestore.instance.collection('classTypes').get();
    final header = 'ID,Name,Image URL\n';
    final lines = snap.docs.map((doc) {
      final d = doc.data();
      return [doc.id, d['name'], d['imageUrl']].map(_csvCell).join(',');
    }).join('\n');
    return '$header$lines';
  }

  Future<String> _buildBookingsCsv() async {
    final snap = await FirebaseFirestore.instance.collection('bookings').get();
    final header = 'ID,User ID,Class,Day,Date,Time,Booked By,Role,Credits,Status,Created At\n';
    final lines = snap.docs.map((doc) {
      final d = doc.data();
      return [
        doc.id, d['userId'], d['displayName'], d['bookingDay'],
        _fmtTimestamp(d['bookingDate']), d['bookingTime'], d['bookedBy'],
        d['bookedByRole'], d['creditsUsed'], d['status'] ?? 'active',
        _fmtTimestamp(d['createdAt']),
      ].map(_csvCell).join(',');
    }).join('\n');
    return '$header$lines';
  }

  List<_BackupModule> _modules() => [
        _BackupModule(id: 'classes', label: 'Classes', fileName: 'Classes',
            buildCsv: _buildClassesCsv),
        _BackupModule(id: 'facilities', label: 'Facilities', fileName: 'Facilities',
            buildCsv: _buildFacilitiesCsv),
        _BackupModule(id: 'types', label: 'Class Types', fileName: 'ClassTypes',
            buildCsv: _buildTypesCsv),
        _BackupModule(id: 'bookings', label: 'Current Bookings', fileName: 'Bookings',
            buildCsv: _buildBookingsCsv),
      ];

  Future<void> _pickModulesAndBackup() async {
    final modules = _modules();
    final selected = await showDialog<List<_BackupModule>>(
      context: context,
      builder: (ctx) => _ModulePickerDialog(modules: modules),
    );
    if (selected == null || selected.isEmpty) return;

    setState(() => _backingUp = true);
    try {
      final today =
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';

      final files = <XFile>[];
      for (final module in selected) {
        final csv = await module.buildCsv();
        final file = await _writeCsv('PSAS_${module.fileName}_$today.csv', csv);
        files.add(XFile(file.path, mimeType: 'text/csv'));
      }

      await Share.shareXFiles(files, subject: 'PSAS Backup – $today');

      await BackupService.recordBackup();
      if (!mounted) return;
      setState(() => _lastBackupAt = DateTime.now());
      AppToast.success(context, 'Backup exported and saved');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Backup failed: $e');
    }
    if (mounted) setState(() => _backingUp = false);
  }

  Future<void> _clearOldData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Clear Old Data?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          'Permanently deletes all bookings and waiting-list entries for '
          'past dates from Firestore. This cannot be undone — make sure '
          "you've backed up first. History stays in the Google Sheet either way.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Clear Old Data'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _clearing = true);
    try {
      final deleted = await CleanupService.runNow();
      if (!mounted) return;
      setState(() => _lastCleanupAt = DateTime.now());
      AppToast.success(context,
          deleted == 0 ? 'Nothing to clear' : 'Cleared $deleted old record${deleted == 1 ? '' : 's'}');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Clear failed: $e');
    }
    if (mounted) setState(() => _clearing = false);
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
            'Exports a snapshot of current classes, facilities, class types, '
            'and bookings as CSV — pick which ones you need. Past event '
            'history (cancellations, waitlist activity, transactions) '
            'already lives in the Google Sheet, not here.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _backingUp ? null : _pickModulesAndBackup,
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
          const SizedBox(height: 28),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Text(
            _loadingStatus
                ? 'Checking last clear…'
                : (_lastCleanupAt == null
                    ? 'Old data has never been cleared'
                    : 'Last cleared: ${_fmtDate(_lastCleanupAt!)}'),
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Permanently removes bookings and waiting-list entries for past '
            'dates from Firestore — they stay recorded in the Google Sheet. '
            'Back up first if you want a local copy before clearing.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _clearing ? null : _clearOldData,
            icon: _clearing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.error),
                  )
                : const Icon(Icons.delete_outline, color: AppColors.error),
            label: Text(_clearing ? 'Clearing…' : 'Clear Old Data',
                style: const TextStyle(color: AppColors.error)),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _ModulePickerDialog extends StatefulWidget {
  final List<_BackupModule> modules;
  const _ModulePickerDialog({required this.modules});

  @override
  State<_ModulePickerDialog> createState() => _ModulePickerDialogState();
}

class _ModulePickerDialogState extends State<_ModulePickerDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('What do you want to back up?',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.modules
              .map((m) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(m.label,
                        style: const TextStyle(color: AppColors.textPrimary)),
                    value: m.selected,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => m.selected = v ?? false),
                  ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
              context, widget.modules.where((m) => m.selected).toList()),
          child: const Text('Back Up Selected'),
        ),
      ],
    );
  }
}
