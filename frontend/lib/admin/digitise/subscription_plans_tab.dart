import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/subscription_feature_catalog.dart';
import 'subscription_models.dart';
import 'add_edit_subscription_plan_page.dart';

// Subscription Plans Tab
class SubscriptionPlansTab extends StatefulWidget {
  @override
  _SubscriptionPlansTabState createState() => _SubscriptionPlansTabState();
}

class _SubscriptionPlansTabState extends State<SubscriptionPlansTab> {
  List<SubscriptionPlan> _plans = [];
  Map<String, bool> _isToggling = {};
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPlans();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SubscriptionPlan> _getFilteredPlans() {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _plans;
    final t = AppLocalizations.of(context).t;
    return _plans.where((plan) {
      final haystack = <String>[
        plan.name,
        plan.price.toStringAsFixed(2),
        '${plan.duration}',
        '${plan.discount}',
        '${plan.free}',
        plan.isAvailable
            ? t('available_label')
            : t('unavailable_label'),
        ...plan.features,
        ...kSubscriptionFeatures
            .where((f) => plan.allowedFeatures.contains(f.key))
            .map((f) => t(f.labelKey)),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
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

  Future<void> _fetchPlans() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.get('/api/admin/subscription-plans');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _plans = data.map((item) => SubscriptionPlan.fromJson(item)).toList();
          _isLoading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        setState(() {
          _error = (body?['message'] ?? t('failed_to_load_plans_message'))
              .toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context).t;
      setState(() {
        _error = '${t('error_prefix')} $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePlanAvailability(
      SubscriptionPlan plan, bool isAvailable) async {
    final t = AppLocalizations.of(context).t;
    setState(() {
      _isToggling[plan.id] = true;
    });

    try {
      final response = await ApiClient.put(
          '/api/admin/subscription-plans/${plan.id}',
          body: {
            'name': plan.name,
            'price': plan.price,
            'duration': plan.duration,
            'features': plan.features,
            'isAvailable': isAvailable,
          });

      if (response.statusCode == 200) {
        _fetchPlans();
        showSnack(context, t('plan_availability_updated_successfully'));
      } else {
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        showStylishSnackBar(context,
            body?['message'] ?? t('failed_to_update_plan_availability_message'),
            isError: true);
      }
    } catch (e) {
      showStylishSnackBar(context, '${t('an_error_occurred')}: $e',
          isError: true);
    } finally {
      if (mounted)
        setState(() {
          _isToggling[plan.id] = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.red[300]),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _fetchPlans,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(t('retry')),
                      ),
                    ],
                  ),
                )
              : _plans.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox,
                              size: 80,
                              color: AppThemeColors.mutedText(context)),
                          SizedBox(height: 16),
                          Text(
                            t('nothing_here'),
                            style: TextStyle(
                                fontSize: 20,
                                color: AppThemeColors.secondaryText(context),
                                fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            t('add_first_subscription_plan'),
                            style: TextStyle(
                                fontSize: 14,
                                color: AppThemeColors.mutedText(context)),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [Colors.orange, Colors.white, Colors.green],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: AppThemeColors.cardBg(context),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: TextField(
                                controller: _searchController,
                                style: TextStyle(
                                    color: AppThemeColors.primaryText(context)),
                                decoration: InputDecoration(
                                  hintText: t('search_plans_hint'),
                                  border: InputBorder.none,
                                  icon: Icon(Icons.search, color: AppColors.cyan),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            setState(() {
                                              _searchController.clear();
                                              _searchQuery = '';
                                            });
                                          },
                                        )
                                      : null,
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Builder(builder: (context) {
                            final filteredPlans = _getFilteredPlans();
                            if (filteredPlans.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.search_off,
                                        size: 64,
                                        color: AppThemeColors.mutedText(context)),
                                    SizedBox(height: 12),
                                    Text(
                                      t('no_plans_match_search_message'),
                                      style: TextStyle(
                                          fontSize: 15,
                                          color:
                                              AppThemeColors.secondaryText(context)),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return ListView.builder(
                              padding: EdgeInsets.all(16),
                              itemCount: filteredPlans.length,
                              itemBuilder: (context, index) {
                                final plan = filteredPlans[index];
                                return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange,
                                Colors.white,
                                Colors.green
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _getCardColor(context, index),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              plan.name,
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppThemeColors
                                                      .primaryText(context)),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              '₹${plan.price} ${t('for_label')} ${plan.duration} ${t('days_label')}',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color: AppThemeColors
                                                      .secondaryText(context)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _isToggling[plan.id] ?? false
                                          ? SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            )
                                          : Switch(
                                              value: plan.isAvailable,
                                              onChanged: (value) {
                                                _togglePlanAvailability(
                                                    plan, value);
                                              },
                                              activeColor: Colors.green,
                                            ),
                                    ],
                                  ),
                                  SizedBox(height: 10),
                                  GestureDetector(
                                    onTap: () => _showFeaturesSheet(context, plan, t),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.cyan.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
                                      ),
                                      child: Row(children: [
                                        Icon(Icons.apps_rounded, size: 16, color: AppColors.cyan),
                                        const SizedBox(width: 8),
                                        Text(
                                          plan.allowedFeatures.isEmpty
                                              ? t('no_features_selected_message')
                                              : '${plan.allowedFeatures.length} ${plan.allowedFeatures.length == 1 ? 'feature' : 'features'} included',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: plan.allowedFeatures.isEmpty
                                                ? AppThemeColors.mutedText(context)
                                                : AppColors.cyan,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (plan.allowedFeatures.isNotEmpty)
                                          Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.cyan),
                                      ]),
                                    ),
                                  ),
                                  SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit,
                                            color: AppColors.cyan),
                                        onPressed: () =>
                                            _showPlanDialog(plan: plan),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () => _deletePlan(plan.id),
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
                          }),
                        ),
                      ],
                    ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cyan,
            borderRadius: BorderRadius.circular(28),
          ),
          child: FloatingActionButton.extended(
            onPressed: () => _showPlanDialog(),
            icon: Icon(Icons.add),
            label: Text(t('add_plan_title')),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
      ),
    );
  }

  static const _featureColors = {
    'quick_transactions':  Color(0xFFFFA000),
    'secure_transactions': Color(0xFF00897B),
    'group_creation':      Color(0xFF1E88E5),
    'group_expenses':      Color(0xFFE53935),
    'private_chat':        Color(0xFF8E24AA),
    'group_chat':          Color(0xFF3949AB),
    'discover':            Color(0xFF00ACC1),
    'view_rankings':       Color(0xFF43A047),
    'reports':             Color(0xFFD81B60),
    'budget_planning':     Color(0xFF6D4C41),
    'smart_insights':      Color(0xFF5E35B1),
  };

  void _showFeaturesSheet(BuildContext context, SubscriptionPlan plan, String Function(String) t) {
    final included = kSubscriptionFeatures
        .where((f) => plan.allowedFeatures.contains(f.key))
        .toList();
    final excluded = kSubscriptionFeatures
        .where((f) => !plan.allowedFeatures.contains(f.key))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                decoration: BoxDecoration(
                  color: AppThemeColors.divider(ctx),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(children: [
                  Icon(Icons.apps_rounded, size: 20, color: AppColors.cyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      plan.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(ctx),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${included.length} / ${kSubscriptionFeatures.length}',
                      style: const TextStyle(fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.bold),
                    ),
                  ),
                ]),
              ),
              const Divider(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (included.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 12),
                          child: Text(
                            'Included in this plan',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppThemeColors.secondaryText(ctx),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        GridView.count(
                          crossAxisCount: 4,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 14,
                          children: included.map((f) => _featureTile(ctx, f, t, enabled: true)).toList(),
                        ),
                      ],
                      if (excluded.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 20, bottom: 12),
                          child: Text(
                            'Not included',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppThemeColors.mutedText(ctx),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        GridView.count(
                          crossAxisCount: 4,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 14,
                          children: excluded.map((f) => _featureTile(ctx, f, t, enabled: false)).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _featureTile(BuildContext ctx, SubscriptionFeature f, String Function(String) t, {required bool enabled}) {
    final color = _featureColors[f.key] ?? AppColors.cyan;
    final isDark = AppThemeColors.isDark(ctx);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: enabled
                ? color
                : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE)),
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled
                ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))]
                : [],
          ),
          child: Icon(
            f.icon,
            size: 26,
            color: enabled ? Colors.white : AppThemeColors.mutedText(ctx),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          t(f.labelKey).split(' ').take(2).join('\n'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.5,
            height: 1.25,
            fontWeight: enabled ? FontWeight.w600 : FontWeight.normal,
            color: enabled ? AppThemeColors.primaryText(ctx) : AppThemeColors.mutedText(ctx),
          ),
        ),
      ],
    );
  }

  void _showPlanDialog({SubscriptionPlan? plan}) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => AddEditSubscriptionPlanPage(plan: plan),
        ))
        .then((result) {
      if (result == true) _fetchPlans();
    });
  }

  Future<void> _deletePlan(String id) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.all(2),
          child: Container(
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(dialogContext,
                  light: const Color(0xFFFFEBEE),
                  dark: const Color(0xFF4A2326)),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 50),
                SizedBox(height: 16),
                Text(
                  t('delete_plan_title'),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(dialogContext)),
                ),
                SizedBox(height: 12),
                Text(
                  t('confirm_delete_plan'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppThemeColors.secondaryText(dialogContext)),
                ),
                SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(t('cancel')),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(t('delete'),
                          style: TextStyle(color: Colors.white)),
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
      final response =
          await ApiClient.delete('/api/admin/subscription-plans/$id');
      if (response.statusCode == 200) {
        _fetchPlans();
        showStylishSnackBar(context, t('plan_deleted_successfully'));
      } else {
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        showStylishSnackBar(
            context, body?['message'] ?? t('failed_to_delete_plan'),
            isError: true);
      }
    }
  }
}


