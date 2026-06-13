import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/api_client.dart';
import '../../session.dart';
import 'package:provider/provider.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  static const _sky = Color(0xFF00B4D8);

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // mobile_scanner supports Android, iOS, macOS, Web — not Windows or Linux
  static bool get _isScannerSupported =>
      kIsWeb ||
      (!kIsWeb &&
          (Platform.isAndroid ||
              Platform.isIOS ||
              Platform.isMacOS));

  MobileScannerController? _controller;
  Razorpay? _razorpay;
  Map<String, dynamic>? _pendingRazorpayMeta;

  bool _processing = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    if (_isScannerSupported) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
      );
    }
    if (_isMobile) {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onRazorpaySuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onRazorpayError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) => _resetProcessing());
    }
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _controller?.dispose();
    super.dispose();
  }

  // ── state helpers ──────────────────────────────────────────────────────────
  void _resetProcessing() {
    if (!mounted) return;
    setState(() => _processing = false);
    _controller?.start();
  }

  void _showError(String msg) {
    if (!mounted) return;
    _resetProcessing();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Razorpay callbacks ─────────────────────────────────────────────────────
  void _onRazorpaySuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    final meta = _pendingRazorpayMeta;
    _pendingRazorpayMeta = null;
    if (meta == null) { _resetProcessing(); return; }

    try {
      final verifyRes = await ApiClient.post(
        '/api/wallet/verify-qr-payment',
        body: {
          'razorpayOrderId': response.orderId ?? '',
          'razorpayPaymentId': response.paymentId ?? '',
          'razorpaySignature': response.signature ?? '',
          'amount': meta['amount'],
          'upiId': meta['upiId'],
          'payeeName': meta['payeeName'],
          'note': meta['note'],
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (verifyRes.statusCode == 200) {
        _showSuccess('Paid ₹${meta['amount']} to ${meta['payeeName']} via Razorpay.');
        Navigator.pop(context, true);
      } else {
        _showError('Payment done but recording failed. Contact support.');
      }
    } on TimeoutException {
      _showError('Verification timed out. Contact support if amount was deducted.');
    } catch (_) {
      _showError('Verification failed. Contact support.');
    }
  }

  void _onRazorpayError(PaymentFailureResponse response) {
    _pendingRazorpayMeta = null;
    _showError('Payment failed: ${response.message ?? 'Cancelled or declined'}');
  }

  // ── scanner callbacks ──────────────────────────────────────────────────────
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    setState(() => _processing = true);
    await _controller?.stop();
    await _handleQrValue(raw);
  }

  Future<void> _pickFromGallery() async {
    if (_processing) return;
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    setState(() => _processing = true);
    await _controller?.stop();
    try {
      final found = await _controller?.analyzeImage(image.path);
      if (!mounted) return;
      if (found != true) _showError('No valid QR code found in this image.');
    } catch (_) {
      if (mounted) _showError('Could not analyse the image. Try another photo.');
    }
  }

  void _openManualEntry() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Enter QR Content',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'lenden://pay?userId=…  or  upi://pay?pa=…',
            hintStyle:
                TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
            filled: true,
            fillColor: const Color(0xFFF8F6FA),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _sky, width: 1.8),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = ctrl.text.trim();
              Navigator.pop(ctx);
              if (val.isNotEmpty) {
                setState(() => _processing = true);
                _controller?.stop().then((_) => _handleQrValue(val));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _sky,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child:
                const Text('Use', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── QR routing ─────────────────────────────────────────────────────────────
  Future<void> _handleQrValue(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      _showError('Invalid QR code.');
      return;
    }

    if (uri.scheme == 'lenden' && uri.host == 'pay') {
      await _handleLenDenPay(uri);
    } else if (uri.scheme == 'upi') {
      await _handleUpiPay(uri);
    } else {
      _showError('Unsupported QR format. Only LenDen and UPI QR codes are supported.');
    }
  }

  // ── LenDen wallet-to-wallet ────────────────────────────────────────────────
  Future<void> _handleLenDenPay(Uri uri) async {
    final userId = uri.queryParameters['userId'] ?? '';
    final amountStr = uri.queryParameters['amount'];
    final note = uri.queryParameters['note'] ?? '';

    if (userId.isEmpty) {
      _showError('Invalid QR: missing recipient ID.');
      return;
    }

    try {
      final res = await ApiClient.get('/api/users/$userId')
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode != 200) {
        _showError('Recipient not found on LenDen.');
        return;
      }
      final userData = jsonDecode(res.body) as Map<String, dynamic>;
      final recipientName =
          (userData['name'] ?? userData['username'] ?? 'User').toString();
      final recipientEmail = (userData['email'] ?? '').toString();

      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _LenDenPaymentDialog(
          recipientName: recipientName,
          recipientEmail: recipientEmail,
          userId: userId,
          presetAmount:
              amountStr != null ? double.tryParse(amountStr) : null,
          note: note,
        ),
      );

      if (!mounted) return;
      if (paid == true) {
        Navigator.pop(context, true);
      } else {
        _resetProcessing();
      }
    } on TimeoutException {
      _showError('Request timed out. Check your connection.');
    } catch (_) {
      _showError('Failed to load recipient. Check your connection.');
    }
  }

  // ── UPI QR (shops) ─────────────────────────────────────────────────────────
  Future<void> _handleUpiPay(Uri uri) async {
    final upiId = uri.queryParameters['pa'] ?? '';
    final payeeName =
        Uri.decodeComponent(uri.queryParameters['pn'] ?? 'Shop');
    final amountStr = uri.queryParameters['am'];
    final note =
        Uri.decodeComponent(uri.queryParameters['tn'] ?? 'UPI Payment');

    if (upiId.isEmpty) {
      _showError('Invalid UPI QR: missing UPI ID.');
      return;
    }

    final session = Provider.of<SessionProvider>(context, listen: false);
    final userEmail = session.user?['email'] ?? '';
    final userName = session.user?['name'] ?? '';

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpiPaymentDialog(
        upiId: upiId,
        payeeName: payeeName,
        presetAmount:
            amountStr != null ? double.tryParse(amountStr) : null,
        note: note,
        isMobile: _isMobile,
        userEmail: userEmail,
        userName: userName,
      ),
    );

    if (!mounted) return;

    if (result == null) {
      // User cancelled
      _resetProcessing();
      return;
    }

    if (result['type'] == 'wallet_success') {
      _showSuccess(
          'Paid ₹${result['amount']} to $payeeName via LenDen Wallet. '
          'Balance: ₹${result['balance'] ?? ''}');
      Navigator.pop(context, true);
    } else if (result['type'] == 'razorpay') {
      // Store meta for the success callback, then open Razorpay
      _pendingRazorpayMeta = {
        'amount': result['amount'],
        'upiId': upiId,
        'payeeName': payeeName,
        'note': note,
      };
      _razorpay!.open(result['options'] as Map<String, dynamic>);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_isScannerSupported) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Scan & Pay',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_rounded,
                  color: Colors.white38, size: 72),
              const SizedBox(height: 16),
              const Text('Scanner not available on this platform',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                'Use the Manual Entry button on Android or iOS.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _openManualEntry,
                icon: const Icon(Icons.keyboard_rounded, size: 18),
                label: const Text('Manual Entry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _sky,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller!,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              final bool isDenied =
                  error.errorCode == MobileScannerErrorCode.permissionDenied;
              return Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDenied
                            ? Icons.no_photography_rounded
                            : Icons.error_outline_rounded,
                        color: Colors.white60,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isDenied
                            ? 'Camera permission denied'
                            : 'Camera unavailable',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isDenied
                            ? 'Grant camera access in Settings\nto scan QR codes'
                            : error.errorCode.name,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      if (isDenied) ...[
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final uri = _isMobile && Platform.isIOS
                                ? Uri.parse('app-settings:')
                                : Uri.parse(
                                    'android.settings.APPLICATION_DETAILS_SETTINGS');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            }
                          },
                          icon: const Icon(Icons.settings_rounded, size: 18),
                          label: const Text('Open Settings'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B4D8),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text('Scan & Pay',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: Icon(
                      _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      color: _torchOn ? Colors.amber : Colors.white,
                    ),
                    onPressed: () {
                      _controller?.toggleTorch();
                      setState(() => _torchOn = !_torchOn);
                    },
                  ),
                ],
              ),
            ),
          ),

          // Hint chip
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Supports LenDen QR  •  UPI QR (shops)',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ),

          Center(child: _ScanFrame(processing: _processing)),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                children: [
                  Text(
                    _processing
                        ? 'Processing…'
                        : 'Point at a LenDen or UPI QR code',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _BottomBtn(
                        icon: Icons.photo_library_rounded,
                        label: 'Gallery',
                        onTap: _processing ? null : _pickFromGallery,
                      ),
                      _BottomBtn(
                        icon: Icons.flip_camera_ios_rounded,
                        label: 'Flip',
                        onTap: _processing
                            ? null
                            : () => _controller?.switchCamera(),
                      ),
                      _BottomBtn(
                        icon: Icons.keyboard_rounded,
                        label: 'Manual',
                        onTap: _processing ? null : _openManualEntry,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Processing overlay — long-press to escape if stuck
          if (_processing)
            GestureDetector(
              onLongPress: _resetProcessing,
              child: Container(
                color: Colors.black45,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: _sky),
                      const SizedBox(height: 16),
                      const Text('Processing…',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 8),
                      Text('Hold to cancel',
                          style: TextStyle(
                              color: Colors.white
                                  .withValues(alpha: 0.35),
                              fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Scan frame ────────────────────────────────────────────────────────────────

class _ScanFrame extends StatelessWidget {
  final bool processing;
  const _ScanFrame({this.processing = false});

  static const _sky = Color(0xFF00B4D8);

  @override
  Widget build(BuildContext context) {
    const size = 240.0;
    const corner = 24.0;
    const stroke = 4.0;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: const Size(size, size),
        painter: _CornerPainter(
          color: processing ? Colors.greenAccent : _sky,
          cornerSize: corner,
          stroke: stroke,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double cornerSize;
  final double stroke;

  const _CornerPainter(
      {required this.color,
      required this.cornerSize,
      required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final c = cornerSize;

    for (final p in [
      Path()
        ..moveTo(0, c)
        ..lineTo(0, 0)
        ..lineTo(c, 0),
      Path()
        ..moveTo(w - c, 0)
        ..lineTo(w, 0)
        ..lineTo(w, c),
      Path()
        ..moveTo(0, h - c)
        ..lineTo(0, h)
        ..lineTo(c, h),
      Path()
        ..moveTo(w - c, h)
        ..lineTo(w, h)
        ..lineTo(w, h - c),
    ]) {
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}

// ── Bottom button ─────────────────────────────────────────────────────────────

class _BottomBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BottomBtn(
      {required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── LenDen wallet-to-wallet dialog ───────────────────────────────────────────

class _LenDenPaymentDialog extends StatefulWidget {
  final String recipientName;
  final String recipientEmail;
  final String userId;
  final double? presetAmount;
  final String note;

  const _LenDenPaymentDialog({
    required this.recipientName,
    required this.recipientEmail,
    required this.userId,
    this.presetAmount,
    this.note = '',
  });

  @override
  State<_LenDenPaymentDialog> createState() => _LenDenPaymentDialogState();
}

class _LenDenPaymentDialogState extends State<_LenDenPaymentDialog> {
  static const _sky = Color(0xFF00B4D8);
  static const _deep = Color(0xFF0077B6);

  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _paying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.presetAmount != null)
      _amountCtrl.text = widget.presetAmount!.toStringAsFixed(2);
    if (widget.note.isNotEmpty) _noteCtrl.text = widget.note;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount greater than ₹0.');
      return;
    }
    setState(() { _paying = true; _error = null; });
    try {
      final res = await ApiClient.post('/api/wallet/qr-pay', body: {
        'toUserId': widget.userId,
        'amount': amount,
        'note': _noteCtrl.text.trim().isEmpty
            ? 'QR Payment'
            : _noteCtrl.text.trim(),
      }).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Paid ₹${amount.toStringAsFixed(2)} to ${widget.recipientName}. '
              'Balance: ₹${(body['balance'] ?? 0).toStringAsFixed(2)}'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      } else {
        final body = jsonDecode(res.body);
        setState(() {
          _error = body['error'] ?? 'Payment failed.';
          _paying = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _error = 'Payment timed out.'; _paying = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Network error.'; _paying = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_deep, _sky]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 10),
              Text(widget.recipientName,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B1F33))),
              const SizedBox(height: 2),
              Text(widget.recipientEmail,
                  style: TextStyle(
                      fontSize: 12, color: Colors.blueGrey.shade500)),
              const SizedBox(height: 18),
              _amountField(),
              const SizedBox(height: 10),
              _noteField(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _errorBox(_error!),
              ],
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _paying ? null : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.blueGrey.shade300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _paying ? null : _pay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _sky,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _sky.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: _paying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Pay Now',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountField() => TextField(
        controller: _amountCtrl,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        readOnly: widget.presetAmount != null,
        enabled: !_paying,
        style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0B1F33)),
        textAlign: TextAlign.center,
        decoration: _fieldDeco('Amount (₹)',
            const Icon(Icons.currency_rupee_rounded, color: _sky)),
      );

  Widget _noteField() => TextField(
        controller: _noteCtrl,
        enabled: !_paying,
        style: const TextStyle(fontSize: 14),
        decoration: _fieldDeco('Note (optional)',
            const Icon(Icons.note_outlined, color: _sky, size: 20)),
      );

  InputDecoration _fieldDeco(String label, Widget prefix) => InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
        prefixIcon: prefix,
        filled: true,
        fillColor: const Color(0xFFF8F6FA),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.blueGrey.shade200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.blueGrey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _sky, width: 1.8)),
      );
}

// ── UPI shop payment dialog ───────────────────────────────────────────────────
// Returns:
//   null                          → cancelled
//   {'type':'wallet_success', 'amount':x, 'balance':y}
//   {'type':'razorpay', 'options':{...}, 'amount':x}

class _UpiPaymentDialog extends StatefulWidget {
  final String upiId;
  final String payeeName;
  final double? presetAmount;
  final String note;
  final bool isMobile;
  final String userEmail;
  final String userName;

  const _UpiPaymentDialog({
    required this.upiId,
    required this.payeeName,
    this.presetAmount,
    this.note = '',
    required this.isMobile,
    required this.userEmail,
    required this.userName,
  });

  @override
  State<_UpiPaymentDialog> createState() => _UpiPaymentDialogState();
}

class _UpiPaymentDialogState extends State<_UpiPaymentDialog> {
  static const _sky = Color(0xFF00B4D8);
  static const _green = Color(0xFF2ECC71);

  final _amountCtrl = TextEditingController();
  bool _loadingWallet = false;
  bool _loadingRazorpay = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.presetAmount != null)
      _amountCtrl.text = widget.presetAmount!.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountCtrl.text.trim());

  Future<void> _payWallet() async {
    final amount = _amount;
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount greater than ₹0.');
      return;
    }
    setState(() { _loadingWallet = true; _error = null; });
    try {
      final res = await ApiClient.post('/api/wallet/pay-upi-qr', body: {
        'amount': amount,
        'upiId': widget.upiId,
        'payeeName': widget.payeeName,
        'note': widget.note.isEmpty ? 'UPI QR Payment' : widget.note,
      }).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        Navigator.of(context).pop({
          'type': 'wallet_success',
          'amount': amount.toStringAsFixed(2),
          'balance': (body['balance'] ?? 0).toStringAsFixed(2),
        });
      } else {
        final body = jsonDecode(res.body);
        setState(() {
          _error = body['error'] ?? 'Payment failed.';
          _loadingWallet = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _error = 'Request timed out.'; _loadingWallet = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Network error.'; _loadingWallet = false; });
    }
  }

  Future<void> _payRazorpay() async {
    if (!widget.isMobile) {
      setState(() => _error =
          'Razorpay is only available on Android & iOS.');
      return;
    }
    final amount = _amount;
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount greater than ₹0.');
      return;
    }
    setState(() { _loadingRazorpay = true; _error = null; });
    try {
      final orderRes = await ApiClient.post('/api/wallet/create-qr-order', body: {
        'amount': amount,
        'upiId': widget.upiId,
        'payeeName': widget.payeeName,
      }).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (orderRes.statusCode != 200) {
        final body = jsonDecode(orderRes.body);
        setState(() {
          _error = body['error'] ?? 'Could not create order.';
          _loadingRazorpay = false;
        });
        return;
      }
      final data = jsonDecode(orderRes.body);
      final options = {
        'key': data['keyId'],
        'amount': data['amount'],
        'currency': 'INR',
        'name': widget.payeeName,
        'description': widget.note.isEmpty
            ? 'UPI QR Payment'
            : widget.note,
        'order_id': data['orderId'],
        'prefill': {
          'email': widget.userEmail,
          'name': widget.userName,
        },
        'theme': {'color': '#00B4D8'},
      };
      // Close dialog first; scanner page opens Razorpay from full-page context
      if (mounted) {
        Navigator.of(context).pop({
          'type': 'razorpay',
          'options': options,
          'amount': amount.toStringAsFixed(2),
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _error = 'Request timed out.'; _loadingRazorpay = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Network error.'; _loadingRazorpay = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loadingWallet || _loadingRazorpay;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shop icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF1A6B4A), Color(0xFF2ECC71)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 10),
              Text(widget.payeeName,
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B1F33)),
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(widget.upiId,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey.shade600,
                        fontFamily: 'monospace')),
              ),
              const SizedBox(height: 18),

              // Amount field
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                readOnly: widget.presetAmount != null,
                enabled: !busy,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0B1F33)),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  labelStyle: TextStyle(
                      color: Colors.blueGrey.shade400, fontSize: 13),
                  prefixIcon: const Icon(
                      Icons.currency_rupee_rounded,
                      color: _sky),
                  filled: true,
                  fillColor: const Color(0xFFF8F6FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: Colors.blueGrey.shade200)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: Colors.blueGrey.shade200)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: _sky, width: 1.8)),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                _errorBox(_error!),
              ],

              const SizedBox(height: 20),

              // Payment method label
              Text('Choose Payment Method',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey.shade400,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
              const SizedBox(height: 12),

              // Wallet button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : _payWallet,
                  icon: _loadingWallet
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 18),
                  label: Text(_loadingWallet
                      ? 'Processing…'
                      : 'Pay with LenDen Wallet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _sky,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _sky.withValues(alpha: 0.5),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Razorpay button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : _payRazorpay,
                  icon: _loadingRazorpay
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.payment_rounded, size: 18),
                  label: Text(_loadingRazorpay
                      ? 'Opening Razorpay…'
                      : 'Pay via Razorpay / UPI'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF072654),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF072654).withValues(alpha: 0.5),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Cancel
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed:
                      busy ? null : () => Navigator.pop(context, null),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.blueGrey.shade300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),

              if (!widget.isMobile) ...[
                const SizedBox(height: 8),
                Text(
                  'Razorpay requires Android or iOS. '
                  'LenDen Wallet works on all platforms.',
                  style: TextStyle(
                      fontSize: 11, color: Colors.blueGrey.shade400),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget _errorBox(String msg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(msg,
          style: TextStyle(
              color: Colors.red.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600),
          textAlign: TextAlign.center),
    );
