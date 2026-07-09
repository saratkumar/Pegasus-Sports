import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks when the admin last exported a backup of logs/requests, so the
/// app can remind them if it's been too long.
class BackupService {
  static final _doc =
      FirebaseFirestore.instance.collection('appMeta').doc('backup');

  static Future<DateTime?> getLastBackupAt() async {
    final snap = await _doc.get();
    final ts = snap.data()?['lastBackupAt'];
    return ts is Timestamp ? ts.toDate() : null;
  }

  static Future<void> recordBackup() async {
    await _doc.set({'lastBackupAt': Timestamp.now()}, SetOptions(merge: true));
  }

  /// True if no backup has ever been taken, or the last one is older than
  /// [days] (defaults to 30).
  static Future<bool> isOverdue({int days = 30}) async {
    final last = await getLastBackupAt();
    if (last == null) return true;
    return DateTime.now().difference(last).inDays >= days;
  }
}
