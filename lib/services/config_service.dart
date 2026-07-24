import 'package:cloud_functions/cloud_functions.dart';

/// Talks to the Google Apps Script Web App backing the ActivityLog and
/// Transactions Sheet mirror — via the `callAppsScript` Cloud Function
/// proxy, so the script's URL and any per-caller authorization never live
/// in the client. See functions/index.js.
class ConfigService {
  // Cloud Functions are deployed to asia-southeast1 (see functions/index.js
  // setGlobalOptions) — the default FirebaseFunctions.instance targets
  // us-central1 and would silently fail to find the function.
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static Future<Map> _call(String action, [Map<String, String> params = const {}]) async {
    final result = await _functions.httpsCallable('callAppsScript').call({
      'action': action,
      'params': params,
    });
    return result.data as Map;
  }

  /// Shared YYYY-MM-DD formatter — keep the write side and read side in sync.
  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Mirrors a booking/request-lifecycle event into the ActivityLog Google
  /// Sheet tab. Firestore remains the source of truth for anything still
  /// pending — this must never throw into the calling flow, so all errors
  /// are swallowed and reported back as `false` instead. Callers that need
  /// to archive-then-delete a Firestore record should only delete once this
  /// returns `true`; on `false`, keep the Firestore record as a fallback
  /// rather than losing the only copy of the event.
  static Future<bool> logActivityEvent({
    required String eventType,
    required String classId,
    required String className,
    required DateTime sessionDate,
    required String sessionTime,
    required String userId,
    required String userName,
    required String bookedByRole,
    int creditsUsed = 1,
    String bookingId = '',
    String note = '',
  }) async {
    try {
      await _call('log_activity', {
        'eventType': eventType,
        'classId': classId,
        'className': className,
        'sessionDate': dateKey(sessionDate),
        'sessionTime': sessionTime,
        'userId': userId,
        'userName': userName,
        'bookedByRole': bookedByRole,
        'creditsUsed': creditsUsed.toString(),
        'bookingId': bookingId,
        'note': note,
      });
      return true;
    } catch (_) {
      // Best-effort mirror only — never surface to the caller.
      return false;
    }
  }

  /// Fetches ActivityLog rows, filtered by [date] (one day), [userId]
  /// (all-time for that person), or both. Returns [] on any failure so
  /// callers degrade to an empty state instead of crashing.
  static Future<List<Map<String, String>>> getActivityLog({
    DateTime? date,
    String? userId,
  }) async {
    try {
      final result = await _call('get_activity_log', {
        if (date != null) 'date': dateKey(date),
        if (userId != null) 'userId': userId,
      });
      final data = result['data'];
      if (data is! List) return [];
      return data
          .map<Map<String, String>>((e) =>
              (e as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetches all rows from the Transactions sheet.
  /// Returns [{invoiceNumber, clientName, clientEmail, planName, credits, amount, currency, date}, …]
  static Future<List<Map<String, String>>> getTransactions() async {
    final result = await _call('get_transactions');
    var data = result['data'];
    // Accept plain array OR {data: [...]} / {records: [...]} wrapper
    if (data is Map) {
      data = data['data'] ?? data['records'] ?? data['rows'];
    }
    if (data is! List) {
      throw Exception('Unexpected response shape from Apps Script');
    }
    return data.map<Map<String, String>>((e) {
      final row = (e as Map)
          .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      String pick(List<String> keys) {
        for (final k in keys) {
          final v = row[k];
          if (v != null && v.isNotEmpty) return v;
        }
        return '';
      }

      return {
        'invoiceNumber': pick(['invoiceNumber', 'Invoice No', 'Invoice Number']),
        'clientName': pick(['clientName', 'Client Name']),
        'clientEmail': pick(['clientEmail', 'Client Email']),
        'planName': pick(['planName', 'Plan', 'Plan Name']),
        'credits': pick(['credits', 'Credits']),
        'amount': pick(['amount', 'Amount']),
        'currency': pick(['currency', 'Currency']),
        // The Sheet's "Date" column currently holds the internal
        // payment/txn reference and the real date ended up under "Payment
        // Ref" instead (columns got swapped when the row was written) — try
        // the correct source first, only falling back to the mislabeled
        // "Date" column if nothing else has a value.
        'date': pick(['date', 'Payment Ref', 'Date']),
      };
    }).toList();
  }

  /// Records a transaction row to the Transactions sheet via the same Apps Script.
  static Future<void> recordTransaction({
    required String invoiceNumber,
    required String paymentIntentId,
    required String clientName,
    required String clientEmail,
    required String planName,
    required int credits,
    required double amount,
    required String currency,
    required String date,
  }) async {
    await _call('record_transaction', {
      'invoiceNumber': invoiceNumber,
      'txId': paymentIntentId,
      'clientName': clientName,
      'clientEmail': clientEmail,
      'planName': planName,
      'credits': credits.toString(),
      'amount': amount.toStringAsFixed(2),
      'currency': currency,
      'date': date,
    });
  }
}
