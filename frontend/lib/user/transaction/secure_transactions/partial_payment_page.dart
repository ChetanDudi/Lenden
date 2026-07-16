import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/api_client.dart';
import '../../../session.dart';
import '../../../otp_input.dart';
import '../../../widgets/wave_widget.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/payment_success_page.dart';
import '../../wallet/lenden_wallet_page.dart';
import '../../../settings/set_wallet_pin_page.dart';
import '../../../utils/display_currency_helper.dart';

class PartialPaymentPage extends StatefulWidget {
  final Map<String, dynamic> transaction;
  // When true, the amount is preset to the full remaining balance and locked
  // — this is the "Pay Now" entry point reusing the same two-sided-OTP,
  // real-wallet-transfer flow instead of a separate no-OTP payment path.
  final bool isFullPayment;

  const PartialPaymentPage(
      {Key? key, required this.transaction, this.isFullPayment = false})
      : super(key: key);

  @override
  _PartialPaymentPageState createState() => _PartialPaymentPageState();
}

class _PartialPaymentPageState extends State<PartialPaymentPage> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _lenderOtpController = TextEditingController();
  final TextEditingController _borrowerOtpController = TextEditingController();

  String? lenderEmail;
  String? borrowerEmail;
  String? paidBy;
  bool lenderOtpSent = false;
  bool borrowerOtpSent = false;
  bool lenderOtpVerified = false;
  bool borrowerOtpVerified = false;
  bool isProcessing = false;
  bool isSendingLenderOtp = false;
  bool isSendingBorrowerOtp = false;
  bool isVerifyingLenderOtp = false;
  bool isVerifyingBorrowerOtp = false;
  String? message;
  bool isMessageError = false;
  String? _amountWarning;
  bool _insufficientBalance = false;

  // PIN alternative for the payer's own verification step.
  bool _hasPinSet = false;
  bool _payerPinMode = false; // true → payer uses PIN, false → payer uses OTP
  String _payerPinCode = '';
  bool _verifyingPayerPin = false;

  int lenderOtpSecondsLeft = 0;
  int borrowerOtpSecondsLeft = 0;
  bool lenderOtpExpired = false;
  bool borrowerOtpExpired = false;
  Timer? _otpTimer;

  @override
  void initState() {
    super.initState();
    _initializeEmails();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _checkOtpExpiration();
    });
    _amountController.addListener(_validateAmount);
    if (widget.isFullPayment) {
      _amountController.text = _calculateRemainingAmount(widget.transaction);
    }
    _loadPinStatus();
  }

  Future<void> _loadPinStatus() async {
    try {
      final res = await ApiClient.get('/api/wallet/pin/status');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _hasPinSet = data['hasPin'] == true;
          _payerPinMode = _hasPinSet;
        });
      }
    } catch (_) {}
  }

  Future<void> _verifyPayerPin() async {
    if (_payerPinCode.length != 6) {
      _showMessage('Please enter your 6-digit PIN.', isError: true);
      return;
    }
    setState(() => _verifyingPayerPin = true);
    try {
      final res = await ApiClient.post(
          '/api/transactions/partial-payment/verify-pin',
          body: {
            'transactionId': widget.transaction['transactionId'],
            'pin': _payerPinCode,
          });
      if (!mounted) return;
      final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
      if (res.statusCode == 200) {
        final role = (data?['role'] ?? '').toString();
        setState(() {
          _verifyingPayerPin = false;
          if (role == 'lender') lenderOtpVerified = true;
          if (role == 'borrower') borrowerOtpVerified = true;
        });
        _showMessage('PIN verified');
      } else {
        setState(() => _verifyingPayerPin = false);
        _showMessage(data?['error'] ?? 'PIN verification failed',
            isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _verifyingPayerPin = false);
        _showMessage('$e', isError: true);
      }
    }
  }

  void _validateAmount() {
    final entered = double.tryParse(_amountController.text);
    final remaining =
        double.tryParse(_calculateRemainingAmount(widget.transaction)) ?? 0.0;
    setState(() {
      if (entered != null && entered > remaining) {
        _amountWarning =
            'Amount exceeds the remaining balance of ${remaining.toStringAsFixed(2)} ${widget.transaction['currency'] ?? ''}. You cannot pay more than what is owed.';
      } else {
        _amountWarning = null;
      }
    });
  }

  void _initializeEmails() {
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    final userEmail = user?['email']?.toString();
    final role = widget.transaction['role']?.toString() ?? '';
    final txUserEmail = widget.transaction['userEmail']?.toString();
    final txCounterpartyEmail = widget.transaction['counterpartyEmail']?.toString();

    if (role == 'lender') {
      lenderEmail = txUserEmail;
      borrowerEmail = txCounterpartyEmail;
    } else {
      lenderEmail = txCounterpartyEmail;
      borrowerEmail = txUserEmail;
    }

    if (userEmail != null && lenderEmail != null &&
        userEmail.toLowerCase() == lenderEmail!.toLowerCase()) {
      paidBy = 'lender';
    } else if (userEmail != null && borrowerEmail != null &&
        userEmail.toLowerCase() == borrowerEmail!.toLowerCase()) {
      paidBy = 'borrower';
    }
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    _amountController.removeListener(_validateAmount);
    _amountController.dispose();
    _descriptionController.dispose();
    _lenderOtpController.dispose();
    _borrowerOtpController.dispose();
    super.dispose();
  }

  void _showMessage(String msg, {bool isError = false}) {
    setState(() {
      message = msg;
      isMessageError = isError;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => message = null);
    });
  }

  String _calculateRemainingAmount(Map transaction) {
    double original = transaction['amount']?.toDouble() ?? 0.0;
    double paid = 0.0;
    bool isFullyCleared = (transaction['userCleared'] == true &&
        transaction['counterpartyCleared'] == true);
    if (isFullyCleared) {
      paid = original;
    } else if (transaction['isPartiallyPaid'] == true &&
        transaction['partialPayments'] != null) {
      List pp = transaction['partialPayments'] as List;
      paid = pp.fold<double>(0, (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0.0));
    }
    double remaining = original - paid;
    if (paid >= original) return '0.00';
    if (transaction['interestType'] != null &&
        transaction['interestRate'] != null) {
      final txDate = DateTime.tryParse(transaction['date'] ?? '');
      if (txDate != null) {
        final days = DateTime.now().difference(txDate).inDays;
        if (days > 0) {
          final rate = transaction['interestRate']?.toDouble() ?? 0.0;
          if (transaction['interestType'] == 'simple') {
            remaining = remaining + (remaining * rate * days / 365);
          } else if (transaction['interestType'] == 'compound') {
            final n = transaction['compoundingFrequency']?.toInt() ?? 1;
            remaining =
                remaining * pow(1 + (rate / 100) / n, n * (days / 365.0));
          }
        }
      }
    }
    return remaining.toStringAsFixed(2);
  }

  void _checkOtpExpiration() {
    if (lenderOtpSecondsLeft > 0 && lenderOtpSent && !lenderOtpVerified) {
      setState(() => lenderOtpSecondsLeft--);
      if (lenderOtpSecondsLeft == 0) {
        setState(() => lenderOtpExpired = true);
        _showMessage('Lender OTP has expired. Please resend.', isError: true);
      }
    }
    if (borrowerOtpSecondsLeft > 0 && borrowerOtpSent && !borrowerOtpVerified) {
      setState(() => borrowerOtpSecondsLeft--);
      if (borrowerOtpSecondsLeft == 0) {
        setState(() => borrowerOtpExpired = true);
        _showMessage('Borrower OTP has expired. Please resend.', isError: true);
      }
    }
  }

  Future<void> _sendOtp(String email, bool isLender) async {
    setState(() {
      if (isLender) {
        isSendingLenderOtp = true;
      } else {
        isSendingBorrowerOtp = true;
      }
    });
    try {
      final response = await ApiClient.post(
          '/api/transactions/send-partial-payment-otp',
          body: {'email': email});
      if (response.statusCode == 200) {
        setState(() {
          if (isLender) {
            lenderOtpSent = true;
            lenderOtpSecondsLeft = 120;
            lenderOtpExpired = false;
            isSendingLenderOtp = false;
          } else {
            borrowerOtpSent = true;
            borrowerOtpSecondsLeft = 120;
            borrowerOtpExpired = false;
            isSendingBorrowerOtp = false;
          }
        });
        _showMessage('OTP sent to ${isLender ? 'lender' : 'borrower'} email');
      } else {
        final data =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        _showMessage(data['error'] ?? 'Failed to send OTP', isError: true);
        setState(() {
          if (isLender) {
            isSendingLenderOtp = false;
          } else {
            isSendingBorrowerOtp = false;
          }
        });
      }
    } catch (e) {
      _showMessage('Network error: ${e.toString()}', isError: true);
      setState(() {
        if (isLender) {
          isSendingLenderOtp = false;
        } else {
          isSendingBorrowerOtp = false;
        }
      });
    }
  }

  Future<void> _verifyOtp(String email, String otp, bool isLender) async {
    if (isLender && lenderOtpExpired) {
      _showMessage('Lender OTP has expired. Please resend.', isError: true);
      return;
    }
    if (!isLender && borrowerOtpExpired) {
      _showMessage('Borrower OTP has expired. Please resend.', isError: true);
      return;
    }
    setState(() {
      if (isLender) {
        isVerifyingLenderOtp = true;
      } else {
        isVerifyingBorrowerOtp = true;
      }
    });
    try {
      final response = await ApiClient.post(
          '/api/transactions/verify-partial-payment-otp',
          body: {
            'email': email,
            'otp': otp,
            'transactionId': widget.transaction['transactionId'],
          });
      if (response.statusCode == 200) {
        setState(() {
          if (isLender) {
            lenderOtpVerified = true;
            isVerifyingLenderOtp = false;
          } else {
            borrowerOtpVerified = true;
            isVerifyingBorrowerOtp = false;
          }
        });
        _showMessage('OTP verified for ${isLender ? 'lender' : 'borrower'}');
      } else {
        final data =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        _showMessage(data['error'] ?? 'Failed to verify OTP', isError: true);
        setState(() {
          if (isLender) {
            isVerifyingLenderOtp = false;
          } else {
            isVerifyingBorrowerOtp = false;
          }
        });
      }
    } catch (e) {
      _showMessage('Network error: ${e.toString()}', isError: true);
      setState(() {
        if (isLender) {
          isVerifyingLenderOtp = false;
        } else {
          isVerifyingBorrowerOtp = false;
        }
      });
    }
  }

  Future<void> _processPartialPayment() async {
    if (!lenderOtpVerified || !borrowerOtpVerified) {
      _showMessage('Both parties must verify their OTP', isError: true);
      return;
    }
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      _showMessage('Please enter a valid amount', isError: true);
      return;
    }
    final remainingAmount =
        double.tryParse(_calculateRemainingAmount(widget.transaction)) ?? 0.0;
    if (amount > remainingAmount) {
      _showMessage(
          'Payment amount cannot exceed remaining amount of ${remainingAmount.toStringAsFixed(2)} ${widget.transaction['currency']}',
          isError: true);
      return;
    }
    setState(() {
      isProcessing = true;
      _insufficientBalance = false;
    });
    try {
      // transactionId + paidBy is enough — the backend derives lender/borrower
      // emails from the transaction record itself and checks OTP verification
      // server-side, rather than trusting client-sent emails/booleans.
      final response =
          await ApiClient.post('/api/transactions/partial-payment', body: {
        'transactionId': widget.transaction['transactionId'],
        'amount': amount,
        'description': _descriptionController.text,
        'paidBy': paidBy,
      });
      if (response.statusCode == 200) {
        final recipient = paidBy == 'lender' ? borrowerEmail : lenderEmail;
        final note = _descriptionController.text.trim();
        if (mounted) {
          // Capture the NavigatorState before pushReplacement — once this
          // page is replaced, its own `context` becomes defunct, so onDone
          // (invoked later when the user taps "Done") must not look it up
          // again via Navigator.of(context).
          final navigator = Navigator.of(context);
          navigator.pushReplacement(
            MaterialPageRoute(
              builder: (_) => PaymentSuccessPage(
                title: widget.isFullPayment
                    ? 'Payment Successful!'
                    : 'Partial Payment Successful!',
                amount: amount,
                currency: currencySymbolFor(widget.transaction['currency'] as String?),
                recipientName: recipient,
                transactionType: widget.isFullPayment
                    ? 'Secure Transaction — Full Payment'
                    : 'Secure Transaction — Partial Payment',
                extraDetails: note.isNotEmpty ? {'Note': note} : const {},
                onDone: () => navigator.pop(true),
              ),
            ),
          );
        }
      } else {
        final data =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        final errMsg =
            (data?['error'] ?? 'Failed to process partial payment').toString();
        setState(() => _insufficientBalance =
            errMsg.toLowerCase().contains('insufficient'));
        _showMessage(errMsg, isError: true);
      }
    } catch (e) {
      _showMessage('Network error: ${e.toString()}', isError: true);
    } finally {
      setState(() => isProcessing = false);
    }
  }

  // Returns the right verification widget for each party.
  // The payer (whichever side matches `paidBy`) gets a PIN/OTP toggle;
  // the counterparty always uses OTP only (they can't use your PIN).
  Widget _buildVerificationSection({required bool isLender}) {
    final isPayerSide = (paidBy == 'lender') == isLender;
    final verified = isLender ? lenderOtpVerified : borrowerOtpVerified;

    if (isPayerSide && !verified) {
      // Payer section — always shows PIN/OTP tabs so user knows the option exists
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _modePillTab('Use PIN', Icons.dialpad_rounded, true),
          const SizedBox(width: 8),
          _modePillTab('Use OTP', Icons.email_outlined, false),
        ]),
        const SizedBox(height: 12),
        if (_payerPinMode) ...[
          if (!_hasPinSet) ...[
            // PIN not configured yet — show redirect prompt
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.info_outline_rounded,
                          color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('You haven\'t set up a wallet PIN yet.',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500))),
                    ]),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      icon: const Icon(Icons.dialpad_rounded,
                          color: Colors.white, size: 15),
                      label: const Text('Set Up PIN',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SetWalletPinPage()));
                        if (mounted) _loadPinStatus();
                      },
                    ),
                  ]),
            ),
          ] else ...[
            // PIN configured — show PIN input
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, 1))
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.dialpad_rounded,
                          color: AppColors.cyan, size: 20),
                      const SizedBox(width: 8),
                      const Text('Your Transaction PIN',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                        'Enter your 6-digit wallet PIN to verify your identity.',
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[600])),
                    const SizedBox(height: 12),
                    OtpInput(
                      onChanged: (code) => setState(() {
                        _payerPinCode = code;
                      }),
                      enabled: !_verifyingPayerPin && !isProcessing,
                      autoFocus: false,
                      obscureText: true,
                      showVisibilityToggle: true,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _verifyingPayerPin ? null : _verifyPayerPin,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                      child: _verifyingPayerPin
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white)),
                              const SizedBox(width: 8),
                              const Text('Verifying…'),
                            ])
                          : const Text('Verify PIN'),
                    ),
                  ]),
            ),
          ],
        ] else ...[
          // OTP mode — existing OTP section
          _otpSection(
            title: isLender
                ? 'Lender OTP Verification'
                : 'Borrower OTP Verification',
            email: isLender ? lenderEmail : borrowerEmail,
            otpSent: isLender ? lenderOtpSent : borrowerOtpSent,
            otpVerified: isLender ? lenderOtpVerified : borrowerOtpVerified,
            otpExpired: isLender ? lenderOtpExpired : borrowerOtpExpired,
            otpSecondsLeft:
                isLender ? lenderOtpSecondsLeft : borrowerOtpSecondsLeft,
            isSending: isLender ? isSendingLenderOtp : isSendingBorrowerOtp,
            isVerifying:
                isLender ? isVerifyingLenderOtp : isVerifyingBorrowerOtp,
            otpController:
                isLender ? _lenderOtpController : _borrowerOtpController,
            isLender: isLender,
          ),
        ],
      ]);
    }

    // Counterparty or already-verified: always OTP-only
    return _otpSection(
      title: isLender ? 'Lender OTP Verification' : 'Borrower OTP Verification',
      email: isLender ? lenderEmail : borrowerEmail,
      otpSent: isLender ? lenderOtpSent : borrowerOtpSent,
      otpVerified: isLender ? lenderOtpVerified : borrowerOtpVerified,
      otpExpired: isLender ? lenderOtpExpired : borrowerOtpExpired,
      otpSecondsLeft: isLender ? lenderOtpSecondsLeft : borrowerOtpSecondsLeft,
      isSending: isLender ? isSendingLenderOtp : isSendingBorrowerOtp,
      isVerifying: isLender ? isVerifyingLenderOtp : isVerifyingBorrowerOtp,
      otpController: isLender ? _lenderOtpController : _borrowerOtpController,
      isLender: isLender,
    );
  }

  Widget _modePillTab(String label, IconData icon, bool isPinMode) {
    final selected = _payerPinMode == isPinMode;
    return Expanded(
        child: GestureDetector(
      onTap: () => setState(() {
        _payerPinMode = isPinMode;
        _payerPinCode = '';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppColors.cyan : Colors.grey.shade300),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon,
              size: 14, color: selected ? Colors.white : Colors.grey[600]),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey[600])),
        ]),
      ),
    ));
  }

  Widget _otpSection({
    required String title,
    required String? email,
    required bool otpSent,
    required bool otpVerified,
    required bool otpExpired,
    required int otpSecondsLeft,
    required bool isSending,
    required bool isVerifying,
    required TextEditingController otpController,
    required bool isLender,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.lock_clock, color: AppColors.cyan, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          Text('Email: ${email ?? ''}'),
          const SizedBox(height: 8),
          if (otpSent) ...[
            Text('Enter the 6-digit OTP sent to $email:',
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 12),
            OtpInput(
              onChanged: (val) => otpController.text = val,
              enabled: otpSent,
              autoFocus: false,
              obscureText: true,
              showVisibilityToggle: true,
            ),
            const SizedBox(height: 12),
          ],
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: (email != null &&
                        !isSending &&
                        !otpVerified &&
                        (!otpSent || otpExpired))
                    ? () => _sendOtp(email, isLender)
                    : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                        otpVerified ? Colors.green : Colors.orange),
                child: isSending
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white)),
                        const SizedBox(width: 8),
                        const Text('Sending OTP...'),
                      ])
                    : otpVerified
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.check_circle,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            const Text('Verified'),
                          ])
                        : otpExpired
                            ? const Text('Resend OTP')
                            : const Text('Send OTP'),
              ),
            ),
          ]),
          if (otpSent && !otpVerified) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(otpExpired ? Icons.warning : Icons.timer,
                  color: otpExpired ? Colors.red : Colors.orange, size: 14),
              const SizedBox(width: 4),
              Text(
                otpExpired
                    ? 'OTP expired. Please resend.'
                    : 'OTP expires in ${otpSecondsLeft ~/ 60}:${(otpSecondsLeft % 60).toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 12,
                    color: otpExpired ? Colors.red : Colors.orange),
              ),
            ]),
          ],
          if (message != null &&
              ((isLender &&
                      (message!.contains('lender') ||
                          message!.contains('Lender'))) ||
                  (!isLender &&
                      (message!.contains('borrower') ||
                          message!.contains('Borrower'))))) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMessageError
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: isMessageError
                        ? Colors.red.withValues(alpha: 0.3)
                        : Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(isMessageError ? Icons.error : Icons.check_circle,
                    color: isMessageError ? Colors.red : Colors.green,
                    size: 16),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(message!,
                        style: TextStyle(
                            color: isMessageError
                                ? Colors.red[700]
                                : Colors.green[700],
                            fontWeight: FontWeight.w500,
                            fontSize: 12))),
              ]),
            ),
          ],
          if (otpSent && !otpVerified) ...[
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: (!isVerifying && email != null)
                  ? () => _verifyOtp(email, otpController.text, isLender)
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: isVerifying
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white)),
                      const SizedBox(width: 8),
                      const Text('Verifying OTP...'),
                    ])
                  : const Text('Verify OTP'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.isFullPayment ? 'Pay Now' : 'Partial Payment',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: const TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.purple, Color(0xFF7B1FA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: context.sh(90)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.payment, color: AppColors.cyan, size: 28),
                    const SizedBox(width: 12),
                    Text(widget.isFullPayment ? 'Pay Now' : 'Partial Payment',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: 'Payment Amount',
                      border: OutlineInputBorder(
                        borderSide: BorderSide(
                          color:
                              _amountWarning != null ? Colors.red : Colors.grey,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color:
                              _amountWarning != null ? Colors.red : Colors.grey,
                          width: _amountWarning != null ? 1.5 : 1.0,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: _amountWarning != null
                              ? Colors.red
                              : AppColors.cyan,
                          width: 2,
                        ),
                      ),
                      prefixIcon: const Icon(Icons.attach_money),
                      helperText: widget.isFullPayment
                          ? 'Paying the full remaining amount'
                          : (lenderOtpVerified && borrowerOtpVerified)
                              ? 'Amount locked after OTP verification'
                              : 'Maximum: ${_calculateRemainingAmount(widget.transaction)} ${widget.transaction['currency']}',
                      helperMaxLines: 2,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    enabled: !widget.isFullPayment &&
                        !(lenderOtpVerified && borrowerOtpVerified),
                  ),
                  if (_amountWarning != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.red, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _amountWarning!,
                            style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded,
                            color: AppColors.cyan, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${currencySymbolFor(widget.transaction['currency'] as String?)}${_amountController.text.trim().isNotEmpty ? _amountController.text.trim() : _calculateRemainingAmount(widget.transaction)} will be deducted from your LenDen Wallet and credited to the other party once both OTPs are verified.',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.blueGrey[700],
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Description (Optional)',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.description),
                      helperText: (lenderOtpVerified && borrowerOtpVerified)
                          ? 'Description locked after OTP verification'
                          : null,
                    ),
                    maxLines: 2,
                    enabled: !(lenderOtpVerified && borrowerOtpVerified),
                  ),
                  const SizedBox(height: 20),
                  _buildVerificationSection(isLender: true),
                  const SizedBox(height: 16),
                  _buildVerificationSection(isLender: false),
                  const SizedBox(height: 20),
                  if (message != null &&
                      !message!.contains('lender') &&
                      !message!.contains('Lender') &&
                      !message!.contains('borrower') &&
                      !message!.contains('Borrower')) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMessageError
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isMessageError
                                ? Colors.red.withValues(alpha: 0.3)
                                : Colors.green.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Icon(isMessageError ? Icons.error : Icons.check_circle,
                            color: isMessageError ? Colors.red : Colors.green,
                            size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(message!,
                                style: TextStyle(
                                    color: isMessageError
                                        ? Colors.red[700]
                                        : Colors.green[700],
                                    fontWeight: FontWeight.w500))),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_insufficientBalance) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppColors.cyan, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.add_card_rounded,
                            color: AppColors.cyan),
                        label: const Text('Add Money',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppColors.cyan)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LendenWalletPage(
                                    autoOpenAddMoney: true)),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                            onPressed: isProcessing
                                ? null
                                : () => Navigator.pop(context, false),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey),
                            child: const Text('Cancel',
                                style: TextStyle(color: Colors.white))),
                        ElevatedButton(
                            onPressed: (lenderOtpVerified &&
                                    borrowerOtpVerified &&
                                    !isProcessing &&
                                    _amountWarning == null)
                                ? _processPartialPayment
                                : null,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green),
                            child: isProcessing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Text(
                                    widget.isFullPayment
                                        ? 'Pay Now'
                                        : 'Process Payment',
                                    style:
                                        const TextStyle(color: Colors.white))),
                      ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
