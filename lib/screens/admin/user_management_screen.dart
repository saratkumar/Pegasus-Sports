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

                // Filter by role
                if (_roleFilter != 'all') {
                  users =
                      users.where((u) => u.role == _roleFilter).toList();
                }

                // Filter by search
                if (_search.isNotEmpty) {
                  final q = _search.toLowerCase();
                  users = users
                      .where((u) =>
                          u.name.toLowerCase().contains(q) ||
                          u.email.toLowerCase().contains(q))
                      .toList();
                }

                // Hide current admin from list to avoid self-edit
                final me = FirebaseAuth.instance.currentUser?.uid;
                users = users.where((u) => u.uid != me).toList();

                if (users.isEmpty) {
                  return const Center(
                    child: Text('No users found',
                        style:
                            TextStyle(color: AppColors.textSecondary)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: users.length,
                  itemBuilder: (context, i) => _UserCard(
                    user: users[i],
                    onEdit: () => _openEditSheet(context, users[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
}

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
              prefixIcon:
                  const Icon(Icons.search, size: 18, color: AppColors.textMuted),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.divider)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.divider)),
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
                          label: Text(r == 'all' ? 'All' : _capitalize(r)),
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

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onEdit;

  const _UserCard({required this.user, required this.onEdit});

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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _roleColor.withValues(alpha: 0.15),
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: _roleColor, fontWeight: FontWeight.w700, fontSize: 16),
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
                        fontSize: 11, color: AppColors.textMuted)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _pill(user.role, _roleColor),
                    if (user.adminLevel != null) ...[
                      const SizedBox(width: 6),
                      _pill(user.adminLevel!, AppColors.error),
                    ],
                    const SizedBox(width: 6),
                    _pill('${user.credits} cr', AppColors.textSecondary),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: AppColors.primary, size: 20),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Edit sheet ───────────────────────────────────────────────────────────────

class _UserEditSheet extends StatefulWidget {
  final UserModel user;
  const _UserEditSheet({required this.user});

  @override
  State<_UserEditSheet> createState() => _UserEditSheetState();
}

class _UserEditSheetState extends State<_UserEditSheet> {
  late String _role;
  late String? _adminLevel;
  late List<String> _permissions;
  late TextEditingController _creditsCtrl;
  bool _saving = false;

  static const _allPermissions = [
    'manage_classes',
    'manage_facilities',
    'manage_users',
    'manage_credits',
    'approve_requests',
  ];

  @override
  void initState() {
    super.initState();
    _role = widget.user.role;
    _adminLevel = widget.user.adminLevel;
    _permissions = List.from(widget.user.adminPermissions);
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
    final newCredits = int.tryParse(_creditsCtrl.text) ?? widget.user.credits;
    final creditDiff = newCredits - widget.user.credits;

    await UserService.updateRole(
      widget.user.uid,
      _role,
      adminLevel: _role == 'admin' ? _adminLevel : null,
      adminPermissions: _role == 'admin' ? _permissions : [],
    );

    if (creditDiff != 0) {
      await UserService.addCredits(widget.user.uid, creditDiff);
    }

    if (mounted) {
      Navigator.pop(context);
      AppToast.success(context, '${widget.user.name} updated');
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
            Text(widget.user.name,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            Text(widget.user.email,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 20),
            const Text('Role',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            _RoleSelector(
              selected: _role,
              onChanged: (r) => setState(() {
                _role = r;
                if (r != 'admin') {
                  _adminLevel = null;
                  _permissions = [];
                }
              }),
            ),
            if (_role == 'admin') ...[
              const SizedBox(height: 16),
              const Text('Admin Level',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['super_admin', 'admin'].map((level) {
                  final selected = _adminLevel == level;
                  return ChoiceChip(
                    label: Text(level == 'super_admin'
                        ? 'Super Admin'
                        : 'Admin'),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _adminLevel = level),
                  );
                }).toList(),
              ),
              if (_adminLevel != 'super_admin') ...[
                const SizedBox(height: 16),
                const Text('Permissions',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                ..._allPermissions.map((p) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.replaceAll('_', ' '),
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary)),
                      value: _permissions.contains(p),
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _permissions.add(p);
                        } else {
                          _permissions.remove(p);
                        }
                      }),
                    )),
              ],
            ],
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

class _RoleSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _RoleSelector({required this.selected, required this.onChanged});

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
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? color : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
