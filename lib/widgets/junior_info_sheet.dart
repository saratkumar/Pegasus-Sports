import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/dependent_model.dart';
import '../utils/app_colors.dart';

/// One junior attendee with what staff need on the day: age, medical notes,
/// emergency contact and the parent's details.
class _JuniorInfo {
  final DependentModel child;
  final String parentName;
  final String parentPhone;
  final String parentEmail;
  const _JuniorInfo(
      this.child, this.parentName, this.parentPhone, this.parentEmail);
}

Future<_JuniorInfo?> _loadJunior(String parentUid, String childId) async {
  final users = FirebaseFirestore.instance.collection('users');
  final results = await Future.wait([
    users.doc(parentUid).collection('dependents').doc(childId).get(),
    users.doc(parentUid).get(),
  ]);
  if (!results[0].exists) return null;
  final parent = results[1].data() ?? {};
  return _JuniorInfo(
    DependentModel.fromFirestore(results[0]),
    parent['name']?.toString() ?? '',
    parent['phone']?.toString() ?? '',
    parent['email']?.toString() ?? '',
  );
}

/// Staff view of every junior booked into [classId] on [date] — read from
/// Firestore bookings (attendeeId set), not the Sheet-mirrored roster, since
/// the medical/emergency details live only on the child profile.
Future<void> showSessionJuniorsSheet(
  BuildContext context, {
  required String classId,
  required String className,
  required DateTime date,
}) {
  Future<List<_JuniorInfo>> load() async {
    final snap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('classId', isEqualTo: classId)
        .get();
    final day = DateTime(date.year, date.month, date.day);
    final refs = snap.docs.map((d) => d.data()).where((data) {
      if (data['attendeeId'] == null) return false;
      if (data['status'] == 'cancelled_by_trainer') return false;
      final bd = data['bookingDate'];
      if (bd is! Timestamp) return false;
      final dt = bd.toDate();
      return DateTime(dt.year, dt.month, dt.day) == day;
    });
    final loaded = await Future.wait(refs.map((data) => _loadJunior(
        data['userId'].toString(), data['attendeeId'].toString())));
    return loaded.whereType<_JuniorInfo>().toList()
      ..sort((a, b) => a.child.name.compareTo(b.child.name));
  }

  return _show(context, title: 'Juniors · $className', date: date, load: load());
}

/// Staff view of a single child profile (e.g. from an appointment request).
Future<void> showJuniorSheet(
  BuildContext context, {
  required String parentUid,
  required String childId,
  DateTime? date,
}) {
  Future<List<_JuniorInfo>> load() async {
    final info = await _loadJunior(parentUid, childId);
    return info == null ? [] : [info];
  }

  return _show(context,
      title: 'Junior details', date: date ?? DateTime.now(), load: load());
}

Future<void> _show(
  BuildContext context, {
  required String title,
  required DateTime date,
  required Future<List<_JuniorInfo>> load,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => FutureBuilder<List<_JuniorInfo>>(
        future: load,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('Could not load: ${snap.error}',
                    style: const TextStyle(color: AppColors.error)));
          }
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final juniors = snap.data!;
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              const Text('Confidential — for session safety only.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 16),
              if (juniors.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No juniors booked',
                        style: TextStyle(color: AppColors.textMuted)),
                  ),
                ),
              for (final j in juniors) _JuniorCard(info: j, date: date),
            ],
          );
        },
      ),
    ),
  );
}

class _JuniorCard extends StatelessWidget {
  final _JuniorInfo info;
  final DateTime date;
  const _JuniorCard({required this.info, required this.date});

  @override
  Widget build(BuildContext context) {
    final c = info.child;
    final medical = c.hasMedicalNotes;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: medical
                ? AppColors.error.withValues(alpha: 0.5)
                : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.child_care, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(c.name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              Text('Age ${c.ageOn(date)} · ${c.verificationLabel}',
                  style: TextStyle(
                      fontSize: 13,
                      color: c.isVerified
                          ? AppColors.textSecondary
                          : AppColors.error)),
            ],
          ),
          const SizedBox(height: 10),
          if (medical)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.medical_information_outlined,
                      size: 18, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(c.medicalNotes,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('No medical notes',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          _line(Icons.family_restroom,
              '${c.relationship}: ${info.parentName}',
              [info.parentPhone, info.parentEmail]
                  .where((s) => s.isNotEmpty)
                  .join(' · ')),
          const SizedBox(height: 6),
          _line(Icons.contact_phone_outlined,
              'Emergency: ${c.emergencyContactName}', c.emergencyContactPhone),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String title, String detail) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText.rich(
              TextSpan(children: [
                TextSpan(
                    text: title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                if (detail.isNotEmpty)
                  TextSpan(
                      text: '\n$detail',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
              ]),
            ),
          ),
        ],
      );
}
