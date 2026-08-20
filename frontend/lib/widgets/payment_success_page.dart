import 'dart:math';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../utils/share_utils.dart';
import 'share_as_note_sheet.dart';

/// Reusable full-screen payment success celebration.
///
/// Push via [Navigator.push] or [Navigator.pushReplacement]:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(builder: (_) =>
///   PaymentSuccessPage(
///     title: 'Payment Successful!',
///     amount: 500.0,
///     currency: '₹',
///     recipientName: 'Alice',
///     transactionType: 'Quick Transaction',
///     extraDetails: {'Reference': 'TXN12345'},
///   )));
/// ```
class PaymentSuccessPage extends StatefulWidget {
  final String title;
  final double? amount;
  final String currency;
  final String? recipientName;
  final String transactionType;
  final Map<String, String> extraDetails;
  final VoidCallback? onDone;

  const PaymentSuccessPage({
    super.key,
    this.title = 'Payment Successful!',
    this.amount,
    this.currency = '₹',
    this.recipientName,
    this.transactionType = 'Payment',
    this.extraDetails = const {},
    this.onDone,
  });

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage>
    with TickerProviderStateMixin {
  late AnimationController _checkController;
  late AnimationController _burstController;
  late Animation<double> _checkScale;
  late Animation<double> _checkOpacity;
  late Animation<double> _burstOpacity;
  late Animation<double> _slideUp;

  static const _cyan = AppColors.cyan;
  static const _green = AppColors.tricolorGreen;
  static const _saffron = AppColors.tricolorOrange;

  @override
  void initState() {
    super.initState();

    _checkController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _burstController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));

    _checkScale = CurvedAnimation(
        parent: _checkController, curve: Curves.elasticOut);
    _checkOpacity = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _checkController, curve: const Interval(0, 0.4)));
    _burstOpacity = Tween<double>(begin: 1, end: 0)
        .animate(CurvedAnimation(parent: _burstController, curve: Curves.easeOut));
    _slideUp = Tween<double>(begin: 40, end: 0)
        .animate(CurvedAnimation(parent: _checkController, curve: Curves.easeOut));

    Future.delayed(const Duration(milliseconds: 100), () {
      _checkController.forward();
      Future.delayed(const Duration(milliseconds: 200), () {
        _burstController.repeat(reverse: false);
      });
    });
  }

  @override
  void dispose() {
    _checkController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  void _shareReceipt() {
    final now = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
    fetchAppInviteLink().then((appLink) {
      final buf = StringBuffer();
      buf.writeln('🎉 ${widget.title}');
      buf.writeln('');
      buf.writeln('📋 Receipt — LenDen App');
      buf.writeln('--------------------');
      buf.writeln('Type     : ${widget.transactionType}');
      if (widget.amount != null) {
        buf.writeln(
            'Amount   : ${widget.currency}${widget.amount!.toStringAsFixed(2)}');
      }
      if (widget.recipientName != null) {
        buf.writeln('To       : ${widget.recipientName}');
      }
      buf.writeln('Date     : $now');
      for (final e in widget.extraDetails.entries) {
        buf.writeln('${e.key.padRight(9)}: ${e.value}');
      }
      buf.writeln('--------------------');
      buf.writeln('Powered by LenDen — Lend, borrow & manage money together.');
      if (appLink.isNotEmpty) buf.writeln('📥 $appLink');
      Share.share(buf.toString(), subject: 'LenDen Payment Receipt');
    });
  }

  void _shareAsNote() {
    final now = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
    final buf = StringBuffer();
    buf.writeln('Type: ${widget.transactionType}');
    if (widget.amount != null) buf.writeln('Amount: ${widget.currency}${widget.amount!.toStringAsFixed(2)}');
    if (widget.recipientName != null) buf.writeln('To: ${widget.recipientName}');
    buf.writeln('Date: $now');
    final _idPattern = RegExp(
      r'^[0-9a-f]{24}$|^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    for (final e in widget.extraDetails.entries) {
      if (_idPattern.hasMatch(e.value.trim())) continue;
      buf.writeln('${e.key}: ${e.value}');
    }
    showShareAsNoteSheet(context, title: widget.title, content: buf.toString().trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF005F85), AppColors.cyan, Color(0xFF48CAE4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Confetti burst circles
              ..._buildBurstDots(),

              // Main content
              Column(
                children: [
                  const Spacer(flex: 2),

                  // Animated check circle
                  AnimatedBuilder(
                    animation: _checkController,
                    builder: (_, __) => Opacity(
                      opacity: _checkOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, _slideUp.value),
                        child: Transform.scale(
                          scale: _checkScale.value,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: AppColors.cyan, size: 65),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Title
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  if (widget.amount != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${widget.currency}${widget.amount!.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ],

                  if (widget.recipientName != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'to ${widget.recipientName}',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],

                  const Spacer(flex: 1),

                  // Receipt card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Tricolor bar at top of card
                          Container(
                            height: 3,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: const LinearGradient(
                                colors: [_saffron, Colors.white, _green],
                              ),
                            ),
                          ),
                          _receiptRow(Icons.category_rounded,
                              t('type'), widget.transactionType),
                          if (widget.amount != null)
                            _receiptRow(Icons.currency_rupee_rounded, t('amount'),
                                '${widget.currency}${widget.amount!.toStringAsFixed(2)}'),
                          if (widget.recipientName != null)
                            _receiptRow(Icons.person_rounded, t('to'),
                                widget.recipientName!),
                          _receiptRow(Icons.calendar_today_rounded, t('date'),
                              DateFormat('dd MMM yyyy, hh:mm a')
                                  .format(DateTime.now())),
                          for (final e in widget.extraDetails.entries)
                            _receiptRow(Icons.info_outline_rounded,
                                e.key, e.value),
                          const SizedBox(height: 8),
                          // Powered by
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.verified_rounded,
                                  size: 13,
                                  color: Colors.grey.shade400),
                              const SizedBox(width: 4),
                              Text(t('secured_by_lenden'),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade400)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _shareReceipt,
                            icon: const Icon(Icons.share_rounded,
                                color: Colors.white),
                            label: Text(t('share_receipt'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Colors.white, width: 1.5),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (widget.onDone != null) {
                                widget.onDone!();
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _cyan,
                              elevation: 0,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(t('done'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _shareAsNote,
                    icon: const Icon(Icons.note_add_rounded, color: Colors.white, size: 18),
                    label: const Text(
                      'Share as Note',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),

                  const Spacer(flex: 1),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _cyan),
          const SizedBox(width: 8),
          Text('$label:',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF005F85)),
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBurstDots() {
    final rng = Random(42);
    final colors = [
      _saffron, Colors.white, _green, _cyan, Colors.yellow,
      Colors.pinkAccent, Colors.white70
    ];
    return List.generate(18, (i) {
      final x = rng.nextDouble();
      final y = rng.nextDouble();
      final size = 6.0 + rng.nextDouble() * 12;
      final color = colors[i % colors.length];
      final delay = rng.nextDouble() * 0.6;

      return AnimatedBuilder(
        animation: _burstController,
        builder: (ctx, _) {
          final t = ((_burstController.value - delay).clamp(0, 1.0));
          final dy = -120.0 * t;
          final opacity = (1.0 - t).clamp(0.0, 1.0);
          return Positioned(
            left: MediaQuery.of(ctx).size.width * x,
            top: MediaQuery.of(ctx).size.height * y + dy,
            child: Opacity(
              opacity: opacity * _burstOpacity.value,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: color,
                  shape: i % 3 == 0 ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius:
                      i % 3 != 0 ? BorderRadius.circular(2) : null,
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
