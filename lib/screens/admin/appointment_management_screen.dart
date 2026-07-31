import 'package:flutter/material.dart';
import '../../models/appointment_model.dart';
import '../../services/appointment_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class AppointmentManagementScreen extends StatelessWidget {
  const AppointmentManagementScreen({super.key});

  Future<void> _openForm(BuildContext context,
      [AppointmentSlotModel? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _SlotFormScreen(existing: existing)),
    );
  }

  Future<void> _delete(
      BuildContext context, AppointmentSlotModel slot) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete "${slot.appointmentName}"?',
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text('This cannot be undone.',
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
    if (ok == true) {
      await AppointmentService.deleteSlot(slot.id!);
      if (context.mounted) AppToast.success(context, 'Slot deleted');
    }
  }

  Future<void> _forceRelease(
      BuildContext context, AppointmentSlotModel slot) async {
    await AppointmentService.forceRelease(slot.id!);
    if (context.mounted) {
      AppToast.success(context, '${slot.appointmentName} freed up');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appointment Slots')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Slot'),
      ),
      body: StreamBuilder<List<AppointmentSlotModel>>(
        stream: AppointmentService.streamSlots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final slots = snap.data ?? [];
          if (slots.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.event_available_outlined,
                      size: 56, color: AppColors.textMuted),
                  const SizedBox(height: 14),
                  const Text('No appointment slots yet',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 15)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Slot'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            itemCount: slots.length,
            itemBuilder: (_, i) => _SlotCard(
              slot: slots[i],
              onEdit: () => _openForm(context, slots[i]),
              onDelete: () => _delete(context, slots[i]),
              onForceRelease: () => _forceRelease(context, slots[i]),
            ),
          );
        },
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  final AppointmentSlotModel slot;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onForceRelease;

  const _SlotCard({
    required this.slot,
    required this.onEdit,
    required this.onDelete,
    required this.onForceRelease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFF7043).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_outline,
                color: Color(0xFFFF7043), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.appointmentName,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text('${slot.day} · ${slot.time} · Coach: ${slot.coach}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (slot.isFree
                            ? const Color(0xFF00D4AA)
                            : const Color(0xFFFFAB40))
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(slot.isFree ? 'Free' : 'Occupied',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: slot.isFree
                              ? const Color(0xFF00D4AA)
                              : const Color(0xFFFFAB40))),
                ),
              ],
            ),
          ),
          Column(children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  color: AppColors.primary, size: 20),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.error, size: 20),
              onPressed: onDelete,
            ),
            if (!slot.isFree)
              IconButton(
                icon: const Icon(Icons.lock_open_outlined,
                    color: AppColors.textMuted, size: 20),
                tooltip: 'Force free this slot',
                onPressed: onForceRelease,
              ),
          ]),
        ],
      ),
    );
  }
}

class _SlotFormScreen extends StatefulWidget {
  final AppointmentSlotModel? existing;
  const _SlotFormScreen({this.existing});

  @override
  State<_SlotFormScreen> createState() => _SlotFormScreenState();
}

class _SlotFormScreenState extends State<_SlotFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _day;
  late final TextEditingController _name;
  late final TextEditingController _coach;
  late final TextEditingController _time;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _day = TextEditingController(text: widget.existing?.day ?? '');
    _name =
        TextEditingController(text: widget.existing?.appointmentName ?? '');
    _coach = TextEditingController(text: widget.existing?.coach ?? '');
    _time = TextEditingController(text: widget.existing?.time ?? '');
  }

  @override
  void dispose() {
    _day.dispose();
    _name.dispose();
    _coach.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final slot = AppointmentSlotModel(
        day: _day.text.trim(),
        appointmentName: _name.text.trim(),
        coach: _coach.text.trim(),
        time: _time.text.trim(),
      );
      if (widget.existing == null) {
        await AppointmentService.createSlot(slot);
      } else {
        await AppointmentService.updateSlot(widget.existing!.id!, slot);
      }
      if (mounted) {
        Navigator.pop(context);
        AppToast.success(
            context, widget.existing == null ? 'Slot added' : 'Slot updated');
      }
    } catch (err) {
      setState(() => _saving = false);
      if (mounted) AppToast.error(context, err.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing == null ? 'New Slot' : 'Edit Slot')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
          children: [
            _field(_name, 'Appointment Name', required: true),
            const SizedBox(height: 12),
            _field(_day, 'Day (e.g. Monday)', required: true),
            const SizedBox(height: 12),
            _field(_time, 'Time (e.g. 3:00 PM)', required: true),
            const SizedBox(height: 12),
            _field(_coach, 'Coach', required: true),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(widget.existing == null ? 'Add Slot' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {bool required = false}) {
    return TextFormField(
      controller: ctrl,
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
}
