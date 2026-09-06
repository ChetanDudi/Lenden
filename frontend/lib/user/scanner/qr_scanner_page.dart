import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/app_colors.dart';
import '../../session.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/payment_success_page.dart';
import '../../otp_input.dart';
import '../../settings/set_wallet_pin_page.dart';
import 'user_qr_page.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  static const _sky = AppColors.cyan;

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
  }

  @override
  void dispose() {
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
    showSnack(context, msg, isError: true);
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
    if (!kIsWeb) {
      var status = await Permission.photos.status;
      if (!status.isGranted) status = await Permission.photos.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) await openAppSettings();
        return;
      }
    }
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    // Do NOT set _processing or stop the controller here.
    // analyzeImage triggers _onDetect which manages both.
    try {
      final found = await _controller?.analyzeImage(image.path);
      if (!mounted) return;
      // Only show error if _onDetect didn't already start handling the result
      if (found != true && !_processing) {
        _showError('No valid QR code found in this image.');
      }
    } catch (_) {
      if (mounted && !_processing) {
        _showError('Could not analyse the image. Try another photo.');
      }
    }
  }

  void _openMyQr() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UserQrPage()),
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
    } else {
      // Don't restart scanner here — _showUnknownQrDialog restarts it on dismiss
      _showUnknownQrDialog(raw);
    }
  }

  // ── Non-LenDen QR ─────────────────────────────────────────────────────────
  void _showUnknownQrDialog(String raw) {
    final uri = Uri.tryParse(raw);
    final isUrl  = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final isUpi  = uri != null && uri.scheme == 'upi';
    final isMail = uri != null && uri.scheme == 'mailto';
    final isTel  = uri != null && uri.scheme == 'tel';
    final isWifi = raw.toUpperCase().startsWith('WIFI:');

    // Classify
    final String typeLabel;
    final IconData typeIcon;
    final Color typeColor;
    if (isUpi)       { typeLabel = 'UPI Payment';   typeIcon = Icons.currency_rupee_rounded;     typeColor = const Color(0xFF2E7D32); }
    else if (isUrl)  { typeLabel = 'Website / URL'; typeIcon = Icons.language_rounded;            typeColor = const Color(0xFF1565C0); }
    else if (isMail) { typeLabel = 'Email';          typeIcon = Icons.email_rounded;               typeColor = const Color(0xFFC62828); }
    else if (isTel)  { typeLabel = 'Phone Number';  typeIcon = Icons.phone_rounded;               typeColor = const Color(0xFF00695C); }
    else if (isWifi) { typeLabel = 'Wi-Fi Network'; typeIcon = Icons.wifi_rounded;                typeColor = const Color(0xFF0277BD); }
    else             { typeLabel = 'Text';           typeIcon = Icons.text_snippet_outlined;      typeColor = Colors.blueGrey; }

    // Parse UPI fields (pa, pn, am, cu, tn)
    final Map<String, String> upi = {};
    if (isUpi) {
      uri.queryParameters.forEach((k, v) => upi[k] = Uri.decodeComponent(v));
    }

    // Parse Wi-Fi fields (S=ssid, T=security, P=password)
    final Map<String, String> wifi = {};
    if (isWifi) {
      final body = raw.replaceFirst(RegExp(r'^WIFI:', caseSensitive: false), '');
      for (final part in body.split(';')) {
        final colon = part.indexOf(':');
        if (colon > 0) wifi[part.substring(0, colon).toUpperCase()] = part.substring(colon + 1);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark    = AppThemeColors.isDark(ctx);
        final cardBg    = isDark ? const Color(0xFF1C1C1E) : Colors.white;
        final surfaceBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF5F6F8);
        final divClr    = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.07);
        final labelClr  = isDark ? Colors.white54 : Colors.black45;
        final valueClr  = isDark ? Colors.white   : Colors.black87;

        Widget infoRow(IconData icon, String label, String value, {Color? iconColor}) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: (iconColor ?? typeColor).withValues(alpha: isDark ? 0.22 : 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: iconColor ?? typeColor),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label.toUpperCase(),
                    style: TextStyle(fontSize: 10, color: labelClr,
                        fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                const SizedBox(height: 3),
                SelectableText(value,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valueClr)),
              ])),
            ]),
          );
        }

        Widget divider() => Divider(height: 1, color: divClr, indent: 46);

        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header banner
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: isDark ? 0.15 : 0.07),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: typeColor.withValues(alpha: isDark ? 0.25 : 0.15)),
                ),
                child: Row(children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: isDark ? 0.28 : 0.13),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 23),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(typeLabel,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                                color: typeColor, letterSpacing: 0.3)),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: isDark ? 0.2 : 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('External QR',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                                color: Colors.orange)),
                      ),
                    ]),
                    const SizedBox(height: 5),
                    Text('Not a LenDen QR code',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: valueClr)),
                    Text('This code is from another app or service.',
                        style: TextStyle(fontSize: 11.5, color: labelClr, height: 1.3)),
                  ])),
                ]),
              ),

              // Parsed content card
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                decoration: BoxDecoration(
                  color: surfaceBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: divClr),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (isUpi) ...[
                      if (upi['pn']?.isNotEmpty == true)
                        infoRow(Icons.person_rounded, 'Pay To', upi['pn']!),
                      if (upi['pa']?.isNotEmpty == true) ...[
                        divider(),
                        infoRow(Icons.account_balance_wallet_outlined, 'UPI ID', upi['pa']!,
                            iconColor: const Color(0xFF2E7D32)),
                      ],
                      if (upi['am']?.isNotEmpty == true) ...[
                        divider(),
                        infoRow(Icons.currency_rupee_rounded, 'Amount',
                            '₹${upi['am']}${upi['cu'] != null && upi['cu'] != 'INR' ? ' ${upi['cu']}' : ''}',
                            iconColor: const Color(0xFF2E7D32)),
                      ],
                      if (upi['tn']?.isNotEmpty == true) ...[
                        divider(),
                        infoRow(Icons.notes_rounded, 'Note / Remark', upi['tn']!),
                      ],
                      if (upi.isEmpty)
                        infoRow(Icons.qr_code_rounded, 'Raw Value', raw),
                    ] else if (isUrl) ...[
                      infoRow(Icons.link_rounded, 'URL', raw, iconColor: const Color(0xFF1565C0)),
                    ] else if (isMail) ...[
                      infoRow(Icons.email_rounded, 'Email Address',
                          uri.path.isNotEmpty ? uri.path : raw,
                          iconColor: const Color(0xFFC62828)),
                    ] else if (isTel) ...[
                      infoRow(Icons.phone_rounded, 'Phone Number',
                          uri.path.isNotEmpty ? uri.path : raw,
                          iconColor: const Color(0xFF00695C)),
                    ] else if (isWifi) ...[
                      if (wifi['S']?.isNotEmpty == true)
                        infoRow(Icons.wifi_rounded, 'Network Name (SSID)', wifi['S']!,
                            iconColor: const Color(0xFF0277BD)),
                      if (wifi['T']?.isNotEmpty == true) ...[
                        divider(),
                        infoRow(Icons.security_rounded, 'Security Type', wifi['T']!),
                      ],
                      if (wifi['P']?.isNotEmpty == true) ...[
                        divider(),
                        infoRow(Icons.lock_rounded, 'Password', wifi['P']!, iconColor: Colors.orange),
                      ],
                    ] else ...[
                      if (raw.length <= 80)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: SelectableText(raw,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                                  color: valueClr, letterSpacing: 0.1)),
                        )
                      else ...[
                        infoRow(Icons.text_snippet_outlined, 'Scanned Content', ''),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 90),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SelectableText(raw,
                                style: TextStyle(fontSize: 13, color: valueClr, height: 1.55)),
                          ),
                        ),
                      ],
                    ],
                  ]),
                ),
              ),

              // Action buttons
              Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16,
                    MediaQuery.of(ctx).padding.bottom + 16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: raw));
                        Navigator.pop(ctx);
                        showSnack(context, 'Copied to clipboard.');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: divClr),
                      ),
                    ),
                  ),
                  if (isUrl) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            await launchUrl(Uri.parse(raw), mode: LaunchMode.externalApplication);
                          } catch (_) {
                            if (mounted) showSnack(context, 'Could not open this URL.', isError: true);
                          }
                        },
                        icon: const Icon(Icons.open_in_browser_rounded, size: 16, color: Colors.white),
                        label: const Text('Open URL', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                  if (isMail) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } catch (_) {
                            if (mounted) showSnack(context, 'Could not open email app.', isError: true);
                          }
                        },
                        icon: const Icon(Icons.email_rounded, size: 16, color: Colors.white),
                        label: const Text('Compose', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC62828),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                  if (isTel) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } catch (_) {
                            if (mounted) showSnack(context, 'Could not open phone app.', isError: true);
                          }
                        },
                        icon: const Icon(Icons.phone_rounded, size: 16, color: Colors.white),
                        label: const Text('Call', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00695C),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ]),
          ),
        );
      },
    ).whenComplete(_resetProcessing);
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

    // Self-pay guard — show own profile details instead of payment dialog
    if (!mounted) return;
    final session = Provider.of<SessionProvider>(context, listen: false);
    final myId = session.user?['_id']?.toString() ?? '';
    if (userId == myId) {
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _QrSelfPayPage(session: session)),
        );
        if (mounted) _resetProcessing();
      }
      return;
    }

    try {
      final res = await ApiClient.get('/api/users/$userId')
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (res.statusCode != 200) {
        _showError('Recipient not found on LenDen.');
        return;
      }
      final userData = jsonDecode(res.body) as Map<String, dynamic>;
      final recipientName =
          (userData['name'] ?? userData['username'] ?? 'User').toString();
      final recipientEmail = (userData['email'] ?? '').toString();
      final recipientUsername = (userData['username'] ?? '').toString();
      final recipientGender = (userData['gender'] ?? 'Other').toString();
      final recipientImageUrl = userData['profileImage']?.toString();

      if (!mounted) return;
      final paidAmount = await Navigator.push<double>(
        context,
        MaterialPageRoute(
          builder: (_) => _QrPaymentPage(
            recipientName: recipientName,
            recipientEmail: recipientEmail,
            recipientUsername: recipientUsername,
            recipientGender: recipientGender,
            recipientImageUrl: recipientImageUrl,
            userId: userId,
            presetAmount: amountStr != null ? double.tryParse(amountStr) : null,
            note: note,
          ),
        ),
      );

      if (!mounted) return;
      if (paidAmount != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentSuccessPage(
              title: 'Payment Successful!',
              amount: paidAmount,
              recipientName: recipientName,
              transactionType: 'Pay via LenDen',
              extraDetails: {
                if (note.isNotEmpty) 'Note': note,
              },
              onDone: () => Navigator.of(context).pop(),
            ),
          ),
        );
        // Success page dismissed — bring scanner back to ready state
        if (mounted) _resetProcessing();
      } else {
        _resetProcessing();
      }
    } on TimeoutException {
      _showError('Request timed out. Check your connection.');
    } catch (_) {
      _showError('Failed to load recipient. Check your connection.');
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
                'Scanner not supported on this platform.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _openMyQr,
                icon: const Icon(Icons.qr_code_rounded, size: 18),
                label: const Text('My QR Code'),
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
                            backgroundColor: AppColors.cyan,
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
                    onPressed: () async {
                      await _controller?.toggleTorch();
                      if (mounted) setState(() => _torchOn = !_torchOn);
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
                  'Scan a LenDen user QR to pay',
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
                        : 'Point at a LenDen user QR code',
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
                        icon: Icons.qr_code_rounded,
                        label: 'My QR',
                        onTap: _processing ? null : _openMyQr,
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

  static const _sky = AppColors.cyan;

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

// ── Auth mode enum ────────────────────────────────────────────────────────────

// ── QR Payment full page ──────────────────────────────────────────────────────

class _QrPaymentPage extends StatefulWidget {
  final String recipientName;
  final String recipientEmail;
  final String recipientUsername;
  final String recipientGender;
  final String? recipientImageUrl;
  final String userId;
  final double? presetAmount;
  final String note;

  const _QrPaymentPage({
    required this.recipientName,
    required this.recipientEmail,
    required this.recipientUsername,
    required this.recipientGender,
    required this.userId,
    this.recipientImageUrl,
    this.presetAmount,
    this.note = '',
  });

  @override
  State<_QrPaymentPage> createState() => _QrPaymentPageState();
}

class _QrPaymentPageState extends State<_QrPaymentPage> {
  static const _sky = AppColors.cyan;
  static const _deep = Color(0xFF0077B6);

  final _amountCtrl = TextEditingController();
  final _noteCtrl   = TextEditingController();

  // Two-step flow
  bool _showAuth    = false;
  double? _balance;

  // Auth state — mirrors _WalletAuthStep in lenden_wallet_page.dart
  bool _hasPinSet    = false;
  bool _usePinMode   = true;
  String _code       = '';
  bool _sendingOtp   = false;
  bool _otpSent      = false;
  String _otpEmail   = '';
  int _timeRemaining = 120;
  Timer? _timer;

  bool _paying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.presetAmount != null)
      _amountCtrl.text = widget.presetAmount!.toStringAsFixed(2);
    if (widget.note.isNotEmpty) _noteCtrl.text = widget.note;
    _loadPinStatus();
    _loadBalance();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    try {
      final res = await ApiClient.get('/api/wallet/balance');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _balance = (data['balance'] ?? 0).toDouble());
      }
    } catch (_) {}
  }

  Future<void> _loadPinStatus() async {
    try {
      final res = await ApiClient.get('/api/wallet/pin/status');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _hasPinSet   = data['hasPin'] == true;
          _usePinMode  = _hasPinSet;
        });
      }
    } catch (_) {}
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        if (_timeRemaining > 0) _timeRemaining--;
        else timer.cancel();
      });
    });
  }

  String _formatTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  void _goToAuth() {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount greater than ₹0.');
      return;
    }
    if (_balance != null && amount > _balance!) {
      setState(() => _error =
          'Insufficient balance. Your wallet has ₹${_balance!.toStringAsFixed(2)}.');
      return;
    }
    setState(() { _showAuth = true; _error = null; });
  }

  void _backToDetails() {
    _timer?.cancel();
    setState(() {
      _showAuth = false;
      _error    = null;
      _code     = '';
      _otpSent  = false;
    });
  }

  Future<void> _sendOtp() async {
    setState(() { _sendingOtp = true; _error = null; });
    try {
      final res = await ApiClient.post('/api/wallet/auth/send-otp', body: {});
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _sendingOtp    = false;
          _otpSent       = true;
          _otpEmail      = (data['email'] ?? '').toString();
          _timeRemaining = 120;
          _code          = '';
        });
        _startTimer();
      } else {
        final b = jsonDecode(res.body);
        setState(() { _error = b['error'] ?? 'Failed to send OTP.'; _sendingOtp = false; });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Network error. Try again.'; _sendingOtp = false; });
    }
  }

  Future<void> _confirm() async {
    if (_code.length != 6) {
      setState(() => _error = 'Please enter a valid 6-digit code.');
      return;
    }
    _timer?.cancel();
    setState(() { _paying = true; _error = null; });
    try {
      final amount = double.parse(_amountCtrl.text.trim());
      final body   = <String, dynamic>{
        'toUserId': widget.userId,
        'amount'  : amount,
        'note'    : _noteCtrl.text.trim().isEmpty ? 'QR Payment' : _noteCtrl.text.trim(),
        if (_usePinMode)  'authPin': _code,
        if (!_usePinMode) 'authOtp': _code,
      };
      final res = await ApiClient.post('/api/wallet/qr-pay', body: body)
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.of(context).pop(amount);
      } else {
        final b = jsonDecode(res.body);
        setState(() { _error = b['error'] ?? 'Payment failed.'; _paying = false; });
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
    final hasImage  = widget.recipientImageUrl != null &&
        widget.recipientImageUrl!.isNotEmpty &&
        widget.recipientImageUrl != 'null';
    final genderIcon = widget.recipientGender == 'Male'
        ? Icons.person_rounded
        : widget.recipientGender == 'Female'
            ? Icons.person_2_rounded
            : Icons.person_outline_rounded;

    return PopScope(
      canPop: !_showAuth,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showAuth && !_paying) _backToDetails();
      },
      child: Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 230,
            backgroundColor: _deep,
            foregroundColor: Colors.white,
            leading: _showAuth
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: _paying ? null : _backToDetails,
                  )
                : null,
            title: Text(
              _showAuth ? 'Authorise Payment' : 'Pay via QR',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_deep, _sky],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 44),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.tricolorGradient,
                        ),
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: _deep,
                          backgroundImage: hasImage
                              ? NetworkImage(widget.recipientImageUrl!) as ImageProvider
                              : null,
                          child: !hasImage
                              ? Icon(genderIcon, color: Colors.white, size: 38)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(widget.recipientName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      if (widget.recipientUsername.isNotEmpty)
                        Text('@${widget.recipientUsername}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(widget.recipientEmail,
                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                _showAuth ? _buildAuthStep() : _buildPaymentStep(),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ── Step 1: amount + note ────────────────────────────────────────────────────

  List<Widget> _buildPaymentStep() => [
    _fieldBox('Amount (₹)', Icons.currency_rupee_rounded,
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: widget.presetAmount != null,
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppThemeColors.primaryText(context)),
          textAlign: TextAlign.center,
          decoration: _inputDeco('Enter amount'),
        )),
    const SizedBox(height: 12),
    _fieldBox('Note (optional)', Icons.note_outlined,
        TextField(
          controller: _noteCtrl,
          style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(context)),
          maxLength: 300,
          buildCounter: (ctx, {required currentLength, required isFocused, maxLength}) =>
              buildDescCounter(ctx, currentLength, maxLength),
          decoration: _inputDeco('e.g. Lunch split'),
        )),
    const SizedBox(height: 16),
    if (_balance != null)
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppThemeColors.tinted(context,
              light: const Color(0xFFF0F7FF),
              dark: const Color(0xFF16323A)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_rounded,
              size: 15, color: AppColors.cyan),
          const SizedBox(width: 8),
          Text('Wallet balance: ',
              style: TextStyle(
                  fontSize: 13, color: AppThemeColors.secondaryText(context))),
          Text('₹${_balance!.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.cyan)),
        ]),
      ),
    if (_error != null) ...[
      const SizedBox(height: 12),
      _errorBox(_error!),
    ],
    const SizedBox(height: 20),
    SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _goToAuth,
        style: ElevatedButton.styleFrom(
          backgroundColor: _sky,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text('Continue',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    ),
  ];

  // ── Step 2: PIN / OTP auth — identical look to _WalletAuthStep ───────────────

  List<Widget> _buildAuthStep() {
    final busy = _sendingOtp || _paying;
    return [
      Row(children: [
        _modeTab('Use PIN', Icons.dialpad_rounded, true),
        const SizedBox(width: 8),
        _modeTab('Use Email OTP', Icons.email_outlined, false),
      ]),
      const SizedBox(height: 16),

      if (_usePinMode) ...[
        if (!_hasPinSet) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.info_outline_rounded, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                    child: Text("You haven't set a transaction PIN yet.",
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 13,
                            fontWeight: FontWeight.w500))),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.dialpad_rounded, color: Colors.white, size: 16),
                  label: const Text('Set Up PIN',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SetWalletPinPage()));
                    _loadPinStatus();
                  },
                ),
              ),
            ]),
          ),
        ] else ...[
          Text('Enter your wallet PIN',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 10),
          Center(
              child: OtpInput(
            key: const ValueKey('pin'),
            onChanged: (code) => setState(() { _code = code; _error = null; }),
            enabled: !busy,
            autoFocus: true,
            obscureText: true,
            showVisibilityToggle: true,
          )),
        ],
      ],

      if (!_usePinMode) ...[
        if (!_otpSent) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _sendingOtp
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.email_outlined, color: Colors.white),
              label: Text(_sendingOtp ? 'Sending…' : 'Send OTP to Email',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: busy ? null : _sendOtp,
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(context,
                  light: const Color(0xFFF0F7FF),
                  dark: const Color(0xFF16323A)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('OTP sent to',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: AppThemeColors.secondaryText(context))),
              const SizedBox(height: 3),
              Text(_otpEmail,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.cyan,
                      fontSize: 13)),
            ]),
          ),
          Center(
              child: OtpInput(
            key: const ValueKey('otp'),
            onChanged: (code) => setState(() { _code = code; _error = null; }),
            enabled: !busy,
            autoFocus: true,
          )),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (_timeRemaining > 30 ? Colors.green : Colors.orange)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: (_timeRemaining > 30 ? Colors.green : Colors.orange)
                        .withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.timer,
                    size: 14,
                    color: _timeRemaining > 30 ? Colors.green : Colors.orange),
                const SizedBox(width: 4),
                Text(_formatTime(_timeRemaining),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _timeRemaining > 30 ? Colors.green : Colors.orange)),
              ]),
            ),
            TextButton(
              onPressed: (_timeRemaining == 0 && !busy) ? _sendOtp : null,
              child: Text('Resend OTP',
                  style: TextStyle(
                      color: (_timeRemaining == 0 && !busy)
                          ? AppColors.cyan
                          : Colors.grey,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
        ],
      ],

      if (_error != null) ...[
        const SizedBox(height: 10),
        _errorBox(_error!),
      ],
      const SizedBox(height: 16),

      if ((_usePinMode && _hasPinSet) || _otpSent)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyan,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: _paying
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.verified_user_rounded, color: Colors.white),
            label: Text(_paying ? 'Processing…' : 'Verify & Pay',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white)),
            onPressed: busy ? null : _confirm,
          ),
        ),
      const SizedBox(height: 8),
      Center(
          child: TextButton(
        onPressed: busy ? null : _backToDetails,
        child: Text('Back',
            style: TextStyle(color: AppThemeColors.secondaryText(context))),
      )),
    ];
  }

  Widget _modeTab(String label, IconData icon, bool isPinMode) {
    final selected = _usePinMode == isPinMode;
    return Expanded(
        child: GestureDetector(
      onTap: () => setState(() {
        _usePinMode = isPinMode;
        _code       = '';
        _error      = null;
        _otpSent    = false;
        _timer?.cancel();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AppColors.cyan : AppThemeColors.divider(context)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon,
              size: 15,
              color: selected
                  ? Colors.white
                  : AppThemeColors.secondaryText(context)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : AppThemeColors.secondaryText(context))),
        ]),
      ),
    ));
  }

  Widget _fieldBox(String label, IconData icon, Widget field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: AppThemeColors.mutedText(context)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColors.mutedText(context))),
          ]),
          const SizedBox(height: 6),
          field,
        ],
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
        filled: true,
        fillColor: AppThemeColors.surfaceBg(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppThemeColors.border(context))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppThemeColors.border(context))),
        focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: _sky, width: 1.8)),
      );

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Flexible(
              child: Text(msg,
                  style: const TextStyle(color: Colors.red, fontSize: 13))),
        ]),
      );
}

// ── Self-pay full page ────────────────────────────────────────────────────────

class _QrSelfPayPage extends StatelessWidget {
  final SessionProvider session;
  const _QrSelfPayPage({required this.session});

  @override
  Widget build(BuildContext context) {
    final name     = session.user?['name']?.toString() ?? 'You';
    final username = session.user?['username']?.toString() ?? '';
    final email    = session.user?['email']?.toString() ?? '';
    final imageUrl = session.user?['profileImage']?.toString();
    final gender   = session.user?['gender']?.toString() ?? 'Other';
    final hasImage = imageUrl != null && imageUrl.isNotEmpty && imageUrl != 'null';
    final genderIcon = gender == 'Male'
        ? Icons.person_rounded
        : gender == 'Female'
            ? Icons.person_2_rounded
            : Icons.person_outline_rounded;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('Scan & Pay',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        foregroundColor: AppThemeColors.primaryText(context),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.tricolorGradient,
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: AppColors.cyan,
                      backgroundImage: hasImage
                          ? NetworkImage(imageUrl) as ImageProvider
                          : null,
                      child: !hasImage
                          ? Icon(genderIcon, color: Colors.white, size: 46)
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(name,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context))),
              if (username.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('@$username',
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.cyan)),
              ],
              if (email.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(email,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppThemeColors.mutedText(context))),
              ],
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFFFFBE6),
                      dark: const Color(0xFF2B1A00)),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                ),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.info_rounded,
                        color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Text("That's You!",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context))),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    'You cannot send money to yourself. Scan another user\'s QR code to make a payment.',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppThemeColors.secondaryText(context),
                        height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: const Text('Back to Scanner',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
