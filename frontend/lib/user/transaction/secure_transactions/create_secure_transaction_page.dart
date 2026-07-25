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
import '../../../widgets/budget_exceeded_sheet.dart';
// Add for wavy background
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'view_secure_transactions_page.dart';
import '../../../settings/set_wallet_pin_page.dart';

import '../../../widgets/stylish_dialog.dart';
import '../../../widgets/payment_success_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../utils/responsive.dart';
import '../../../utils/receipt_ocr_service.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/wave_widget.dart'
    show DeeperTopWaveClipper, TopWaveClipper;

class TransactionPage extends StatefulWidget {
  final String? prefillCounterpartyEmail;
  final bool useCoins;

  const TransactionPage(
      {Key? key, this.prefillCounterpartyEmail, this.useCoins = false})
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
  bool _scanningReceipt = false;
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
  // PIN alternative for the user self-verification step
  bool _hasPinSet = false;
  bool _userPinMode = false;
  String _userPinCode = '';
  bool _verifyingUserPin = false;
  String _category = 'other';
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

  int _currentStep = 0;
  bool _showStepList = true;
  final Set<int> _completedSteps = {};
  String? _stepError;

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
    final t = AppLocalizations.of(context).t;
    if (_expectedReturnDate == null) {
      return t('no_interest_applied_label');
    }
    final days = _expectedReturnDate!
        .difference(_previewStartDate())
        .inDays
        .clamp(0, 36500);
    if (days == 0) return t('same_day_return_label');
    if (days < 30) {
      return days == 1
          ? t('days_count_singular_label').replaceFirst('{count}', '$days')
          : t('days_count_plural_label').replaceFirst('{count}', '$days');
    }
    final months = (days / 30).toStringAsFixed(1);
    return t('months_count_label').replaceFirst('{count}', months);
  }

  int? _remainingDaysCount() {
    if (_expectedReturnDate == null) return null;
    final difference = _expectedReturnDate!.difference(_previewStartDate());
    return difference.inDays;
  }

  String _remainingDaysLabel() {
    final t = AppLocalizations.of(context).t;
    final days = _remainingDaysCount();
    if (days == null) return t('not_scheduled_label');
    if (days < 0)
      return t('days_overdue_label').replaceFirst('{count}', '${days.abs()}');
    return t('days_remaining_label').replaceFirst('{count}', '$days');
  }

  String _draftStatusLabel() {
    final savedAt = _lastDraftSavedAt;
    if (savedAt == null) return _draftStatusMessage;
    final t = AppLocalizations.of(context).t;
    return t('draft_saved_at_label')
        .replaceFirst('{time}', DateFormat('hh:mm a').format(savedAt));
  }

  Widget _buildRepaymentPreviewCard() {
    final t = AppLocalizations.of(context).t;
    final principal = _parsedPrincipalAmount();
    final repayment = _estimatedRepaymentAmount();
    if (principal == null || repayment == null) return const SizedBox.shrink();

    final interestValue = math.max(repayment - principal, 0).toDouble();
    final needsReturnDate =
        _interestType != 'none' && _expectedReturnDate == null;

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
          color: AppThemeColors.cardBg(context),
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
                Expanded(
                  child: Text(
                    t('repayment_preview_title'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context),
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
                _buildPreviewStat(
                    t('principal_label'), _formatPreviewAmount(principal)),
                _buildPreviewStat(
                  t('est_interest_label'),
                  _formatPreviewAmount(interestValue),
                ),
                _buildPreviewStat(
                    t('est_repayment_label'), _formatPreviewAmount(repayment)),
                _buildPreviewStat(t('tenure_label'), _repaymentTenureLabel()),
              ],
            ),
            if (needsReturnDate) ...[
              const SizedBox(height: 12),
              Text(
                t('pick_expected_return_date_message'),
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
    final t = AppLocalizations.of(context).t;

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
                    color: AppThemeColors.secondaryText(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
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
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('repayment_timeline_title'),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context)),
            ),
            const SizedBox(height: 12),
            item(
              icon: Icons.play_circle_outline_rounded,
              title: t('start_date_label'),
              value: DateFormat('MMM d, yyyy • hh:mm a').format(startDate),
              color: AppColors.cyan,
            ),
            const SizedBox(height: 10),
            item(
              icon: Icons.event_available_rounded,
              title: t('expected_return_date_label'),
              value: DateFormat('MMM d, yyyy').format(_expectedReturnDate!),
              color: Colors.green,
            ),
            const SizedBox(height: 10),
            item(
              icon: Icons.payments_outlined,
              title: t('estimated_total_repayment_label'),
              value: _formatPreviewAmount(estimatedRepayment),
              color: Colors.orange,
            ),
            const SizedBox(height: 10),
            item(
              icon: Icons.schedule_rounded,
              title: t('remaining_time_label'),
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
        color: AppThemeColors.tinted(context,
            light: const Color(0xFFF7FBFD), dark: const Color(0xFF173238)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppThemeColors.tinted(context,
                light: const Color(0xFFBFE8F2), dark: const Color(0xFF2A6E80))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppThemeColors.secondaryText(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context),
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppThemeColors.secondaryText(context),
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


  Widget _buildTransactionPreviewCard() {
    final t = AppLocalizations.of(context).t;
    final amount = _parsedPrincipalAmount();
    final roleLabel = _role == 'lender'
        ? t('you_are_lending_label')
        : t('you_are_borrowing_label');
    final counterparty = _counterpartyEmailController.text.trim().isEmpty
        ? t('not_selected_yet_label')
        : _counterpartyEmailController.text.trim();
    final dateLabel = _selectedDate == null
        ? t('not_selected_label')
        : DateFormat('MMM d, yyyy').format(_selectedDate!);
    final returnLabel = _expectedReturnDate == null
        ? (_interestType == 'none'
            ? t('not_needed_label')
            : t('select_expected_return_date_label'))
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
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('transaction_preview_title'),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildPreviewStat(t('role_label'), roleLabel),
                _buildPreviewStat(
                  t('amount_label'),
                  amount == null
                      ? t('enter_amount_label')
                      : _formatPreviewAmount(amount),
                ),
                _buildPreviewStat(t('counterparty_label'), counterparty),
                _buildPreviewStat(
                  t('interest_label'),
                  _interestType == 'none'
                      ? t('no_interest_label')
                      : _interestType == 'simple'
                          ? t('simple_interest_label')
                          : t('compound_interest_label'),
                ),
                _buildPreviewStat(t('txn_date_label'), dateLabel),
                _buildPreviewStat(t('return_date_label'), returnLabel),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterestGuidanceCard() {
    if (_interestType == 'none') return const SizedBox.shrink();
    final t = AppLocalizations.of(context).t;

    final guidance = _interestType == 'simple'
        ? t('simple_interest_guidance_message')
        : t('compound_interest_guidance_message');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.tinted(context,
            light: const Color(0xFFEAF7FB), dark: const Color(0xFF173238)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppThemeColors.tinted(context,
                light: const Color(0xFFBFE8F2), dark: const Color(0xFF2A6E80))),
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
                color: AppThemeColors.secondaryText(context),
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
    _loadPinStatus();
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

  Widget _creationPinTab(String label, IconData icon, bool isPinMode) {
    final selected = _userPinMode == isPinMode;
    return Expanded(
        child: GestureDetector(
      onTap: () => setState(() {
        _userPinMode = isPinMode;
        _userPinCode = '';
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
          Icon(icon, size: 14, color: selected ? Colors.white : Colors.grey),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey)),
        ]),
      ),
    ));
  }

  Future<void> _loadPinStatus() async {
    try {
      final res = await ApiClient.get('/api/wallet/pin/status');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _hasPinSet = data['hasPin'] == true;
          _userPinMode = _hasPinSet;
        });
      }
    } catch (_) {}
  }

  Future<void> _verifyUserPin() async {
    if (_userPinCode.length != 6) return;
    setState(() => _verifyingUserPin = true);
    try {
      final res = await ApiClient.post('/api/transactions/verify-creation-pin',
          body: {'pin': _userPinCode});
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _verifyingUserPin = false;
          _userVerified = true;
        });
      } else {
        final err = res.body.isNotEmpty ? jsonDecode(res.body) : null;
        setState(() => _verifyingUserPin = false);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(err?['error'] ?? 'PIN verification failed'),
              backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) setState(() => _verifyingUserPin = false);
    }
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
      'category': _category,
    };
    await _storage.write(key: _draftStorageKey(), value: jsonEncode(payload));
    _lastDraftSavedAt = DateTime.now();
    if (mounted) {
      setState(() {
        _draftStatusMessage =
            AppLocalizations.of(context).t('draft_saved_label');
      });
    }
  }

  Future<void> _saveDraftWithFeedback() async {
    await _saveDraft();
    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    await _showDraftStatusDialog(
      title: t('draft_saved_title'),
      message: t('secure_transaction_draft_saved_message'),
      icon: Icons.save_outlined,
      accentColor: AppColors.cyan,
      actionLabel: t('continue'),
    );
  }

  Future<void> _clearDraft() async {
    await _storage.delete(key: _draftStorageKey());
    _lastDraftSavedAt = null;
    if (mounted) {
      setState(() {
        _draftStatusMessage =
            AppLocalizations.of(context).t('no_saved_draft_label');
      });
    }
  }

  Future<void> _discardDraftWithConfirmation() async {
    final t = AppLocalizations.of(context).t;
    final shouldDiscard = await _showDraftChoiceDialog(
      title: t('discard_draft_title'),
      message: t('discard_draft_confirm_message'),
      icon: Icons.delete_outline,
      accentColor: const Color(0xFFFF6B6B),
      primaryLabel: t('discard_label'),
      secondaryLabel: t('keep_draft_label'),
    );
    if (shouldDiscard != true) return;
    await _clearDraft();
    if (!mounted) return;
    await _showDraftStatusDialog(
      title: t('draft_discarded_title'),
      message: t('saved_draft_removed_message'),
      icon: Icons.delete_sweep_outlined,
      accentColor: const Color(0xFFFF6B6B),
      actionLabel: t('ok'),
    );
  }

  Future<void> _restoreDraftIfAvailable() async {
    final raw = await _storage.read(key: _draftStorageKey());
    if (raw == null || raw.isEmpty || !mounted) return;
    final t = AppLocalizations.of(context).t;

    final shouldRestore = await _showDraftChoiceDialog(
          title: t('saved_draft_found_title'),
          message: t('saved_draft_found_message'),
          icon: Icons.auto_awesome_outlined,
          accentColor: AppColors.cyan,
          primaryLabel: t('continue_draft_label'),
          secondaryLabel: t('start_fresh_label'),
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
        _category = (data['category'] ?? 'other').toString();
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
        _draftStatusMessage =
            AppLocalizations.of(context).t('draft_restored_label');
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
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipPath(
                      clipper: const DeeperTopWaveClipper(),
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
                  style: TextStyle(
                    fontSize: 16,
                    color: AppThemeColors.primaryText(context),
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
                      side: BorderSide(
                          color: accentColor.withValues(alpha: 0.45)),
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
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipPath(
                      clipper: const DeeperTopWaveClipper(),
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
                  style: TextStyle(
                    fontSize: 16,
                    color: AppThemeColors.primaryText(context),
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
              color: AppThemeColors.cardBg(context),
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
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppThemeColors.secondaryText(context),
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
    final t = AppLocalizations.of(context).t;
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

      String searchQuery = '';

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) => StatefulBuilder(
            builder: (ctx2, setSheetState) {
              final filtered = friends.where((f) {
                final name =
                    (f['name'] ?? f['username'] ?? '').toString().toLowerCase();
                final email = (f['email'] ?? '').toString().toLowerCase();
                final q = searchQuery.toLowerCase();
                return name.contains(q) || email.contains(q);
              }).toList();

              return Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppThemeColors.border(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          Text(t('select_friend_label'),
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppThemeColors.primaryText(context))),
                          const Spacer(),
                          Text(
                              filtered.length == 1
                                  ? t('friend_count_singular_label')
                                  : t('friend_count_plural_label').replaceFirst(
                                      '{count}', '${filtered.length}'),
                              style: TextStyle(
                                  color: AppThemeColors.secondaryText(context),
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: false,
                        style: TextStyle(
                            color: AppThemeColors.primaryText(context)),
                        decoration: InputDecoration(
                          hintText: t('search_by_name_or_email_hint'),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 14),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: AppThemeColors.surfaceBg(context),
                        ),
                        onChanged: (v) => setSheetState(() => searchQuery = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(t('no_friends_found_label'),
                                  style: TextStyle(
                                      color:
                                          AppThemeColors.mutedText(context))))
                          : ListView.builder(
                              controller: scrollController,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final f = filtered[i];
                                final email = (f['email'] ?? '').toString();
                                final name =
                                    (f['name'] ?? f['username'] ?? email)
                                        .toString();
                                final isBlocked = _blockedEmails
                                    .contains(email.toLowerCase().trim());
                                final initials = name.isNotEmpty
                                    ? name
                                        .trim()
                                        .split(' ')
                                        .where((p) => p.isNotEmpty)
                                        .take(2)
                                        .map((p) => p[0].toUpperCase())
                                        .join()
                                    : '?';
                                final avatarColor = Colors.primaries[
                                    name.hashCode.abs() %
                                        Colors.primaries.length];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          avatarColor.withValues(alpha: 0.2),
                                      child: Text(initials,
                                          style: TextStyle(
                                              color: avatarColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15)),
                                    ),
                                    title: Text(name,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AppThemeColors.primaryText(
                                                context))),
                                    subtitle: Text(email,
                                        style: TextStyle(
                                            color: AppThemeColors.secondaryText(
                                                context),
                                            fontSize: 12)),
                                    trailing: isBlocked
                                        ? Text(t('blocked_label'),
                                            style: const TextStyle(
                                                color: Colors.red,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12))
                                        : Icon(Icons.chevron_right,
                                            color: AppThemeColors.mutedText(
                                                context)),
                                    onTap: () {
                                      if (isBlocked) {
                                        Navigator.pop(ctx);
                                        showBlockedUserDialog(context);
                                        return;
                                      }
                                      setState(() {
                                        _counterpartyEmailController.text =
                                            email;
                                      });
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
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

  Future<void> _scanReceipt() async {
    final t = AppLocalizations.of(context).t;
    PlatformFile? target;
    final imageFiles = _pickedFiles.where((f) => f.extension != 'pdf').toList();
    if (imageFiles.isNotEmpty) target = imageFiles.last;

    if (target == null) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      target = result.files.first;
      setState(() => _pickedFiles.add(target!));
      await _saveDraft();
    }

    setState(() => _scanningReceipt = true);
    try {
      String? path = target.path;
      if (path == null && target.bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${target.name}');
        await tempFile.writeAsBytes(target.bytes!, flush: true);
        path = tempFile.path;
      }
      if (path == null) {
        throw Exception(t('could_not_read_selected_image_message'));
      }

      final ocrResult = await ReceiptOcrService.extractFromImage(path);
      if (!mounted) return;

      if (ocrResult.amount == null &&
          ocrResult.date == null &&
          ocrResult.place == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t('could_not_detect_receipt_details_message'))),
        );
        return;
      }

      await _showOcrConfirmDialog(ocrResult);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t('receipt_scan_failed_message')
                  .replaceFirst('{error}', '$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _scanningReceipt = false);
    }
  }

  Future<void> _showOcrConfirmDialog(ReceiptOcrResult result) async {
    final t = AppLocalizations.of(context).t;
    bool useAmount = result.amount != null;
    bool useDate = result.date != null;
    final hasPlace = result.place != null && result.place!.trim().isNotEmpty;
    bool usePlace = hasPlace;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppThemeColors.cardBg(dialogContext),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(t('detected_from_receipt_title'),
              style:
                  TextStyle(color: AppThemeColors.primaryText(dialogContext))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.amount != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: useAmount,
                  onChanged: (v) =>
                      setDialogState(() => useAmount = v ?? false),
                  title: Text('${t('amount_colon_label')} ${result.amount}',
                      style: TextStyle(
                          color: AppThemeColors.primaryText(dialogContext))),
                ),
              if (result.date != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: useDate,
                  onChanged: (v) => setDialogState(() => useDate = v ?? false),
                  title: Text(
                      '${t('date_colon_label')} ${DateFormat('MMM d, yyyy').format(result.date!)}',
                      style: TextStyle(
                          color: AppThemeColors.primaryText(dialogContext))),
                ),
              if (hasPlace)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: usePlace,
                  onChanged: (v) => setDialogState(() => usePlace = v ?? false),
                  title: Text('${t('place_colon_label')} ${result.place}',
                      style: TextStyle(
                          color: AppThemeColors.primaryText(dialogContext))),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('cancel'),
                  style: TextStyle(
                      color: AppThemeColors.secondaryText(dialogContext))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('apply_label'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      if (useAmount && result.amount != null) {
        _amountController.text = result.amount!.toStringAsFixed(2);
      }
      if (useDate && result.date != null) {
        _selectedDate = result.date;
      }
      if (usePlace && result.place != null) {
        _placeController.text = result.place!;
      }
    });
    _saveDraft();
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
    final t = AppLocalizations.of(context).t;
    final proofCount = _pickedFiles.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                proofCount == 0
                    ? t('no_proof_files_added_yet_label')
                    : (proofCount == 1
                        ? t('proof_file_attached_singular_label')
                        : t('proof_file_attached_plural_label')
                            .replaceFirst('{count}', '$proofCount')),
                style: TextStyle(
                  color: AppThemeColors.secondaryText(context),
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
                proofCount == 0 ? t('optional_label') : t('ready_label'),
                style: const TextStyle(
                  color: Color(0xFF0077B6),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _bothUsersVerified ? null : _pickFiles,
              icon: const Icon(Icons.attach_file),
              label: Text(t('add_proof_files_label')),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            ),
            OutlinedButton.icon(
              onPressed:
                  _bothUsersVerified || _scanningReceipt ? null : _scanReceipt,
              icon: _scanningReceipt
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(_scanningReceipt
                  ? t('scanning_ellipsis_label')
                  : t('scan_receipt_label')),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.cyan),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_pickedFiles.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(context,
                  light: const Color(0xFFF7FBFD),
                  dark: const Color(0xFF173238)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFBFE8F2),
                      dark: const Color(0xFF2A6E80))),
            ),
            child: Row(
              children: [
                const Icon(Icons.image_outlined, color: AppColors.cyan),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('add_screenshots_or_photos_message'),
                    style:
                        TextStyle(color: AppThemeColors.secondaryText(context)),
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
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppThemeColors.tinted(context,
                            light: const Color(0xFFBFE8F2),
                            dark: const Color(0xFF2A6E80))),
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
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppThemeColors.primaryText(context),
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
        color: AppThemeColors.tinted(context,
            light: const Color(0xFFF6FBFD), dark: const Color(0xFF173238)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppThemeColors.tinted(context,
                light: const Color(0xFFBFE8F2), dark: const Color(0xFF2A6E80))),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined, color: AppColors.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _draftStatusLabel(),
              style: TextStyle(
                color: AppThemeColors.primaryText(context),
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
          color: AppThemeColors.cardBg(context),
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
              color: AppThemeColors.cardBg(context),
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
                    color: AppThemeColors.secondaryText(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppThemeColors.primaryText(context),
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
    final t = AppLocalizations.of(context).t;
    final amt = double.tryParse(_amountController.text.replaceAll(',', ''));
    final recipient = _counterpartyEmailController.text.trim();
    final extraDetails = <String, String>{
      if (_transactionId != null) t('transaction_id_label'): _transactionId!,
      t('role_label_colon'): _role,
      if (giftCardAwarded) t('bonus_label_colon'): t('gift_card_won_emoji'),
    };

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessPage(
          title: t('transaction_created_exclaim'),
          amount: amt,
          currency: _currencySymbol(),
          recipientName: recipient.isNotEmpty ? recipient : null,
          transactionType: t('secure_transaction_label'),
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
    final t = AppLocalizations.of(context).t;
    final amount = _parsedPrincipalAmount();
    final repayment = _estimatedRepaymentAmount();
    final roleLabel = _role == 'lender'
        ? t('you_are_lending_label')
        : t('you_are_borrowing_label');
    final counterparty = _counterpartyEmailController.text.trim().isEmpty
        ? t('not_selected_label')
        : _counterpartyEmailController.text.trim();
    final transactionDate = _selectedDate == null
        ? t('not_selected_label')
        : DateFormat('MMM d, yyyy').format(_selectedDate!);
    final returnDate = _expectedReturnDate == null
        ? (_interestType == 'none'
            ? t('optional_and_not_selected_label')
            : t('required_before_submit_label'))
        : DateFormat('MMM d, yyyy').format(_expectedReturnDate!);
    final interestLabel = _interestType == 'none'
        ? t('no_interest_label')
        : _interestType == 'simple'
            ? t('simple_interest_label')
            : t('compound_interest_label');
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('review_and_submit_title'),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppThemeColors.primaryText(context),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                t('check_details_before_creating_secure_transaction_message'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppThemeColors.secondaryText(context),
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
                        color: AppThemeColors.tinted(context,
                            light: const Color(0xFFF8FCFE),
                            dark: const Color(0xFF173238)),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: AppThemeColors.tinted(context,
                                light: const Color(0xFFBFE8F2),
                                dark: const Color(0xFF2A6E80))),
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _buildPreviewStat(t('role_label'), roleLabel),
                          _buildPreviewStat(
                            t('amount_label'),
                            amount == null
                                ? t('not_entered_label')
                                : _formatPreviewAmount(amount),
                          ),
                          _buildPreviewStat(t('interest_label'), interestLabel),
                          _buildPreviewStat(
                            t('proof_files_label'),
                            t('count_attached_label').replaceFirst(
                                '{count}', '${_pickedFiles.length}'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildReviewInfoTile(
                      icon: Icons.person_outline_rounded,
                      title: t('counterparty_label'),
                      value: counterparty,
                      accent: AppColors.cyan,
                    ),
                    const SizedBox(height: 10),
                    _buildReviewInfoTile(
                      icon: Icons.event_available_rounded,
                      title: t('transaction_date_label'),
                      value: transactionDate,
                      accent: Colors.orange,
                    ),
                    const SizedBox(height: 10),
                    _buildReviewInfoTile(
                      icon: Icons.update_rounded,
                      title: t('expected_return_date_label'),
                      value: returnDate,
                      accent: Colors.green,
                    ),
                    if (repayment != null) ...[
                      const SizedBox(height: 10),
                      _buildReviewInfoTile(
                        icon: Icons.payments_outlined,
                        title: t('estimated_repayment_label'),
                        value: _formatPreviewAmount(repayment),
                        accent: Colors.purple,
                      ),
                    ],
                    if (_expectedReturnDate != null) ...[
                      const SizedBox(height: 10),
                      _buildReviewInfoTile(
                        icon: Icons.schedule_rounded,
                        title: t('time_until_return_label'),
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
                        label: Text(
                          t('confirm_and_submit_label'),
                          style: const TextStyle(
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
                        child: Text(t('go_back_and_edit_label')),
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
      final t = AppLocalizations.of(context).t;
      setState(() {
        if (isCounterparty) {
          _counterpartyOtpError = t('invalid_or_expired_otp_message');
        } else {
          _userOtpError = t('invalid_or_expired_otp_message');
        }
      });
    }
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (_isBlockedEmail(_counterpartyEmailController.text)) {
      showBlockedUserDialog(context);
      return;
    }

    // Safety net: re-check daily limit in case user had the page open a while.
    if (!session.isSubscribed) await _loadDailyLimits();

    if (!session.isSubscribed &&
        _dailyUserTxRemaining != null &&
        _dailyUserTxRemaining! <= 0) {
      showDailyLimitDialog(context,
          message: t('daily_secure_transactions_limit_reached_message'));
      return;
    }

    // useCoins was determined before this page was opened.
    if (session.isSubscribed || !widget.useCoins) {
      _submitWithApi();
    } else {
      _submitWithCoins();
    }
  }

  Future<void> _submitWithCoins() async {
    setState(() => _sameEmailError = null);
    final t = AppLocalizations.of(context).t;
    if (_selectedDate == null) {
      _showStylishErrorDialog(
        t('transaction_date_required_title'),
        t('select_transaction_date_message'),
      );
      return;
    }
    if (_selectedTime == null) {
      _showStylishErrorDialog(
        t('transaction_time_required_title'),
        t('select_transaction_time_message'),
      );
      return;
    }
    if (_interestType != 'none' && _expectedReturnDate == null) {
      _showStylishErrorDialog(t('expected_return_date_required_title'),
          t('select_expected_return_date_interest_message'));
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showStylishErrorDialog(
        t('incomplete_form_title'),
        t('fill_required_fields_message'),
      );
      return;
    }
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
        'category': _category,
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
        final t = AppLocalizations.of(context).t;
        String errorMsg = t('forbidden_label');
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
        final t = AppLocalizations.of(context).t;
        String errorMsg = t('daily_limit_reached');
        try {
          final data = jsonDecode(res.body);
          errorMsg = data['error'] ?? data['message'] ?? errorMsg;
        } catch (_) {}
        showDailyLimitDialog(context, message: errorMsg);
      } else {
        final t = AppLocalizations.of(context).t;
        final errBody =
            (res.body.isNotEmpty) ? res.body : t('unknown_error_label');
        String errorMsg = t('failed_to_create_transaction_message');
        try {
          final data = jsonDecode(errBody);
          errorMsg = data['error'] ?? data['message'] ?? errBody;
        } catch (_) {
          errorMsg = errBody;
        }
        _showStylishErrorDialog(t('transaction_failed_title'), errorMsg);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showStylishErrorDialog(
          AppLocalizations.of(context).t('transaction_failed_title'),
          e.toString());
    }
  }

  Future<void> _submitWithApi() async {
    setState(() => _sameEmailError = null);
    final t = AppLocalizations.of(context).t;

    if (_selectedDate == null) {
      _showStylishErrorDialog(
        t('transaction_date_required_title'),
        t('select_transaction_date_message'),
      );
      return;
    }
    if (_selectedTime == null) {
      _showStylishErrorDialog(
        t('transaction_time_required_title'),
        t('select_transaction_time_message'),
      );
      return;
    }

    // Custom validation for expected return date when interest is selected
    if (_interestType != 'none' && _expectedReturnDate == null) {
      _showStylishErrorDialog(t('expected_return_date_required_title'),
          t('select_expected_return_date_interest_message'));
      return;
    }

    // Validate form — show dialog so the error is never silently lost below the fold
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showStylishErrorDialog(
        t('incomplete_form_title'),
        t('fill_required_fields_message'),
      );
      return;
    }

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
        'category': _category,
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
        final errBody = res.body.isNotEmpty ? res.body : t('unknown_error_label');
        // Budget exceeded — show stylish sheet and let user decide
        final exceeded = parseBudgetExceeded(errBody);
        if (exceeded != null) {
          final proceed = await showBudgetExceededSheet(context, exceeded);
          if (!mounted) return;
          if (proceed) {
            body['force'] = 'true';
            setState(() => _isLoading = true);
            final res2 = await ApiClient.postMultipart(
              '/api/transactions/create',
              fields: body,
              files: _buildMultipartFiles(),
            );
            setState(() => _isLoading = false);
            if (!mounted) return;
            if (res2.statusCode == 200 || res2.statusCode == 201) {
              final data2 = jsonDecode(res2.body);
              final giftCardAwarded = data2['giftCardAwarded'] == true;
              await _clearDraft();
              setState(() { _transactionId = data2['transactionId']; });
              Provider.of<SessionProvider>(context, listen: false).loadFreebieCounts();
              _showTransactionSuccessDialog(giftCardAwarded: giftCardAwarded);
            } else {
              try {
                final d = jsonDecode(res2.body);
                _showStylishErrorDialog(t('transaction_failed_title'), d['error'] ?? d['message'] ?? res2.body);
              } catch (_) {
                _showStylishErrorDialog(t('transaction_failed_title'), res2.body);
              }
            }
          }
          return;
        }
        String errorMsg = t('failed_to_create_transaction_message');
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
        _showStylishErrorDialog(t('transaction_failed_title'), errorMsg);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showStylishErrorDialog(t('transaction_failed_title'), e.toString());
    }
  }

  void _showStylishErrorDialog(String title, String message) {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: AppThemeColors.cardBg(dialogContext),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipPath(
                    clipper: const DeeperTopWaveClipper(),
                    child: Container(
                      height: 80,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFFF6B6B), Color(0xFFFF8E8E)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
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
              const SizedBox(height: 24),
              Text(title,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF6B6B))),
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                    fontSize: 16,
                    color: AppThemeColors.primaryText(dialogContext)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B6B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(t('ok'),
                      style:
                          const TextStyle(fontSize: 16, color: Colors.white)),
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
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: AppColors.cyan,
                            onPrimary: Colors.white,
                          ),
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.cyan,
                        ),
                      ),
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
          labelText: AppLocalizations.of(context).t('transaction_date_label'),
          prefixIcon: Icon(Icons.calendar_today, color: AppColors.cyan),
          border: InputBorder.none,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedDate == null
                  ? AppLocalizations.of(context).t('select_date_label')
                  : DateFormat('MMM d, yyyy').format(_selectedDate!),
              style: TextStyle(
                color: _selectedDate == null
                    ? AppThemeColors.mutedText(context)
                    : AppThemeColors.primaryText(context),
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
                    data: Theme.of(context).copyWith(
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: AppColors.cyan,
                            onPrimary: Colors.white,
                          ),
                      textButtonTheme: TextButtonThemeData(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.cyan,
                        ),
                      ),
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
          labelText: AppLocalizations.of(context).t('time_label'),
          prefixIcon: Icon(Icons.access_time, color: AppColors.cyan),
          border: InputBorder.none,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedTime == null
                  ? AppLocalizations.of(context).t('select_time_label')
                  : _selectedTime!.format(context),
              style: TextStyle(
                color: _selectedTime == null
                    ? AppThemeColors.mutedText(context)
                    : AppThemeColors.primaryText(context),
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
    final t = AppLocalizations.of(context).t;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      color: AppThemeColors.cardBg(context),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 8),
            _buildStylishField(
              child: TextFormField(
                controller: emailController,
                enabled: !verified && !readOnlyEmail,
                readOnly: readOnlyEmail,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  labelText: t('email'),
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
                  if (val == null || val.isEmpty)
                    return t('email_required_label');
                  if (!val.contains('@')) return t('invalid_email_label');
                  return null;
                },
              ),
            ),
            if (!verified) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (otpSeconds == 0)
                    ElevatedButton(
                      onPressed: enabled ? onSendOtp : null,
                      child: Text(t('send_otp_label')),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                          t('resend_otp_seconds_label')
                              .replaceFirst('{seconds}', '$otpSeconds'),
                          style: const TextStyle(
                              color: Colors.teal, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const SizedBox(width: 12),
                  if (otpError != null)
                    Text(otpError, style: const TextStyle(color: Colors.red)),
                ],
              ),
              const SizedBox(height: 8),
              OtpInput(
                onChanged: onOtpChanged,
                enabled: enabled,
                autoFocus: false,
                obscureText: true,
                showVisibilityToggle: true,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: enabled ? onVerifyOtp : null,
                child: Text(t('verify_otp_label')),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.verified, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(t('verified_label'),
                      style: const TextStyle(color: Colors.green)),
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

  // â”€â”€â”€ Wizard navigation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static const List<String> _stepTitles = [
    'Basic Details',
    'Proofs',
    'Interest',
    'Return Date',
    'Review',
    'Verification',
    'Final Review',
  ];

  static const List<IconData> _stepIcons = [
    Icons.edit_note_rounded,
    Icons.attach_file_rounded,
    Icons.percent_rounded,
    Icons.event_rounded,
    Icons.preview_rounded,
    Icons.verified_user_rounded,
    Icons.check_circle_rounded,
  ];

  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_amountController.text.trim().isEmpty) return 'Amount is required';
        if (double.tryParse(_amountController.text.trim()) == null) return 'Enter a valid amount';
        if (_selectedDate == null) return 'Transaction date is required';
        if (_selectedTime == null) return 'Transaction time is required';
        if (_placeController.text.trim().isEmpty) return 'Place is required';
        return null;
      case 2:
        if (_interestType != 'none') {
          if (_interestRateController.text.trim().isEmpty) return 'Interest rate is required';
          final rate = double.tryParse(_interestRateController.text.trim());
          if (rate == null) return 'Enter a valid interest rate';
          if (rate <= 0) return 'Interest rate must be greater than 0';
          if (rate > 100) return 'Interest rate cannot exceed 100%';
        }
        return null;
      case 3:
        if (_interestType != 'none' && _expectedReturnDate == null) {
          return 'Expected return date is required when interest is applied';
        }
        return null;
      case 5:
        if (!_bothUsersVerified) return 'Both parties must verify before you can proceed';
        return null;
      default:
        return null;
    }
  }

  void _nextStep() {
    final error = _validateStep(_currentStep);
    if (error != null) {
      setState(() => _stepError = error);
      return;
    }
    setState(() {
      _completedSteps.add(_currentStep);
      _stepError = null;
      if (_currentStep < 6) {
        _currentStep++;
        _showStepList = false;
      } else {
        _showStepList = true;
      }
    });
  }

  void _saveAndGoToList() {
    final error = _validateStep(_currentStep);
    if (error != null) {
      setState(() => _stepError = error);
      return;
    }
    setState(() {
      _completedSteps.add(_currentStep);
      _stepError = null;
      _showStepList = true;
    });
  }

  bool _isStepAccessible(int index) {
    if (index == 0) return true;
    return _completedSteps.containsAll(List.generate(index, (i) => i));
  }

  void _goToStep(int index) {
    if (!_isStepAccessible(index)) return;
    setState(() { _currentStep = index; _showStepList = false; _stepError = null; });
  }

  static const List<String> _stepSubtitleKeys = [
    'step_basic_details_subtitle',
    'step_proofs_subtitle',
    'step_interest_subtitle',
    'step_return_date_subtitle',
    'step_review_subtitle',
    'step_verification_subtitle',
    'step_final_review_subtitle',
  ];

  static const List<Color> _stepColors = [
    Color(0xFF0077B6),
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.indigo,
    Colors.green,
    Colors.deepOrange,
  ];

  Color _stepFillColor(int index) {
    if (AppThemeColors.isDark(context)) {
      const darkFills = [
        Color(0xFF1A2E1A), // dark green tint
        Color(0xFF2A1A2E), // dark purple tint
        Color(0xFF2E2A1A), // dark amber tint
        Color(0xFF1A2E2B), // dark teal tint
        Color(0xFF1A1C2E), // dark indigo tint
        Color(0xFF1A2E20), // dark green tint 2
        Color(0xFF2E1A1E), // dark pink/orange tint
      ];
      return darkFills[index % darkFills.length];
    }
    const fills = [
      Color(0xFFE8F5E9), // soft green
      Color(0xFFF3E5F5), // soft purple
      Color(0xFFFFF8E7), // soft cream/orange
      Color(0xFFE0F2F1), // soft teal
      Color(0xFFE8EAF6), // soft indigo
      Color(0xFFE8F5E9), // soft green again
      Color(0xFFFCE4EC), // soft pink/deep-orange
    ];
    return fills[index % fills.length];
  }

  Widget _buildStepList() {
    final t = AppLocalizations.of(context).t;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: 7,
      itemBuilder: (_, i) => _buildStepCard(i, t),
    );
  }

  Widget _buildStepCard(int index, String Function(String) t) {
    final isDone = _completedSteps.contains(index);
    final isLocked = !_isStepAccessible(index);
    final color = isLocked ? Colors.grey : _stepColors[index];
    // Steps 0–4 can be edited after completion, until both users verify
    final canEdit = isDone && !_bothUsersVerified && index < 5;

    final String statusLabel;
    if (isDone) {
      statusLabel = t('step_completed_label');
    } else if (isLocked) {
      statusLabel = t('step_locked_label');
    } else {
      statusLabel = t('tap_to_fill_label');
    }

    return GestureDetector(
      onTap: isLocked ? null : () => _goToStep(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: isLocked
              ? LinearGradient(colors: AppThemeColors.isDark(context)
                  ? [Colors.grey.shade800, Colors.grey.shade700, Colors.grey.shade800]
                  : [Colors.grey.shade300, Colors.grey.shade200, Colors.grey.shade300])
              : const LinearGradient(
                  colors: [Colors.orange, Colors.white, Colors.green],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 10))],
        ),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: _stepFillColor(index),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: AppThemeColors.cardBg(context).withValues(alpha: 0.92),
                ),
                child: isDone
                    ? Icon(Icons.check_circle_rounded, color: Colors.green, size: 28)
                    : isLocked
                        ? Icon(Icons.lock_rounded, color: Colors.grey, size: 24)
                        : Icon(_stepIcons[index], color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stepTitles[index],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isLocked ? Colors.grey : AppThemeColors.primaryText(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDone ? Colors.green : isLocked ? Colors.grey : color,
                          ),
                        ),
                        if (canEdit) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: color.withValues(alpha: 0.4)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.edit_rounded, size: 10, color: color),
                              const SizedBox(width: 3),
                              Text(t('edit'), style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      t(_stepSubtitleKeys[index]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isLocked ? Colors.grey.shade400 : AppThemeColors.secondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                canEdit
                    ? Icons.edit_rounded
                    : isDone
                        ? Icons.chevron_right_rounded
                        : isLocked
                            ? Icons.lock_outline_rounded
                            : Icons.chevron_right_rounded,
                color: isLocked ? Colors.grey.shade400 : canEdit ? color : color,
                size: canEdit ? 18 : 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(String Function(String) t) {
    switch (_currentStep) {
      case 0: return _buildStep0(t);
      case 1: return _buildStep1(t);
      case 2: return _buildStep2(t);
      case 3: return _buildStep3(t);
      case 4: return _buildStep4(t);
      case 5: return _buildStep5(t);
      case 6: return _buildStep6(t);
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildWizardBottomBar() {
    final t = AppLocalizations.of(context).t;
    final isLast = _currentStep == 6;
    final canSubmit = _bothUsersVerified && !_isLoading;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_stepError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_stepError!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                ]),
              ),
            ],
            if (isLast)
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveAndGoToList,
                    icon: const Icon(Icons.list_rounded, size: 15),
                    label: Text(t('save_and_steps_label')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(color: AppThemeColors.divider(context)),
                      foregroundColor: AppThemeColors.primaryText(context),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: canSubmit ? _showReviewSheetAndSubmit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(canSubmit ? t('review_and_submit_short_label') : t('verify_to_submit_label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ])
            else
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveAndGoToList,
                    icon: const Icon(Icons.list_rounded, size: 15),
                    label: Text(t('save_and_steps_label'), style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(color: AppThemeColors.divider(context)),
                      foregroundColor: AppThemeColors.primaryText(context),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _nextStep,
                    icon: const Icon(Icons.arrow_forward_ios, size: 13, color: Colors.white),
                    label: Text(t('save_and_next_label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 13),
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

  // â”€â”€â”€ Step builders â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildStep0(String Function(String) t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subscription/limit info banner
          Consumer<SessionProvider>(builder: (context, session, _) {
            if (session.isSubscribed) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(t('unlimited_transactions_message'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.cyan)),
              );
            }
            final remaining = session.freeUserTransactionsRemaining;
            if (remaining == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(t('free_transactions_remaining_message').replaceFirst('{count}', '$remaining'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppThemeColors.secondaryText(context))),
            );
          }),
          if (_bothUsersVerified)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(context, light: const Color(0xFFE0F7FA), dark: const Color(0xFF173238)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock, color: AppColors.cyan, size: 16),
                const SizedBox(width: 8),
                Text(t('details_locked_label'), style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
          // Info card
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.info_outline_rounded, color: AppColors.cyan, size: 16),
                SizedBox(width: 8),
                Text('What is a Secure Transaction?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.cyan)),
              ]),
              const SizedBox(height: 8),
              Text('A Secure Transaction records a real-world money exchange between two people — a lender and a borrower — with dual verification, optional interest, and proofs for full accountability.',
                  style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context), height: 1.5)),
            ]),
          ),
          _buildSectionHeader(title: t('basic_details_title'), subtitle: t('basic_details_subtitle_message'), icon: Icons.edit_note_rounded),
          _buildStylishField(
            child: DropdownButtonFormField<String>(
              value: _role,
              items: [
                DropdownMenuItem(value: 'lender', child: Text(t('lender_giving_money_label'))),
                DropdownMenuItem(value: 'borrower', child: Text(t('borrower_taking_money_label'))),
              ],
              onChanged: _bothUsersVerified ? null : (val) => setState(() { _role = val ?? 'lender'; _saveDraft(); }),
              decoration: InputDecoration(labelText: t('your_role_label'), prefixIcon: Icon(Icons.people, color: AppColors.cyan), border: InputBorder.none,
                helperText: _bothUsersVerified ? t('details_locked_label') : null),
            ),
          ),
          const SizedBox(height: 16),
          _buildStylishField(
            child: DropdownButtonFormField<String>(
              value: _currency,
              items: _currencies.map((c) => DropdownMenuItem(value: c['code'], child: Text('${c['symbol']} ${c['code']}'))) .toList(),
              onChanged: _bothUsersVerified ? null : (val) => setState(() { _currency = val ?? 'INR'; _saveDraft(); }),
              decoration: InputDecoration(labelText: t('currency_label'), prefixIcon: Icon(Icons.currency_exchange, color: AppColors.cyan), border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 16),
          _buildStylishField(
            child: TextFormField(
              controller: _amountController,
              enabled: !_bothUsersVerified,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: t('amount_label'),
                prefixIcon: Padding(padding: const EdgeInsets.all(14), child: Text(_currencySymbol(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.cyan))),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildStylishField(child: _buildDatePickerField()),
          const SizedBox(height: 16),
          _buildStylishField(child: _buildTimePickerField()),
          const SizedBox(height: 16),
          _buildStylishField(
            child: TextFormField(
              controller: _placeController,
              enabled: !_bothUsersVerified,
              decoration: InputDecoration(
                labelText: t('place_label'),
                prefixIcon: Icon(Icons.location_on, color: AppColors.cyan),
                border: InputBorder.none,
                helperText: _bothUsersVerified ? t('transaction_details_locked_after_verification_label') : null,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _buildDraftActionCard(title: t('save_draft'), subtitle: t('pause_now_continue_later_label'), icon: Icons.save_outlined, accentColor: AppColors.cyan, onTap: _saveDraftWithFeedback)),
            const SizedBox(width: 12),
            Expanded(child: _buildDraftActionCard(title: t('discard_draft_title'), subtitle: t('remove_saved_version_label'), icon: Icons.delete_outline, accentColor: const Color(0xFFFF6B6B), onTap: _discardDraftWithConfirmation)),
          ]),
          const SizedBox(height: 10),
          _buildDraftStatusCard(),
        ],
      ),
    );
  }

  Widget _buildStep1(String Function(String) t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title: t('proof_files_label'), subtitle: t('proof_files_subtitle_message'), icon: Icons.attach_file_rounded),
          const SizedBox(height: 12),
          _buildFilePicker(),
          const SizedBox(height: 20),
          _infoTile(Icons.image_outlined, 'Accepted formats', 'You can attach JPG, PNG, and PDF files as proof — receipts, agreements, screenshots.', Colors.blue),
          const SizedBox(height: 12),
          _infoTile(Icons.security_rounded, 'Why attach proofs?', 'Proofs add legal weight to your transaction record. In case of disputes, these documents serve as evidence.', Colors.green),
          const SizedBox(height: 12),
          _infoTile(Icons.cloud_upload_outlined, 'Storage', 'Files are encrypted and securely stored. Only transaction participants can access them.', Colors.purple),
          const SizedBox(height: 12),
          _infoTile(Icons.auto_awesome_rounded, 'OCR Support', 'LenDen can auto-read receipt amounts using OCR — tap the scan icon after attaching an image.', AppColors.cyan),
        ],
      ),
    );
  }

  Widget _buildStep2(String Function(String) t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title: t('interest_label'), subtitle: t('interest_subtitle_message'), icon: Icons.percent_rounded),
          _buildStylishField(
            child: DropdownButtonFormField<String>(
              value: _interestType,
              items: [
                DropdownMenuItem(value: 'none', child: Text(t('no_interest_default_label'))),
                DropdownMenuItem(value: 'simple', child: Text(t('simple_interest_label'))),
                DropdownMenuItem(value: 'compound', child: Text(t('compound_interest_label'))),
              ],
              onChanged: _bothUsersVerified ? null : (val) { setState(() { _interestType = val ?? 'none'; if (_interestType == 'none') _interestRateController.clear(); _saveDraft(); }); },
              decoration: InputDecoration(labelText: t('interest_type_optional_label'), border: InputBorder.none,
                helperText: _bothUsersVerified ? t('transaction_details_locked_after_verification_label') : t('leave_as_no_interest_message')),
            ),
          ),
          if (_interestType != 'none') ...[
            const SizedBox(height: 12),
            _buildInterestGuidanceCard(),
            const SizedBox(height: 12),
            _buildStylishField(
              child: TextFormField(
                controller: _interestRateController,
                enabled: !_bothUsersVerified,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: t('interest_rate_percent_label'), border: InputBorder.none,
                  helperText: _bothUsersVerified ? t('transaction_details_locked_after_verification_label') : null),
              ),
            ),
          ],
          if (_interestType == 'compound') ...[
            const SizedBox(height: 12),
            _buildStylishField(
              child: DropdownButtonFormField<int>(
                value: _compoundingFrequency,
                items: [
                  DropdownMenuItem(value: 1, child: Text(t('annually_label'))),
                  DropdownMenuItem(value: 2, child: Text(t('semi_annually_label'))),
                  DropdownMenuItem(value: 4, child: Text(t('quarterly_label'))),
                  DropdownMenuItem(value: 12, child: Text(t('monthly_label'))),
                ],
                onChanged: _bothUsersVerified ? null : (val) => setState(() { _compoundingFrequency = val ?? 1; _saveDraft(); }),
                decoration: InputDecoration(labelText: t('compounding_frequency_label'), border: InputBorder.none,
                  helperText: _bothUsersVerified ? t('transaction_details_locked_after_verification_label') : t('how_often_interest_compounded_label')),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _infoTile(Icons.calculate_outlined, 'Simple Interest', 'Interest = Principal × Rate × Time.\nThe same interest amount is charged every period. Predictable and easy to understand.', Colors.blue),
          const SizedBox(height: 12),
          _infoTile(Icons.trending_up_rounded, 'Compound Interest', 'A = P × (1 + r/n)^(n×t)\nWhere P = principal, r = annual rate, n = times compounded per year, t = years.\nInterest earns on top of previously accumulated interest — grows faster over time.', Colors.orange),
          const SizedBox(height: 12),
          _infoTile(Icons.handshake_outlined, 'No Interest', 'Record a money exchange without any interest — useful for friendly loans or family transfers.', Colors.green),
        ],
      ),
    );
  }

  Widget _buildStep3(String Function(String) t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title: t('expected_return_date_optional_label'), subtitle: 'When do you expect the money to be returned?', icon: Icons.event_rounded),
          _buildStylishField(
            child: InkWell(
              onTap: _bothUsersVerified ? null : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _expectedReturnDate ?? DateTime.now(),
                  firstDate: DateTime(2000), lastDate: DateTime(2100),
                  builder: (context, child) => Theme(
                    data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.cyan, onPrimary: Colors.white),
                      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.cyan))),
                    child: child!,
                  ),
                );
                if (picked != null) { setState(() => _expectedReturnDate = picked); _saveDraft(); }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: _interestType == 'none' ? t('expected_return_date_optional_label') : t('expected_return_date_required_star_label'),
                  border: InputBorder.none,
                  helperText: _bothUsersVerified ? t('transaction_details_locked_after_verification_label') : (_interestType == 'none' ? t('can_set_return_date_without_interest_message') : t('required_when_interest_applied_label')),
                  prefixIcon: Icon(Icons.calendar_today, color: _bothUsersVerified ? AppThemeColors.mutedText(context) : (_interestType == 'none' ? AppColors.cyan : Colors.red.shade300)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_expectedReturnDate == null ? t('select_date_label') : DateFormat('yyyy-MM-dd').format(_expectedReturnDate!)),
                  const Icon(Icons.calendar_today, color: Colors.teal),
                ]),
              ),
            ),
          ),
          if (_amountController.text.trim().isNotEmpty && _expectedReturnDate != null) ...[
            const SizedBox(height: 16),
            _buildRepaymentPreviewCard(),
            const SizedBox(height: 12),
            _buildRepaymentTimelineCard(),
          ],
          const SizedBox(height: 20),
          _infoTile(Icons.event_available_rounded, 'Why set a return date?', 'It creates a deadline for repayment and is required when interest is applied to calculate total due.', Colors.blue),
          const SizedBox(height: 12),
          _infoTile(Icons.notifications_active_outlined, 'Reminders', 'LenDen sends automated reminders to the borrower as the return date approaches, reducing disputes.', AppColors.cyan),
          const SizedBox(height: 12),
          _infoTile(Icons.update_rounded, 'Flexible', 'Both parties can agree to extend the return date later through the transaction details page.', Colors.green),
        ],
      ),
    );
  }

  Widget _buildStep4(String Function(String) t) {
    final amount = _parsedPrincipalAmount();
    final sym = _currencySymbol();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title: 'Review Your Details', subtitle: 'Check everything before verification. You can go back to edit.', icon: Icons.preview_rounded),
          _reviewCard([
            _reviewRow(Icons.people, 'Your Role', _role == 'lender' ? t('lender_giving_money_label') : t('borrower_taking_money_label'), Colors.blue),
            _reviewRow(Icons.currency_exchange, 'Currency', _currency, Colors.teal),
            _reviewRow(Icons.payments_outlined, 'Amount', amount != null ? '$sym${amount.toStringAsFixed(2)}' : '—', Colors.green),
            _reviewRow(Icons.calendar_today, 'Date', _selectedDate != null ? DateFormat('MMM d, yyyy').format(_selectedDate!) : '—', Colors.orange),
            _reviewRow(Icons.access_time, 'Time', _selectedTime != null ? _selectedTime!.format(context) : '—', Colors.purple),
            _reviewRow(Icons.location_on, 'Place', _placeController.text.trim().isNotEmpty ? _placeController.text.trim() : '—', Colors.red),
          ]),
          const SizedBox(height: 14),
          _reviewCard([
            _reviewRow(Icons.attach_file_rounded, 'Proofs Attached', '${_pickedFiles.length} file(s)', Colors.blue),
          ]),
          const SizedBox(height: 14),
          _reviewCard([
            _reviewRow(Icons.percent_rounded, 'Interest Type', _interestType == 'none' ? 'No Interest' : (_interestType == 'simple' ? 'Simple' : 'Compound'), Colors.orange),
            if (_interestType != 'none')
              _reviewRow(Icons.numbers_rounded, 'Rate', _interestRateController.text.trim().isNotEmpty ? '${_interestRateController.text.trim()}%' : '—', Colors.red),
            if (_interestType == 'compound')
              _reviewRow(Icons.repeat_rounded, 'Compounding', _compoundingFrequency == 1 ? 'Annual' : _compoundingFrequency == 2 ? 'Semi-Annual' : _compoundingFrequency == 4 ? 'Quarterly' : 'Monthly', Colors.purple),
            _reviewRow(Icons.event_rounded, 'Return Date', _expectedReturnDate != null ? DateFormat('MMM d, yyyy').format(_expectedReturnDate!) : '—', Colors.green),
          ]),
          if (amount != null && _expectedReturnDate != null) ...[
            const SizedBox(height: 14),
            _buildTransactionPreviewCard(),
          ],
          const SizedBox(height: 14),
          _infoTile(Icons.check_circle_outline_rounded, 'All good?', 'If everything looks correct, proceed to Verification where both parties will confirm via OTP or PIN.', AppColors.cyan),
        ],
      ),
    );
  }

  Widget _reviewCard(List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Colors.orange, Colors.white, Colors.green], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(16)),
        child: Column(children: rows),
      ),
    );
  }

  Widget _reviewRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context)))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      ]),
    );
  }

  Widget _infoTile(IconData icon, String title, String body, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context), height: 1.45)),
        ])),
      ]),
    );
  }

  Widget _buildStep5(String Function(String) t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title: t('verification_title'), subtitle: t('verification_subtitle_message'), icon: Icons.verified_user_rounded),
          const SizedBox(height: 8),
          _buildStylishField(
            child: DropdownButtonFormField<String>(
              value: _category,
              items: const [
                DropdownMenuItem(value: 'other', child: Text('Other')),
                DropdownMenuItem(value: 'personal', child: Text('Personal')),
                DropdownMenuItem(value: 'food', child: Text('Food & Dining')),
                DropdownMenuItem(value: 'shopping', child: Text('Shopping')),
                DropdownMenuItem(value: 'transport', child: Text('Transport')),
                DropdownMenuItem(value: 'entertainment', child: Text('Entertainment')),
                DropdownMenuItem(value: 'healthcare', child: Text('Healthcare')),
                DropdownMenuItem(value: 'education', child: Text('Education')),
                DropdownMenuItem(value: 'utilities', child: Text('Utilities')),
                DropdownMenuItem(value: 'rent', child: Text('Rent')),
                DropdownMenuItem(value: 'business', child: Text('Business')),
                DropdownMenuItem(value: 'travel', child: Text('Travel')),
              ],
              onChanged: _bothUsersVerified ? null : (v) => setState(() => _category = v ?? 'other'),
              decoration: InputDecoration(
                labelText: t('category'),
                prefixIcon: const Icon(Icons.label_outline_rounded),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildStylishField(
            child: TextFormField(
              controller: _descriptionController,
              enabled: !_bothUsersVerified,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: t('description_optional_label'),
                border: InputBorder.none,
                hintText: _bothUsersVerified ? t('transaction_details_locked_after_verification_label') : t('add_note_or_description_hint'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildOtpSection(
            label: t('counterparty_email_label'),
            emailController: _counterpartyEmailController,
            verified: _counterpartyVerified,
            otpError: _counterpartyOtpError,
            otpSeconds: _counterpartyOtpSeconds,
            onSendOtp: () async {
              final email = _counterpartyEmailController.text;
              if (_isBlockedEmail(email)) { showBlockedUserDialog(context); return; }
              if (email.trim() == _userEmailController.text.trim()) {
                setState(() => _counterpartyEmailError = t('emails_cannot_be_same_message'));
                return;
              }
              if (!await _checkEmailExists(email)) {
                setState(() => _counterpartyEmailError = t('email_not_registered_label'));
                return;
              }
              setState(() => _counterpartyEmailError = null);
              await _sendOtp(email, true);
            },
            onOtpChanged: (val) => _counterpartyOtp = val,
            onVerifyOtp: () async {
              if ((_counterpartyOtp ?? '').length != 6) {
                setState(() => _counterpartyOtpError = t('enter_6_digit_otp_label'));
                return;
              }
              await _verifyOtp(_counterpartyEmailController.text, _counterpartyOtp!, true);
            },
            enabled: !_counterpartyVerified,
            emailError: _counterpartyEmailError,
            onPickFriend: _counterpartyVerified ? null : _pickFriendForCounterparty,
            friendSuggestions: _friendSuggestions,
            onSelectFriend: (email) => setState(() => _counterpartyEmailController.text = email),
          ),
          const SizedBox(height: 12),
          if (!_userVerified) ...[
            Row(children: [
              _creationPinTab(t('use_pin_label'), Icons.dialpad_rounded, true),
              const SizedBox(width: 8),
              _creationPinTab(t('use_email_otp_label'), Icons.email_outlined, false),
            ]),
            const SizedBox(height: 12),
          ],
          if (_userPinMode && !_userVerified) ...[
            if (!_hasPinSet) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(child: Text('You haven\'t set up a wallet PIN yet.', style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w500))),
                  ]),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    icon: const Icon(Icons.dialpad_rounded, color: Colors.white, size: 15),
                    label: const Text('Set Up PIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const SetWalletPinPage()));
                      if (mounted) _loadPinStatus();
                    },
                  ),
                ]),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 1))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.dialpad_rounded, color: AppColors.cyan, size: 18),
                    const SizedBox(width: 8),
                    Text(t('enter_wallet_pin_label'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ]),
                  const SizedBox(height: 12),
                  OtpInput(onChanged: (code) => setState(() => _userPinCode = code), enabled: !_verifyingUserPin, autoFocus: false, obscureText: true, showVisibilityToggle: true),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _verifyingUserPin ? null : _verifyUserPin,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: _verifyingUserPin
                        ? const Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 8), Text('Verifying…')])
                        : const Text('Verify PIN'),
                  ),
                ]),
              ),
            ],
          ] else if (!_userVerified) ...[
            _buildOtpSection(
              label: t('your_email_label'),
              emailController: _userEmailController,
              verified: _userVerified,
              otpError: _userOtpError,
              otpSeconds: _userOtpSeconds,
              onSendOtp: () async {
                final email = _userEmailController.text;
                if (!await _checkEmailExists(email)) { setState(() => _userEmailError = t('email_not_registered_label')); return; }
                setState(() => _userEmailError = null);
                await _sendOtp(email, false);
              },
              onOtpChanged: (val) => _userOtp = val,
              onVerifyOtp: () async {
                if ((_userOtp ?? '').length != 6) { setState(() => _userOtpError = t('enter_6_digit_otp_label')); return; }
                await _verifyOtp(_userEmailController.text, _userOtp!, false);
              },
              enabled: !_userVerified,
              emailError: _userEmailError,
              readOnlyEmail: true,
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withValues(alpha: 0.3))),
              child: Row(children: [
                const Icon(Icons.verified_user_rounded, color: Colors.green, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Your identity is verified. Both parties must verify before submission.', style: TextStyle(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.w500))),
              ]),
            ),
          ],
          if (_sameEmailError != null) ...[
            const SizedBox(height: 8),
            Text(_sameEmailError!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          _infoTile(Icons.shield_outlined, 'Why verification?', 'Both parties verify their identity to prevent unauthorised transactions. Neither can deny the agreement once both verify.', AppColors.cyan),
          const SizedBox(height: 12),
          _infoTile(Icons.timer_outlined, 'OTP expiry', 'Email OTPs expire in 2 minutes. Request a new one if it expires. PINs work instantly without expiry.', Colors.orange),
        ],
      ),
    );
  }

  Widget _buildStep6(String Function(String) t) {
    final amount = _parsedPrincipalAmount();
    final sym = _currencySymbol();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title: 'Final Review', subtitle: 'Your details are locked. Review and submit the transaction.', icon: Icons.check_circle_rounded),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(context, light: const Color(0xFFE0F7FA), dark: const Color(0xFF173238)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.lock, color: AppColors.cyan, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(t('details_locked_label'), style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600))),
              const Icon(Icons.verified, color: Colors.green, size: 18),
              const SizedBox(width: 6),
              const Text('Verified', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
          ),
          _reviewCard([
            _reviewRow(Icons.people, 'Your Role', _role == 'lender' ? t('lender_giving_money_label') : t('borrower_taking_money_label'), Colors.blue),
            _reviewRow(Icons.currency_exchange, 'Currency', _currency, Colors.teal),
            _reviewRow(Icons.payments_outlined, 'Amount', amount != null ? '$sym${amount.toStringAsFixed(2)}' : '—', Colors.green),
            _reviewRow(Icons.calendar_today, 'Date', _selectedDate != null ? DateFormat('MMM d, yyyy').format(_selectedDate!) : '—', Colors.orange),
            _reviewRow(Icons.access_time, 'Time', _selectedTime != null ? _selectedTime!.format(context) : '—', Colors.purple),
            _reviewRow(Icons.location_on, 'Place', _placeController.text.trim().isNotEmpty ? _placeController.text.trim() : '—', Colors.red),
          ]),
          const SizedBox(height: 14),
          _reviewCard([
            _reviewRow(Icons.percent_rounded, 'Interest', _interestType == 'none' ? 'None' : (_interestType == 'simple' ? 'Simple' : 'Compound'), Colors.orange),
            if (_interestType != 'none')
              _reviewRow(Icons.numbers_rounded, 'Rate', '${_interestRateController.text.trim()}%', Colors.red),
            _reviewRow(Icons.event_rounded, 'Return Date', _expectedReturnDate != null ? DateFormat('MMM d, yyyy').format(_expectedReturnDate!) : '—', Colors.green),
            _reviewRow(Icons.attach_file_rounded, 'Proofs', '${_pickedFiles.length} file(s)', Colors.blue),
            _reviewRow(Icons.mail_outlined, 'Counterparty', _counterpartyEmailController.text.trim().isNotEmpty ? _counterpartyEmailController.text.trim() : '—', Colors.purple),
          ]),
          if (amount != null) ...[
            const SizedBox(height: 14),
            _buildTransactionPreviewCard(),
            if (_expectedReturnDate != null) ...[
              const SizedBox(height: 12),
              _buildRepaymentPreviewCard(),
            ],
          ],
          if (_transactionId != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withValues(alpha: 0.3))),
              child: Row(children: [
                const Icon(Icons.task_alt, color: Colors.green, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('${t('transaction_id_label')}: $_transactionId', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal))),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Text(t('review_submit_from_sticky_bar_message'), style: TextStyle(color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
        ],
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
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      bottomNavigationBar: _showStepList ? null : _buildWizardBottomBar(),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(context.sh(156)),
        child: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back,
                    color: AppThemeColors.primaryText(context)),
                onPressed: () {
                  if (!_showStepList) {
                    setState(() { _showStepList = true; _stepError = null; });
                  } else if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.pushReplacementNamed(context, '/user/dashboard');
                  }
                },
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    _showStepList
                        ? AppLocalizations.of(context).t('create_secure_transaction_title')
                        : _stepTitles[_currentStep],
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: AppThemeColors.primaryText(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
          flexibleSpace: ClipPath(
            clipper: const TopWaveClipper(),
            child: Container(
              height: context.sh(156),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.cyan, Color(0xFF48CAE4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Builder(builder: (ctx) {
        final t = AppLocalizations.of(ctx).t;
        if (_showStepList) {
          return Form(key: _formKey, child: _buildStepList());
        }
        return Form(
          key: _formKey,
          child: _buildStepContent(t),
        );
      }),
    );
  }
}
