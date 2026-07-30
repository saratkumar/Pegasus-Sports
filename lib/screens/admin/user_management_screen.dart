import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/config_service.dart';
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

  const _UserCard({
    required this.user,
    required this.onTap,
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
                  Text('${user.totalUsableCredits} credits',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                  if (user.hasUnrestrictedAccess) ...[
                    const SizedBox(width: 8),
                    _pill(
                        'Admin credit · exp '
                        '${_fmtDate(user.activeAdminGrant!.expiryDate)}',
                        const Color(0xFFFFAB40)),
                  ],
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

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
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
  late List<MembershipEntry> _memberships;
  bool _saving = false;
  bool _sendingReminder = false;

  @override
  void initState() {
    super.initState();
    _role = widget.user.role;
    _creditsCtrl =
        TextEditingController(text: widget.user.credits.toString());
    _memberships = List.of(widget.user.memberships);
  }

  @override
  void dispose() {
    _creditsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newCredits =
        int.tryParse(_creditsCtrl.text) ?? widget.user.credits;
    final creditDiff = newCredits - widget.user.credits;

    // Credit increases are recorded via a dedicated AdminCreditGrant field
    // (not a raw credits++) so they unlock unrestricted class booking and
    // carry a real expiry — kept separate from real purchased plans, see
    // AdminCreditGrant's doc comment in user_model.dart.
    DateTime? grantExpiry;
    if (creditDiff > 0) {
      grantExpiry = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 30)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
        helpText: 'Credit expiry date',
      );
      if (grantExpiry == null) return; // cancelled — abort, nothing saved
    }

    setState(() => _saving = true);

    await UserService.updateRole(
      widget.user.uid,
      _role,
      adminLevel: _role == 'admin' ? 'super_admin' : null,
      adminPermissions: const [],
    );

    if (creditDiff > 0) {
      await UserService.grantAdminCredit(
        widget.user.uid,
        creditDelta: creditDiff,
        expiryDate: grantExpiry!,
      );
    } else if (creditDiff < 0) {
      await UserService.addCredits(widget.user.uid, creditDiff);
    }

    if (creditDiff != 0) {
      final admin = FirebaseAuth.instance.currentUser;
      unawaited(ConfigService.logActivityEvent(
        eventType: 'Credit Adjusted by Admin',
        classId: '',
        className: '',
        sessionDate: DateTime.now(),
        sessionTime: '',
        userId: widget.user.uid,
        userName: widget.user.name,
        bookedByRole: 'admin',
        creditsUsed: creditDiff,
        note: '${creditDiff > 0 ? '+' : ''}$creditDiff credits by '
            '${admin?.displayName ?? admin?.email ?? 'admin'} '
            '(new total: $newCredits)'
            '${grantExpiry != null ? ', expires ${_fmtDate(grantExpiry)}' : ''}',
      ));
    }

    if (mounted) {
      Navigator.pop(context);
      AppToast.success(context, '${widget.user.name} updated');
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _editPlanDates(int index) async {
    final entry = _memberships[index];

    final newStart = await showDatePicker(
      context: context,
      initialDate: entry.startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '${entry.planName} — start date',
    );
    if (newStart == null || !mounted) return;

    final newEnd = await showDatePicker(
      context: context,
      initialDate:
          entry.endDate.isAfter(newStart) ? entry.endDate : newStart,
      firstDate: newStart,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '${entry.planName} — end date',
    );
    if (newEnd == null || !mounted) return;

    final updatedEntry = entry.copyWith(startDate: newStart, endDate: newEnd);
    final newList = List<MembershipEntry>.of(_memberships)
      ..[index] = updatedEntry;

    setState(() => _saving = true);
    await UserService.updateMemberships(widget.user.uid, newList);
    if (!mounted) return;
    setState(() {
      _memberships = newList;
      _saving = false;
    });
    AppToast.success(context, 'Plan dates updated');
  }

  /// Admin-only manual status override. Guarded against creating two
  /// simultaneously-`active` entries, since credit deduction/gating
  /// (UserService.deductCredit, UserModel.activeMembership) assumes at
  /// most one active plan at a time.
  Future<void> _setPlanStatus(int index, String newStatus) async {
    if (newStatus == 'active' &&
        _memberships.any((m) => m.isActive && m != _memberships[index])) {
      AppToast.error(context,
          'Another plan is already active — set it to expired first');
      return;
    }

    final newList = List<MembershipEntry>.of(_memberships)
      ..[index] = _memberships[index].copyWith(status: newStatus);

    setState(() => _saving = true);
    await UserService.updateMemberships(widget.user.uid, newList);
    if (!mounted) return;
    setState(() {
      _memberships = newList;
      _saving = false;
    });
    AppToast.success(context, 'Plan status updated');
  }

  static const _reminderSkipReasons = {
    'no-active-plan': 'No active plan to remind about',
    'already-queued': 'Already renewed — a plan is queued next',
    'no-email': 'This user has no email on file',
  };

  Future<void> _sendReminder() async {
    setState(() => _sendingReminder = true);
    try {
      final (sent, reason) =
          await UserService.sendRenewalReminderNow(widget.user.uid);
      if (!mounted) return;
      if (sent) {
        AppToast.success(context, 'Reminder sent to ${widget.user.name}');
      } else {
        AppToast.error(context,
            _reminderSkipReasons[reason] ?? 'Nothing to remind — $reason');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _sendingReminder = false);
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
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
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
            const Text('Admin-Granted Credits',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _creditsCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Admin credit pool',
                helperText:
                    'Current: ${widget.user.credits} — set new total. This '
                    'is separate from plan credits (see Plans below). '
                    'Raising it will ask for an expiry date and grant '
                    'unrestricted class access until then.',
                helperMaxLines: 4,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            if (_memberships.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Plans',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              ..._memberships.asMap().entries.map(
                    (e) => _PlanRow(
                      entry: e.value,
                      onEdit: _saving ? null : () => _editPlanDates(e.key),
                      onSetStatus: _saving
                          ? null
                          : (status) => _setPlanStatus(e.key, status),
                    ),
                  ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _sendingReminder ? null : _sendReminder,
                  icon: _sendingReminder
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.mail_outline, size: 16),
                  label: const Text('Send Renewal Reminder',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
            if (widget.user.hasUnrestrictedAccess) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFAB40).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFFFAB40).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.stars_rounded,
                        size: 16, color: Color(0xFFFFAB40)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Has admin-granted credits — unlocks any class '
                        'until ${_fmtDate(widget.user.activeAdminGrant!.expiryDate)}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFFFAB40),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

class _PlanRow extends StatelessWidget {
  final MembershipEntry entry;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onSetStatus;

  const _PlanRow({
    required this.entry,
    required this.onEdit,
    required this.onSetStatus,
  });

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Color get _statusColor {
    switch (entry.status) {
      case 'active':
        return AppColors.primary;
      case 'queued':
        return const Color(0xFFFFAB40);
      default:
        return AppColors.textMuted;
    }
  }

  String get _statusLabel {
    switch (entry.status) {
      case 'active':
        return 'Active';
      case 'queued':
        return 'Queued';
      default:
        return 'Expired';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(entry.planName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 6),
                    PopupMenuButton<String>(
                      enabled: onSetStatus != null,
                      onSelected: onSetStatus,
                      tooltip: 'Change status',
                      padding: EdgeInsets.zero,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'active', child: Text('Active')),
                        PopupMenuItem(value: 'queued', child: Text('Queued')),
                        PopupMenuItem(
                            value: 'expired', child: Text('Expired')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _statusLabel,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: _statusColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${_fmtDate(entry.startDate)} → ${_fmtDate(entry.endDate)} · '
                  '${entry.creditsRemaining}/${entry.credits} credits',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_calendar_outlined,
                size: 18, color: AppColors.primary),
            tooltip: 'Edit start/end date',
            visualDensity: VisualDensity.compact,
          ),
        ],
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
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
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
