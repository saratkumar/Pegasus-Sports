import 'package:cloud_firestore/cloud_firestore.dart';

class ClassModel {
  final String? id; // Firestore document ID; null for Google Sheets fallback
  final String day;
  final String mode; // class display name
  final String coach;
  final String location;
  final String? facilityId;
  final String groupSize;
  final String duration;
  final String detailLocation;
  final String startTime;
  final String type;
  final String image;
  final String description;
  final bool isActive;
  // Recurrence: 'weekly' | 'daily' | 'once' | 'monthly'
  final String occurrence;
  // Used for 'once' (exact date) and 'monthly' (reference date → week-of-month)
  final String? specificDate; // format: 'YYYY-MM-DD'
  // Dates where this session was cancelled (YYYY-MM-DD strings)
  final List<String> cancelledDates;
  // Per-session capacity overrides: 'YYYY-MM-DD' → total capacity for that day
  // Populated when admin approves a slot-increase request for a specific session
  final Map<String, int> sessionSlotOverrides;
  // Membership plan names allowed to book this class — empty means
  // unrestricted (any plan or the admin-granted credit pool works, the
  // default for every class unless an admin explicitly restricts it).
  final List<String> allowedPlanNames;

  ClassModel({
    this.id,
    required this.day,
    required this.mode,
    required this.coach,
    required this.location,
    this.facilityId,
    required this.groupSize,
    required this.duration,
    required this.detailLocation,
    required this.startTime,
    required this.type,
    required this.image,
    this.description = '',
    this.isActive = true,
    this.occurrence = 'weekly',
    this.specificDate,
    this.cancelledDates = const [],
    this.sessionSlotOverrides = const {},
    this.allowedPlanNames = const [],
  });

  String get effectiveId => id ?? '${day}_${mode}_$startTime';

  /// Returns effective capacity for [date], respecting per-session overrides.
  int effectiveCapacity(DateTime date) {
    final key = _dateKey(date);
    return sessionSlotOverrides[key] ?? (int.tryParse(groupSize) ?? 0);
  }

  /// Returns true if [date]'s session was cancelled.
  bool isCancelledOn(DateTime date) => cancelledDates.contains(_dateKey(date));

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  factory ClassModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // Parse cancelledDates — stored as List<String> in Firestore
    final rawCancelled = data['cancelledDates'];
    final cancelledDates = rawCancelled is List
        ? rawCancelled.map((e) => e.toString()).toList()
        : <String>[];
    // Parse sessionSlotOverrides — stored as Map<String, int> in Firestore
    final rawOverrides = data['sessionSlotOverrides'];
    final sessionSlotOverrides = <String, int>{};
    if (rawOverrides is Map) {
      rawOverrides.forEach((k, v) {
        if (k is String && v is int) sessionSlotOverrides[k] = v;
      });
    }
    final rawAllowedPlanNames = data['allowedPlanNames'];
    final allowedPlanNames = rawAllowedPlanNames is List
        ? rawAllowedPlanNames.map((e) => e.toString()).toList()
        : <String>[];
    return ClassModel(
      id: doc.id,
      day: data['day'] ?? '',
      mode: data['mode'] ?? '',
      coach: data['coach'] ?? '',
      location: data['location'] ?? '',
      facilityId: data['facilityId'],
      groupSize: data['groupSize']?.toString() ?? '0',
      duration: data['duration'] ?? '',
      detailLocation: data['detailLocation'] ?? '',
      startTime: data['startTime'] ?? '',
      type: data['type'] ?? '',
      image: data['image'] ?? '',
      description: data['description'] ?? '',
      isActive: data['isActive'] ?? true,
      occurrence: data['occurrence'] ?? 'weekly',
      specificDate: data['specificDate'],
      cancelledDates: cancelledDates,
      sessionSlotOverrides: sessionSlotOverrides,
      allowedPlanNames: allowedPlanNames,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'day': day,
        'mode': mode,
        'coach': coach,
        'location': location,
        if (facilityId != null) 'facilityId': facilityId,
        'groupSize': groupSize,
        'duration': duration,
        'detailLocation': detailLocation,
        'startTime': startTime,
        'type': type,
        'image': image,
        'description': description,
        'isActive': isActive,
        'occurrence': occurrence,
        if (specificDate != null) 'specificDate': specificDate,
        'allowedPlanNames': allowedPlanNames,
        // cancelledDates and sessionSlotOverrides are managed via targeted
        // Firestore arrayUnion / field updates — never overwrite them here
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
