import 'package:flutter/material.dart';
import '../../services/qr_payment_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../utils/error_reporter.dart';

/// Lets admin configure the business QR code shown to clients as an
/// alternative to Stripe checkout — a plain image URL rather than an
/// in-app upload, so no new Storage infrastructure is needed for what's
/// normally a single, rarely-changing image (e.g. a bank/PayNow QR).
class PaymentQrScreen extends StatefulWidget {
  const PaymentQrScreen({super.key});

  @override
  State<PaymentQrScreen> createState() => _PaymentQrScreenState();
}

class _PaymentQrScreenState extends State<PaymentQrScreen> {
  final _urlCtrl = TextEditingController();
  final _captionCtrl = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_urlCtrl.text.trim().isEmpty) {
      AppToast.error(context, 'Enter an image URL');
      return;
    }
    setState(() => _saving = true);
    try {
      await QrPaymentService.setConfig(
        imageUrl: _urlCtrl.text.trim(),
        caption: _captionCtrl.text.trim(),
      );
      if (mounted) AppToast.success(context, 'QR code updated');
    } catch (e, st) {
      if (mounted) {
        reportError(
          context,
          e,
          st,
          userMessage: 'Could not save the QR code. Please try again.',
          reason: 'Payment QR save failed',
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Business QR Code')),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: QrPaymentService.streamConfig(),
        builder: (context, snap) {
          if (!_loaded && snap.hasData) {
            _loaded = true;
            _urlCtrl.text = snap.data?['imageUrl']?.toString() ?? '';
            _captionCtrl.text = snap.data?['caption']?.toString() ?? '';
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
            children: [
              const Text(
                "Shown to clients at checkout as an alternative to card "
                "payment. They scan it in their own banking app, tap "
                "\"I've Paid\" in the app, and you confirm the payment "
                "landed under the Requests tab before it activates.",
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _urlCtrl,
                decoration: InputDecoration(
                  labelText: 'QR Code Image URL',
                  helperText: 'A direct link to the QR image (PNG/JPG)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _captionCtrl,
                decoration: InputDecoration(
                  labelText: 'Caption (optional)',
                  helperText: 'e.g. "Scan with your banking app to pay via PayNow"',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _urlCtrl,
                builder: (context, value, _) {
                  final url = value.text.trim();
                  if (url.isEmpty) return const SizedBox();
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Image.network(
                        url,
                        height: 220,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 220,
                          child: Center(
                            child: Text('Could not load image',
                                style: TextStyle(color: AppColors.textMuted)),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48)),
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
