import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/error_reporter.dart';
import '../../widgets/coach_profile.dart';

/// Admin view of every coach (trainers and admins, including yourself) with
/// their photo and description — tap one to edit what members see when they
/// tap the coach on a class.
class TrainerProfilesScreen extends StatelessWidget {
  const TrainerProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trainers')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', whereIn: ['trainer', 'admin'])
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Could not load trainers: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final coaches = snap.data!.docs
              .map((d) => UserModel.fromFirestore(d.data(), d.id))
              .toList()
            ..sort((a, b) {
              // Trainers first, then admins; alphabetical within each.
              final r = (a.role == 'trainer' ? 0 : 1)
                  .compareTo(b.role == 'trainer' ? 0 : 1);
              return r != 0
                  ? r
                  : a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          if (coaches.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No trainers yet. Give a user the Trainer role first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: coaches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _CoachCard(coach: coaches[i]),
          );
        },
      ),
    );
  }
}

class _CoachCard extends StatelessWidget {
  final UserModel coach;
  const _CoachCard({required this.coach});

  @override
  Widget build(BuildContext context) {
    final bio = coach.coachBio?.trim() ?? '';
    final hasPhoto = (coach.coachPhotoUrl ?? '').isNotEmpty;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _edit(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CoachAvatar(photoUrl: coach.coachPhotoUrl, radius: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coach.name.isEmpty ? coach.email : coach.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(coach.role == 'trainer' ? 'Trainer' : 'Admin',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                    const SizedBox(height: 6),
                    Text(
                      bio.isNotEmpty
                          ? bio
                          : hasPhoto
                              ? 'No description yet'
                              : 'No photo or description yet',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: bio.isNotEmpty
                              ? AppColors.textSecondary
                              : AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _edit(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CoachEditSheet(coach: coach),
    );
  }
}

class _CoachEditSheet extends StatefulWidget {
  final UserModel coach;
  const _CoachEditSheet({required this.coach});

  @override
  State<_CoachEditSheet> createState() => _CoachEditSheetState();
}

class _CoachEditSheetState extends State<_CoachEditSheet> {
  late final _photoCtrl =
      TextEditingController(text: widget.coach.coachPhotoUrl ?? '');
  late final _bioCtrl = TextEditingController(text: widget.coach.coachBio ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _photoCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await UserService.updateCoachProfile(
        uid: widget.coach.uid,
        photoUrl: _photoCtrl.text,
        bio: _bioCtrl.text,
      );
      CoachDirectory.clear();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${widget.coach.name}\'s profile')),
      );
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _saving = false);
      reportError(context, e, st,
          userMessage: 'Could not save the coach profile.',
          reason: 'Admin coach profile save failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.coach.name,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              CoachProfileFields(
                photoCtrl: _photoCtrl,
                bioCtrl: _bioCtrl,
                uploadForUid: widget.coach.uid,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
