import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// "Bringing anyone?" — lets a member add up to [maxGuests] friends by name,
/// each booked on one of the member's own credits. When [memberAlreadyBooked]
/// is false the member's own spot is included in the credit total and an
/// empty list ("just me") is a valid answer. Returns the guest names, or
/// null if cancelled.
Future<List<String>?> pickGuests(
  BuildContext context, {
  required String className,
  required int maxGuests,
  required bool memberAlreadyBooked,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _GuestSheet(
      className: className,
      maxGuests: maxGuests,
      memberAlreadyBooked: memberAlreadyBooked,
    ),
  );
}

class _GuestSheet extends StatefulWidget {
  final String className;
  final int maxGuests;
  final bool memberAlreadyBooked;

  const _GuestSheet({
    required this.className,
    required this.maxGuests,
    required this.memberAlreadyBooked,
  });

  @override
  State<_GuestSheet> createState() => _GuestSheetState();
}

class _GuestSheetState extends State<_GuestSheet> {
  final List<TextEditingController> _names = [];
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Adding friends to an existing booking only makes sense with one.
    if (widget.memberAlreadyBooked) _addGuest();
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _addGuest() => setState(() => _names.add(TextEditingController()));

  void _removeGuest(int i) => setState(() => _names.removeAt(i).dispose());

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _names.map((c) => c.text.trim()).toList());
  }

  @override
  Widget build(BuildContext context) {
    final credits = _names.length + (widget.memberAlreadyBooked ? 0 : 1);
    final canAddMore = _names.length < widget.maxGuests;
    final String action;
    if (widget.memberAlreadyBooked) {
      action = 'Add ${_names.length} friend${_names.length == 1 ? '' : 's'}';
    } else if (_names.isEmpty) {
      action = 'Book just me';
    } else {
      action = 'Book for ${_names.length + 1}';
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    widget.memberAlreadyBooked
                        ? 'Bring friends to ${widget.className}'
                        : 'Bringing anyone?',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'Each friend uses 1 of your credits. '
                  'You can bring up to ${widget.maxGuests}.',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < _names.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _names[i],
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Friend ${i + 1} name',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter a name'
                                : null,
                          ),
                        ),
                        if (!widget.memberAlreadyBooked || _names.length > 1)
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () => _removeGuest(i),
                            icon: const Icon(Icons.close,
                                color: AppColors.textMuted),
                          ),
                      ],
                    ),
                  ),
                if (canAddMore)
                  TextButton.icon(
                    onPressed: _addGuest,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: Text(_names.isEmpty ? 'Add a friend' : 'Add another friend'),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _names.isEmpty && widget.memberAlreadyBooked
                        ? null
                        : _submit,
                    child: Text(
                        '$action · $credits credit${credits == 1 ? '' : 's'}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
