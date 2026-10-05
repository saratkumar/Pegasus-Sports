import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/dependent_model.dart';
import '../utils/app_colors.dart';

/// Result of [pickAttendee] — [child] null means the account holder.
class AttendeeChoice {
  final DependentModel? child;
  const AttendeeChoice(this.child);
}

/// "Who is this [action] for?" — lets a parent choose themselves or one of
/// their [children] (only those aged 6–17 on [date] are selectable).
/// Returns the account holder straight away when there are no children, so
/// callers can always go through this. [takenKeys] ('' = account holder,
/// else child id) are shown as already booked. Null = cancelled.
Future<AttendeeChoice?> pickAttendee(
  BuildContext context, {
  required List<DependentModel> children,
  required DateTime date,
  required String action,
  Set<String> takenKeys = const {},
}) async {
  if (children.isEmpty) return const AttendeeChoice(null);
  final me = FirebaseAuth.instance.currentUser?.displayName ?? 'Me';
  return showModalBottomSheet<AttendeeChoice>(
    context: context,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      Widget option({
        required String title,
        required String subtitle,
        required IconData icon,
        required bool enabled,
        required AttendeeChoice value,
      }) =>
          ListTile(
            enabled: enabled,
            onTap: () => Navigator.pop(ctx, value),
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Who is this $action for?',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              option(
                title: me,
                subtitle: takenKeys.contains('') ? 'Already booked' : 'Myself',
                icon: Icons.person,
                enabled: !takenKeys.contains(''),
                value: const AttendeeChoice(null),
              ),
              for (final c in children)
                option(
                  title: c.name,
                  subtitle: takenKeys.contains(c.id)
                      ? 'Already booked'
                      : c.isEligibleJuniorOn(date)
                          ? 'Junior · age ${c.ageOn(date)}'
                          : 'Not eligible — juniors must be '
                              '${DependentModel.minAge}–${DependentModel.maxAgeExclusive - 1}',
                  icon: Icons.child_care,
                  enabled:
                      !takenKeys.contains(c.id) && c.isEligibleJuniorOn(date),
                  value: AttendeeChoice(c),
                ),
            ],
          ),
        ),
      );
    },
  );
}
