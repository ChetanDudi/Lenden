import 'package:flutter/material.dart';
import '../../utils/pickers.dart';
import 'dart:convert';
import 'user_edit_page.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/search_tab_bar.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class UserDetailsPage extends StatefulWidget {
  final Map<String, dynamic> user;

  const UserDetailsPage({super.key, required this.user});

  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  bool _showAllNotes = false;
  Map<String, dynamic>? _userStats;
  List<Map<String, dynamic>> _recentTransactions = [];
  List<Map<String, dynamic>> _userActivity = [];
  final TextEditingController _adminNoteController = TextEditingController();
  final TextEditingController _suspensionReasonController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadUserDetails();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _adminNoteController.dispose();
    _suspensionReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadUserDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response =
          await ApiClient.get('/api/admin/users/${widget.user['_id']}/details');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          if (data['user'] is Map) {
            widget.user.addAll(Map<String, dynamic>.from(data['user']));
          }
          _userStats = data['stats'];
          _recentTransactions =
              List<Map<String, dynamic>>.from(data['recentTransactions'] ?? []);
          _userActivity =
              List<Map<String, dynamic>>.from(data['userActivity'] ?? []);
        });
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, '${AppLocalizations.of(context).t('error_loading_user_details')}: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleUserStatus() async {
    final t = AppLocalizations.of(context).t;
    final currentStatus = widget.user['isActive'] ?? false;
    final action = currentStatus ? t('deactivate') : t('activate');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('$action ${t('user_label')}?',
            style: TextStyle(color: AppThemeColors.primaryText(ctx))),
        content: Text(
          currentStatus
              ? t('deactivate_user_confirm_message')
              : t('activate_user_confirm_message'),
          style: TextStyle(color: AppThemeColors.secondaryText(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('cancel'),
                style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: currentStatus ? Colors.deepOrange : Colors.green,
            ),
            child: Text(action, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await ApiClient.patch(
          '/api/admin/users/${widget.user['_id']}/status',
          body: {'isActive': !currentStatus});
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          widget.user['isActive'] = !currentStatus;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (data['message'] ?? (!currentStatus ? t('user_activated_successfully') : t('user_deactivated_successfully'))).toString(),
            ),
            backgroundColor: !currentStatus ? Colors.green : Colors.deepOrange,
          ),
        );
      } else {
        throw Exception((data['message'] ?? t('failed_to_update_status')).toString());
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final user = widget.user;
    final isActive = user['isActive'] ?? false;
    final isVerified = user['isVerified'] ?? false;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(
        context,
        title: user['name'] ?? t('user_details_title'),
        actions: [
          IconButton(
            icon: Icon(Icons.edit, color: AppThemeColors.primaryText(context)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserEditPage(user: user),
                ),
              ).then((_) => _loadUserDetails());
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // User Profile Header
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withValues(alpha: 0.1),
                        spreadRadius: 1,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Profile Image and Basic Info
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColors.cyan,
                            child: _buildProfileImage(user),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user['name'] ?? t('unknown_user'),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppThemeColors.primaryText(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user['email'] ?? t('no_email'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppThemeColors.secondaryText(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '@${user['username'] ?? t('unknown')}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.cyan,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Status Indicators
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isActive ? Colors.green : Colors.red,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isActive ? Icons.check_circle : Icons.block,
                                    color: isActive ? Colors.green : Colors.red,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isActive ? t('active') : t('inactive'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          isActive ? Colors.green : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              decoration: BoxDecoration(
                                color: isVerified
                                    ? Colors.blue.withValues(alpha: 0.1)
                                    : Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      isVerified ? Colors.blue : Colors.orange,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isVerified ? Icons.verified : Icons.pending,
                                    color: isVerified
                                        ? Colors.blue
                                        : Colors.orange,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isVerified ? t('verified') : t('pending'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isVerified
                                          ? Colors.blue
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _toggleUserStatus,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    isActive ? Colors.red : Colors.green,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                isActive ? t('deactivate') : t('activate'),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: isVerified
                                ? OutlinedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              UserEditPage(user: user),
                                        ),
                                      ).then((_) => _loadUserDetails());
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: AppColors.cyan),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      t('edit_user'),
                                      style:
                                          const TextStyle(color: AppColors.cyan),
                                    ),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: _reviewPendingUser,
                                    icon: const Icon(Icons.fact_check_rounded),
                                    label: Text(t('review_pending')),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                          ),
                          if (!isVerified) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          UserEditPage(user: user),
                                    ),
                                  ).then((_) => _loadUserDetails());
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: AppColors.cyan),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  t('edit_user'),
                                  style: const TextStyle(color: AppColors.cyan),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Tab Bar
                AppTabBar(
                  controller: _tabController,
                  tabs: [
                    AppTabItem(label: t('profile')),
                    AppTabItem(label: t('stats_tab_label')),
                    AppTabItem(label: t('transactions')),
                    AppTabItem(label: t('activity')),
                  ],
                ),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildProfileTab(),
                      _buildStatsTab(),
                      _buildTransactionsTab(),
                      _buildActivityTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildProfileTab() {
    final t = AppLocalizations.of(context).t;
    final user = widget.user;
    final adminNotes =
        List<Map<String, dynamic>>.from(user['adminNotes'] ?? const []);
    final suspendedUntil = DateTime.tryParse('${user['suspendedUntil'] ?? ''}');
    final isSuspended =
        suspendedUntil != null && suspendedUntil.isAfter(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildInfoSection(t('personal_information'), [
            _buildInfoTile(t('full_name'), user['name'] ?? t('not_available')),
            _buildInfoTile(t('username'), '@${user['username'] ?? t('unknown')}'),
            _buildInfoTile(t('email'), user['email'] ?? t('not_available')),
            _buildInfoTile(t('phone'), user['phone'] ?? t('not_available')),
            _buildInfoTile(t('gender'), user['gender'] ?? t('not_specified')),
            _buildInfoTile(
                t('birthday'), user['dateOfBirth'] ?? t('not_available')),
            _buildInfoTile(t('address'), user['address'] ?? t('not_available')),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection(t('account_information'), [
            _buildInfoTile(t('user_id_label'), user['_id'] ?? t('unknown')),
            _buildInfoTile(t('account_type_label'), user['role'] ?? t('user_label')),
            _buildInfoTile(t('joined_date_label'), _formatDate(user['createdAt'])),
            _buildInfoTile(
                t('last_activity_label'), _formatDate(_userStats?['lastActivity'])),
            _buildInfoTile(t('alternative_email'), user['altEmail'] ?? t('not_set')),
            _buildInfoTile(
              t('lenden_coins_label'),
              (_userStats?['lenDenCoins'] ?? user['lenDenCoins'] ?? 0)
                  .toString(),
            ),
            _buildInfoTile(
              t('subscriptions_label'),
              (_userStats?['activeSubscription'] is Map)
                  ? ((_userStats?['activeSubscription']['plan'] ??
                          t('active_plan_label'))
                      .toString())
                  : t('not_active'),
            ),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection(t('account_status'), [
            _buildInfoTile(t('account_status'),
                widget.user['isActive'] == true ? t('active') : t('inactive')),
            _buildInfoTile(t('email_verified_label'),
                widget.user['isVerified'] == true ? t('yes') : t('no')),
            _buildInfoTile(t('phone_verified_label'),
                widget.user['phoneVerified'] == true ? t('yes') : t('no')),
            _buildInfoTile(
                t('two_factor_auth_label'),
                widget.user['twoFactorEnabled'] == true
                    ? t('enabled')
                    : t('disabled')),
            _buildInfoTile(
              t('suspension_label'),
              isSuspended
                  ? '${t('until_label')} ${_formatDate(user['suspendedUntil'])}'
                  : t('not_suspended'),
            ),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection(t('admin_controls_label'), [
            TextField(
              controller: _suspensionReasonController,
              decoration: InputDecoration(
                labelText: t('suspension_reason_label'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _updateSuspension(clear: false),
                    icon: const Icon(Icons.lock_clock_outlined),
                    label: Text(t('suspend_label')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _updateSuspension(clear: true),
                    icon: const Icon(Icons.lock_open_rounded),
                    label: Text(t('clear')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _forceLogoutUser,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.logout_rounded),
                label: Text(
                  t('force_logout_user_label'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection(t('internal_admin_notes_label'), [
            TextField(
              controller: _adminNoteController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: t('add_internal_note'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _addAdminNote,
                icon: const Icon(Icons.note_add_outlined),
                label: Text(t('save_note_label')),
              ),
            ),
            if (adminNotes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t('no_notes_added_yet')),
              ),
            ...(_showAllNotes ? adminNotes : adminNotes.take(5)).map(
              (note) => Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppThemeColors.surfaceBg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (note['noteText'] ?? '').toString(),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppThemeColors.primaryText(context)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${t('by_label')} ${(note['admin'] is Map ? note['admin']['email'] : t('admin_label')) ?? t('admin_label')}',
                      style: TextStyle(
                        color: AppThemeColors.secondaryText(context),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatDate(note['createdAt']),
                      style: TextStyle(
                        color: AppThemeColors.secondaryText(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (adminNotes.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton.icon(
                    icon: Icon(
                      _showAllNotes ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: Text(
                      _showAllNotes
                          ? t('show_less_label')
                          : '${t('show_all')} (${adminNotes.length})',
                    ),
                    onPressed: () =>
                        setState(() => _showAllNotes = !_showAllNotes),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.cyan,
                    ),
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _buildStatsTab() {
    final t = AppLocalizations.of(context).t;
    if (_userStats == null) {
      return Center(
        child: Text(t('no_statistics_available'),
            style: TextStyle(color: AppThemeColors.primaryText(context))),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Summary Cards
          Row(
            children: [
              Expanded(
                  child: _buildStatCard(
                      t('total_transactions_label'),
                      _userStats!['totalTransactions']?.toString() ?? '0',
                      Icons.receipt)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildStatCard(
                      t('total_amount_label'),
                      '\$${_userStats!['totalAmount']?.toString() ?? '0'}',
                      Icons.attach_money)),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                  child: _buildStatCard(
                      t('secure_transactions_short_label'),
                      _userStats!['secureTransactions']?.toString() ?? '0',
                      Icons.shield_outlined)),
              const SizedBox(width: 12),
              Expanded(
                  child: _buildStatCard(
                      t('quick_transactions_short_label'),
                      _userStats!['quickTransactions']?.toString() ?? '0',
                      Icons.flash_on_rounded)),
            ],
          ),

          const SizedBox(height: 16),

          // Detailed Stats
          _buildInfoSection(t('transaction_statistics_label'), [
            _buildInfoTile(t('successful_transactions_label'),
                _userStats!['successfulTransactions']?.toString() ?? '0'),
            _buildInfoTile(t('pending_uncleared_label'),
                _userStats!['pendingTransactions']?.toString() ?? '0'),
            _buildInfoTile(t('average_transaction_label'),
                _formatCurrency(_userStats!['averageTransaction'])),
            _buildInfoTile(t('largest_transaction_label'),
                _formatCurrency(_userStats!['largestTransaction'])),
          ]),

          const SizedBox(height: 16),

          _buildInfoSection(t('activity_statistics_label'), [
            _buildInfoTile(
                t('groups_joined_label'), _userStats!['totalGroups']?.toString() ?? '0'),
            _buildInfoTile(t('groups_created_label'),
                _userStats!['groupsCreated']?.toString() ?? '0'),
            _buildInfoTile(
                t('friends_label'), _userStats!['totalFriends']?.toString() ?? '0'),
            _buildInfoTile(
                t('days_active_label'), _userStats!['daysActive']?.toString() ?? '0'),
            _buildInfoTile(
                t('last_activity_label'), _formatDate(_userStats!['lastActivity'])),
            _buildInfoTile(
                t('login_count_label'), _userStats!['loginCount']?.toString() ?? '0'),
          ]),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    final t = AppLocalizations.of(context).t;
    return _recentTransactions.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  t('no_transactions_found'),
                  style: TextStyle(fontSize: 18, color: AppThemeColors.secondaryText(context)),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _recentTransactions.length,
            itemBuilder: (context, index) {
              final transaction = _recentTransactions[index];
              return _buildTransactionCard(transaction);
            },
          );
  }

  Widget _buildActivityTab() {
    final t = AppLocalizations.of(context).t;
    return _userActivity.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  t('no_activity_found'),
                  style: TextStyle(fontSize: 18, color: AppThemeColors.secondaryText(context)),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _userActivity.length,
            itemBuilder: (context, index) {
              final activity = _userActivity[index];
              return _buildActivityCard(activity);
            },
          );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.cyan,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: AppThemeColors.secondaryText(context),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppThemeColors.primaryText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.cyan, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context),
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: AppThemeColors.secondaryText(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final t = AppLocalizations.of(context).t;
    final amount = transaction['amount'];
    final date = transaction['createdAt'] ?? transaction['date'];
    final status = (transaction['status'] ?? 'unknown').toString();
    final source = (transaction['source'] ?? 'secure').toString();
    final counterpart = (transaction['counterpart'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.receipt,
              color: AppColors.cyan,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source == 'quick'
                      ? t('quick_transaction_label')
                      : t('secure_transaction_label'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${t('amount_colon_label')} ${_formatCurrency(amount, transaction['currency'])}',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                if (counterpart.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${t('counterpart_colon_label')} $counterpart',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${t('date_colon_label')} ${_formatDate(date)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppThemeColors.secondaryText(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${t('status_colon_label')} ${status.replaceAll('_', ' ').capitalize()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(status),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    final t = AppLocalizations.of(context).t;
    if (date == null) return t('not_available');
    try {
      final dateTime = DateTime.parse(date.toString()).toLocal();
      final twoDigits = (int n) => n.toString().padLeft(2, '0');
      return '${twoDigits(dateTime.day)}/${twoDigits(dateTime.month)}/${dateTime.year} ${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
    } catch (e) {
      return date.toString();
    }
  }

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    final t = AppLocalizations.of(context).t;
    final action = (activity['action'] ?? 'activity').toString();
    final timestamp = activity['timestamp'];
    final when = _formatDate(timestamp);
    final title = (activity['title'] ?? _getActivityTitle(action, t)).toString();
    final description = (activity['description'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getActivityIcon(action),
              color: AppColors.cyan,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context))),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
                ),
              ],
              const SizedBox(height: 4),
              Text(when,
                  style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
            ]),
          ),
        ],
      ),
    );
  }

  IconData _getActivityIcon(String action) {
    switch (action) {
      case 'user_registration':
        return Icons.person_add;
      case 'user_login':
        return Icons.login;
      case 'user_logout':
        return Icons.logout;
      case 'profile_update':
        return Icons.edit;
      case 'password_change':
        return Icons.lock;
      default:
        return Icons.info;
    }
  }

  String _getActivityTitle(String action, String Function(String) t) {
    switch (action) {
      case 'user_registration':
        return t('new_user_registered_label');
      case 'user_login':
        return t('user_logged_in_label');
      case 'user_logout':
        return t('user_logged_out_label');
      case 'profile_update':
        return t('profile_updated_label');
      case 'password_change':
        return t('password_changed_label');
      default:
        return t('activity_logged_label');
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'successful':
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'partially_paid':
        return Colors.deepOrange;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<void> _addAdminNote() async {
    final text = _adminNoteController.text.trim();
    if (text.isEmpty) return;

    try {
      final response = await ApiClient.post(
        '/api/admin/users/${widget.user['_id']}/notes',
        body: {'noteText': text},
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          final notes = List<Map<String, dynamic>>.from(
            widget.user['adminNotes'] ?? const [],
          );
          notes.insert(0, Map<String, dynamic>.from(data['note']));
          widget.user['adminNotes'] = notes;
        });
        _adminNoteController.clear();
        if (!mounted) return;
        showSnack(context, AppLocalizations.of(context).t('internal_note_added_successfully'));
      } else {
        throw Exception((data['message'] ?? AppLocalizations.of(context).t('failed_to_add_note')).toString());
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _updateSuspension({required bool clear}) async {
    try {
      DateTime? selectedUntil;
      if (!clear) {
        final pickedDate = await showAppDatePicker(
          context: context,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          initialDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (pickedDate == null) return;
        final pickedTime = await showAppTimePicker(
          context: context,
          initialTime: TimeOfDay.now(),
        );
        if (pickedTime == null) return;
        selectedUntil = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
      }

      final response = await ApiClient.patch(
        '/api/admin/users/${widget.user['_id']}/suspension',
        body: clear
            ? {'clearSuspension': true}
            : {
                'suspendedUntil': selectedUntil?.toIso8601String(),
                'suspensionReason': _suspensionReasonController.text.trim(),
              },
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          widget.user.addAll(Map<String, dynamic>.from(data['user']));
        });
        _suspensionReasonController.clear();
        if (!mounted) return;
        showSnack(context, (data['message'] ?? AppLocalizations.of(context).t('suspension_updated_message')).toString());
      } else {
        throw Exception((data['message'] ?? AppLocalizations.of(context).t('failed_to_update_suspension')).toString());
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _forceLogoutUser() async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(t('force_logout_user_title'), style: TextStyle(color: AppThemeColors.primaryText(ctx))),
        content: Text(
          t('force_logout_user_all_devices_desc'),
          style: TextStyle(color: AppThemeColors.secondaryText(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('cancel'), style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.logout_rounded),
            label: Text(t('force_logout_label')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await ApiClient.post(
        '/api/admin/users/${widget.user['_id']}/force-logout',
        body: const {},
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        if (data['user'] is Map) {
          setState(() {
            widget.user.addAll(Map<String, dynamic>.from(data['user']));
          });
        }
        if (!mounted) return;
        showSnack(context, (data['message'] ?? t('user_logged_out_all_devices_message')).toString(), isError: true);
      } else {
        throw Exception((data['message'] ?? t('failed_to_force_logout_short')).toString());
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _reviewPendingUser() async {
    try {
      final response = await ApiClient.patch(
        '/api/admin/users/${widget.user['_id']}/review-pending',
        body: const {},
      );
      final data = json.decode(response.body);
      final t = AppLocalizations.of(context).t;

      if (response.statusCode == 200) {
        setState(() {
          widget.user['isVerified'] = true;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.transparent,
            elevation: 0,
            content: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: Colors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (data['message'] ?? t('pending_user_marked_verified'))
                          .toString(),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppThemeColors.primaryText(context)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        throw Exception(
          (data['message'] ?? t('failed_to_review_pending_user')).toString(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  String _formatCurrency(dynamic value, [dynamic currency]) {
    final amount = (value is num) ? value.toDouble() : double.tryParse('$value');
    if (amount == null) {
      return currency == null || '$currency'.isEmpty ? '$value' : '$currency $value';
    }
    final code = (currency ?? '').toString().trim();
    final formatted = amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2);
    return code.isEmpty ? '\$$formatted' : '$formatted $code';
  }

  Widget _buildProfileImage(Map<String, dynamic> user) {
    final imageUrl = user['profileImage'] ?? '';

    if (imageUrl.isEmpty) {
      return const Icon(
        Icons.person,
        size: 40,
        color: Colors.white,
      );
    }

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.error,
            size: 40,
            color: Colors.red,
          );
        },
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
}
