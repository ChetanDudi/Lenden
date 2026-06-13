import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../utils/api_client.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  static const _sky = Color(0xFF00B4D8);

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _processing = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    setState(() => _processing = true);
    await _controller.stop();
    await _handleQrValue(raw);
  }

  Future<void> _pickFromGallery() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() => _processing = true);
    await _controller.stop();
    await _controller.analyzeImage(image.path);
  }

  Future<void> _handleQrValue(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'lenden' || uri.host != 'pay') {
      _showError('Not a valid LenDen payment QR code.');
      return;
    }

    final userId = uri.queryParameters['userId'] ?? '';
    final amountStr = uri.queryParameters['amount'];
    final note = uri.queryParameters['note'] ?? '';

    if (userId.isEmpty) {
      _showError('Invalid QR: missing recipient.');
      return;
    }

    try {
      final res = await ApiClient.get('/api/users/$userId');
      if (!mounted) return;
      if (res.statusCode != 200) {
        _showError('Recipient not found on LenDen.');
        return;
      }
      final userData = jsonDecode(res.body) as Map<String, dynamic>;
      final recipientName = (userData['name'] ?? userData['username'] ?? 'User').toString();
      final recipientEmail = (userData['email'] ?? '').toString();

      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PaymentDialog(
          recipientName: recipientName,
          recipientEmail: recipientEmail,
          userId: userId,
          presetAmount: amountStr != null ? double.tryParse(amountStr) : null,
          note: note,
        ),
      );

      if (!mounted) return;
      if (paid == true) {
        Navigator.pop(context, true);
      } else {
        setState(() => _processing = false);
        await _controller.start();
      }
    } catch (e) {
      _showError('Failed to load recipient. Check your connection.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() => _processing = false);
    _controller.start();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera view
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Scan QR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                      color: _torchOn ? Colors.amber : Colors.white,
                    ),
                    onPressed: () {
                      _controller.toggleTorch();
                      setState(() => _torchOn = !_torchOn);
                    },
                  ),
                ],
              ),
            ),
          ),

          // Scan frame overlay
          Center(
            child: _ScanFrame(processing: _processing),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                children: [
                  Text(
                    _processing ? 'Processing…' : 'Point camera at a LenDen QR code',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Gallery
                      _BottomBtn(
                        icon: Icons.photo_library_rounded,
                        label: 'Gallery',
                        onTap: _processing ? null : _pickFromGallery,
                      ),
                      // Flip camera
                      _BottomBtn(
                        icon: Icons.flip_camera_ios_rounded,
                        label: 'Flip',
                        onTap: _processing ? null : () => _controller.switchCamera(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Processing indicator
          if (_processing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(color: _sky),
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
      child: Stack(
        children: [
          // Semi-transparent dim around frame (outside)
          CustomPaint(
            size: const Size(size, size),
            painter: _DimPainter(),
          ),
          // Corner brackets
          CustomPaint(
            size: const Size(size, size),
            painter: _CornerPainter(
              color: processing ? Colors.greenAccent : _sky,
              cornerSize: corner,
              stroke: stroke,
            ),
          ),
        ],
      ),
    );
  }
}

class _DimPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.transparent;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_DimPainter _) => false;
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double cornerSize;
  final double stroke;

  const _CornerPainter({
    required this.color,
    required this.cornerSize,
    required this.stroke,
  });

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

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, c)
        ..lineTo(0, 0)
        ..lineTo(c, 0),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(w - c, 0)
        ..lineTo(w, 0)
        ..lineTo(w, c),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(0, h - c)
        ..lineTo(0, h)
        ..lineTo(c, h),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(w - c, h)
        ..lineTo(w, h)
        ..lineTo(w, h - c),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}

// ── Bottom button ─────────────────────────────────────────────────────────────

class _BottomBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BottomBtn({
    required this.icon,
    required this.label,
    this.onTap,
  });

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
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Payment dialog ────────────────────────────────────────────────────────────

class _PaymentDialog extends StatefulWidget {
  final String recipientName;
  final String recipientEmail;
  final String userId;
  final double? presetAmount;
  final String note;

  const _PaymentDialog({
    required this.recipientName,
    required this.recipientEmail,
    required this.userId,
    this.presetAmount,
    this.note = '',
  });

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  static const _sky = Color(0xFF00B4D8);
  static const _deepBlue = Color(0xFF0077B6);

  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _paying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.presetAmount != null) {
      _amountCtrl.text = widget.presetAmount!.toStringAsFixed(2);
    }
    if (widget.note.isNotEmpty) {
      _noteCtrl.text = widget.note;
    }
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
      setState(() => _error = 'Enter a valid amount greater than 0.');
      return;
    }

    setState(() {
      _paying = true;
      _error = null;
    });

    try {
      final res = await ApiClient.post(
        '/api/wallet/qr-pay',
        body: {
          'toUserId': widget.userId,
          'amount': amount,
          'note': _noteCtrl.text.trim().isEmpty ? 'QR Payment' : _noteCtrl.text.trim(),
        },
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Paid ₹${amount.toStringAsFixed(2)} to ${widget.recipientName}. Balance: ₹${(body['balance'] ?? 0).toStringAsFixed(2)}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else {
        final body = jsonDecode(res.body);
        setState(() {
          _error = body['error'] ?? 'Payment failed. Please try again.';
          _paying = false;
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Network error. Please check your connection.';
        _paying = false;
      });
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Recipient
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_deepBlue, _sky]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded,
                    color: Colors.white, size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                widget.recipientName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0B1F33),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.recipientEmail,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.blueGrey.shade500,
                ),
              ),
              const SizedBox(height: 20),

              // Amount field
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                readOnly: widget.presetAmount != null,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF0B1F33)),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'Amount (₹)',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                  prefixIcon: const Icon(Icons.currency_rupee_rounded, color: _sky),
                  filled: true,
                  fillColor: const Color(0xFFF8F6FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.blueGrey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.blueGrey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _sky, width: 1.8),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Note field
              TextField(
                controller: _noteCtrl,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Note (optional)',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                  prefixIcon: const Icon(Icons.note_outlined, color: _sky, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF8F6FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.blueGrey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.blueGrey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _sky, width: 1.8),
                  ),
                ),
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _paying ? null : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.blueGrey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                        disabledBackgroundColor: _sky.withValues(alpha: 0.55),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _paying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Pay Now',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
