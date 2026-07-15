import 'package:cloud_firestore/cloud_firestore.dart';

/// Purges past-date bookings/waiting-list entries from Firestore so it only
/// ever holds live/current data — history already lives in the ActivityLog
/// Google Sheet mirror (see ConfigService.logActivityEvent), written at the
/// moment each event happened.
///
/// Manual only, triggered by an admin from the Backup screen — irreversible,
/// so this is never run silently/automatically. Best-effort: if a booking's
/// mirror write silently failed at creation time, purging it here removes
/// the only remaining record — accepted tradeoff, matching the mirror's
/// existing best-effort design.
class CleanupService {
  static final _doc =
      FirebaseFirestore.instance.collection('appMeta').doc('cleanup');

  static const _purgedCollections = ['bookings', 'waitingList'];

  static Future<DateTime?> getLastRunAt() async {
    final snap = await _doc.get();
    final ts = snap.data()?['lastRunAt'];
    return ts is Timestamp ? ts.toDate() : null;
  }

  /// Deletes every doc in [_purgedCollections] whose bookingDate is before
  /// today. Returns the total number of documents deleted.
  static Future<int> runNow() async {
    final cutoff =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    var total = 0;
    for (final collection in _purgedCollections) {
      total += await _purge(collection, cutoff);
    }

    await _doc.set({'lastRunAt': Timestamp.now()}, SetOptions(merge: true));
    return total;
  }

  static Future<int> _purge(String collection, DateTime cutoff) async {
    final snap = await FirebaseFirestore.instance
        .collection(collection)
        .where('bookingDate', isLessThan: Timestamp.fromDate(cutoff))
        .get();
    if (snap.docs.isEmpty) return 0;

    // Firestore batches cap at 500 writes — chunk in case a lot of history
    // has piled up before this ever ran.
    for (var i = 0; i < snap.docs.length; i += 500) {
      final chunk = snap.docs.skip(i).take(500);
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    return snap.docs.length;
  }
}
