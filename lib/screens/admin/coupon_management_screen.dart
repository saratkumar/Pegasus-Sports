import 'package:flutter/material.dart';
import '../../models/coupon_model.dart';
import '../../services/coupon_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class CouponManagementScreen extends StatelessWidget {
  const CouponManagementScreen({super.key});

  Future<void> _openForm(BuildContext context, [CouponModel? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _CouponFormScreen(existing: existing)),
    );
  }

  Future<void> _delete(BuildContext context, CouponModel coupon) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Coupon?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
            'This will permanently remove "${coupon.code}". It will no longer be redeemable.',
            style: const TextStyle(color: AppColors.textSecondary)),
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
    if (ok == true && coupon.id != null) {
      await CouponService.deleteCoupon(coupon.id!);
      if (context.mounted) AppToast.success(context, 'Coupon deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coupons')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Coupon'),
      ),
      body: StreamBuilder<List<CouponModel>>(
        stream: CouponService.streamCoupons(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final coupons = snap.data ?? [];
          if (coupons.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_offer_outlined,
                      size: 56, color: AppColors.textMuted),
                  const SizedBox(height: 14),
                  const Text('No coupons yet',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 15)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Coupon'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            itemCount: coupons.length,
            itemBuilder: (ctx, i) => _CouponCard(
              coupon: coupons[i],
              onEdit: () => _openForm(context, coupons[i]),
              onDelete: () => _delete(context, coupons[i]),
            ),
          );
        },
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  final CouponModel coupon;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _CouponCard(
      {required this.coupon, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final valid = coupon.isValidNow;
    final valueLabel = coupon.discountType == 'percent'
        ? '${coupon.value.toStringAsFixed(coupon.value % 1 == 0 ? 0 : 1)}% off'
        : '\$${coupon.value.toStringAsFixed(2)} off';
    final usageLabel = coupon.maxRedemptions != null
        ? '${coupon.redeemedCount}/${coupon.maxRedemptions} used'
        : '${coupon.redeemedCount} used · unlimited';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: valid ? AppColors.card : AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: valid ? AppColors.divider : AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_offer_outlined,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(coupon.code,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.textPrimary)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (valid ? const Color(0xFF00D4AA) : AppColors.error)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                        valid
                            ? 'Active'
                            : (!coupon.isActive
                                ? 'Disabled'
                                : coupon.isExpired
                                    ? 'Expired'
                                    : 'Limit reached'),
                        style: TextStyle(
                            fontSize: 10,
                            color: valid ? const Color(0xFF00D4AA) : AppColors.error,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(valueLabel,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                    usageLabel +
                        (coupon.expiresAt != null
                            ? ' · expires ${_fmt(coupon.expiresAt!)}'
                            : ''),
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
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
    );
  }

  String _fmt(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}

// ── Coupon form screen ────────────────────────────────────────────────────────

class _CouponFormScreen extends StatefulWidget {
  final CouponModel? existing;
  const _CouponFormScreen({this.existing});

  @override
  State<_CouponFormScreen> createState() => _CouponFormScreenState();
}

class _CouponFormScreenState extends State<_CouponFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _value;
  late final TextEditingController _maxRedemptions;
  String _discountType = 'percent';
  DateTime? _expiresAt;
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _code = TextEditingController(text: e?.code ?? '');
    _value = TextEditingController(text: e != null ? e.value.toString() : '');
    _maxRedemptions =
        TextEditingController(text: e?.maxRedemptions?.toString() ?? '');
    _discountType = e?.discountType ?? 'percent';
    _expiresAt = e?.expiresAt;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _maxRedemptions.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final coupon = CouponModel(
      id: widget.existing?.id,
      code: _code.text.trim(),
      discountType: _discountType,
      value: double.tryParse(_value.text.trim()) ?? 0,
      isActive: _isActive,
      maxRedemptions: _maxRedemptions.text.trim().isEmpty
          ? null
          : int.tryParse(_maxRedemptions.text.trim()),
      expiresAt: _expiresAt,
    );

    try {
      if (widget.existing?.id != null) {
        await CouponService.updateCoupon(widget.existing!.id!, coupon);
      } else {
        await CouponService.createCoupon(coupon);
      }
      if (mounted) {
        Navigator.pop(context);
        AppToast.success(context,
            widget.existing == null ? 'Coupon created' : 'Coupon updated');
      }
    } catch (err) {
      setState(() => _saving = false);
      if (mounted) {
        AppToast.error(context, err.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Coupon' : 'New Coupon')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _code,
              enabled: !isEdit,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Coupon Code',
                helperText: isEdit ? null : 'e.g. WELCOME20 — not case sensitive',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            const Text('Discount Type',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _typeChip('percent', 'Percentage', Icons.percent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _typeChip('fixed', 'Fixed Amount', Icons.attach_money),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _discountType == 'percent'
                    ? 'Discount Percentage (e.g. 20)'
                    : 'Discount Amount (e.g. 10.00)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Enter a value greater than 0';
                if (_discountType == 'percent' && n > 100) {
                  return 'Percentage cannot exceed 100';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _maxRedemptions,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Max total redemptions (blank = unlimited)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _pickExpiry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.event_outlined,
                      size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _expiresAt == null
                          ? 'No expiration date'
                          : 'Expires ${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year}',
                      style: TextStyle(
                        color: _expiresAt == null
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (_expiresAt != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _expiresAt = null),
                    ),
                ]),
              ),
            ),
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
              subtitle: const Text('Disabled coupons cannot be redeemed by clients',
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
                  : Text(isEdit ? 'Save Changes' : 'Create Coupon'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String value, String label, IconData icon) {
    final selected = _discountType == value;
    return GestureDetector(
      onTap: () => setState(() => _discountType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? AppColors.primary : AppColors.textMuted),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                )),
          ],
        ),
      ),
    );
  }
}
