import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../models/facility_model.dart';
import '../../services/class_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class ClassManagementScreen extends StatelessWidget {
  const ClassManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Classes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, null),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Class'),
      ),
      body: StreamBuilder<List<ClassModel>>(
        stream: ClassService.streamClasses(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final classes = snap.data ?? [];
          if (classes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fitness_center,
                      size: 56, color: AppColors.textMuted),
                  const SizedBox(height: 14),
                  const Text('No classes yet',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 15)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(context, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Class'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: classes.length,
            itemBuilder: (context, i) => _ClassCard(
              cls: classes[i],
              onEdit: () => _openForm(context, classes[i]),
              onDelete: () => _delete(context, classes[i].id!),
            ),
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, ClassModel? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ClassFormScreen(existing: existing)),
    );
  }

  Future<void> _delete(BuildContext context, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Class?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
            'This will hide the class. Existing bookings are unaffected.',
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
      await ClassService.deleteClass(id);
      if (context.mounted) AppToast.success(context, 'Class deleted');
    }
  }
}

class _ClassCard extends StatelessWidget {
  final ClassModel cls;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClassCard(
      {required this.cls, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
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
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.fitness_center,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(cls.mode,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(cls.type,
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    '${cls.day} · ${cls.startTime} · ${cls.duration} · Cap: ${cls.groupSize}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text('${cls.location} · ${cls.coach}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          Column(
            children: [
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
            ],
          ),
        ],
      ),
    );
  }
}

// ── Class form screen ────────────────────────────────────────────────────────

class _ClassFormScreen extends StatefulWidget {
  final ClassModel? existing;
  const _ClassFormScreen({this.existing});

  @override
  State<_ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<_ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _mode;
  late final TextEditingController _coach;
  late final TextEditingController _location;
  late final TextEditingController _detailLocation;
  late final TextEditingController _groupSize;
  late final TextEditingController _duration;
  late final TextEditingController _startTime;
  late final TextEditingController _image;

  String _day = 'Monday';
  String _type = 'Fitness';
  String? _facilityId;
  List<FacilityModel> _facilities = [];
  bool _saving = false;

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];
  static const _types = [
    'Fitness', 'Boxing', 'Yoga', 'Group PT', 'Muay Thai', 'Kids'
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _mode = TextEditingController(text: e?.mode ?? '');
    _coach = TextEditingController(text: e?.coach ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _detailLocation = TextEditingController(text: e?.detailLocation ?? '');
    _groupSize = TextEditingController(text: e?.groupSize ?? '');
    _duration = TextEditingController(text: e?.duration ?? '');
    _startTime = TextEditingController(text: e?.startTime ?? '');
    _image = TextEditingController(text: e?.image ?? '');
    _day = e?.day ?? 'Monday';
    _type = e?.type ?? 'Fitness';
    _facilityId = e?.facilityId;
    _loadFacilities();
  }

  @override
  void dispose() {
    for (final c in [
      _mode, _coach, _location, _detailLocation,
      _groupSize, _duration, _startTime, _image
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFacilities() async {
    final snap = await FirebaseFirestore.instance
        .collection('facilities')
        .where('isActive', isEqualTo: true)
        .get();
    setState(() {
      _facilities = snap.docs.map(FacilityModel.fromFirestore).toList();
      // keep _facilityId in sync if it no longer exists in facilities list
      if (_facilityId != null &&
          _facilities.every((f) => f.id != _facilityId)) {
        _facilityId = null;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final cls = ClassModel(
      id: widget.existing?.id,
      day: _day,
      mode: _mode.text.trim(),
      coach: _coach.text.trim(),
      location: _location.text.trim(),
      facilityId: _facilityId,
      groupSize: _groupSize.text.trim(),
      duration: _duration.text.trim(),
      detailLocation: _detailLocation.text.trim(),
      startTime: _startTime.text.trim(),
      type: _type,
      image: _image.text.trim(),
    );

    if (widget.existing == null) {
      await ClassService.createClass(cls);
    } else {
      await ClassService.updateClass(widget.existing!.id!, cls);
    }

    if (mounted) {
      Navigator.pop(context);
      AppToast.success(context,
          widget.existing == null ? 'Class created' : 'Class updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.existing == null ? 'New Class' : 'Edit Class')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _dropdown('Day', _days, _day, (v) => setState(() => _day = v!)),
            const SizedBox(height: 12),
            _field(_mode, 'Class Name', required: true),
            const SizedBox(height: 12),
            _dropdown('Type', _types, _type,
                (v) => setState(() => _type = v!)),
            const SizedBox(height: 12),
            _field(_coach, 'Coach', required: true),
            const SizedBox(height: 12),
            _field(_startTime, 'Start Time (e.g. 6:30 AM)', required: true),
            const SizedBox(height: 12),
            _field(_duration, 'Duration (e.g. 60 mins)', required: true),
            const SizedBox(height: 12),
            _field(_groupSize, 'Capacity', required: true,
                keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            // Facility dropdown
            if (_facilities.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _facilityId,
                decoration: InputDecoration(
                  labelText: 'Facility (optional)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('None')),
                  ..._facilities.map((f) => DropdownMenuItem(
                      value: f.id, child: Text(f.name))),
                ],
                onChanged: (v) => setState(() => _facilityId = v),
              ),
            if (_facilities.isNotEmpty) const SizedBox(height: 12),
            _field(_location, 'Short Location Label', required: true),
            const SizedBox(height: 12),
            _field(_detailLocation, 'Detail Location / Address',
                required: true),
            const SizedBox(height: 12),
            _field(_image, 'Image URL (optional)'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(widget.existing == null
                      ? 'Create Class'
                      : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
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
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }

  Widget _dropdown(String label, List<String> options, String value,
      ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
