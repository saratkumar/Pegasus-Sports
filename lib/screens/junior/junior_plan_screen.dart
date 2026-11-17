import 'package:flutter/material.dart';
import '../../models/dependent_model.dart';
import '../../models/user_model.dart';
import '../../services/dependent_service.dart';
import '../../utils/app_colors.dart';
import '../../widgets/junior_plans.dart';

/// A junior account's own packages: credits left and when each ends. Read
/// only — packages are bought by the parent or guardian.
class JuniorPlanScreen extends StatelessWidget {
  final UserModel junior;
  const JuniorPlanScreen({super.key, required this.junior});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('My Plan')),
      body: StreamBuilder<DependentModel?>(
        stream:
            DependentService.streamOne(junior.parentUid!, junior.dependentId!),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final child = snap.data;
          if (child == null) {
            return const _Message(
                'Your profile could not be found. Please ask your parent or '
                'guardian, or contact the gym.');
          }
          final hasPlans = child.activeMemberships.isNotEmpty ||
              child.queuedMemberships.isNotEmpty;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    AppColors.primary.withValues(alpha: 0.18),
                    AppColors.primary.withValues(alpha: 0.05),
                  ]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.toll_rounded,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('${child.usableCredits} Credits',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                        hasPlans
                            ? 'Your junior package — use it to book classes '
                                'for yourself.'
                            : "You don't have a junior package yet. Ask your "
                                'parent or guardian to buy one for you.',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    JuniorPlansSection(
                        parentUid: junior.parentUid!, child: child),
                  ],
                ),
              ),
              if (!child.isEligibleJuniorOn()) ...[
                const SizedBox(height: 16),
                const _Note(
                    'Junior accounts are for ages 6–17. Once you turn 18, '
                    'please ask the gym for your own adult account.'),
              ],
              const SizedBox(height: 16),
              const _Note(
                  'Packages are bought by your parent or guardian. Your '
                  'credits can only be used to book classes for you.'),
            ],
          );
        },
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary))),
        ]),
      );
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
      );
}
