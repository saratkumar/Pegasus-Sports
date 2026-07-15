import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  String _search = '';
  String _roleFilter = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateSheet(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add User'),
      ),
      body: Column(
        children: [
          _Filters(
            search: _search,
            roleFilter: _roleFilter,
            onSearch: (v) => setState(() => _search = v),
            onRole: (v) => setState(() => _roleFilter = v),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary));
                }
                var docs = snap.data?.docs ?? [];
                var users = docs
                    .map((d) => UserModel.fromFirestore(
                        d.data() as Map<String, dynamic>, d.id))
                    .toList();

                if (_roleFilter != 'all') {
                  users =
                      users.where((u) => u.role == _roleFilter).toList();
                }
                if (_search.isNotEmpty) {
                  final q = _search.toLowerCase();
                  users = users
                      .where((u) =>
                          u.name.toLowerCase().contains(q) ||
                          u.email.toLowerCase().contains(q))
                      .toList();
                }

                final me = FirebaseAuth.instance.currentUser?.uid;
                users = users.where((u) => u.uid != me).toList();

                if (users.isEmpty) {
                  return const Center(
                    child: Text('No users found',
                        style: TextStyle(color: AppColors.textSecondary)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: users.length,
                  itemBuilder: (context, i) => _UserCard(
                    user: users[i],
                    onTap: () => _openEditSheet(context, users[i]),
                    onQuickCredit: (delta) =>
                        _quickCredit(context, users[i], delta),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CreateUserSheet(),
    );
  }

  void _openEditSheet(BuildContext context, UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _UserEditSheet(user: user),
    );
  }

  Future<void> _quickCredit(
      BuildContext context, UserModel user, int delta) async {
    await UserService.addCredits(user.uid, delta);
    if (context.mounted) {
      AppToast.success(
          context,
          delta > 0
              ? '+$delta credits added to ${user.name}'
              : '${delta.abs()} credits removed from ${user.name}');
    }
  }
}

// ── Filters ──────────────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  final String search;
  final String roleFilter;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onRole;

  const _Filters({
    required this.search,
    required this.roleFilter,
    required this.onSearch,
    required this.onRole,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      color: AppColors.bg,
      child: Column(
        children: [
          TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Search by name or email...',
              prefixIcon: const Icon(Icons.search,
                  size: 18, color: AppColors.textMuted),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.divider)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.divider)),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['all', 'client', 'trainer', 'admin']
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(r == 'all'
                              ? 'All'
                              : r[0].toUpperCase() + r.substring(1)),
                          selected: roleFilter == r,
                          onSelected: (_) => onRole(r),
                          selectedColor:
                              AppColors.primary.withValues(alpha: 0.15),
                          labelStyle: TextStyle(
                            color: roleFilter == r
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontWeight: roleFilter == r
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── User card ─────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  final void Function(int delta) onQuickCredit;

  const _UserCard({
    required this.user,
    required this.onTap,
    required this.onQuickCredit,
  });

  Color get _roleColor {
    switch (user.role) {
      case 'admin':
        return AppColors.error;
      case 'trainer':
        return const Color(0xFF00D4AA);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            // Main row
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor:
                        _roleColor.withValues(alpha: 0.15),
                    child: Text(
                      user.name.isNotEmpty
                          ? user.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          color: _roleColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                fontSize: 14)),
                        Text(user.email,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted)),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 5,
                          children: [
                            _pill(
                                user.role[0].toUpperCase() +
                                    user.role.substring(1),
                                _roleColor),
                            if (user.adminLevel != null)
                              _pill(
                                  user.adminLevel == 'super_admin'
                                      ? 'Super Admin'
                                      : 'Admin',
                                  AppColors.error),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Edit indicator
                  Column(
                    children: [
                      const Icon(Icons.chevron_right,
                          color: AppColors.textMuted, size: 20),
                      const SizedBox(height: 2),
                      Text('Edit',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted
                                  .withValues(alpha: 0.7))),
                    ],
                  ),
                ],
              ),
            ),
            // Credit bar
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.toll_outlined,
                      size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Text('${user.credits} credits',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                  const Spacer(),
                  // Quick credit buttons
                  _creditBtn(context, -10, AppColors.error),
                  const SizedBox(width: 6),
                  _creditBtn(context, 10, const Color(0xFF00D4AA)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _creditBtn(BuildContext context, int delta, Color color) {
    return GestureDetector(
      onTap: () => onQuickCredit(delta),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          delta >= 0 ? '+$delta' : '$delta',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color),
        ),
      ),
    );
  }
}

// ── Edit sheet ────────────────────────────────────────────────────────────────

class _UserEditSheet extends StatefulWidget {
  final UserModel user;
  const _UserEditSheet({required this.user});

  @override
  State<_UserEditSheet> createState() => _UserEditSheetState();
}

class _UserEditSheetState extends State<_UserEditSheet> {
  late String _role;
  late TextEditingController _creditsCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _role = widget.user.role;
    _creditsCtrl =
        TextEditingController(text: widget.user.credits.toString());
  }

  @override
  void dispose() {
    _creditsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final newCredits =
        int.tryParse(_creditsCtrl.text) ?? widget.user.credits;
    final creditDiff = newCredits - widget.user.credits;

    await UserService.updateRole(
      widget.user.uid,
      _role,
      adminLevel: _role == 'admin' ? 'super_admin' : null,
      adminPermissions: const [],
    );

    if (creditDiff != 0) {
      await UserService.addCredits(widget.user.uid, creditDiff);
    }

    if (mounted) {
      Navigator.pop(context);
      AppToast.success(context, '${widget.user.name} updated');
    }
  }

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate User?'),
        content: Text(
            'This will block ${widget.user.name} from logging in. '
            'Their data is preserved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              child: const Text('Deactivate')),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .update({'isActive': false});
      if (mounted) {
        Navigator.pop(context);
        AppToast.success(context, '${widget.user.name} deactivated');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.user.name,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      Text(widget.user.email,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _deactivate,
                  icon: const Icon(Icons.block,
                      size: 16, color: AppColors.error),
                  label: const Text('Deactivate',
                      style: TextStyle(
                          color: AppColors.error, fontSize: 12)),
                ),
              ],
            ),
            const Divider(height: 28),
            // Role
            const Text('Role',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            _RoleSelector(
              selected: _role,
              onChanged: (r) => setState(() => _role = r),
            ),
            const SizedBox(height: 16),
            const Text('Credits',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _creditsCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Credit balance',
                helperText:
                    'Current: ${widget.user.credits} — set new total',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create user sheet ─────────────────────────────────────────────────────────

class _CreateUserSheet extends StatefulWidget {
  const _CreateUserSheet();

  @override
  State<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends State<_CreateUserSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String _role = 'client';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await UserService.createInvitation(
        email: _email.text.trim(),
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        role: _role,
        initialCredits: 0,
        adminLevel: _role == 'admin' ? 'super_admin' : null,
      );
      if (mounted) {
        Navigator.pop(context);
        AppToast.success(context,
            'Invitation created — ${_name.text.trim()} can now sign in with Google');
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) AppToast.error(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add User',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              const Text(
                'Creates an invitation — the role applies when they first sign in with Google.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              _field(_name, 'Full Name', required: true,
                  icon: Icons.person_outline),
              const SizedBox(height: 12),
              _field(_email, 'Email (Google account they will use)',
                  required: true,
                  icon: Icons.email_outlined,
                  keyboard: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  }),
              const SizedBox(height: 12),
              _field(_phone, 'Mobile Number',
                  required: true,
                  icon: Icons.phone_outlined,
                  keyboard: TextInputType.phone),
              const SizedBox(height: 16),
              const Text('Role',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              _RoleSelector(
                selected: _role,
                onChanged: (r) => setState(() => _role = r),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Create Invitation'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    IconData? icon,
    TextInputType keyboard = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null
            ? Icon(icon, size: 18, color: AppColors.textMuted)
            : null,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: validator ??
          (required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _RoleSelector(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['client', 'trainer', 'admin'].map((role) {
        final isSelected = selected == role;
        final color = role == 'admin'
            ? AppColors.error
            : role == 'trainer'
                ? const Color(0xFF00D4AA)
                : AppColors.primary;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(role),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.15)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? color.withValues(alpha: 0.6)
                      : AppColors.divider,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                role[0].toUpperCase() + role.substring(1),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: isSelected
                      ? color
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
