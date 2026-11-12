import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_model.dart';
import '../services/class_service.dart';
import '../utils/app_colors.dart';
import '../utils/drive_image.dart';

/// Trainer photo + description fields with a live preview, shared by the
/// trainer's own Profile screen and the admin user editor. The caller owns
/// the controllers and saves via UserService.updateCoachProfile.
///
/// When [uploadForUid] is set (admin screens only — the uploadCoachPhoto
/// function is admin-only), an "Upload photo" button picks an image, sends
/// it to Google Drive via the function, and fills in the resulting link.
class CoachProfileFields extends StatefulWidget {
  final TextEditingController photoCtrl;
  final TextEditingController bioCtrl;
  final String? uploadForUid;

  const CoachProfileFields({
    super.key,
    required this.photoCtrl,
    required this.bioCtrl,
    this.uploadForUid,
  });

  @override
  State<CoachProfileFields> createState() => _CoachProfileFieldsState();
}

class _CoachProfileFieldsState extends State<CoachProfileFields> {
  @override
  void initState() {
    super.initState();
    widget.photoCtrl.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.photoCtrl.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool _uploading = false;

  Future<void> _upload() async {
    final XFile? picked;
    try {
      // Resized on-device so each photo is ~100-200 KB: fast for members to
      // load and well under the function's 5 MB limit.
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
    } catch (e) {
      _toast('Could not open photos: $e');
      return;
    }
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final mime = picked.mimeType ?? _mimeFromName(picked.name);
      final result = await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('uploadCoachPhoto',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call({
        'uid': widget.uploadForUid,
        'mimeType': mime,
        'data': base64Encode(bytes),
      });
      widget.photoCtrl.text = (result.data as Map)['url'] as String;
      _toast('Photo uploaded to Google Drive — tap Save to keep it.');
    } on FirebaseFunctionsException catch (e) {
      _toast(e.message ?? 'Upload failed.');
    } catch (e) {
      _toast('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  static String _mimeFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final preview = driveDirectImageUrl(widget.photoCtrl.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Coach profile',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(
          widget.uploadForUid != null
              ? 'Shown to members when they tap the coach on a class. '
                  'Upload a photo (it is saved to Google Drive), or paste a '
                  'Drive link shared as "Anyone with the link".'
              : 'Shown to members when they tap the coach on a class. '
                  'Upload the photo to Google Drive, share it as "Anyone with the link", '
                  'and paste the link here.',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        if (widget.uploadForUid != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_outlined, size: 18),
            label: Text(_uploading ? 'Uploading…' : 'Upload photo'),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoachAvatar(photoUrl: preview, radius: 30),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: widget.photoCtrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Photo link (Google Drive)',
                  hintText: 'https://drive.google.com/file/d/…/view',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: widget.bioCtrl,
          maxLines: 4,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Description',
            hintText: 'Experience, specialties, certifications…',
            alignLabelWithHint: true,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

/// Round coach photo, falling back to a person icon when there's no photo
/// or it fails to load (e.g. a Drive file not shared publicly).
class CoachAvatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;

  const CoachAvatar({super.key, required this.photoUrl, this.radius = 14});

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      child: Icon(Icons.person, size: radius, color: AppColors.primary),
    );
    final url = photoUrl?.trim() ?? '';
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

/// Trainers and admins by name — classes store the coach as a name, so the
/// profile is looked up by it. Loaded once per app session.
class CoachDirectory {
  static Future<Map<String, UserModel>>? _byName;

  static Future<Map<String, UserModel>> byName() =>
      _byName ??= ClassService.getCoaches().then(
          (coaches) => {for (final c in coaches) c.name.trim(): c},
          onError: (Object e) {
        _byName = null;
        throw e;
      });

  /// Forget the cached coaches so an edited profile shows on next lookup.
  static void clear() => _byName = null;

  static Future<UserModel?> find(String name) async =>
      (await byName())[name.trim()];
}

/// Bottom sheet with a coach's photo and description, opened from a class.
Future<void> showCoachProfile(BuildContext context, String coachName) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: FutureBuilder<UserModel?>(
        future: CoachDirectory.find(coachName),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 200,
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            );
          }
          final coach = snap.data;
          final bio = coach?.coachBio?.trim() ?? '';
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CoachAvatar(photoUrl: coach?.coachPhotoUrl, radius: 56),
                const SizedBox(height: 14),
                Text(coachName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                const Text('Coach',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textMuted)),
                const SizedBox(height: 16),
                Text(
                  bio.isNotEmpty ? bio : 'More about this coach coming soon.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
