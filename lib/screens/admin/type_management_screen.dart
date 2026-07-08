import 'package:flutter/material.dart';
import '../../services/class_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class TypeManagementScreen extends StatelessWidget {
  const TypeManagementScreen({super.key});

  Future<void> _openForm(BuildContext context,
      [Map<String, dynamic>? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => _TypeFormScreen(existing: existing)),
    );
  }

  Future<void> _delete(
      BuildContext context, Map<String, dynamic> type) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete "${type['name']}"?',
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
            'Classes using this type will keep their current type value.',
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
      await ClassService.deleteClassType(type['id'] as String);
      if (context.mounted) AppToast.success(context, 'Type deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Class Types')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Type'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: ClassService.streamClassTypes(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final types = snap.data ?? [];
          if (types.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.category_outlined,
                      size: 56, color: AppColors.textMuted),
                  const SizedBox(height: 14),
                  const Text('No types yet',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text('Add types like Fitness, Boxing, Yoga…',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 13)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Type'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            itemCount: types.length,
            itemBuilder: (_, i) => _TypeCard(
              type: types[i],
              onEdit: () => _openForm(context, types[i]),
              onDelete: () => _delete(context, types[i]),
            ),
          );
        },
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final Map<String, dynamic> type;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TypeCard(
      {required this.type, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name = type['name']?.toString() ?? '';
    final imageUrl = type['imageUrl']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: imageUrl.isNotEmpty
              ? Image.network(imageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder())
              : _placeholder(),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 3),
              Text(
                imageUrl.isNotEmpty ? imageUrl : 'No image URL',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    color: imageUrl.isNotEmpty
                        ? AppColors.textMuted
                        : AppColors.error.withValues(alpha: 0.7)),
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
        ]),
      ]),
    );
  }

  Widget _placeholder() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.category_outlined,
            color: AppColors.primary, size: 24),
      );
}

class _TypeFormScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _TypeFormScreen({this.existing});

  @override
  State<_TypeFormScreen> createState() => _TypeFormScreenState();
}

class _TypeFormScreenState extends State<_TypeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _imageUrl;
  bool _saving = false;
  bool _previewError = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
        text: widget.existing?['name']?.toString() ?? '');
    _imageUrl = TextEditingController(
        text: widget.existing?['imageUrl']?.toString() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await ClassService.addClassType(
            _name.text.trim(), _imageUrl.text.trim());
      } else {
        await ClassService.updateClassType(
          widget.existing!['id'] as String,
          _name.text.trim(),
          _imageUrl.text.trim(),
        );
      }
      if (mounted) {
        Navigator.pop(context);
        AppToast.success(context,
            widget.existing == null ? 'Type added' : 'Type updated');
      }
    } catch (err) {
      setState(() => _saving = false);
      if (mounted) AppToast.error(context, err.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = _imageUrl.text.trim();
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.existing == null ? 'New Type' : 'Edit Type')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: previewUrl.isNotEmpty && !_previewError
                  ? ClipRRect(
                      key: ValueKey(previewUrl),
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        previewUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _previewError = true);
                          });
                          return _emptyPreview();
                        },
                      ),
                    )
                  : _emptyPreview(key: const ValueKey('empty')),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Type Name',
                hintText: 'e.g. Boxing, Yoga, Muay Thai…',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _imageUrl,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() => _previewError = false),
              decoration: InputDecoration(
                labelText: 'Image URL (optional)',
                hintText: 'https://…',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: previewUrl.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _imageUrl.clear();
                          setState(() => _previewError = false);
                        },
                      )
                    : null,
              ),
            ),
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
                      ? 'Create Type'
                      : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyPreview({Key? key}) => Container(
        key: key,
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: 40, color: AppColors.textMuted),
              SizedBox(height: 8),
              Text('Paste an image URL to preview',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
}
