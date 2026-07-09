import 'package:flutter/material.dart';
import '../../models/membership_plan_model.dart';
import '../../services/membership_plan_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../utils/plan_category_style.dart';

class PlanManagementScreen extends StatefulWidget {
  const PlanManagementScreen({super.key});

  @override
  State<PlanManagementScreen> createState() => _PlanManagementScreenState();
}

class _PlanManagementScreenState extends State<PlanManagementScreen> {
  @override
  void initState() {
    super.initState();
    MembershipPlanService.ensureSeeded();
  }

  Future<void> _openForm(BuildContext context, [MembershipPlanModel? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PlanFormScreen(existing: existing)),
    );
  }

  Future<void> _delete(BuildContext context, MembershipPlanModel plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Plan?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
            'This will permanently remove the plan. Members who already purchased it keep their existing credits/validity.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.primary))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && plan.id != null) {
      await MembershipPlanService.deletePlan(plan.id!);
      if (context.mounted) AppToast.success(context, 'Plan deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Membership Plans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Plan'),
      ),
      body: StreamBuilder<List<MembershipPlanModel>>(
        stream: MembershipPlanService.streamPlans(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final plans = snap.data ?? [];
          if (plans.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.card_membership_outlined,
                      size: 56, color: AppColors.textMuted),
                  const SizedBox(height: 14),
                  const Text('No plans yet',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 15)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Plan'),
                  ),
                ],
              ),
            );
          }
          final byCategory = <String, List<MembershipPlanModel>>{};
          for (final p in plans) {
            byCategory.putIfAbsent(p.category, () => []).add(p);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            children: byCategory.entries.map((entry) {
              final style = PlanCategoryStyle.of(entry.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(style.icon, size: 16, color: style.color),
                      const SizedBox(width: 8),
                      Text(entry.key,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: style.color,
                              letterSpacing: 0.4)),
                    ]),
                    const SizedBox(height: 8),
                    ...entry.value.map((plan) => _PlanCard(
                          plan: plan,
                          color: style.color,
                          onEdit: () => _openForm(context, plan),
                          onDelete: () => _delete(context, plan),
                        )),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ── Plan card ────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final MembershipPlanModel plan;
  final Color color;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PlanCard(
      {required this.plan,
      required this.color,
      required this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final active = plan.isActive;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active ? AppColors.card : AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: active ? AppColors.divider : AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Opacity(
        opacity: active ? 1 : 0.7,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.card_membership, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(plan.name,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (active ? const Color(0xFF00D4AA) : AppColors.error)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(active ? 'Active' : 'Inactive',
                          style: TextStyle(
                              fontSize: 10,
                              color: active
                                  ? const Color(0xFF00D4AA)
                                  : AppColors.error,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(plan.subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                      '\$${plan.price.toStringAsFixed(2)}${plan.priceLabel ?? ''} · '
                      '${plan.credits} credits · '
                      '${plan.validityDays > 0 ? '${plan.validityDays}d validity' : 'no expiry'}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            Column(children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    color: AppColors.primary, size: 20),
                onPressed: onEdit,
                tooltip: 'Edit',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 20),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Plan form screen ──────────────────────────────────────────────────────────

class _PlanFormScreen extends StatefulWidget {
  final MembershipPlanModel? existing;
  const _PlanFormScreen({this.existing});

  @override
  State<_PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends State<_PlanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _category;
  late final TextEditingController _name;
  late final TextEditingController _subtitle;
  late final TextEditingController _price;
  late final TextEditingController _priceLabel;
  late final TextEditingController _credits;
  late final TextEditingController _validityDays;
  late final TextEditingController _badge;
  late final TextEditingController _featureInput;
  late List<String> _features;
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _category = TextEditingController(text: e?.category ?? '');
    _name = TextEditingController(text: e?.name ?? '');
    _subtitle = TextEditingController(text: e?.subtitle ?? '');
    _price = TextEditingController(text: e != null ? e.price.toString() : '');
    _priceLabel = TextEditingController(text: e?.priceLabel ?? '');
    _credits = TextEditingController(text: e != null ? e.credits.toString() : '');
    _validityDays =
        TextEditingController(text: e != null ? e.validityDays.toString() : '');
    _badge = TextEditingController(text: e?.badge ?? '');
    _featureInput = TextEditingController();
    _features = List<String>.from(e?.features ?? []);
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _category.dispose();
    _name.dispose();
    _subtitle.dispose();
    _price.dispose();
    _priceLabel.dispose();
    _credits.dispose();
    _validityDays.dispose();
    _badge.dispose();
    _featureInput.dispose();
    super.dispose();
  }

  void _addFeature() {
    final text = _featureInput.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _features.add(text);
      _featureInput.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final plan = MembershipPlanModel(
      id: widget.existing?.id,
      category: _category.text.trim(),
      name: _name.text.trim(),
      subtitle: _subtitle.text.trim(),
      price: double.tryParse(_price.text.trim()) ?? 0,
      priceLabel: _priceLabel.text.trim().isEmpty ? null : _priceLabel.text.trim(),
      credits: int.tryParse(_credits.text.trim()) ?? 0,
      validityDays: int.tryParse(_validityDays.text.trim()) ?? 0,
      badge: _badge.text.trim().isEmpty ? null : _badge.text.trim(),
      features: _features,
      order: 0,
      isActive: _isActive,
    );

    try {
      if (widget.existing?.id != null) {
        await MembershipPlanService.updatePlan(widget.existing!.id!, plan);
      } else {
        await MembershipPlanService.createPlan(plan);
      }
      if (mounted) {
        Navigator.pop(context);
        AppToast.success(context,
            widget.existing == null ? 'Plan created' : 'Plan updated');
      }
    } catch (err) {
      setState(() => _saving = false);
      if (mounted) AppToast.error(context, err.toString());
    }
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null ? 'New Plan' : 'Edit Plan')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_category, 'Category (e.g. Credits, Monthly)', required: true),
            const SizedBox(height: 12),
            _field(_name, 'Plan Name', required: true),
            const SizedBox(height: 12),
            _field(_subtitle, 'Subtitle', required: true),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: _field(_price, 'Price',
                      required: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true))),
              const SizedBox(width: 12),
              Expanded(child: _field(_priceLabel, 'Price Label (e.g. /mo)')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: _field(_credits, 'Credits',
                      required: true, keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(
                  child: _field(_validityDays, 'Validity Days (0 = no expiry)',
                      required: true, keyboardType: TextInputType.number)),
            ]),
            const SizedBox(height: 12),
            _field(_badge, 'Badge (optional, e.g. Popular)'),
            const SizedBox(height: 16),
            const Text('Features',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _featureInput,
                  decoration: InputDecoration(
                    hintText: 'Add a feature bullet',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  onFieldSubmitted: (_) => _addFeature(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_circle,
                    color: AppColors.primary, size: 28),
                onPressed: _addFeature,
              ),
            ]),
            if (_features.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _features
                    .map((f) => Chip(
                          label: Text(f, style: const TextStyle(fontSize: 12)),
                          onDeleted: () => setState(() => _features.remove(f)),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              activeThumbColor: const Color(0xFF00D4AA),
              title: const Text('Active',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              subtitle: const Text(
                  'Inactive plans are hidden from clients but keep working for members who already own them',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(widget.existing == null ? 'Create Plan' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}
