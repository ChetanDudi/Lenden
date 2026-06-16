//This file is to create Transactions.
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import '../../../otp_input.dart';
import 'package:provider/provider.dart';
import 'package:http_parser/http_parser.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
// Add for wavy background
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'view_secure_transactions_page.dart';
import '../../digitise/gift_card_page.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../widgets/payment_success_page.dart';
import '../../digitise/subscriptions_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.8);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height * 0.8,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.6,
      size.width,
      size.height * 0.8,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class TransactionPage extends StatefulWidget {
  final String? prefillCounterpartyEmail;

  const TransactionPage({Key? key, this.prefillCounterpartyEmail})
      : super(key: key);

  @override
  _TransactionPageState createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  String _currency = 'INR';
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final TextEditingController _placeController = TextEditingController();
  List<PlatformFile> _pickedFiles = [];
  final TextEditingController _counterpartyEmailController =
      TextEditingController();
  final TextEditingController _userEmailController = TextEditingController();
  String? _transactionId;
  String _role = 'lender'; // default
  bool _isLoading = false;
  String? _counterpartyOtp;
  String? _userOtp;
  String? _counterpartyOtpError;
  String? _userOtpError;
  String? _counterpartyEmailError;
  String? _userEmailError;
  String? _sameEmailError;
  int _counterpartyOtpSeconds = 0;
  int _userOtpSeconds = 0;
  bool _counterpartyVerified = false;
  bool _userVerified = false;
  String _interestType = 'none';
  final TextEditingController _interestRateController = TextEditingController();
  DateTime? _expectedReturnDate;
  int _compoundingFrequency = 1; // default annually
  final TextEditingController _descriptionController = TextEditingController();
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _friendSuggestions = [];
  Set<String> _blockedEmails = {};
  int? _dailyUserTxRemaining;
  bool _restoringDraft = false;
  DateTime? _lastDraftSavedAt;
  String _draftStatusMessage = 'Auto-save ready';

  // Computed property to check if both users are verified
  bool get _bothUsersVerified => _counterpartyVerified && _userVerified;

  final List<Map<String, String>> _currencies = [
    {'code': 'INR', 'symbol': '₹'},
    {'code': 'USD', 'symbol': '\$'},
    {'code': 'EUR', 'symbol': '€'},
    {'code': 'GBP', 'symbol': '£'},
    {'code': 'JPY', 'symbol': '¥'},
    {'code': 'CNY', 'symbol': '¥'},
    {'code': 'CAD', 'symbol': '\$'},
    {'code': 'AUD', 'symbol': '\$'},
    {'code': 'CHF', 'symbol': 'Fr'},
    {'code': 'RUB', 'symbol': '₽'},
  ];

  String _currencySymbol([String? code]) {
    final selectedCode = (code ?? _currency).toUpperCase();
    final match = _currencies.firstWhere(
      (item) => item['code'] == selectedCode,
      orElse: () => const {'code': 'INR', 'symbol': '₹'},
    );
    return match['symbol'] ?? '₹';
  }

  double? _parsedPrincipalAmount() {
    return double.tryParse(_amountController.text.trim());
  }

  double? _parsedInterestRate() {
    return double.tryParse(_interestRateController.text.trim());
  }

  DateTime _previewStartDate() {
    final selectedDate = _selectedDate;
    if (selectedDate == null) return DateTime.now();
    final selectedTime = _selectedTime ?? TimeOfDay.now();
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
  }

  double _repaymentYears() {
    if (_expectedReturnDate == null) return 0;
    final days = _expectedReturnDate!
        .difference(_previewStartDate())
        .inDays
        .clamp(0, 36500);
    return days / 365.0;
  }

  double? _estimatedRepaymentAmount() {
    final principal = _parsedPrincipalAmount();
    if (principal == null) return null;
    if (_interestType == 'none') return principal;

    final rate = _parsedInterestRate();
    final years = _repaymentYears();
    if (rate == null || years <= 0) return principal;

    final rateFraction = rate / 100.0;
    if (_interestType == 'simple') {
      return principal * (1 + (rateFraction * years));
    }

    if (_interestType == 'compound') {
      final frequency = _compoundingFrequency <= 0 ? 1 : _compoundingFrequency;
      return principal *
          math
              .pow(1 + (rateFraction / frequency), frequency * years)
              .toDouble();
    }

    return principal;
  }

  String _formatPreviewAmount(double value) {
    return '${_currencySymbol()}${value.toStringAsFixed(2)}';
  }

  String _repaymentTenureLabel() {
    if (_expectedReturnDate == null) {
      return 'No interest applied';
    }
    final days = _expectedReturnDate!
        .difference(_previewStartDate())
        .inDays
        .clamp(0, 36500);
    if (days == 0) return 'Same-day return';
    if (days < 30) return '$days day${days == 1 ? '' : 's'}';
    final months = (days / 30).toStringAsFixed(1);
    return '$months months';
  }

  int? _remainingDaysCount() {
    if (_expectedReturnDate == null) return null;
    final difference = _expectedReturnDate!.difference(_previewStartDate());
    return difference.inDays;
  }

  String _remainingDaysLabel() {
    final days = _remainingDaysCount();
    if (days == null) return 'Not scheduled';
    if (days < 0) return '${days.abs()} day(s) overdue';
    return '$days day(s) remaining';
  }

  String _draftStatusLabel() {
    final savedAt = _lastDraftSavedAt;
    if (savedAt == null) return _draftStatusMessage;
    return 'Draft saved ${DateFormat('hh:mm a').format(savedAt)}';
  }

  Widget _buildRepaymentPreviewCard() {
    final principal = _parsedPrincipalAmount();
    final repayment = _estimatedRepaymentAmount();
    if (principal == null || repayment == null) return const SizedBox.shrink();

    final interestValue = math.max(repayment - principal, 0).toDouble();
    final needsReturnDate = _interestType != 'none' && _expectedReturnDate == null;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.preview_rounded,
                    color: AppColors.cyan,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Repayment Preview',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildPreviewStat('Principal', _formatPreviewAmount(principal)),
                _buildPreviewStat(
                  'Est. Interest',
                  _formatPreviewAmount(interestValue),
                ),
                _buildPreviewStat('Est. Repayment', _formatPreviewAmount(repayment)),
                _buildPreviewStat('Tenure', _repaymentTenureLabel()),
              ],
            ),
            if (needsReturnDate) ...[
              const SizedBox(height: 12),
              Text(
                'Pick an expected return date to calculate interest more accurately.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRepaymentTimelineCard() {
    if (_expectedReturnDate == null) return const SizedBox.shrink();

    final startDate = _previewStartDate();
    final estimatedRepayment =
        _estimatedRepaymentAmount() ?? _parsedPrincipalAmount() ?? 0;

    Widget item({
      required IconData icon,
      required String title,
      required String value,
      required Color color,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Repayment Timeline',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            item(
              icon: Icons.play_circle_outline_rounded,
              title: 'Start date',
              value: DateFormat('MMM d, yyyy • hh:mm a').format(startDate),
              color: AppColors.cyan,
            ),
            const SizedBox(height: 10),
            item(
              icon: Icons.event_available_rounded,
              title: 'Expected return date',
              value:
                  DateFormat('MMM d, yyyy').format(_expectedReturnDate!),
              color: Colors.green,
            ),
            const SizedBox(height: 10),
            item(
              icon: Icons.payments_outlined,
              title: 'Estimated total repayment',
              value: _formatPreviewAmount(estimatedRepayment),
              color: Colors.orange,
            ),
            const SizedBox(height: 10),
            item(
              icon: Icons.schedule_rounded,
              title: 'Remaining time',
              value: _remainingDaysLabel(),
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewStat(String label, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFE8F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.cyan, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStepper() {
    final step2Ready = _counterpartyVerified || _userVerified;
    final step3Ready = _bothUsersVerified;

    Widget step({
      required int number,
      required String title,
      required bool active,
      required bool complete,
    }) {
      final color = complete || active
          ? AppColors.cyan
          : Colors.grey.shade400;
      return Expanded(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 3,
                    color: number == 1 ? Colors.transparent : color,
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: complete || active ? color : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Center(
                    child: complete
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : Text(
                            '$number',
                            style: TextStyle(
                              color: active ? Colors.white : color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 3,
                    color: number == 3 ? Colors.transparent : color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: complete || active ? Colors.black87 : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          step(number: 1, title: 'Enter Details', active: !step2Ready, complete: step2Ready),
          step(number: 2, title: 'Verify Emails', active: step2Ready && !step3Ready, complete: step3Ready),
          step(number: 3, title: 'Create Txn', active: step3Ready, complete: false),
        ],
      ),
    );
  }

  Widget _buildTransactionPreviewCard() {
    final amount = _parsedPrincipalAmount();
    final roleLabel = _role == 'lender' ? 'You are lending' : 'You are borrowing';
    final counterparty = _counterpartyEmailController.text.trim().isEmpty
        ? 'Not selected yet'
        : _counterpartyEmailController.text.trim();
    final dateLabel = _selectedDate == null
        ? 'Not selected'
        : DateFormat('MMM d, yyyy').format(_selectedDate!);
    final returnLabel = _expectedReturnDate == null
        ? (_interestType == 'none' ? 'Not needed' : 'Select expected return date')
        : DateFormat('MMM d, yyyy').format(_expectedReturnDate!);

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transaction Preview',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildPreviewStat('Role', roleLabel),
                _buildPreviewStat(
                  'Amount',
                  amount == null ? 'Enter amount' : _formatPreviewAmount(amount),
                ),
                _buildPreviewStat('Counterparty', counterparty),
                _buildPreviewStat(
                  'Interest',
                  _interestType == 'none'
                      ? 'No interest'
                      : _interestType == 'simple'
                          ? 'Simple interest'
                          : 'Compound interest',
                ),
                _buildPreviewStat('Txn Date', dateLabel),
                _buildPreviewStat('Return Date', returnLabel),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterestGuidanceCard() {
    if (_interestType == 'none') return const SizedBox.shrink();

    final guidance = _interestType == 'simple'
        ? 'Simple interest grows only on the original principal for the selected period.'
        : 'Compound interest grows on principal plus accumulated interest based on the compounding frequency.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFE8F2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: AppColors.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              guidance,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _compoundingFrequency = 1;
    _descriptionController.text = '';
    if ((widget.prefillCounterpartyEmail ?? '').isNotEmpty) {
      _counterpartyEmailController.text =
          widget.prefillCounterpartyEmail!.trim();
    }
    _loadFriends();
    _loadDailyLimits();
    _counterpartyEmailController.addListener(_updateFriendSuggestions);
    _amountController.addListener(_saveDraft);
    _placeController.addListener(_saveDraft);
    _counterpartyEmailController.addListener(_saveDraft);
    _interestRateController.addListener(_saveDraft);
    _descriptionController.addListener(_saveDraft);
    // Prefill user email from session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<SessionProvider>(context, listen: false).user;
      if (user != null && user['email'] != null) {
        _userEmailController.text = user['email'];
      }
      _restoreDraftIfAvailable();
    });
  }

  String _draftStorageKey() {
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    final email = (user?['email'] ?? 'guest').toString().toLowerCase().trim();
    return 'secure_transaction_draft_$email';
  }

  Future<void> _saveDraft() async {
    if (_restoringDraft) return;
    final payload = {
      'amount': _amountController.text,
      'currency': _currency,
      'selectedDate': _selectedDate?.toIso8601String(),
      'selectedTime': _selectedTime == null
          ? null
          : {'hour': _selectedTime!.hour, 'minute': _selectedTime!.minute},
      'place': _placeController.text,
      'counterpartyEmail': _counterpartyEmailController.text,
      'role': _role,
      'interestType': _interestType,
      'interestRate': _interestRateController.text,
      'expectedReturnDate': _expectedReturnDate?.toIso8601String(),
      'compoundingFrequency': _compoundingFrequency,
      'description': _descriptionController.text,
    };
    await _storage.write(key: _draftStorageKey(), value: jsonEncode(payload));
    _lastDraftSavedAt = DateTime.now();
    if (mounted) {
      setState(() {
        _draftStatusMessage = 'Draft saved';
      });
    }
  }

  Future<void> _saveDraftWithFeedback() async {
    await _saveDraft();
    if (!mounted) return;
    await _showDraftStatusDialog(
      title: 'Draft Saved',
      message:
          'Your secure transaction draft is saved. You can continue it anytime from this page.',
      icon: Icons.save_outlined,
      accentColor: AppColors.cyan,
      actionLabel: 'Continue',
    );
  }

  Future<void> _clearDraft() async {
    await _storage.delete(key: _draftStorageKey());
    _lastDraftSavedAt = null;
    if (mounted) {
      setState(() {
        _draftStatusMessage = 'No saved draft';
      });
    }
  }

  Future<void> _resetFormForAnotherTransaction() async {
    await _clearDraft();
    if (!mounted) return;
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    setState(() {
      _formKey.currentState?.reset();
      _amountController.clear();
      _placeController.clear();
      _counterpartyEmailController.clear();
      _userEmailController.text = (user?['email'] ?? '').toString();
      _interestRateController.clear();
      _descriptionController.clear();
      _pickedFiles = [];
      _transactionId = null;
      _role = 'lender';
      _currency = 'INR';
      _selectedDate = null;
      _selectedTime = null;
      _counterpartyOtp = null;
      _userOtp = null;
      _counterpartyOtpError = null;
      _userOtpError = null;
      _counterpartyEmailError = null;
      _userEmailError = null;
      _sameEmailError = null;
      _counterpartyOtpSeconds = 0;
      _userOtpSeconds = 0;
      _counterpartyVerified = false;
      _userVerified = false;
      _interestType = 'none';
      _expectedReturnDate = null;
      _compoundingFrequency = 1;
      _draftStatusMessage = 'Start your next secure transaction';
    });
  }

  Future<void> _discardDraftWithConfirmation() async {
    final shouldDiscard = await _showDraftChoiceDialog(
      title: 'Discard Draft?',
      message:
          'This will remove your saved secure transaction draft from this device.',
      icon: Icons.delete_outline,
      accentColor: const Color(0xFFFF6B6B),
      primaryLabel: 'Discard',
      secondaryLabel: 'Keep Draft',
    );
    if (shouldDiscard != true) return;
    await _clearDraft();
    if (!mounted) return;
    await _showDraftStatusDialog(
      title: 'Draft Discarded',
      message: 'The saved draft has been removed.',
      icon: Icons.delete_sweep_outlined,
      accentColor: const Color(0xFFFF6B6B),
      actionLabel: 'OK',
    );
  }

  Future<void> _restoreDraftIfAvailable() async {
    final raw = await _storage.read(key: _draftStorageKey());
    if (raw == null || raw.isEmpty || !mounted) return;

    final shouldRestore = await _showDraftChoiceDialog(
          title: 'Saved Draft Found',
          message:
              'A saved secure transaction draft was found. Do you want to continue from where you left off?',
          icon: Icons.auto_awesome_outlined,
          accentColor: AppColors.cyan,
          primaryLabel: 'Continue Draft',
          secondaryLabel: 'Start Fresh',
        ) ??
        false;

    if (!shouldRestore) {
      await _clearDraft();
      return;
    }

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _restoringDraft = true;
      setState(() {
        _amountController.text = (data['amount'] ?? '').toString();
        _currency = (data['currency'] ?? 'INR').toString();
        _placeController.text = (data['place'] ?? '').toString();
        _counterpartyEmailController.text =
            (data['counterpartyEmail'] ?? '').toString();
        _role = (data['role'] ?? 'lender').toString();
        _interestType = (data['interestType'] ?? 'none').toString();
        _interestRateController.text = (data['interestRate'] ?? '').toString();
        _descriptionController.text = (data['description'] ?? '').toString();
        _compoundingFrequency =
            int.tryParse('${data['compoundingFrequency']}') ?? 1;
        _selectedDate = data['selectedDate'] == null
            ? null
            : DateTime.tryParse(data['selectedDate'].toString());
        _expectedReturnDate = data['expectedReturnDate'] == null
            ? null
            : DateTime.tryParse(data['expectedReturnDate'].toString());
        final time = data['selectedTime'];
        if (time is Map) {
          _selectedTime = TimeOfDay(
            hour: int.tryParse('${time['hour']}') ?? 0,
            minute: int.tryParse('${time['minute']}') ?? 0,
          );
        }
        _draftStatusMessage = 'Draft restored';
      });
    } catch (_) {
      await _clearDraft();
    } finally {
      _restoringDraft = false;
    }
  }

  Future<bool?> _showDraftChoiceDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color accentColor,
    required String primaryLabel,
    required String secondaryLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipPath(
                      clipper: TopWaveClipper(),
                      child: Container(
                        height: 86,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentColor,
                              accentColor.withValues(alpha: 0.72),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white,
                        child: Icon(icon, color: accentColor, size: 34),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      primaryLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: accentColor.withValues(alpha: 0.45)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      secondaryLabel,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDraftStatusDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color accentColor,
    required String actionLabel,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipPath(
                      clipper: TopWaveClipper(),
                      child: Container(
                        height: 86,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentColor,
                              accentColor.withValues(alpha: 0.72),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white,
                        child: Icon(icon, color: accentColor, size: 34),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      actionLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDraftActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFriendForCounterparty() async {
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final friends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
      final blocked =
          List<Map<String, dynamic>>.from(data['blockedUsers'] ?? []);
      _blockedEmails = blocked
          .map((u) => (u['email'] ?? '').toString().toLowerCase().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) => Container(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: _getFriendNoteColor(0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Select Friend',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (friends.isEmpty)
                    const Text('No friends found')
                  else
                    ...friends.map((f) {
                      final email = f['email'] ?? '';
                      final name = f['name'] ?? f['username'] ?? '';
                      final isBlocked = _blockedEmails
                          .contains(email.toString().toLowerCase().trim());
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Colors.orange, Colors.white, Colors.green],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                _getFriendNoteColor(email.hashCode.abs() % 6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            title: Text(name.toString()),
                            subtitle: Text(email.toString()),
                            trailing: isBlocked
                                ? const Text('Blocked',
                                    style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600))
                                : null,
                            onTap: () {
                              if (isBlocked) {
                                showBlockedUserDialog(context);
                                return;
                              }
                              setState(() {
                                _counterpartyEmailController.text =
                                    email.toString();
                              });
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      );
                    }).toList(),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (_) {}
  }

  Color _getFriendNoteColor(int index) {
    final colors = [
      Color(0xFFFFF4E6),
      Color(0xFFE8F5E9),
      Color(0xFFFCE4EC),
      Color(0xFFE3F2FD),
      Color(0xFFFFF9C4),
      Color(0xFFF3E5F5),
    ];
    return colors[index % colors.length];
  }

  @override
  void dispose() {
    _counterpartyEmailController.removeListener(_updateFriendSuggestions);
    _amountController.removeListener(_saveDraft);
    _placeController.removeListener(_saveDraft);
    _counterpartyEmailController.removeListener(_saveDraft);
    _interestRateController.removeListener(_saveDraft);
    _descriptionController.removeListener(_saveDraft);
    _amountController.dispose();
    _placeController.dispose();
    _counterpartyEmailController.dispose();
    _userEmailController.dispose();
    _interestRateController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _friends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
          final blocked =
              List<Map<String, dynamic>>.from(data['blockedUsers'] ?? []);
          _blockedEmails = blocked
              .map((u) => (u['email'] ?? '').toString().toLowerCase().trim())
              .where((e) => e.isNotEmpty)
              .toSet();
        });
        _updateFriendSuggestions();
      }
    } catch (_) {}
  }

  Future<void> _loadDailyLimits() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.isSubscribed) return;
    try {
      final res = await ApiClient.get('/api/limits/daily');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _dailyUserTxRemaining =
              data['limits']?['userTransactions']?['remaining'];
        });
      }
    } catch (_) {}
  }

  bool _isBlockedEmail(String? email) {
    final target = email?.toLowerCase().trim();
    if (target == null || target.isEmpty) return false;
    return _blockedEmails.contains(target);
  }

  void _updateFriendSuggestions() {
    final query = _counterpartyEmailController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _friendSuggestions = []);
      return;
    }
    final matches = _friends.where((f) {
      final email = (f['email'] ?? '').toString().toLowerCase();
      final name = (f['name'] ?? f['username'] ?? '').toString().toLowerCase();
      if (_isBlockedEmail(email)) return false;
      return email.contains(query) || name.contains(query);
    }).toList();
    setState(() => _friendSuggestions = matches.take(5).toList());
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _pickedFiles.addAll(result.files);
      });
      await _saveDraft();
    }
  }

  void _removeFile(int idx) {
    if (_bothUsersVerified) return; // Prevent file removal when verified
    setState(() {
      _pickedFiles.removeAt(idx);
    });
    _saveDraft();
  }

  Widget _buildFileThumbnail(int i) {
    final file = _pickedFiles[i];
    if (file.extension == 'pdf') {
      return GestureDetector(
        onTap: () async {
          if (file.bytes != null) {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/${file.name}');
            await tempFile.writeAsBytes(file.bytes!, flush: true);
            await OpenFile.open(tempFile.path);
          }
        },
        child: Icon(Icons.picture_as_pdf, size: 80, color: Colors.red),
      );
    } else {
      return GestureDetector(
        onTap: () {
          if (file.bytes != null) {
            showDialog(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.black,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: InteractiveViewer(
                    child: Image.memory(file.bytes!, fit: BoxFit.contain),
                  ),
                ),
              ),
            );
          }
        },
        child: file.bytes != null
            ? Image.memory(file.bytes!,
                width: 80, height: 80, fit: BoxFit.cover)
            : Icon(Icons.image, size: 80),
      );
    }
  }

  Widget _buildFilePicker() {
    final proofCount = _pickedFiles.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                proofCount == 0
                    ? 'No proof files added yet'
                    : '$proofCount proof file${proofCount == 1 ? '' : 's'} attached',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                proofCount == 0 ? 'Optional' : 'Ready',
                style: const TextStyle(
                  color: Color(0xFF0077B6),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _bothUsersVerified ? null : _pickFiles,
          icon: const Icon(Icons.attach_file),
          label: const Text('Add Proof Files'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
        ),
        const SizedBox(height: 12),
        if (_pickedFiles.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FBFD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBFE8F2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.image_outlined, color: AppColors.cyan),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add screenshots or photos to make the secure transaction easier to verify later.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _pickedFiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final file = _pickedFiles[i];
                return Container(
                  width: 108,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBFE8F2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: _buildFileThumbnail(i),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (!_bothUsersVerified)
                        GestureDetector(
                          onTap: () => _removeFile(i),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.red,
                            child: Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDraftStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FBFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFE8F2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined, color: AppColors.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _draftStatusLabel(),
              style: TextStyle(
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTricolorFrame({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
    BorderRadius? borderRadius,
  }) {
    final radius = borderRadius ?? BorderRadius.circular(22);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
        ),
        child: child,
      ),
    );
  }

  Widget _buildReviewInfoTile({
    required IconData icon,
    required String title,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTransactionSuccessDialog({
    required bool giftCardAwarded,
  }) async {
    final amt = double.tryParse(_amountController.text.replaceAll(',', ''));
    final recipient = _counterpartyEmailController.text.trim();
    final extraDetails = <String, String>{
      if (_transactionId != null) 'Transaction ID': _transactionId!,
      'Role': _role,
      if (giftCardAwarded) 'Bonus': '🎉 Gift card won!',
    };

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessPage(
          title: 'Transaction Created!',
          amount: amt,
          currency: _currency == 'INR' ? '₹' : _currency,
          recipientName: recipient.isNotEmpty ? recipient : null,
          transactionType: 'Secure Transaction',
          extraDetails: extraDetails,
          onDone: () {
            Navigator.of(context).pop();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => UserTransactionsPage()),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showReviewSheetAndSubmit() async {
    final amount = _parsedPrincipalAmount();
    final repayment = _estimatedRepaymentAmount();
    final roleLabel =
        _role == 'lender' ? 'You are lending' : 'You are borrowing';
    final counterparty = _counterpartyEmailController.text.trim().isEmpty
        ? 'Not selected'
        : _counterpartyEmailController.text.trim();
    final transactionDate = _selectedDate == null
        ? 'Not selected'
        : DateFormat('MMM d, yyyy').format(_selectedDate!);
    final returnDate = _expectedReturnDate == null
        ? (_interestType == 'none'
            ? 'Optional and not selected'
            : 'Required before submit')
        : DateFormat('MMM d, yyyy').format(_expectedReturnDate!);
    final interestLabel = _interestType == 'none'
        ? 'No interest'
        : _interestType == 'simple'
            ? 'Simple interest'
            : 'Compound interest';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildTricolorFrame(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              borderRadius: BorderRadius.circular(28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.cyan.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.fact_check_outlined,
                            color: AppColors.cyan,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Review and Submit',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Check the details once before creating the secure transaction.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FCFE),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFBFE8F2)),
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _buildPreviewStat('Role', roleLabel),
                          _buildPreviewStat(
                            'Amount',
                            amount == null
                                ? 'Not entered'
                                : _formatPreviewAmount(amount),
                          ),
                          _buildPreviewStat('Interest', interestLabel),
                          _buildPreviewStat(
                            'Proof Files',
                            '${_pickedFiles.length} attached',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildReviewInfoTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Counterparty',
                      value: counterparty,
                      accent: AppColors.cyan,
                    ),
                    const SizedBox(height: 10),
                    _buildReviewInfoTile(
                      icon: Icons.event_available_rounded,
                      title: 'Transaction Date',
                      value: transactionDate,
                      accent: Colors.orange,
                    ),
                    const SizedBox(height: 10),
                    _buildReviewInfoTile(
                      icon: Icons.update_rounded,
                      title: 'Expected Return Date',
                      value: returnDate,
                      accent: Colors.green,
                    ),
                    if (repayment != null) ...[
                      const SizedBox(height: 10),
                      _buildReviewInfoTile(
                        icon: Icons.payments_outlined,
                        title: 'Estimated Repayment',
                        value: _formatPreviewAmount(repayment),
                        accent: Colors.purple,
                      ),
                    ],
                    if (_expectedReturnDate != null) ...[
                      const SizedBox(height: 10),
                      _buildReviewInfoTile(
                        icon: Icons.schedule_rounded,
                        title: 'Time Until Return',
                        value: _remainingDaysLabel(),
                        accent: Colors.teal,
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _submit();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(
                          Icons.verified_rounded,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Confirm and Submit',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go Back and Edit'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStickySummaryBar() {
    final amount = _parsedPrincipalAmount();
    final canSubmit = _counterpartyVerified && _userVerified && !_isLoading;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        amount == null
                            ? 'Enter amount to build summary'
                            : _formatPreviewAmount(amount),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _counterpartyEmailController.text.trim().isEmpty
                            ? 'Counterparty not selected'
                            : _counterpartyEmailController.text.trim(),
                        style: TextStyle(color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _expectedReturnDate == null
                            ? 'Return date not selected'
                            : 'Return: ${DateFormat('MMM d').format(_expectedReturnDate!)}',
                        style: TextStyle(
                          color: const Color(0xFF0077B6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canSubmit ? _showReviewSheetAndSubmit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            canSubmit ? 'Review & Submit' : 'Verify to Submit',
                            style: const TextStyle(color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  MediaType? _mediaTypeForFile(PlatformFile file) {
    final ext = (file.extension ?? '').toLowerCase();
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      default:
        return null;
    }
  }

  List<ApiMultipartFile> _buildMultipartFiles() {
    return _pickedFiles
        .where((file) => file.bytes != null || (file.path?.isNotEmpty ?? false))
        .map(
          (file) => ApiMultipartFile(
            field: 'files',
            filename: file.name,
            bytes: file.bytes,
            path: file.bytes == null ? file.path : null,
            contentType: _mediaTypeForFile(file),
          ),
        )
        .toList();
  }

  Future<bool> _checkEmailExists(String email) async {
    final res = await ApiClient.post(
      '/api/transactions/check-email',
      body: {'email': email},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['exists'] == true;
    }
    return false;
  }

  Future<void> _sendOtp(String email, bool isCounterparty) async {
    setState(() {
      if (isCounterparty) {
        _counterpartyOtpError = null;
        _counterpartyOtpSeconds = 120;
      } else {
        _userOtpError = null;
        _userOtpSeconds = 120;
      }
    });
    final url = isCounterparty
        ? '/api/transactions/send-counterparty-otp'
        : '/api/transactions/send-user-otp';
    await ApiClient.post(
      url,
      body: {'email': email},
    );
    _startOtpTimer(isCounterparty);
  }

  void _startOtpTimer(bool isCounterparty) {
    Future.doWhile(() async {
      await Future.delayed(Duration(seconds: 1));
      setState(() {
        if (isCounterparty && _counterpartyOtpSeconds > 0) {
          _counterpartyOtpSeconds--;
        } else if (!isCounterparty && _userOtpSeconds > 0) {
          _userOtpSeconds--;
        }
      });
      return (isCounterparty ? _counterpartyOtpSeconds : _userOtpSeconds) > 0;
    });
  }

  Future<void> _verifyOtp(String email, String otp, bool isCounterparty) async {
    final url = isCounterparty
        ? '/api/transactions/verify-counterparty-otp'
        : '/api/transactions/verify-user-otp';
    final res = await ApiClient.post(
      url,
      body: {'email': email, 'otp': otp},
    );
    if (res.statusCode == 200) {
      setState(() {
        if (isCounterparty) {
          _counterpartyVerified = true;
        } else {
          _userVerified = true;
        }
      });
    } else {
      setState(() {
        if (isCounterparty) {
          _counterpartyOtpError = 'Invalid or expired OTP';
        } else {
          _userOtpError = 'Invalid or expired OTP';
        }
      });
    }
  }

  Future<void> _submit() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final dailyLimitExceeded = !session.isSubscribed &&
        _dailyUserTxRemaining != null &&
        _dailyUserTxRemaining! <= 0;
    final shouldUseCoins = !session.isSubscribed &&
        (dailyLimitExceeded ||
            (session.freeUserTransactionsRemaining ?? 0) <= 0);
    if (_isBlockedEmail(_counterpartyEmailController.text)) {
      showBlockedUserDialog(context);
      return;
    }
    if (session.isSubscribed || !shouldUseCoins) {
      _submitWithApi();
    } else {
      if ((session.lenDenCoins ?? 0) < 10) {
        if ((session.lenDenCoins ?? 0) == 0) {
          showZeroCoinsDialog(context);
        } else {
          showInsufficientCoinsDialog(context);
        }
      } else {
        showDialog(
          context: context,
          builder: (context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.white, Colors.green],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.monetization_on,
                          color: Colors.orange, size: 48),
                      SizedBox(height: 16),
                      Text(
                        'Use LenDen Coins',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        dailyLimitExceeded
                            ? 'Your daily secure transaction limit is finished. You can still create this transaction now by spending 10 LenDen coins.'
                            : 'You have no free transactions remaining. Would you like to use 10 LenDen coins to create this transaction?',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                      ),
                      if (dailyLimitExceeded) ...[
                        SizedBox(height: 12),
                        Text(
                          'Warning: this will bypass today\'s free daily limit.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.orange[800],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      SizedBox(height: 8),
                      Text(
                        'OR',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Subscribe now for unlimited access',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 24),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[300],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                  color: Colors.grey[800],
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SubscriptionsPage(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                            child: Text(
                              'Subscribe',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _submitWithCoins();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                            child: Text(
                              'Use Coins',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }
    }
  }

  Future<void> _submitWithCoins() async {
    // Logic to submit with coins
    setState(() => _isLoading = true);
    try {
      final Map<String, dynamic> body = {
        'amount': _amountController.text,
        'currency': _currency,
        'date': _selectedDate?.toIso8601String() ?? '',
        'time': _selectedTime?.format(context) ?? '',
        'place': _placeController.text,
        'counterpartyEmail': _counterpartyEmailController.text,
        'userEmail': _userEmailController.text,
        'role': _role,
        'interestType': _interestType,
        'description': _descriptionController.text,
      };

      if (_expectedReturnDate != null) {
        body['expectedReturnDate'] = _expectedReturnDate!.toIso8601String();
      }

      if (_interestType != 'none') {
        body['interestRate'] = _interestRateController.text;
        if (_interestType == 'compound') {
          body['compoundingFrequency'] = _compoundingFrequency;
        }
      }
      final res = await ApiClient.postMultipart(
        '/api/transactions/with-coins',
        fields: body,
        files: _buildMultipartFiles(),
      );
      setState(() => _isLoading = false);
      if (res.statusCode == 201) {
        final data = jsonDecode(res.body);
        final giftCardAwarded = data['giftCardAwarded'] == true;
        await _clearDraft();
        setState(() {
          _transactionId = data['transactionId'];
        });
        final session = Provider.of<SessionProvider>(context, listen: false);
        session.loadFreebieCounts();
        _showTransactionSuccessDialog(giftCardAwarded: giftCardAwarded);
      } else if (res.statusCode == 403) {
        String errorMsg = 'Forbidden';
        try {
          final data = jsonDecode(res.body);
          errorMsg = data['error'] ?? data['message'] ?? errorMsg;
        } catch (_) {}
        if (errorMsg.toLowerCase().contains('blocked')) {
          showBlockedUserDialog(context, message: errorMsg);
          return;
        }
        showInsufficientCoinsDialog(context);
      } else if (res.statusCode == 429) {
        String errorMsg = 'Daily limit reached';
        try {
          final data = jsonDecode(res.body);
          errorMsg = data['error'] ?? data['message'] ?? errorMsg;
        } catch (_) {}
        showDailyLimitDialog(context, message: errorMsg);
      } else {
        final errBody = (res.body.isNotEmpty) ? res.body : 'Unknown error';
        String errorMsg = 'Failed to create transaction';
        try {
          final data = jsonDecode(errBody);
          errorMsg = data['error'] ?? data['message'] ?? errBody;
        } catch (_) {
          errorMsg = errBody;
        }
        _showStylishErrorDialog('Transaction Failed', errorMsg);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showStylishErrorDialog('Transaction Failed', e.toString());
    }
  }

  Future<void> _submitWithApi() async {
    setState(() => _sameEmailError = null);

    // Custom validation for expected return date when interest is selected
    if (_interestType != 'none' && _expectedReturnDate == null) {
      _showStylishErrorDialog('Expected Return Date Required',
          'Please select an expected return date when interest is applied.');
      return;
    }

    // Validate form
    if (!_formKey.currentState!.validate()) {
      print('Form validation failed');
      return;
    }

    print('Form validation passed, proceeding with submission');
    setState(() => _isLoading = true);
    try {
      final Map<String, dynamic> body = {
        'amount': _amountController.text,
        'currency': _currency,
        'date': _selectedDate?.toIso8601String() ?? '',
        'time': _selectedTime?.format(context) ?? '',
        'place': _placeController.text,
        'counterpartyEmail': _counterpartyEmailController.text,
        'userEmail': _userEmailController.text,
        'role': _role,
        'interestType': _interestType,
        'description': _descriptionController.text,
      };

      if (_expectedReturnDate != null) {
        body['expectedReturnDate'] = _expectedReturnDate!.toIso8601String();
      }

      if (_interestType != 'none') {
        body['interestRate'] = _interestRateController.text;
        if (_interestType == 'compound') {
          body['compoundingFrequency'] = _compoundingFrequency;
        }
      }
      final res = await ApiClient.postMultipart(
        '/api/transactions/create',
        fields: body,
        files: _buildMultipartFiles(),
      );
      setState(() => _isLoading = false);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        final giftCardAwarded = data['giftCardAwarded'] == true;
        await _clearDraft();
        setState(() {
          _transactionId = data['transactionId'];
        });
        final session = Provider.of<SessionProvider>(context, listen: false);
        session.loadFreebieCounts();

        _showTransactionSuccessDialog(giftCardAwarded: giftCardAwarded);
      } else {
        final errBody = (res.body.isNotEmpty) ? res.body : 'Unknown error';
        String errorMsg = 'Failed to create transaction';
        try {
          final data = jsonDecode(errBody);
          errorMsg = data['error'] ?? data['message'] ?? errBody;
        } catch (_) {
          errorMsg = errBody;
        }
        if (errorMsg.toLowerCase().contains('blocked')) {
          showBlockedUserDialog(context, message: errorMsg);
          return;
        }
        if (errorMsg.toLowerCase().contains('daily limit')) {
          showDailyLimitDialog(context, message: errorMsg);
          return;
        }
        _showStylishErrorDialog('Transaction Failed', errorMsg);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showStylishErrorDialog('Transaction Failed', e.toString());
    }
  }

  void _showStylishErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipPath(
                    clipper: TopWaveClipper(),
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFF6B6B), Color(0xFFFF8E8E)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.error_outline,
                          color: Color(0xFFFF6B6B), size: 48),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              Text(title,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6B6B))),
              SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(fontSize: 16, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFF6B6B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('OK',
                      style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatePickerField() {
    return InkWell(
      onTap: _bothUsersVerified
          ? null
          : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.light().copyWith(
                      colorScheme: ColorScheme.light(
                        primary: AppColors.cyan,
                        onPrimary: Colors.white,
                        surface: Colors.white,
                        onSurface: Colors.black87,
                      ),
                      dialogTheme: DialogTheme(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.cyan,
                        ),
                      ),
                      cardColor: Colors.white,
                      canvasColor: Colors.white,
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
                _saveDraft();
              }
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Transaction Date',
          prefixIcon: Icon(Icons.calendar_today, color: AppColors.cyan),
          border: InputBorder.none,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedDate == null
                  ? 'Select date'
                  : DateFormat('MMM d, yyyy').format(_selectedDate!),
              style: TextStyle(
                color:
                    _selectedDate == null ? Colors.grey[500] : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePickerField() {
    return InkWell(
      onTap: _bothUsersVerified
          ? null
          : () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _selectedTime ?? TimeOfDay.now(),
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.light().copyWith(
                      colorScheme: ColorScheme.light(
                        primary: AppColors.cyan,
                        onPrimary: Colors.white,
                        surface: Colors.white,
                        onSurface: Colors.black87,
                      ),
                      dialogTheme: DialogTheme(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.cyan,
                        ),
                      ),
                      cardColor: Colors.white,
                      canvasColor: Colors.white,
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() => _selectedTime = picked);
                _saveDraft();
              }
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Time',
          prefixIcon: Icon(Icons.access_time, color: AppColors.cyan),
          border: InputBorder.none,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedTime == null
                  ? 'Select time'
                  : _selectedTime!.format(context),
              style: TextStyle(
                color:
                    _selectedTime == null ? Colors.grey[500] : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpSection({
    required String label,
    required TextEditingController emailController,
    required bool verified,
    required String? otpError,
    required int otpSeconds,
    required void Function() onSendOtp,
    required void Function(String) onOtpChanged,
    required void Function() onVerifyOtp,
    required bool enabled,
    required String? emailError,
    bool readOnlyEmail = false,
    VoidCallback? onPickFriend,
    List<Map<String, dynamic>>? friendSuggestions,
    void Function(String email)? onSelectFriend,
  }) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            _buildStylishField(
              child: TextFormField(
                controller: emailController,
                enabled: !verified && !readOnlyEmail,
                readOnly: readOnlyEmail,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: InputBorder.none,
                  errorText: emailError,
                  suffixIcon: onPickFriend != null
                      ? IconButton(
                          icon: const Icon(Icons.people),
                          onPressed: onPickFriend,
                        )
                      : null,
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Email required';
                  if (!val.contains('@')) return 'Invalid email';
                  return null;
                },
              ),
            ),
            if (!verified) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  if (otpSeconds == 0)
                    ElevatedButton(
                      onPressed: enabled ? onSendOtp : null,
                      child: Text('Send OTP'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal),
                    )
                  else ...[
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Resend OTP (${otpSeconds}s)',
                          style: TextStyle(
                              color: Colors.teal, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  SizedBox(width: 12),
                  if (otpError != null)
                    Text(otpError, style: TextStyle(color: Colors.red)),
                ],
              ),
              SizedBox(height: 8),
              OtpInput(
                onChanged: onOtpChanged,
                enabled: enabled,
                autoFocus: false,
              ),
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: enabled ? onVerifyOtp : null,
                child: Text('Verify OTP'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              ),
            ] else ...[
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.verified, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Verified', style: TextStyle(color: Colors.green)),
                ],
              ),
            ],
            if (!verified &&
                (friendSuggestions ?? []).isNotEmpty &&
                onSelectFriend != null) ...[
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (friendSuggestions ?? []).map((f) {
                  final email = (f['email'] ?? '').toString();
                  final name = (f['name'] ?? f['username'] ?? '').toString();
                  return Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _getFriendNoteColor(email.hashCode.abs() % 6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ActionChip(
                        label: Text(name.isNotEmpty ? '$name ($email)' : email),
                        onPressed: () => onSelectFriend(email),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStylishField({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      extendBodyBehindAppBar: true,
      bottomNavigationBar: _buildStickySummaryBar(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.pushReplacementNamed(context, '/user/dashboard');
            }
          },
        ),
      ),
      body: Stack(
        children: [
          // Wavy blue background at the top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                children: [
                  Text(
                    'New Secure Transaction',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
                    ),
                  ),
                  Consumer<SessionProvider>(
                    builder: (context, session, child) {
                      if (session.isSubscribed) {
                        return Text('You have unlimited transactions.',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white));
                      }
                      final remaining = session.freeUserTransactionsRemaining;
                      if (remaining == null) {
                        return SizedBox.shrink();
                      }
                      return Text('$remaining free transactions remaining',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white));
                    },
                  ),
                  if (!Provider.of<SessionProvider>(context, listen: false)
                          .isSubscribed &&
                      _dailyUserTxRemaining != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Daily limit: $_dailyUserTxRemaining',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70),
                      ),
                    ),
                  if (_bothUsersVerified) ...[
                    SizedBox(height: 8),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock, color: Colors.white, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Details Locked',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 120),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProgressStepper(),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildDraftActionCard(
                          title: 'Save Draft',
                          subtitle: 'Pause now and continue later',
                          icon: Icons.save_outlined,
                          accentColor: AppColors.cyan,
                          onTap: () {
                            _saveDraftWithFeedback();
                          },
                        ),
                        const SizedBox(width: 12),
                        _buildDraftActionCard(
                          title: 'Discard Draft',
                          subtitle: 'Remove the saved version',
                          icon: Icons.delete_outline,
                          accentColor: const Color(0xFFFF6B6B),
                          onTap: () {
                            _discardDraftWithConfirmation();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildDraftStatusCard(),
                    const SizedBox(height: 18),
                    _buildSectionHeader(
                      title: 'Basic Details',
                      subtitle:
                          'Set the role, amount, date, place, and the other person involved in this secure transaction.',
                      icon: Icons.edit_note_rounded,
                    ),
                    _buildStylishField(
                      child: DropdownButtonFormField<String>(
                        value: _role,
                        items: [
                          DropdownMenuItem(
                            value: 'lender',
                            child: Text('Lender (giving money)'),
                          ),
                          DropdownMenuItem(
                            value: 'borrower',
                            child: Text('Borrower (taking money)'),
                          ),
                        ],
                        onChanged: _bothUsersVerified
                            ? null
                            : (val) => setState(() {
                                  _role = val ?? 'lender';
                                  _saveDraft();
                                }),
                        decoration: InputDecoration(
                          labelText: 'Your Role',
                          prefixIcon:
                              Icon(Icons.people, color: AppColors.cyan),
                          border: InputBorder.none,
                          helperText:
                              _bothUsersVerified ? 'Details locked' : null,
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    _buildStylishField(
                      child: DropdownButtonFormField<String>(
                        value: _currency,
                        items: _currencies
                            .map((c) => DropdownMenuItem(
                                  value: c['code'],
                                  child: Text('${c['symbol']} ${c['code']}'),
                                ))
                            .toList(),
                        onChanged: _bothUsersVerified
                            ? null
                            : (val) => setState(() {
                                  _currency = val ?? 'INR';
                                  _saveDraft();
                                }),
                        decoration: InputDecoration(
                          labelText: 'Currency',
                          prefixIcon: Icon(Icons.currency_exchange,
                              color: AppColors.cyan),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                    _buildStylishField(
                      child: TextFormField(
                        controller: _amountController,
                        enabled: !_bothUsersVerified,
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              _currencySymbol(),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.cyan,
                              ),
                            ),
                          ),
                          border: InputBorder.none,
                        ),
                        validator: (val) => val == null || val.isEmpty
                            ? 'Amount required'
                            : null,
                      ),
                    ),
                    SizedBox(height: 16),
                    _buildStylishField(
                      child: _buildDatePickerField(),
                    ),
                    SizedBox(height: 16),
                    _buildStylishField(
                      child: _buildTimePickerField(),
                    ),
                    SizedBox(height: 16),
                    _buildStylishField(
                      child: TextFormField(
                        controller: _placeController,
                        enabled: !_bothUsersVerified,
                        decoration: InputDecoration(
                          labelText: 'Place',
                          prefixIcon:
                              Icon(Icons.location_on, color: AppColors.cyan),
                          border: InputBorder.none,
                          helperText: _bothUsersVerified
                              ? 'Transaction details locked after verification'
                              : null,
                        ),
                        validator: (val) => val == null || val.isEmpty
                            ? 'Place required'
                            : null,
                      ),
                    ),
                    SizedBox(height: 12),
                    _buildSectionHeader(
                      title: 'Proof Files',
                      subtitle:
                          'Attach any supporting screenshots or photos that help confirm this transaction later.',
                      icon: Icons.attach_file_rounded,
                    ),
                    SizedBox(height: 12),
                    _buildFilePicker(),
                    SizedBox(height: 12),
                    _buildSectionHeader(
                      title: 'Interest',
                      subtitle:
                          'Choose whether interest applies and preview how repayment changes over time.',
                      icon: Icons.percent_rounded,
                    ),
                    _buildStylishField(
                      child: DropdownButtonFormField<String>(
                        value: _interestType,
                        items: [
                          DropdownMenuItem(
                              value: 'none',
                              child: Text('No Interest (Default)')),
                          DropdownMenuItem(
                              value: 'simple', child: Text('Simple Interest')),
                          DropdownMenuItem(
                              value: 'compound',
                              child: Text('Compound Interest')),
                        ],
                        onChanged: _bothUsersVerified
                            ? null
                            : (val) {
                                setState(() {
                                  _interestType = val ?? 'none';
                                  if (_interestType == 'none') {
                                    _interestRateController.clear();
                                  }
                                  _saveDraft();
                                });
                              },
                        decoration: InputDecoration(
                            labelText: 'Interest Type (Optional)',
                            border: InputBorder.none,
                            helperText: _bothUsersVerified
                                ? 'Transaction details locked after verification'
                                : 'Leave as "No Interest" if no interest applies to this transaction.'),
                      ),
                    ),
                    if (_interestType != 'none') ...[
                      SizedBox(height: 12),
                      _buildInterestGuidanceCard(),
                      SizedBox(height: 12),
                      _buildStylishField(
                        child: TextFormField(
                          controller: _interestRateController,
                          enabled: !_bothUsersVerified,
                          keyboardType:
                              TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Interest Rate (%)',
                            border: InputBorder.none,
                            helperText: _bothUsersVerified
                                ? 'Transaction details locked after verification'
                                : null,
                          ),
                          validator: (val) {
                            // Only validate if interest type is selected
                            if (_interestType == 'none') return null;

                            if (val == null || val.isEmpty)
                              return 'Interest rate required when interest type is selected';
                            if (double.tryParse(val) == null)
                              return 'Enter a valid number';
                            if (double.tryParse(val)! <= 0)
                              return 'Interest rate must be greater than 0';
                            if (double.tryParse(val)! > 100)
                              return 'Interest rate cannot exceed 100%';
                            return null;
                          },
                        ),
                      ),
                    ],
                    if (_interestType == 'compound') ...[
                      SizedBox(height: 12),
                      _buildStylishField(
                        child: DropdownButtonFormField<int>(
                          value: _compoundingFrequency,
                          items: [
                            DropdownMenuItem(
                                value: 1, child: Text('Annually (1x/year)')),
                            DropdownMenuItem(
                                value: 2,
                                child: Text('Semi-annually (2x/year)')),
                            DropdownMenuItem(
                                value: 4, child: Text('Quarterly (4x/year)')),
                            DropdownMenuItem(
                                value: 12, child: Text('Monthly (12x/year)')),
                          ],
                          onChanged: _bothUsersVerified
                              ? null
                              : (val) => setState(() {
                                  _compoundingFrequency = val ?? 1;
                                  _saveDraft();
                                }),
                          decoration: InputDecoration(
                              labelText: 'Compounding Frequency',
                              border: InputBorder.none,
                              helperText: _bothUsersVerified
                                  ? 'Transaction details locked after verification'
                                  : 'How often is interest compounded?'),
                          validator: (val) {
                            // Only validate if compound interest is selected
                            if (_interestType != 'compound') return null;

                            if (val == null || val <= 0)
                              return 'Select frequency';
                            return null;
                          },
                        ),
                      ),
                    ],
                    SizedBox(height: 12),
                    _buildStylishField(
                      child: InkWell(
                        onTap: _bothUsersVerified
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _expectedReturnDate ?? DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                  builder: (context, child) {
                                    return Theme(
                                      data: ThemeData.light().copyWith(
                                        colorScheme: ColorScheme.light(
                                          primary: AppColors.cyan,
                                          onPrimary: Colors.white,
                                          surface: Colors.white,
                                          onSurface: Colors.black87,
                                        ),
                                        dialogTheme: DialogTheme(
                                          backgroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                        textButtonTheme: TextButtonThemeData(
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                AppColors.cyan,
                                          ),
                                        ),
                                        cardColor: Colors.white,
                                        canvasColor: Colors.white,
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setState(() => _expectedReturnDate = picked);
                                  _saveDraft();
                                }
                              },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: _interestType == 'none'
                                ? 'Expected Return Date (Optional)'
                                : 'Expected Return Date *',
                            border: InputBorder.none,
                            helperText: _bothUsersVerified
                                ? 'Transaction details locked after verification'
                                : _interestType == 'none'
                                    ? 'You can set a return date even without interest.'
                                    : 'Required when interest is applied',
                            prefixIcon: Icon(
                              Icons.calendar_today,
                              color: _bothUsersVerified
                                  ? Colors.grey.shade300
                                  : (_interestType == 'none'
                                      ? AppColors.cyan
                                      : Colors.red.shade300),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_expectedReturnDate == null
                                  ? 'Select date'
                                  : DateFormat('yyyy-MM-dd')
                                      .format(_expectedReturnDate!)),
                              Icon(Icons.calendar_today, color: Colors.teal),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_amountController.text.trim().isNotEmpty) ...[
                      SizedBox(height: 12),
                      _buildTransactionPreviewCard(),
                      SizedBox(height: 12),
                      _buildRepaymentPreviewCard(),
                      SizedBox(height: 12),
                      _buildRepaymentTimelineCard(),
                    ],
                    SizedBox(height: 12),
                    _buildSectionHeader(
                      title: 'Verification',
                      subtitle:
                          'Verify both email addresses with OTP. After both are verified, key transaction details get locked for safety.',
                      icon: Icons.verified_user_rounded,
                    ),
                    SizedBox(height: 12),
                    _buildStylishField(
                      child: TextFormField(
                        controller: _descriptionController,
                        enabled: !_bothUsersVerified,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Description (optional)',
                          border: InputBorder.none,
                          hintText: _bothUsersVerified
                              ? 'Transaction details locked after verification'
                              : 'Add a note or description for this transaction',
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    _buildOtpSection(
                      label: 'Counterparty Email',
                      emailController: _counterpartyEmailController,
                      verified: _counterpartyVerified,
                      otpError: _counterpartyOtpError,
                      otpSeconds: _counterpartyOtpSeconds,
                      onSendOtp: () async {
                        final email = _counterpartyEmailController.text;
                        if (_isBlockedEmail(email)) {
                          showBlockedUserDialog(context);
                          return;
                        }
                        if (email.trim() == _userEmailController.text.trim()) {
                          setState(() => _counterpartyEmailError =
                              'Your email and counterparty email cannot be the same.');
                          return;
                        }
                        if (!await _checkEmailExists(email)) {
                          setState(() =>
                              _counterpartyEmailError = 'Email not registered');
                          return;
                        }
                        setState(() => _counterpartyEmailError = null);
                        await _sendOtp(email, true);
                      },
                      onOtpChanged: (val) => _counterpartyOtp = val,
                      onVerifyOtp: () async {
                        if ((_counterpartyOtp ?? '').length != 6) {
                          setState(() =>
                              _counterpartyOtpError = 'Enter 6-digit OTP');
                          return;
                        }
                        await _verifyOtp(_counterpartyEmailController.text,
                            _counterpartyOtp!, true);
                      },
                      enabled: !_counterpartyVerified,
                      emailError: _counterpartyEmailError,
                      onPickFriend: _counterpartyVerified
                          ? null
                          : _pickFriendForCounterparty,
                      friendSuggestions: _friendSuggestions,
                      onSelectFriend: (email) {
                        setState(() {
                          _counterpartyEmailController.text = email;
                        });
                      },
                    ),
                    SizedBox(height: 12),
                    _buildOtpSection(
                      label: 'Your Email',
                      emailController: _userEmailController,
                      verified: _userVerified,
                      otpError: _userOtpError,
                      otpSeconds: _userOtpSeconds,
                      onSendOtp: () async {
                        final email = _userEmailController.text;
                        if (!await _checkEmailExists(email)) {
                          setState(
                              () => _userEmailError = 'Email not registered');
                          return;
                        }
                        setState(() => _userEmailError = null);
                        await _sendOtp(email, false);
                      },
                      onOtpChanged: (val) => _userOtp = val,
                      onVerifyOtp: () async {
                        if ((_userOtp ?? '').length != 6) {
                          setState(() => _userOtpError = 'Enter 6-digit OTP');
                          return;
                        }
                        await _verifyOtp(
                            _userEmailController.text, _userOtp!, false);
                      },
                      enabled: !_userVerified,
                      emailError: _userEmailError,
                      readOnlyEmail: true,
                    ),
                    if (_sameEmailError != null) ...[
                      SizedBox(height: 8),
                      Text(_sameEmailError!,
                          style: TextStyle(color: Colors.red)),
                    ],
                    SizedBox(height: 20),
                    Text(
                      'Review and submit from the sticky summary bar below.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_transactionId != null) ...[
                      SizedBox(height: 20),
                      Center(
                          child: Text('Transaction ID: $_transactionId',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal))),
                    ],
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
