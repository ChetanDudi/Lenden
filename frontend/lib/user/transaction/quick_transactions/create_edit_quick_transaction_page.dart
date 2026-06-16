import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';

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
  bool _isLoading = false;
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
        final counterparty = users.cast<Map<String, dynamic>>().firstWhere(
          (user) => user['email'] != currentUserEmail,
          orElse: () => <String, dynamic>{},
        );
        _counterpartyEmailController.text =
            counterparty.isNotEmpty ? (counterparty['email'] ?? '') : '';
      }
      _role = widget.initialRole ?? widget.transaction!['role'] ?? 'lender';
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
    } catch (_) {}
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

  Color _avatarColor(String name) {
    final colors = [
      const Color(0xFF00BCD4),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
      const Color(0xFFE91E63),
      const Color(0xFF2196F3),
      const Color(0xFF009688),
      const Color(0xFFFF5722),
    ];
    if (name.isEmpty) return colors[0];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  String _initials(String name, String email) {
    final src = name.isNotEmpty ? name : email;
    final parts = src.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return src.isNotEmpty ? src[0].toUpperCase() : '?';
  }

  Future<void> _pickFriend() async {
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final allFriends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
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
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    children: [
                      // Drag handle
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
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
                                const Text(
                                  'Select Friend',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                Text(
                                  '${allFriends.length} friend${allFriends.length == 1 ? '' : 's'}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500]),
                                ),
                              ],
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: Icon(Icons.close,
                                  color: Colors.grey[600], size: 22),
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
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: TextField(
                            autofocus: false,
                            onChanged: (v) =>
                                setSheetState(() => searchQuery = v),
                            decoration: InputDecoration(
                              hintText: 'Search by name or email…',
                              hintStyle: TextStyle(
                                  color: Colors.grey[400], fontSize: 14),
                              prefixIcon: Icon(Icons.search,
                                  color: Colors.grey[400], size: 20),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      const Divider(height: 1),

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
                                            color: Colors.grey[300]),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No match for "$searchQuery"',
                                          style: TextStyle(
                                              color: Colors.grey[400],
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
                                          _initials(name, email);
                                      final color =
                                          _avatarColor(displayName);

                                      return GestureDetector(
                                        onTap: () {
                                          if (isBlocked) {
                                            Navigator.pop(ctx);
                                            showSnack(context,
                                                'This user is blocked.',
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
                                                : Colors.grey[50],
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: isBlocked
                                                  ? Colors.red
                                                      .withValues(alpha: 0.2)
                                                  : Colors.grey[200]!,
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
                                                            : Colors.black87,
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
                                                          color: Colors
                                                              .grey[500],
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
                                                  child: const Text(
                                                    'Blocked',
                                                    style: TextStyle(
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
                                                  color: Colors.grey[400],
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
    } catch (_) {}
  }

  Widget _emptyFriendsState() {
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
          const Text(
            'No friends yet',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(
            'Add friends to quickly select them here',
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final isEditing = widget.transaction != null;
    if (!_formKey.currentState!.validate()) return;
    if (_isBlockedEmail(_counterpartyEmailController.text)) {
      showSnack(context, 'This user is blocked.', isError: true);
      return;
    }
    setState(() => _isLoading = true);

    final body = {
      'amount': _amountController.text,
      'currency': _currency,
      'description': _descriptionController.text,
      'counterpartyEmail': _counterpartyEmailController.text,
      'role': _storedRoleForSubmission(_role),
      'date': DateTime.now().toIso8601String(),
      'time': TimeOfDay.now().format(context),
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
        final error = jsonDecode(res.body)['error'] ?? res.body;
        setState(() => _isLoading = false);
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
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
    final userEmail = _userEmail;
    final isEditing = widget.transaction != null;
    final limitReached = !widget.useCoins &&
        !widget.isSubscribed &&
        (widget.dailyRemaining != null) &&
        (widget.dailyRemaining! <= 0) &&
        !isEditing;

    if (userEmail == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Error: User not logged in.'),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
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
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isEditing ? Icons.edit : Icons.add_circle_outline,
                    color: Colors.white,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEditing
                          ? 'Edit Quick Transaction'
                          : 'New Quick Transaction',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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
                            color: const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Daily quick transactions remaining: ${widget.dailyRemaining}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
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
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.orange.shade300),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Daily free limit is exhausted. This will spend 5 LenDen coins.',
                                  style: TextStyle(fontWeight: FontWeight.w600),
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
                            labelText: 'Currency',
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
                            labelText: 'Amount (${_currencySymbol()})',
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
                              return 'Please enter an amount';
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
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            prefixIcon:
                                Icon(Icons.description, color: AppColors.cyan),
                            border: InputBorder.none,
                          ),
                          maxLines: 2,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a description';
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
                          decoration: const InputDecoration(
                            labelText: 'Your Email',
                            prefixIcon:
                                Icon(Icons.person, color: Colors.grey),
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
                            labelText: 'Counterparty Email',
                            prefixIcon: Icon(Icons.person_outline,
                                color: isEditing
                                    ? Colors.grey
                                    : AppColors.cyan),
                            suffixIcon: IconButton(
                              icon: Icon(Icons.people,
                                  color: isEditing
                                      ? Colors.grey
                                      : AppColors.cyan),
                              onPressed: isEditing ? null : _pickFriend,
                            ),
                            border: InputBorder.none,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a counterparty email';
                            }
                            if (value == userEmail) {
                              return 'Counterparty cannot be the same as your email';
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
                          items: const [
                            DropdownMenuItem(
                              value: 'lender',
                              child: Text('Lending (You gave money)'),
                            ),
                            DropdownMenuItem(
                              value: 'borrower',
                              child: Text('Borrowing (You took money)'),
                            ),
                          ],
                          onChanged: (val) =>
                              setState(() => _role = val ?? 'lender'),
                          decoration: const InputDecoration(
                            labelText: 'Your Position',
                            prefixIcon:
                                Icon(Icons.people, color: AppColors.cyan),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),

            // Action buttons
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
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
                        'Cancel',
                        style:
                            TextStyle(color: Colors.grey[700], fontSize: 16),
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
                              isEditing ? 'Update' : 'Create',
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
