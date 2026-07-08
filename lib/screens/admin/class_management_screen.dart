import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../models/user_model.dart';
import '../../services/class_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class ClassManagementScreen extends StatelessWidget {
  const ClassManagementScreen({super.key});

  Future<void> _openForm(BuildContext context, [ClassModel? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ClassFormScreen(existing: existing)),
    );
  }

  Future<void> _delete(BuildContext context, ClassModel cls) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete Class?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
            'This will permanently remove the class. Existing bookings are unaffected.',
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
      await ClassService.deleteClass(cls.id!);
      if (context.mounted) AppToast.success(context, 'Class deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Classes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Class'),
      ),
      body: StreamBuilder<List<ClassModel>>(
        stream: ClassService.streamClasses(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
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
                    onPressed: () => _openForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Class'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            itemCount: classes.length,
            itemBuilder: (ctx, i) => _ClassCard(
              cls: classes[i],
              onEdit: () => _openForm(context, classes[i]),
              onDelete: () => _delete(context, classes[i]),
            ),
          );
        },
      ),
    );
  }
}

// ── Class card ────────────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  final ClassModel cls;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClassCard(
      {required this.cls, required this.onEdit, required this.onDelete});

  static const _abbr = {
    'Monday': 'Mon', 'Tuesday': 'Tue', 'Wednesday': 'Wed',
    'Thursday': 'Thu', 'Friday': 'Fri', 'Saturday': 'Sat', 'Sunday': 'Sun',
  };
  static const _ordered = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];

  static String _formatDay(String day, String occurrence) {
    if (occurrence == 'daily') { return 'Every day'; }
    if (occurrence == 'once') { return 'Once'; }
    if (occurrence == 'monthly') { return 'Monthly'; }
    final days = day.split(',').map((d) => d.trim()).where((d) => d.isNotEmpty).toSet();
    if (days.length == 7) { return 'Every day'; }
    if (days.length == 5 && !days.contains('Saturday') && !days.contains('Sunday')) { return 'Weekdays'; }
    if (days.length == 2 && days.contains('Saturday') && days.contains('Sunday')) { return 'Weekends'; }
    final sorted = _ordered.where(days.contains).map((d) => _abbr[d] ?? d).toList();
    return sorted.isEmpty ? day : sorted.join(', ');
  }

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
                Row(children: [
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
                ]),
                const SizedBox(height: 4),
                Text(
                    '${_formatDay(cls.day, cls.occurrence)} · ${cls.startTime} · ${cls.duration} · Cap: ${cls.groupSize}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text('${cls.location} · ${cls.coach}',
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
    );
  }
}

// ── Class form screen ─────────────────────────────────────────────────────────

class _ClassFormScreen extends StatefulWidget {
  final ClassModel? existing;
  const _ClassFormScreen({this.existing});

  @override
  State<_ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<_ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _mode;
  late final TextEditingController _startTime;
  late final TextEditingController _duration;
  late final TextEditingController _groupSize;
  late final TextEditingController _location;

  String _type = '';
  String? _selectedFacilityId;
  String? _selectedCoach;
  String _occurrence = 'weekly';
  Set<String> _selectedDays = {'Monday'};
  DateTime? _specificDate;
  bool _saving = false;
  bool _loadingData = true;

  List<Map<String, dynamic>> _facilities = [];
  List<Map<String, dynamic>> _types = [];
  List<UserModel> _coaches = [];
  Map<String, String> _typeImages = {};

  static const _weekdayOrder = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _mode = TextEditingController(text: e?.mode ?? '');
    _startTime = TextEditingController(text: e?.startTime ?? '');
    _duration = TextEditingController(text: e?.duration ?? '');
    _groupSize = TextEditingController(text: e?.groupSize ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _occurrence = e?.occurrence ?? 'weekly';
    _selectedFacilityId = e?.facilityId;
    _selectedCoach = e?.coach.isNotEmpty == true ? e!.coach : null;
    if (e != null && e.day.isNotEmpty) {
      final parsed = e.day
          .split(',')
          .map((d) => d.trim())
          .where((d) => d.isNotEmpty)
          .toSet();
      _selectedDays = parsed.isEmpty ? {'Monday'} : parsed;
    }
    if (e?.specificDate != null) {
      final parts = e!.specificDate!.split('-');
      if (parts.length == 3) {
        _specificDate = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    }
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ClassService.getFacilities(),
        ClassService.getClassTypes(),
        ClassService.getCoaches(),
      ]);
      if (!mounted) return;
      final facilities = results[0] as List<Map<String, dynamic>>;
      final types = results[1] as List<Map<String, dynamic>>;
      final coaches = results[2] as List<UserModel>;

      final typeImages = Map.fromEntries(
        types.map((t) => MapEntry(
            t['name']?.toString() ?? '', t['imageUrl']?.toString() ?? '')),
      );

      // Determine initial type
      final existingType = widget.existing?.type ?? '';
      String initialType;
      if (existingType.isNotEmpty &&
          types.any((t) => t['name'] == existingType)) {
        initialType = existingType;
      } else {
        initialType = types.isNotEmpty
            ? (types.first['name']?.toString() ?? '')
            : '';
      }

      setState(() {
        _facilities = facilities;
        _types = types;
        _coaches = coaches;
        _typeImages = typeImages;
        _type = initialType;
        _loadingData = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  @override
  void dispose() {
    _mode.dispose();
    _startTime.dispose();
    _duration.dispose();
    _groupSize.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final coachName = (_selectedCoach ?? '').trim();
    if (coachName.isEmpty) {
      AppToast.error(context, 'Please select a coach');
      return;
    }

    // Build day value
    final String dayValue;
    if (_occurrence == 'weekly') {
      final sorted = _weekdayOrder.where(_selectedDays.contains).toList();
      if (sorted.isEmpty) {
        AppToast.error(context, 'Select at least one day');
        return;
      }
      dayValue = sorted.join(',');
    } else if (_occurrence == 'daily') {
      dayValue = 'Daily';
    } else {
      dayValue = '';
    }

    setState(() => _saving = true);

    // Resolve location from facility or manual field
    final fac = _selectedFacilityId != null
        ? _facilities.firstWhere(
            (f) => f['id'] == _selectedFacilityId,
            orElse: () => {})
        : {};
    final locationLabel = fac.isNotEmpty
        ? (fac['name']?.toString() ?? _location.text.trim())
        : _location.text.trim();
    final detailLabel = fac.isNotEmpty
        ? (fac['address']?.toString() ?? '')
        : '';

    final specificDateStr = _specificDate != null
        ? '${_specificDate!.year}-'
            '${_specificDate!.month.toString().padLeft(2, '0')}-'
            '${_specificDate!.day.toString().padLeft(2, '0')}'
        : null;

    final cls = ClassModel(
      id: widget.existing?.id,
      day: dayValue,
      mode: _mode.text.trim(),
      coach: coachName,
      location: locationLabel,
      facilityId: _selectedFacilityId,
      groupSize: _groupSize.text.trim(),
      duration: _duration.text.trim(),
      detailLocation: detailLabel,
      startTime: _startTime.text.trim(),
      type: _type,
      image: _typeImages[_type] ?? '',
      occurrence: _occurrence,
      specificDate: specificDateStr,
    );

    try {
      if (widget.existing?.id != null) {
        await ClassService.updateClass(widget.existing!.id!, cls);
      } else {
        await ClassService.createClass(cls);
      }
      if (mounted) {
        Navigator.pop(context);
        AppToast.success(context,
            widget.existing == null ? 'Class created' : 'Class updated');
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
          title: Text(widget.existing == null ? 'New Class' : 'Edit Class')),
      body: _loadingData
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _field(_mode, 'Class Name', required: true),
                  const SizedBox(height: 12),
                  _typeDropdown(),
                  const SizedBox(height: 12),
                  _coachDropdown(),
                  const SizedBox(height: 12),
                  _facilityDropdown(),
                  const SizedBox(height: 12),
                  // Manual location — hidden if facility auto-fills it
                  if (_selectedFacilityId == null)
                    Column(children: [
                      _field(_location, 'Location (optional)'),
                      const SizedBox(height: 12),
                    ]),
                  _field(_startTime, 'Start Time (e.g. 7:00 PM)',
                      required: true),
                  const SizedBox(height: 12),
                  _field(_duration, 'Duration (e.g. 60 mins)', required: true),
                  const SizedBox(height: 12),
                  _field(_groupSize, 'Capacity',
                      required: true,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 16),
                  const Text('Occurrence',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  _OccurrencePicker(
                    value: _occurrence,
                    onChanged: (v) => setState(() {
                      _occurrence = v;
                      if (v != 'once' && v != 'monthly') _specificDate = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (_occurrence == 'weekly')
                    _WeekDayPicker(
                      selected: _selectedDays,
                      onChanged: (days) =>
                          setState(() => _selectedDays = days),
                    )
                  else if (_occurrence == 'daily')
                    const Row(children: [
                      Icon(Icons.info_outline,
                          size: 14, color: AppColors.textMuted),
                      SizedBox(width: 6),
                      Text('Runs every day',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                    ])
                  else
                    _datePicker(),
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

  // ── Sub-widgets ──────────────────────────────────────────────────────────

  Widget _typeDropdown() {
    if (_types.isEmpty) {
      return TextFormField(
        enabled: false,
        decoration: InputDecoration(
          labelText: 'Type (add types in Class Types screen first)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _type.isNotEmpty ? _type : null,
      decoration: InputDecoration(
        labelText: 'Type',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      items: _types
          .map((t) => DropdownMenuItem(
                value: t['name']?.toString() ?? '',
                child: Text(t['name']?.toString() ?? ''),
              ))
          .toList(),
      onChanged: (v) => setState(() => _type = v ?? _type),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Select a type' : null,
    );
  }

  Widget _coachDropdown() {
    // Build items — include existing coach name if it's not in the list
    final names = _coaches.map((c) => c.name).where((n) => n.isNotEmpty).toList();
    if (_selectedCoach != null &&
        _selectedCoach!.isNotEmpty &&
        !names.contains(_selectedCoach)) {
      names.insert(0, _selectedCoach!);
    }
    if (names.isEmpty) {
      return TextFormField(
        enabled: false,
        decoration: InputDecoration(
          labelText: 'Coach (no trainers or admins found in Firestore)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: (_selectedCoach != null && names.contains(_selectedCoach))
          ? _selectedCoach
          : null,
      decoration: InputDecoration(
        labelText: 'Coach',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        prefixIcon: const Icon(Icons.person_outline,
            size: 18, color: AppColors.textMuted),
      ),
      items: names
          .map((n) => DropdownMenuItem(value: n, child: Text(n)))
          .toList(),
      onChanged: (v) => setState(() => _selectedCoach = v),
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Select a coach' : null,
    );
  }

  Widget _facilityDropdown() {
    if (_facilities.isEmpty) {
      return TextFormField(
        enabled: false,
        decoration: InputDecoration(
          labelText: 'Facility (add in Facilities screen first)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedFacilityId,
      decoration: InputDecoration(
        labelText: 'Facility (optional)',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('— None —')),
        ..._facilities.map((f) => DropdownMenuItem(
              value: f['id']?.toString(),
              child: Text(f['name']?.toString() ?? ''),
            )),
      ],
      onChanged: (v) {
        setState(() => _selectedFacilityId = v);
        if (v == null) return;
        final fac = _facilities.firstWhere(
            (f) => f['id'] == v, orElse: () => {});
        if (fac.isNotEmpty && _location.text.trim().isEmpty) {
          _location.text = fac['name']?.toString() ?? '';
        }
      },
    );
  }

  Widget _datePicker() {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _specificDate ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) setState(() => _specificDate = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
              color: _specificDate == null
                  ? AppColors.error
                  : AppColors.divider),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined,
              size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(
            _specificDate == null
                ? (_occurrence == 'once'
                    ? 'Pick the class date *'
                    : 'Pick reference date *')
                : '${_specificDate!.day}/${_specificDate!.month}/${_specificDate!.year}',
            style: TextStyle(
              color: _specificDate == null
                  ? AppColors.textMuted
                  : AppColors.textPrimary,
              fontSize: 14,
            ),
          ),
        ]),
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

// ── Week-day multi-selector ───────────────────────────────────────────────────

class _WeekDayPicker extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const _WeekDayPicker({required this.selected, required this.onChanged});

  static const _full = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  static const _abbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Repeat on',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: List.generate(7, (i) {
            final day = _full[i];
            final lbl = _abbr[i];
            final sel = selected.contains(day);
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  final next = Set<String>.from(selected);
                  if (sel) {
                    if (next.length > 1) next.remove(day);
                  } else {
                    next.add(day);
                  }
                  onChanged(next);
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? AppColors.primary : AppColors.divider,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(lbl,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color:
                            sel ? Colors.white : AppColors.textSecondary,
                      )),
                ),
              ),
            );
          }),
        ),
        if (selected.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Select at least one day',
                style: TextStyle(fontSize: 11, color: AppColors.error)),
          ),
      ],
    );
  }
}

// ── Occurrence picker ─────────────────────────────────────────────────────────

class _OccurrencePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _OccurrencePicker({required this.value, required this.onChanged});

  static const _options = [
    ('weekly', Icons.repeat, 'Weekly'),
    ('daily', Icons.repeat_one, 'Daily'),
    ('monthly', Icons.calendar_view_month, 'Monthly'),
    ('once', Icons.looks_one_outlined, 'Once'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _options.map((opt) {
        final (key, icon, label) = opt;
        final selected = value == key;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(key),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
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
                      color:
                          selected ? AppColors.primary : AppColors.textMuted),
                  const SizedBox(height: 4),
                  Text(label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      )),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
