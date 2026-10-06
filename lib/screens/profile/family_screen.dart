import 'package:flutter/material.dart';
import '../../models/dependent_model.dart';
import '../../services/dependent_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

/// "My Family" — a parent's child profiles (aged 6–17). Children never sign
/// in; the parent books for them from the Classes screen. [staffMode] is
/// the admin view of a client's family (User Management): same screens,
/// but consent is recorded on the parent's behalf.
class FamilyScreen extends StatelessWidget {
  final String parentUid;
  final String? parentName;
  final bool staffMode;
  const FamilyScreen({
    super.key,
    required this.parentUid,
    this.parentName,
    this.staffMode = false,
  });

  Future<void> _openEditor(BuildContext context, [DependentModel? child]) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ChildEditorScreen(
              parentUid: parentUid, existing: child, staffMode: staffMode),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              staffMode ? 'Family · ${parentName ?? 'Client'}' : 'My Family')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add child'),
      ),
      body: StreamBuilder<List<DependentModel>>(
        stream: DependentService.streamActive(parentUid),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final children = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              const Text(
                'Add your children (aged ${DependentModel.minAge}–17) to book '
                'classes for them using your account. Juniors can join any '
                'class and can use your credits. Our staff approve each new '
                'child before junior packages can be bought or used for them.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              if (children.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('No children added yet',
                        style: TextStyle(color: AppColors.textMuted)),
                  ),
                ),
              for (final c in children) _childCard(context, c),
            ],
          );
        },
      ),
    );
  }

  Widget _childCard(BuildContext context, DependentModel c) {
    final age = c.ageOn();
    final eligible = c.isEligibleJuniorOn();
    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: ListTile(
        onTap: () => _openEditor(context, c),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          child: const Icon(Icons.child_care, color: AppColors.primary),
        ),
        title: Text(c.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          eligible
              ? 'Age $age · ${c.verificationLabel}'
                  '${c.hasMedicalNotes ? ' · Medical notes added' : ''}'
              : age >= DependentModel.maxAgeExclusive
                  ? 'Age $age — now an adult, please create their own account'
                  : 'Age $age — can book from age ${DependentModel.minAge}',
          style: TextStyle(
              fontSize: 12,
              color: !eligible || c.isRejected
                  ? AppColors.error
                  : c.isVerified
                      ? AppColors.textSecondary
                      : const Color(0xFFE08A00)),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      ),
    );
  }
}

class _ChildEditorScreen extends StatefulWidget {
  final String parentUid;
  final DependentModel? existing;
  final bool staffMode;
  const _ChildEditorScreen({
    required this.parentUid,
    this.existing,
    this.staffMode = false,
  });

  @override
  State<_ChildEditorScreen> createState() => _ChildEditorScreenState();
}

class _ChildEditorScreenState extends State<_ChildEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  late final TextEditingController _medical;
  DateTime? _dob;
  late String _relationship;
  bool _consent = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  /// Once staff approve a child, only staff may change who they are —
  /// otherwise a verified profile could be repurposed (also enforced in
  /// firestore.rules).
  bool get _identityLocked =>
      !widget.staffMode && (widget.existing?.isVerified ?? false);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _emergencyName = TextEditingController(text: e?.emergencyContactName ?? '');
    _emergencyPhone =
        TextEditingController(text: e?.emergencyContactPhone ?? '');
    _medical = TextEditingController(text: e?.medicalNotes ?? '');
    _dob = e?.dateOfBirth;
    _relationship = e?.relationship ?? 'Parent';
    // Consent was recorded when the child was added.
    _consent = _isEdit;
  }

  @override
  void dispose() {
    _name.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
    _medical.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final first = DateTime(
        now.year - DependentModel.maxAgeExclusive, now.month, now.day + 1);
    final last = DateTime(now.year - DependentModel.minAge, now.month, now.day);
    // An existing child may have aged out of range since being added.
    var initial = _dob ?? DateTime(now.year - 10, now.month, now.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      AppToast.error(context, 'Please select a date of birth');
      return;
    }
    if (!_consent) {
      AppToast.error(context, 'Please confirm parental consent');
      return;
    }
    setState(() => _saving = true);
    final child = DependentModel(
      id: widget.existing?.id,
      name: _name.text.trim(),
      dateOfBirth: _dob!,
      relationship: _relationship,
      emergencyContactName: _emergencyName.text.trim(),
      emergencyContactPhone: _emergencyPhone.text.trim(),
      medicalNotes: _medical.text.trim(),
      consentAcceptedAt: widget.existing?.consentAcceptedAt ?? DateTime.now(),
      consentTermsVersion: widget.existing?.consentTermsVersion ??
          DependentModel.consentVersion,
    );
    try {
      if (_isEdit) {
        await DependentService.update(widget.parentUid, child);
      } else {
        await DependentService.add(widget.parentUid, child,
            addedByStaff: widget.staffMode);
      }
      if (mounted) {
        AppToast.success(
            context,
            _isEdit
                ? 'Saved'
                : widget.staffMode
                    ? '${child.name} added and approved'
                    : '${child.name} added — awaiting approval by our staff');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${widget.existing!.name}?'),
        content: const Text(
            'Existing bookings are kept. You can add them again later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DependentService.deactivate(widget.parentUid, widget.existing!.id!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _setVerification(bool approved) async {
    setState(() => _saving = true);
    try {
      await DependentService.setVerification(
          widget.parentUid, widget.existing!.id!,
          approved: approved);
      if (mounted) {
        AppToast.success(context,
            '${widget.existing!.name} ${approved ? 'approved' : 'rejected'}');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _statusBanner() {
    final c = widget.existing!;
    final color = c.isVerified
        ? const Color(0xFF1A9E5C)
        : c.isRejected
            ? AppColors.error
            : const Color(0xFFE08A00);
    final text = c.isVerified
        ? 'Approved by our staff. Contact us to change the name or date of birth.'
        : c.isRejected
            ? 'Not approved by our staff — please contact us.'
            : 'Awaiting approval by our staff. You can still book classes for '
                'this child with your own credits; junior packages unlock once '
                'approved.';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
              c.isVerified
                  ? Icons.verified_outlined
                  : c.isRejected
                      ? Icons.block
                      : Icons.hourglass_top,
              color: color,
              size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textMuted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit child' : 'Add child'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: 'Remove',
              onPressed: _saving ? null : _remove,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
          children: [
            if (_isEdit) _statusBanner(),
            TextFormField(
              controller: _name,
              enabled: !_identityLocked,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration('Child\'s full name', Icons.person_outline),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _identityLocked ? null : _pickDob,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration:
                    _decoration('Date of birth', Icons.cake_outlined),
                child: Text(
                  _dob == null
                      ? 'Select (age ${DependentModel.minAge}–17)'
                      : '${_fmt(_dob!)} · age ${DependentModel(name: '', dateOfBirth: _dob!).ageOn()}',
                  style: TextStyle(
                      color: _dob == null
                          ? AppColors.textMuted
                          : AppColors.textPrimary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _relationship,
              decoration:
                  _decoration('Your relationship', Icons.family_restroom),
              items: const [
                DropdownMenuItem(value: 'Parent', child: Text('Parent')),
                DropdownMenuItem(
                    value: 'Legal guardian', child: Text('Legal guardian')),
              ],
              onChanged: (v) => setState(() => _relationship = v ?? 'Parent'),
            ),
            const SizedBox(height: 24),
            const Text('Emergency contact',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('Someone other than you we can call if needed.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emergencyName,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration('Contact name', Icons.contact_phone_outlined),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Emergency contact is required'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emergencyPhone,
              keyboardType: TextInputType.phone,
              decoration: _decoration('Contact phone', Icons.phone_outlined,
                  hint: 'e.g. +65 9123 4567'),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                return digits.length < 8 ? 'Enter a valid phone number' : null;
              },
            ),
            const SizedBox(height: 24),
            const Text('Medical information',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text(
                'Allergies, conditions, injuries or medication our trainers '
                'should know about. Only visible to you and our staff.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _medical,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Leave blank if none',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),
            if (!_isEdit)
              CheckboxListTile(
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  widget.staffMode
                      ? 'The parent or legal guardian has given consent for '
                          'this child\'s participation and for the collection '
                          'of the information above, and accepts the Terms & '
                          'Conditions on their behalf.'
                      : 'I am this child\'s parent or legal guardian. I consent '
                          'to their participation in sessions and to the '
                          'collection of the information above, and I accept '
                          'the Terms & Conditions on their behalf.',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isEdit ? 'Save Changes' : 'Add Child',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (widget.staffMode &&
                _isEdit &&
                !widget.existing!.isVerified) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => _setVerification(false),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : () => _setVerification(true),
                      child: const Text('Approve child'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
