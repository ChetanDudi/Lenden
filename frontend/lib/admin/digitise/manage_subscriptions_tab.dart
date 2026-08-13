import 'package:flutter/material.dart';
import '../../utils/pickers.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import './widgets/subscription_dialogs.dart';
import '../../widgets/search_tab_bar.dart';

class ManageSubscriptionsTab extends StatefulWidget {
  @override
  _ManageSubscriptionsTabState createState() => _ManageSubscriptionsTabState();
}

class _ManageSubscriptionsTabState extends State<ManageSubscriptionsTab>
    with SingleTickerProviderStateMixin {
  late TabController _innerTabController;

  // Subscriptions tab
  List<dynamic> _subscriptions = [];
  bool _isLoading = false;
  String? _error;
  String _statusFilter = 'all';
  String _sortBy = 'newest';
  bool _showAll = false;
  final TextEditingController _searchController = TextEditingController();

  // History tab
  final TextEditingController _historySearchController = TextEditingController();
  List<dynamic> _historyResults = [];
  bool _historyLoading = false;
  String? _historyError;
  bool _historySearched = false;

  List<dynamic> get _filteredSubs {
    final now = DateTime.now();
    final q = _searchController.text.toLowerCase();
    var result = _subscriptions.where((s) {
      if (q.isNotEmpty) {
        final name = (s['user']?['name'] ?? '').toString().toLowerCase();
        final email = (s['user']?['email'] ?? '').toString().toLowerCase();
        final plan = (s['subscriptionPlan'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !email.contains(q) && !plan.contains(q)) {
          return false;
        }
      }
      if (_statusFilter == 'all') return true;
      final endDate = DateTime.tryParse((s['endDate'] ?? '').toString());
      if (_statusFilter == 'active') {
        return endDate != null && endDate.isAfter(now);
      }
      if (_statusFilter == 'expired') {
        return endDate == null || endDate.isBefore(now);
      }
      return true;
    }).toList();

    result.sort((a, b) {
      switch (_sortBy) {
        case 'oldest':
          return (a['createdAt'] ?? '')
              .toString()
              .compareTo((b['createdAt'] ?? '').toString());
        case 'ending_soon':
          final aEnd = DateTime.tryParse(a['endDate'] ?? '') ?? DateTime(9999);
          final bEnd = DateTime.tryParse(b['endDate'] ?? '') ?? DateTime(9999);
          return aEnd.compareTo(bEnd);
        case 'price_high':
          return ((b['price'] as num?) ?? 0)
              .compareTo((a['price'] as num?) ?? 0);
        default:
          return (b['createdAt'] ?? '')
              .toString()
              .compareTo((a['createdAt'] ?? '').toString());
      }
    });
    return result;
  }

  Widget _buildOverviewChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppColors.cyan,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _innerTabController = TabController(length: 2, vsync: this);
    _fetchSubscriptions();
  }

  @override
  void dispose() {
    _innerTabController.dispose();
    _searchController.dispose();
    _historySearchController.dispose();
    super.dispose();
  }

  Future<void> _searchUserHistory() async {
    final query = _historySearchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _historyLoading = true;
      _historyError = null;
      _historySearched = true;
    });
    try {
      final response = await ApiClient.get(
          '/api/admin/subscriptions?search=${Uri.encodeQueryComponent(query)}');
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _historyResults = List<dynamic>.from(json.decode(response.body) as List);
          _historyLoading = false;
        });
      } else {
        final body = response.body.isNotEmpty ? json.decode(response.body) : null;
        setState(() {
          _historyError = (body?['message'] ?? 'No results found').toString();
          _historyResults = [];
          _historyLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = 'Error: $e';
        _historyResults = [];
        _historyLoading = false;
      });
    }
  }

  String _fmtEventTime(DateTime dt) =>
      DateFormat('MMM d, yyyy h:mm a').format(dt.toLocal());

  Future<void> _fetchSubscriptions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.get('/api/admin/subscriptions');
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _subscriptions =
              List<dynamic>.from(json.decode(response.body) as List);
          _isLoading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        setState(() {
          _error = (body?['message'] ?? t('failed_to_load_subscriptions'))
              .toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context).t;
      setState(() {
        _error = t('unable_to_connect_check_internet_message');
        _isLoading = false;
      });
    }
  }

  void _showEditSubscriptionDialog(dynamic subscription) {
    showDialog(
      context: context,
      builder: (context) {
        return EditSubscriptionDialog(
            subscription: subscription, onSave: () => _fetchSubscriptions());
      },
    );
  }

  void _showGrantSubscriptionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return GrantSubscriptionDialog(onSave: () => _fetchSubscriptions());
      },
    );
  }

  Future<void> _reactivateSubscription(String subscriptionId, int remainingDays) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(dialogContext,
                  light: const Color(0xFFE8F5E9),
                  dark: const Color(0xFF1B3A26)),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.restart_alt_rounded, color: Colors.green, size: 50),
                const SizedBox(height: 16),
                Text(
                  t('reactivate_subscription_title'),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(dialogContext)),
                ),
                const SizedBox(height: 12),
                Text(
                  t('confirm_reactivate_subscription'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppThemeColors.secondaryText(dialogContext)),
                ),
                const SizedBox(height: 8),
                Text(
                  '$remainingDays ${remainingDays == 1 ? t('day_remaining_label') : t('days_remaining_label')} ${t('will_be_restored_label')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.green),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(t('cancel')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(t('reactivate_label'),
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final response = await ApiClient.put(
          '/api/admin/subscriptions/$subscriptionId/reactivate',
          body: {},
        );
        if (response.statusCode == 200) {
          _fetchSubscriptions();
          showSnack(context, t('subscription_reactivated_successfully'));
        } else {
          final body =
              response.body.isNotEmpty ? json.decode(response.body) : null;
          showSnack(context,
              body?['message'] ?? t('failed_to_reactivate_subscription'),
              isError: true);
        }
      } catch (e) {
        showSnack(context, '${t('an_error_occurred')}: $e', isError: true);
      }
    }
  }

  Future<void> _deactivateSubscription(String subscriptionId) async {
    final t = AppLocalizations.of(context).t;
    final reasonController = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(dialogContext,
                    light: const Color(0xFFFFEBEE),
                    dark: const Color(0xFF4A2326)),
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
                  const SizedBox(height: 16),
                  Text(
                    t('deactivate_subscription_title'),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(dialogContext)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t('confirm_deactivate_subscription'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: AppThemeColors.secondaryText(dialogContext)),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(dialogContext),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: TextField(
                        controller: reasonController,
                        maxLines: 2,
                        style: TextStyle(color: AppThemeColors.primaryText(dialogContext)),
                        decoration: InputDecoration(
                          hintText: t('deactivation_reason_hint'),
                          hintStyle: TextStyle(color: AppThemeColors.mutedText(dialogContext)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(null),
                        child: Text(t('cancel')),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(reasonController.text.trim()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(t('deactivate_label'),
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    reasonController.dispose();

    if (result != null) {
      try {
        final response = await ApiClient.put(
          '/api/admin/subscriptions/$subscriptionId/deactivate',
          body: {'reason': result},
        );
        if (response.statusCode == 200) {
          _fetchSubscriptions();
          showSnack(context, t('subscription_deactivated_successfully'));
        } else {
          final body =
              response.body.isNotEmpty ? json.decode(response.body) : null;
          showSnack(context,
              body?['message'] ?? t('failed_to_deactivate_subscription'),
              isError: true);
        }
      } catch (e) {
        showSnack(context, '${t('an_error_occurred')}: $e', isError: true);
      }
    }
  }

  void _showSortSheet() {
    final t = AppLocalizations.of(context).t;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(sheetContext),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppThemeColors.divider(sheetContext),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(t('sort_by'),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(sheetContext))),
              ),
            ),
            _buildSortTile(
                'newest', t('newest_first'), Icons.arrow_downward_rounded),
            _buildSortTile(
                'oldest', t('oldest_first'), Icons.arrow_upward_rounded),
            _buildSortTile('ending_soon', t('ending_soon_label'),
                Icons.hourglass_bottom_rounded),
            _buildSortTile('price_high', t('highest_price_label'),
                Icons.attach_money_rounded),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSortTile(String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    return ListTile(
      leading: Icon(icon,
          color: isSelected
              ? AppColors.cyan
              : AppThemeColors.secondaryText(context)),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? AppColors.cyan
              : AppThemeColors.secondaryText(context),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.cyan)
          : null,
      onTap: () {
        setState(() => _sortBy = value);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildStatusChip(String value, String label, Color color) {
    final selected = _statusFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : AppThemeColors.border(context)),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 6)]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color:
                selected ? Colors.white : AppThemeColors.secondaryText(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSubCard(dynamic sub, int index) {
    final t = AppLocalizations.of(context).t;
    final now = DateTime.now();
    final endDate = DateTime.tryParse((sub['endDate'] ?? '').toString());
    final adminDeactivated = sub['adminDeactivated'] == true;
    final deactivatedAt = sub['deactivatedAt'] != null
        ? DateTime.tryParse(sub['deactivatedAt'].toString())
        : null;
    // Days remaining = original endDate minus when it was paused (not minus now)
    final remainingDays = adminDeactivated && endDate != null && deactivatedAt != null
        ? endDate.difference(deactivatedAt).inDays.clamp(0, 99999)
        : null;
    final isExpired = !adminDeactivated && endDate != null && endDate.isBefore(now);
    final daysLeft = (!adminDeactivated && endDate != null)
        ? endDate.difference(now).inDays
        : null;
    final isFree = sub['free'] == true;
    final planName =
        (sub['subscriptionPlan'] ?? t('plan_fallback_label')).toString();
    final userName =
        (sub['user']?['name'] ?? t('unknown_user_label')).toString();
    final userEmail = (sub['user']?['email'] ?? '').toString();
    final price = (sub['price'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: adminDeactivated
              ? AppThemeColors.tinted(context,
                  light: const Color(0xFFFFF3E0), dark: const Color(0xFF3A2E1A))
              : isExpired
                  ? AppThemeColors.tinted(context,
                      light: const Color(0xFFFFF5F5), dark: const Color(0xFF3A2326))
                  : _getCardColor(context, index),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                  child: Text(
                    userName.isNotEmpty
                        ? userName.substring(0, 1).toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppThemeColors.primaryText(context)),
                      ),
                      if (userEmail.isNotEmpty)
                        Text(
                          userEmail,
                          style: TextStyle(
                              fontSize: 12,
                              color: AppThemeColors.secondaryText(context)),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isFree
                            ? Colors.green.withValues(alpha: 0.12)
                            : AppColors.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isFree
                            ? t('free_label')
                            : '₹${price.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isFree ? Colors.green : AppColors.cyan,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: adminDeactivated
                            ? Colors.orange.withValues(alpha: 0.12)
                            : isExpired
                                ? Colors.red.withValues(alpha: 0.12)
                                : Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        adminDeactivated
                            ? t('subscription_paused_label')
                            : isExpired
                                ? t('expired_label')
                                : t('active'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: adminDeactivated
                              ? Colors.orange
                              : isExpired
                                  ? Colors.red
                                  : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.card_membership_rounded,
                    size: 14, color: AppThemeColors.mutedText(context)),
                const SizedBox(width: 4),
                Text(
                  planName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColors.secondaryText(context),
                  ),
                ),
                const Spacer(),
                if (endDate != null) ...[
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 12,
                    color: isExpired
                        ? Colors.red[400]
                        : AppThemeColors.mutedText(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${t('ends_colon_label')}: ${DateFormat('MMM dd, yyyy').format(endDate.toLocal())}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isExpired
                          ? Colors.red[400]
                          : AppThemeColors.secondaryText(context),
                    ),
                  ),
                ],
              ],
            ),
            if (adminDeactivated && remainingDays != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.pause_circle_outline_rounded,
                      size: 12, color: Colors.orange[400]),
                  const SizedBox(width: 4),
                  Text(
                    '$remainingDays ${remainingDays == 1 ? t('day_remaining_label') : t('days_remaining_label')} paused',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ] else if (!isExpired && daysLeft != null && daysLeft <= 30) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.hourglass_bottom_rounded,
                      size: 12, color: Colors.orange[400]),
                  const SizedBox(width: 4),
                  Text(
                    '$daysLeft ${daysLeft == 1 ? t('day_remaining_label') : t('days_remaining_label')}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: Text(t('edit')),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.cyan,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _showEditSubscriptionDialog(sub),
                ),
                const SizedBox(width: 8),
                if (adminDeactivated)
                  TextButton.icon(
                    icon: const Icon(Icons.restart_alt_rounded, size: 14),
                    label: Text('${t('reactivate_label')} ($remainingDays ${t('days_remaining_label')})'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _reactivateSubscription(
                        sub['_id'].toString(), remainingDays ?? 0),
                  )
                else
                  TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 14),
                    label: Text(t('deactivate_label')),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () =>
                        _deactivateSubscription(sub['_id'].toString()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          AppTabBar(
            controller: _innerTabController,
            tabs: [
              AppTabItem(label: t('subscriptions_tab_label')),
              AppTabItem(label: t('subscription_history_tab_label')),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _innerTabController,
              children: [
                _buildSubscriptionsTab(context),
                _buildHistoryTab(context),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _innerTabController,
        builder: (_, __) => _innerTabController.index == 0
            ? Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.white, Colors.green],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                  ),
                  child: FloatingActionButton.extended(
                    onPressed: _showGrantSubscriptionDialog,
                    icon: const Icon(Icons.card_giftcard_rounded),
                    label: Text(t('grant_subscription_label')),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildSubscriptionsTab(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final filtered = _filteredSubs;
    final now = DateTime.now();
    final activeCount = _subscriptions.where((s) {
      final d = DateTime.tryParse((s['endDate'] ?? '').toString());
      return d != null && d.isAfter(now);
    }).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            children: [
              AppSearchBar(
                controller: _searchController,
                hintText: t('search_by_name_email_plan_placeholder'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              // Status chips + sort
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildStatusChip('all', t('all'), AppColors.cyan),
                          const SizedBox(width: 8),
                          _buildStatusChip('active', t('active'), Colors.green),
                          const SizedBox(width: 8),
                          _buildStatusChip('expired', t('expired_label'), Colors.red),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sort_rounded),
                    tooltip: t('sort_tooltip'),
                    onPressed: _showSortSheet,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Overview chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildOverviewChip(t('total_label'), '${_subscriptions.length}'),
                  _buildOverviewChip(t('active'), '$activeCount'),
                  _buildOverviewChip(
                    t('free_label'),
                    '${_subscriptions.where((s) => s['free'] == true).length}',
                  ),
                  _buildOverviewChip(
                    t('revenue_label'),
                    '₹${_subscriptions.fold<num>(0, (sum, s) => sum + ((s['price'] ?? 0) as num))}',
                  ),
                ],
              ),
              if (!_isLoading && _error == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${filtered.length} ${filtered.length == 1 ? t('subscription_count_label') : t('subscriptions_count_label')}',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppThemeColors.secondaryText(context)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? errorStateWidget(context, _error!, _fetchSubscriptions)
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.subscriptions_outlined,
                                  size: 64, color: AppThemeColors.mutedText(context)),
                              const SizedBox(height: 16),
                              Text(
                                _subscriptions.isEmpty
                                    ? t('no_subscriptions_found')
                                    : t('no_matching_subscriptions'),
                                style: TextStyle(
                                    fontSize: 17,
                                    color: AppThemeColors.mutedText(context)),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchSubscriptions,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 100),
                            itemCount: (_showAll
                                    ? filtered.length
                                    : math.min(3, filtered.length)) +
                                (filtered.length > 3 ? 1 : 0),
                            itemBuilder: (_, i) {
                              final itemsToShow = _showAll
                                  ? filtered.length
                                  : math.min(3, filtered.length);
                              if (i == itemsToShow) {
                                return Center(
                                  child: TextButton(
                                    onPressed: () =>
                                        setState(() => _showAll = !_showAll),
                                    child: Text(_showAll
                                        ? t('show_less_label')
                                        : '${t('view_all_label')} (${filtered.length})'),
                                  ),
                                );
                              }
                              return _buildSubCard(filtered[i], i);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
          child: AppSearchBar(
            controller: _historySearchController,
            hintText: t('search_user_history_hint'),
            onSubmit: _searchUserHistory,
          ),
        ),
        Expanded(
          child: _historyLoading
              ? const Center(child: CircularProgressIndicator())
              : _historyError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded,
                                size: 56, color: AppThemeColors.mutedText(context)),
                            const SizedBox(height: 12),
                            Text(
                              _historyError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppThemeColors.secondaryText(context),
                                  fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  : !_historySearched
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.manage_search_rounded,
                                    size: 72,
                                    color: AppThemeColors.divider(context)),
                                const SizedBox(height: 16),
                                Text(
                                  t('search_to_view_history_message'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: AppThemeColors.secondaryText(context)),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _historyResults.isEmpty
                          ? Center(
                              child: Text(
                                t('no_history_for_user_message'),
                                style: TextStyle(
                                    color: AppThemeColors.mutedText(context)),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: _historyResults.length + 1,
                              itemBuilder: (_, i) {
                                if (i == 0) {
                                  final user = _historyResults.first['user'];
                                  final name = (user?['name'] ?? '').toString();
                                  final email = (user?['email'] ?? '').toString();
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor:
                                              AppColors.cyan.withValues(alpha: 0.15),
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                                color: AppColors.cyan,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(name,
                                                  style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                      color: AppThemeColors
                                                          .primaryText(context))),
                                              if (email.isNotEmpty)
                                                Text(email,
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: AppThemeColors
                                                            .secondaryText(context))),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.cyan
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '${_historyResults.length} ${_historyResults.length == 1 ? t('subscription_count_label') : t('subscriptions_count_label')}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.cyan),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return _buildHistoryCard(_historyResults[i - 1]);
                              },
                            ),
        ),
      ],
    );
  }

  Widget _buildHistoryCard(dynamic sub) {
    final t = AppLocalizations.of(context).t;
    final now = DateTime.now();
    final endDate = DateTime.tryParse((sub['endDate'] ?? '').toString());
    final adminDeactivated = sub['adminDeactivated'] == true;
    final isActive = !adminDeactivated &&
        endDate != null &&
        sub['status'] == 'active' &&
        endDate.isAfter(now);
    final isExpired = !adminDeactivated && (endDate == null || endDate.isBefore(now));
    final planName = (sub['subscriptionPlan'] ?? t('plan_fallback_label')).toString();
    final price = (sub['price'] as num?)?.toDouble() ?? 0.0;
    final paymentMethod = (sub['paymentMethod'] ?? 'razorpay').toString();

    // Build admin events list (same merge logic as user side)
    final List<Map<String, dynamic>> adminEvents = () {
      final raw = sub['adminEvents'];
      final newEvents = (raw is List && raw.isNotEmpty)
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      if (newEvents.isEmpty) {
        final synth = <Map<String, dynamic>>[];
        if (sub['deactivatedAt'] != null) {
          synth.add({'type': 'deactivated', 'at': sub['deactivatedAt'],
              'reason': sub['deactivationReason']});
        }
        if (sub['reactivatedAt'] != null) {
          synth.add({'type': 'reactivated', 'at': sub['reactivatedAt'], 'reason': null});
        }
        synth.sort((a, b) =>
            (a['at']?.toString() ?? '').compareTo(b['at']?.toString() ?? ''));
        return synth;
      }
      final combined = List<Map<String, dynamic>>.from(newEvents);
      if (sub['reactivatedAt'] != null) {
        final oldReact = DateTime.tryParse(sub['reactivatedAt'].toString());
        final earliest = newEvents
            .map((e) => DateTime.tryParse(e['at']?.toString() ?? ''))
            .whereType<DateTime>()
            .fold<DateTime?>(null,
                (acc, dt) => acc == null || dt.isBefore(acc) ? dt : acc);
        if (oldReact != null && (earliest == null || oldReact.isBefore(earliest))) {
          combined.add({'type': 'reactivated', 'at': sub['reactivatedAt'], 'reason': null});
        }
      }
      combined.sort((a, b) =>
          (a['at']?.toString() ?? '').compareTo(b['at']?.toString() ?? ''));
      return combined;
    }();

    final statusColor = adminDeactivated
        ? Colors.orange
        : isActive
            ? Colors.green
            : Colors.red;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan name + status badge + price
            Row(
              children: [
                Expanded(
                  child: Text(planName,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppThemeColors.primaryText(context))),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    adminDeactivated
                        ? t('subscription_paused_label').toUpperCase()
                        : isActive
                            ? t('active_caps_label')
                            : t('expired_caps_label'),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Payment method + price + dates
            Row(
              children: [
                Icon(Icons.payment_rounded,
                    size: 12, color: AppThemeColors.mutedText(context)),
                const SizedBox(width: 4),
                Text(paymentMethod,
                    style: TextStyle(
                        fontSize: 11,
                        color: AppThemeColors.secondaryText(context))),
                if (price > 0) ...[
                  const SizedBox(width: 8),
                  Text('₹${price.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF8000))),
                ],
                const Spacer(),
                if (endDate != null)
                  Text(
                    '${isExpired ? t('expired_on_message').split(':')[0] : t('ends_colon_label')} ${DateFormat('MMM d, yyyy').format(endDate.toLocal())}',
                    style: TextStyle(
                        fontSize: 11,
                        color: isExpired
                            ? Colors.red[400]
                            : AppThemeColors.mutedText(context)),
                  ),
              ],
            ),
            // Admin events timeline — always visible in history view
            if (adminEvents.isNotEmpty || (adminDeactivated && adminEvents.isEmpty)) ...[
              const SizedBox(height: 8),
              Divider(
                  color: AppThemeColors.divider(context),
                  height: 1,
                  thickness: 0.7),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.history_rounded, size: 12, color: AppColors.cyan),
                  const SizedBox(width: 4),
                  Text(t('admin_history_events_label'),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.cyan)),
                ],
              ),
              const SizedBox(height: 5),
              if (adminEvents.isEmpty && adminDeactivated)
                Row(
                  children: [
                    Icon(Icons.pause_circle_outline_rounded,
                        size: 13, color: Colors.orange[600]),
                    const SizedBox(width: 5),
                    Text(t('subscription_paused_label'),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[700])),
                  ],
                ),
              ...adminEvents.asMap().entries.map((entry) {
                final idx = entry.key;
                final event = entry.value;
                final isPause = event['type'] == 'deactivated';
                final at = event['at'] != null
                    ? DateTime.tryParse(event['at'].toString())
                    : null;
                final evReason = event['reason']?.toString();
                return Padding(
                  padding: EdgeInsets.only(top: idx == 0 ? 0 : 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isPause
                            ? Icons.pause_circle_outline_rounded
                            : Icons.play_circle_outline_rounded,
                        size: 13,
                        color: isPause ? Colors.orange[600] : Colors.green[600],
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${t(isPause ? 'event_paused_on_label' : 'event_reactivated_on_label')}: ${at != null ? _fmtEventTime(at) : '—'}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isPause
                                      ? Colors.orange[700]
                                      : Colors.green[700]),
                            ),
                            if (isPause && evReason != null && evReason.isNotEmpty)
                              Text(
                                evReason,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.orange[600]),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Color _getCardColor(BuildContext context, int index) {
    final colors = AppThemeColors.isDark(context)
        ? [
            const Color(0xFF4A3F1F),
            const Color(0xFF1E3A26),
            const Color(0xFF3A2230),
            const Color(0xFF1B3A57),
            const Color(0xFF3A3420),
            const Color(0xFF332139),
          ]
        : [
            const Color(0xFFFFF4E6),
            const Color(0xFFE8F5E9),
            const Color(0xFFFCE4EC),
            const Color(0xFFE3F2FD),
            const Color(0xFFFFF9C4),
            const Color(0xFFF3E5F5),
          ];
    return colors[index % colors.length];
  }
}
