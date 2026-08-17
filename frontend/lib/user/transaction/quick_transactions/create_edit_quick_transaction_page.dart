import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../utils/pickers.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../utils/avatar_helpers.dart' as ah;
import '../../../session.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/budget_exceeded_sheet.dart';

class CreateEditQuickTransactionPage extends StatefulWidget {
  final Map<String, dynamic>? transaction;
  final bool useCoins;
  final String? prefillCounterpartyEmail;
  final String? initialAmount;
  final String? initialCurrency;
  final String? initialDescription;
  final String? initialRole;
  final Set<String> blockedEmails;
  final int? dailyRemaining;
  final bool isSubscribed;

  const CreateEditQuickTransactionPage({
    super.key,
    this.transaction,
    this.useCoins = false,
    this.prefillCounterpartyEmail,
    this.initialAmount,
    this.initialCurrency,
    this.initialDescription,
    this.initialRole,
    this.blockedEmails = const {},
    this.dailyRemaining,
    this.isSubscribed = false,
  });

  @override
  State<CreateEditQuickTransactionPage> createState() =>
      _CreateEditQuickTransactionPageState();
}

class _CreateEditQuickTransactionPageState
    extends State<CreateEditQuickTransactionPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  String _currency = 'INR';
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _counterpartyEmailController =
      TextEditingController();
  String _role = 'lender';
  String _category = 'other';
  bool _isScheduled = false;
  DateTime? _scheduledAt;
  bool _isLoading = false;
  bool _loadingFriends = false;
  String? _userEmail;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _suggestions = [];

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

  bool _isEditingAsCreator() {
    final creatorEmail =
        (widget.transaction?['creatorEmail'] ?? '').toString().toLowerCase().trim();
    final userEmail = (_userEmail ?? '').toLowerCase().trim();
    return creatorEmail.isEmpty || creatorEmail == userEmail;
  }

  String _storedRoleForSubmission(String selectedRole) {
    if (widget.transaction == null || _isEditingAsCreator()) {
      return selectedRole;
    }
    return selectedRole == 'lender' ? 'borrower' : 'lender';
  }

  String _currencySymbol([String? code]) {
    final selectedCode = (code ?? _currency).toUpperCase();
    final match = _currencies.firstWhere(
      (item) => item['code'] == selectedCode,
      orElse: () => const {'code': 'INR', 'symbol': '₹'},
    );
    return match['symbol'] ?? '₹';
  }

  @override
  void initState() {
    super.initState();
    final session = Provider.of<SessionProvider>(context, listen: false);
    _userEmail = session.user?['email'];

    _loadFriends();
    _counterpartyEmailController.addListener(_updateSuggestions);

    if (widget.transaction != null) {
      _amountController.text = widget.transaction!['amount']?.toString() ?? '';
      _currency = widget.transaction!['currency'] ?? 'INR';
      _descriptionController.text = widget.transaction!['description'] ?? '';
      final currentUserEmail = _userEmail;
      if (currentUserEmail != null) {
        final users = widget.transaction!['users'] as List? ?? [];
        String counterpartyEmail = '';
        for (final user in users) {
          String email = '';
          if (user is Map) {
            email = (user['email'] ?? '').toString();
          } else if (user is String) {
            email = user;
          }
          if (email.isNotEmpty &&
              email.toLowerCase() != currentUserEmail.toLowerCase()) {
            counterpartyEmail = email;
            break;
          }
        }
        _counterpartyEmailController.text = counterpartyEmail;
      }
      _role = widget.initialRole ?? widget.transaction!['role'] ?? 'lender';
      final rawCat = widget.transaction!['category'] ?? 'other';
      _category = rawCat == 'healthcare' ? 'medical' : rawCat;
    } else if ((widget.prefillCounterpartyEmail ?? '').isNotEmpty) {
      _counterpartyEmailController.text =
          widget.prefillCounterpartyEmail!.trim();
      _amountController.text = widget.initialAmount ?? '';
      _currency = widget.initialCurrency ?? 'INR';
      _descriptionController.text = widget.initialDescription ?? '';
      _role = widget.initialRole ?? 'lender';
    }
  }

  bool _isBlockedEmail(String? email) {
    final target = email?.toLowerCase().trim();
    if (target == null || target.isEmpty) return false;
    return widget.blockedEmails.contains(target);
  }

  @override
  void dispose() {
    _counterpartyEmailController.removeListener(_updateSuggestions);
    _amountController.dispose();
    _descriptionController.dispose();
    _counterpartyEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _friends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
        });
        _updateSuggestions();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  void _updateSuggestions() {
    final query = _counterpartyEmailController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final matches = _friends.where((f) {
      final email = (f['email'] ?? '').toString().toLowerCase();
      final name = (f['name'] ?? f['username'] ?? '').toString().toLowerCase();
      if (_isBlockedEmail(email)) return false;
      return email.contains(query) || name.contains(query);
    }).toList();
    setState(() => _suggestions = matches.take(5).toList());
  }


  Future<void> _pickFriend() async {
    final t = AppLocalizations.of(context).t;
    List<Map<String, dynamic>> allFriends;
    if (_friends.isNotEmpty) {
      allFriends = _friends;
    } else {
      setState(() => _loadingFriends = true);
      try {
        final res = await ApiClient.get('/api/friends');
        if (!mounted) return;
        if (res.statusCode != 200) return;
        final data = jsonDecode(res.body);
        allFriends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
        if (mounted) setState(() { _friends = allFriends; _loadingFriends = false; });
      } catch (_) {
        if (mounted) setState(() => _loadingFriends = false);
        return;
      }
    }
    if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          String searchQuery = '';
          return StatefulBuilder(
            builder: (ctx, setSheetState) {
              final filtered = allFriends.where((f) {
                final email = (f['email'] ?? '').toString().toLowerCase();
                final name = (f['name'] ?? f['username'] ?? '')
                    .toString()
                    .toLowerCase();
                final q = searchQuery.toLowerCase();
                return q.isEmpty ||
                    email.contains(q) ||
                    name.contains(q);
              }).toList();

              return DraggableScrollableSheet(
                initialChildSize: 0.65,
                minChildSize: 0.4,
                maxChildSize: 0.92,
                builder: (_, scrollController) => Container(
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(ctx),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    children: [
                      // Drag handle
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppThemeColors.divider(ctx),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.cyan.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.people_rounded,
                                  color: AppColors.cyan, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t('select_friend_title'),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppThemeColors.primaryText(ctx),
                                  ),
                                ),
                                Text(
                                  allFriends.length == 1
                                      ? t('one_friend_label')
                                      : '${allFriends.length} ${t('friends_count_label')}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppThemeColors.secondaryText(ctx)),
                                ),
                              ],
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: Icon(Icons.close,
                                  color: AppThemeColors.secondaryText(ctx), size: 22),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Search box
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppThemeColors.surfaceBg(ctx),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: TextField(
                            autofocus: false,
                            style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                            onChanged: (v) =>
                                setSheetState(() => searchQuery = v),
                            decoration: InputDecoration(
                              hintText: t('search_by_name_or_email_placeholder'),
                              hintStyle: TextStyle(
                                  color: AppThemeColors.mutedText(ctx), fontSize: 14),
                              prefixIcon: Icon(Icons.search,
                                  color: AppThemeColors.mutedText(ctx), size: 20),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      Divider(height: 1, color: AppThemeColors.divider(ctx)),

                      // Friend list
                      Expanded(
                        child: allFriends.isEmpty
                            ? _emptyFriendsState()
                            : filtered.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.search_off,
                                            size: 48,
                                            color: AppThemeColors.mutedText(ctx)),
                                        const SizedBox(height: 12),
                                        Text(
                                          '${t('no_match_for_label')} "$searchQuery"',
                                          style: TextStyle(
                                              color: AppThemeColors.mutedText(ctx),
                                              fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    controller: scrollController,
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 8, 16, 24),
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (_, idx) {
                                      final f = filtered[idx];
                                      final email =
                                          (f['email'] ?? '').toString();
                                      final name = (f['name'] ??
                                              f['username'] ??
                                              '')
                                          .toString();
                                      final isBlocked =
                                          _isBlockedEmail(email);
                                      final displayName =
                                          name.isNotEmpty ? name : email;
                                      final initials =
                                          ah.initials(name, email);
                                      final color =
                                          ah.avatarColor(displayName);

                                      return GestureDetector(
                                        onTap: () {
                                          if (isBlocked) {
                                            Navigator.pop(ctx);
                                            showSnack(context,
                                                t('this_user_is_blocked'),
                                                isError: true);
                                            return;
                                          }
                                          setState(() {
                                            _counterpartyEmailController
                                                .text = email;
                                            _suggestions = [];
                                          });
                                          Navigator.pop(ctx);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: isBlocked
                                                ? Colors.red
                                                    .withValues(alpha: 0.04)
                                                : AppThemeColors.surfaceBg(ctx),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: isBlocked
                                                  ? Colors.red
                                                      .withValues(alpha: 0.2)
                                                  : AppThemeColors.border(ctx),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              // Avatar
                                              Container(
                                                width: 46,
                                                height: 46,
                                                decoration: BoxDecoration(
                                                  color: isBlocked
                                                      ? Colors.red[100]
                                                      : color.withValues(
                                                          alpha: 0.18),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    initials,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isBlocked
                                                          ? Colors.red
                                                          : color,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 14),

                                              // Name & email
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .start,
                                                  children: [
                                                    Text(
                                                      name.isNotEmpty
                                                          ? name
                                                          : email,
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: isBlocked
                                                            ? Colors.red[700]
                                                            : AppThemeColors
                                                                .primaryText(ctx),
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                    ),
                                                    if (name.isNotEmpty) ...[
                                                      const SizedBox(
                                                          height: 2),
                                                      Text(
                                                        email,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: AppThemeColors
                                                              .secondaryText(ctx),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),

                                              // Trailing
                                              if (isBlocked)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red[50],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    border: Border.all(
                                                        color: Colors
                                                            .red.shade200),
                                                  ),
                                                  child: Text(
                                                    t('blocked_label'),
                                                    style: const TextStyle(
                                                      color: Colors.red,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                )
                                              else
                                                Icon(
                                                  Icons.arrow_forward_ios,
                                                  size: 14,
                                                  color: AppThemeColors.mutedText(ctx),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
  }

  Widget _emptyFriendsState() {
    final t = AppLocalizations.of(context).t;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_add_alt_1,
                size: 40, color: AppColors.cyan),
          ),
          const SizedBox(height: 16),
          Text(
            t('no_friends_yet'),
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context)),
          ),
          const SizedBox(height: 6),
          Text(
            t('add_friends_to_quickly_select_them_here'),
            style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context).t;
    final isEditing = widget.transaction != null;
    if (!_formKey.currentState!.validate()) return;
    if (_isBlockedEmail(_counterpartyEmailController.text)) {
      showSnack(context, t('this_user_is_blocked'), isError: true);
      return;
    }
    if (!isEditing && _isScheduled && _scheduledAt == null) {
      showSnack(context, t('pick_scheduled_date_label'), isError: true);
      return;
    }
    setState(() => _isLoading = true);

    final body = {
      'amount': _amountController.text,
      'currency': _currency,
      'description': _descriptionController.text,
      'counterpartyEmail': _counterpartyEmailController.text,
      'role': _storedRoleForSubmission(_role),
      'category': _category,
      'date': DateTime.now().toIso8601String(),
      'time': TimeOfDay.now().format(context),
      if (!isEditing && _isScheduled && _scheduledAt != null) ...{
        'isScheduled': true,
        'scheduledAt': _scheduledAt!.toIso8601String(),
      },
    };

    try {
      final url = widget.useCoins
          ? '/api/quick-transactions/with-coins'
          : '/api/quick-transactions';
      final res = isEditing
          ? await ApiClient.put(
              '/api/quick-transactions/${widget.transaction!['_id']}',
              body: body)
          : await ApiClient.post(url, body: body);

      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        Navigator.pop(context, jsonDecode(res.body));
      } else {
        setState(() => _isLoading = false);
        final exceeded = parseBudgetExceeded(res.body);
        if (exceeded != null) {
          final proceed = await showBudgetExceededSheet(context, exceeded);
          if (!mounted) return;
          if (proceed) {
            body['force'] = true;
            setState(() => _isLoading = true);
            final res2 = await ApiClient.post(url, body: body);
            if (!mounted) return;
            setState(() => _isLoading = false);
            if (res2.statusCode == 200 || res2.statusCode == 201) {
              Navigator.pop(context, jsonDecode(res2.body));
            } else {
              showSnack(context, jsonDecode(res2.body)['error'] ?? res2.body, isError: true);
            }
          }
          return;
        }
        final error = jsonDecode(res.body)['error'] ?? jsonDecode(res.body)['message'] ?? res.body;
        showSnack(context, error.toString(), isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showSnack(context, e.toString(), isError: true);
    }
  }

  Widget _buildStylishField({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final userEmail = _userEmail;
    final isEditing = widget.transaction != null;
    final limitReached = !widget.useCoins &&
        !widget.isSubscribed &&
        (widget.dailyRemaining != null) &&
        (widget.dailyRemaining! <= 0) &&
        !isEditing;

    if (userEmail == null) {
      return Scaffold(
        backgroundColor: AppThemeColors.scaffoldBg(context),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('error_user_not_logged_in'),
                  style: TextStyle(color: AppThemeColors.primaryText(context))),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('go_back_label')),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(4, 16, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.cyan, Color(0xFF48CAE4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isEditing ? Icons.edit : Icons.add_circle_outline,
                    color: AppThemeColors.primaryText(context),
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEditing
                          ? t('edit_quick_transaction_title')
                          : t('new_quick_transaction_title'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Form content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (!widget.isSubscribed &&
                          widget.dailyRemaining != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppThemeColors.tinted(context,
                                light: const Color(0xFFE3F2FD),
                                dark: const Color(0xFF1B3A57)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${t('daily_quick_transactions_remaining_label')}: ${widget.dailyRemaining}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppThemeColors.primaryText(context)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.useCoins &&
                          !widget.isSubscribed &&
                          widget.dailyRemaining != null &&
                          widget.dailyRemaining! <= 0)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppThemeColors.tinted(context,
                                light: const Color(0xFFFFF3E0),
                                dark: const Color(0xFF4A3F1F)),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t('daily_free_limit_exhausted_coins_message'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppThemeColors.primaryText(context)),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Currency
                      _buildStylishField(
                        child: DropdownButtonFormField<String>(
                          value: _currency,
                          items: _currencies
                              .map((c) => DropdownMenuItem(
                                    value: c['code'],
                                    child:
                                        Text('${c['symbol']} ${c['code']}'),
                                  ))
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _currency = val ?? 'INR'),
                          decoration: InputDecoration(
                            labelText: t('currency'),
                            prefixIcon: Icon(Icons.currency_exchange,
                                color: AppColors.cyan),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Amount
                      _buildStylishField(
                        child: TextFormField(
                          controller: _amountController,
                          decoration: InputDecoration(
                            labelText: '${t('amount')} (${_currencySymbol()})',
                            prefixIcon: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                _currencySymbol(),
                                style: const TextStyle(
                                  color: AppColors.cyan,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            border: InputBorder.none,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return t('please_enter_an_amount');
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Description
                      _buildStylishField(
                        child: TextFormField(
                          controller: _descriptionController,
                          decoration: InputDecoration(
                            labelText: t('description'),
                            prefixIcon: const Icon(Icons.description,
                                color: AppColors.cyan),
                            border: InputBorder.none,
                          ),
                          maxLines: 2,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return t('please_enter_a_description');
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Your email (read-only)
                      _buildStylishField(
                        child: TextFormField(
                          initialValue: userEmail,
                          enabled: false,
                          decoration: InputDecoration(
                            labelText: t('your_email'),
                            prefixIcon:
                                const Icon(Icons.person, color: Colors.grey),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Counterparty email
                      _buildStylishField(
                        child: TextFormField(
                          controller: _counterpartyEmailController,
                          enabled: !isEditing,
                          decoration: InputDecoration(
                            labelText: t('counterparty_email'),
                            prefixIcon: Icon(Icons.person_outline,
                                color: isEditing
                                    ? Colors.grey
                                    : AppColors.cyan),
                            suffixIcon: _loadingFriends
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan),
                                    ),
                                  )
                                : IconButton(
                                    icon: Icon(Icons.people,
                                        color: isEditing ? Colors.grey : AppColors.cyan),
                                    onPressed: isEditing ? null : _pickFriend,
                                  ),
                            border: InputBorder.none,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return t('please_enter_counterparty_email');
                            }
                            if (value == userEmail) {
                              return t(
                                  'counterparty_cannot_be_same_as_your_email');
                            }
                            return null;
                          },
                        ),
                      ),
                      if (_suggestions.isNotEmpty && !isEditing) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _suggestions.map((f) {
                            final email =
                                (f['email'] ?? '').toString();
                            final name = (f['name'] ?? f['username'] ?? '')
                                .toString();
                            return ActionChip(
                              label: Text(name.isNotEmpty
                                  ? '$name ($email)'
                                  : email),
                              onPressed: () {
                                setState(() {
                                  _counterpartyEmailController.text = email;
                                  _suggestions = [];
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Role
                      _buildStylishField(
                        child: DropdownButtonFormField<String>(
                          value: _role,
                          items: [
                            DropdownMenuItem(
                              value: 'lender',
                              child: Text(t('lending_you_gave_money')),
                            ),
                            DropdownMenuItem(
                              value: 'borrower',
                              child: Text(t('borrowing_you_took_money')),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => _role = val ?? 'lender'),
                          decoration: InputDecoration(
                            labelText: t('your_position'),
                            prefixIcon: const Icon(Icons.people,
                                color: AppColors.cyan),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Category
                      _buildStylishField(
                        child: DropdownButtonFormField<String>(
                          value: _category,
                          items: const [
                            DropdownMenuItem(value: 'food', child: Text('Food & Dining')),
                            DropdownMenuItem(value: 'transport', child: Text('Transport')),
                            DropdownMenuItem(value: 'accommodation', child: Text('Accommodation')),
                            DropdownMenuItem(value: 'entertainment', child: Text('Entertainment')),
                            DropdownMenuItem(value: 'shopping', child: Text('Shopping')),
                            DropdownMenuItem(value: 'utilities', child: Text('Utilities')),
                            DropdownMenuItem(value: 'medical', child: Text('Medical / Healthcare')),
                            DropdownMenuItem(value: 'education', child: Text('Education')),
                            DropdownMenuItem(value: 'personal', child: Text('Personal')),
                            DropdownMenuItem(value: 'rent', child: Text('Rent')),
                            DropdownMenuItem(value: 'business', child: Text('Business')),
                            DropdownMenuItem(value: 'travel', child: Text('Travel')),
                            DropdownMenuItem(value: 'other', child: Text('Other')),
                          ],
                          onChanged: (val) => setState(() => _category = val ?? 'other'),
                          decoration: InputDecoration(
                            labelText: t('category'),
                            prefixIcon: const Icon(Icons.label_outline_rounded, color: AppColors.cyan),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Schedule for later (only on create)
                      if (!isEditing) ...[
                        _buildStylishField(
                          child: SwitchListTile(
                            value: _isScheduled,
                            onChanged: (v) => setState(() {
                              _isScheduled = v;
                              if (!v) _scheduledAt = null;
                            }),
                            title: Text(t('schedule_for_later_label'),
                                style: TextStyle(color: AppThemeColors.primaryText(context))),
                            subtitle: _scheduledAt != null
                                ? Text(
                                    '${_scheduledAt!.year}-${_scheduledAt!.month.toString().padLeft(2, '0')}-${_scheduledAt!.day.toString().padLeft(2, '0')}',
                                    style: TextStyle(color: AppColors.cyan, fontSize: 13),
                                  )
                                : null,
                            secondary: const Icon(Icons.schedule_rounded, color: AppColors.cyan),
                            activeColor: AppColors.cyan,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          ),
                        ),
                        if (_isScheduled) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today_rounded, color: AppColors.cyan, size: 18),
                            label: Text(
                              _scheduledAt == null
                                  ? t('pick_scheduled_date_label')
                                  : '${_scheduledAt!.year}-${_scheduledAt!.month.toString().padLeft(2, '0')}-${_scheduledAt!.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: AppColors.cyan),
                            ),
                            onPressed: () async {
                              final picked = await showAppDatePicker(
                                context: context,
                                initialDate: DateTime.now().add(const Duration(days: 1)),
                                firstDate: DateTime.now().add(const Duration(minutes: 1)),
                                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                              );
                              if (picked != null) setState(() => _scheduledAt = picked);
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.cyan),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),

            // Action buttons
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: AppThemeColors.surfaceBg(context),
                border: Border(
                  top: BorderSide(color: AppThemeColors.divider(context)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        t('cancel'),
                        style: TextStyle(
                            color: AppThemeColors.secondaryText(context),
                            fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _isLoading || limitReached ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              isEditing ? t('update') : t('create'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
