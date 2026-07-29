import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../session.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/theme_helper.dart';

class UserQrPage extends StatefulWidget {
  const UserQrPage({super.key});

  @override
  State<UserQrPage> createState() => _UserQrPageState();
}

class _UserQrPageState extends State<UserQrPage> {
  final _qrKey = GlobalKey();
  bool _sharing = false;

  String _buildQrData(SessionProvider session) {
    final userId = session.user?['_id']?.toString() ?? '';
    final username = Uri.encodeComponent(
        session.user?['username']?.toString() ?? '');
    return 'lenden://pay?userId=$userId&username=$username';
  }

  Future<void> _shareQr(SessionProvider session) async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) showSnack(context, 'QR code not ready. Please try again.', isError: true);
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || !mounted) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/lenden_qr.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      final username =
          session.user?['username']?.toString() ?? 'me';
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Scan this QR code to pay me on LenDen (@$username)',
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Could not share QR code. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _buildAvatar(SessionProvider session) {
    final imageUrl = session.user?['profileImage']?.toString();
    final gender = session.user?['gender']?.toString() ?? 'Other';
    final hasImage = imageUrl != null &&
        imageUrl.isNotEmpty &&
        imageUrl != 'null';
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
      ),
      child: ClipOval(
        child: hasImage
            ? Image.network(
                '$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultAvatarImage(gender),
              )
            : _defaultAvatarImage(gender),
      ),
    );
  }

  Widget _defaultAvatarImage(String gender) => Image.asset(
        gender == 'Male'
            ? 'assets/Male.png'
            : gender == 'Female'
                ? 'assets/Female.png'
                : 'assets/Other.png',
        fit: BoxFit.cover,
      );

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final name = session.user?['name']?.toString() ?? 'User';
    final username = session.user?['username']?.toString() ?? '';
    final qrData = _buildQrData(session);
    final isDark = AppThemeColors.isDark(context);

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: 'My QR Code'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Card containing the QR
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.15),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Gradient header band
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0077B6), AppColors.cyan],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24)),
                      ),
                      child: Column(
                        children: [
                          _buildAvatar(session),
                          const SizedBox(height: 10),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '@$username',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // QR code area
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: RepaintBoundary(
                        key: _qrKey,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.cyan.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              QrImageView(
                                data: qrData,
                                version: QrVersions.auto,
                                size: 200,
                                backgroundColor: Colors.white,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Color(0xFF0077B6),
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Color(0xFF003d75),
                                ),
                              ),
                              const SizedBox(height: 10),
                              // LenDen branding below QR
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.account_balance_wallet_rounded,
                                    size: 14,
                                    color: AppColors.cyan,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'LenDen Pay',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.cyan,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Instruction
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 20, right: 20, bottom: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : AppColors.cyan.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 16, color: AppColors.cyan),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Show this QR code to someone who wants to pay you. '
                                'They scan it with their LenDen app.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      AppThemeColors.secondaryText(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Share button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sharing
                      ? null
                      : () => _shareQr(session),
                  icon: _sharing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.share_rounded,
                          color: Colors.white, size: 18),
                  label: Text(
                    _sharing ? 'Preparing…' : 'Share QR Code',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Only other LenDen users can pay via this QR.',
                style: TextStyle(
                    fontSize: 12,
                    color: AppThemeColors.mutedText(context)),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
