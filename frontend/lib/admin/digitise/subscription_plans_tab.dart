import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/subscription_feature_catalog.dart';
import 'subscription_models.dart';

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
                                  if (plan.allowedFeatures.isEmpty)
                                    Text(t('no_features_selected_message'),
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: AppThemeColors.mutedText(
                                                context)))
                                  else
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: kSubscriptionFeatures
                                          .where((f) => plan.allowedFeatures
                                              .contains(f.key))
                                          .map((f) => Chip(
                                                avatar: Icon(f.icon,
                                                    size: 14,
                                                    color: AppColors.cyan),
                                                label: Text(t(f.labelKey),
                                                    style: const TextStyle(
                                                        fontSize: 10)),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                padding: EdgeInsets.zero,
                                                backgroundColor:
                                                    AppColors.cyan
                                                        .withValues(alpha: 0.1),
                                              ))
                                          .toList(),
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

  void _showPlanDialog({SubscriptionPlan? plan}) {
    showDialog(
      context: context,
      builder: (context) {
        return PlanDialog(plan: plan, onSave: _fetchPlans);
      },
    );
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

class PlanDialog extends StatefulWidget {
  final SubscriptionPlan? plan;
  final VoidCallback onSave;

  PlanDialog({this.plan, required this.onSave});

  @override
  _PlanDialogState createState() => _PlanDialogState();
}

class _PlanDialogState extends State<PlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late double _price;
  late int _duration;
  late List<String> _features;
  late int _discount;
  late int _free;
  late Set<String> _allowedFeatures;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _name = widget.plan?.name ?? '';
    _price = widget.plan?.price ?? 0.0;
    _duration = widget.plan?.duration ?? 0;
    _features = widget.plan?.features ?? [];
    _discount = widget.plan?.discount ?? 0;
    _free = widget.plan?.free ?? 0;
    _allowedFeatures = Set<String>.from(widget.plan?.allowedFeatures ?? []);
  }

  Widget _buildStylishTextField({
    required String label,
    required String initialValue,
    required FormFieldValidator<String> validator,
    required FormFieldSetter<String> onSaved,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextFormField(
          initialValue: initialValue,
          style: TextStyle(color: AppThemeColors.primaryText(context)),
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: AppThemeColors.cardBg(context),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Dialog(
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
            color: AppThemeColors.tinted(context,
                light: const Color(0xFFFCE4EC), dark: const Color(0xFF3A2230)),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.plan == null
                        ? t('add_plan_title')
                        : t('edit_plan_title'),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context)),
                  ),
                  SizedBox(height: 20),
                  _buildStylishTextField(
                    label: t('plan_name_label'),
                    initialValue: _name,
                    validator: (value) =>
                        value!.isEmpty ? t('please_enter_a_name') : null,
                    onSaved: (value) => _name = value!,
                  ),
                  _buildStylishTextField(
                    label: t('price_rupees_label'),
                    initialValue: _price.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return t('please_enter_a_price');
                      final parsed = double.tryParse(value);
                      if (parsed == null || parsed <= 0)
                        return t('please_enter_a_valid_price');
                      return null;
                    },
                    onSaved: (value) => _price = double.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: t('duration_days_label'),
                    initialValue: _duration.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return t('please_enter_a_duration');
                      final parsed = int.tryParse(value);
                      if (parsed == null || parsed <= 0)
                        return t('please_enter_a_valid_duration');
                      return null;
                    },
                    onSaved: (value) => _duration = int.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: t('discount_percent_label'),
                    initialValue: _discount.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return t('please_enter_a_discount');
                      final parsed = int.tryParse(value);
                      if (parsed == null || parsed < 0 || parsed > 100)
                        return t('please_enter_a_valid_discount');
                      return null;
                    },
                    onSaved: (value) => _discount = int.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: t('free_days_label'),
                    initialValue: _free.toString(),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return t('please_enter_free_days');
                      final parsed = int.tryParse(value);
                      if (parsed == null || parsed < 0)
                        return t('please_enter_a_valid_free_days');
                      return null;
                    },
                    onSaved: (value) => _free = int.parse(value!),
                  ),
                  _buildStylishTextField(
                    label: t('features_comma_separated_label'),
                    initialValue: _features.join(', '),
                    maxLines: 3,
                    validator: (value) => null,
                    onSaved: (value) => _features = value!
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList(),
                  ),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t('select_plan_features_label'),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context)),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_allowedFeatures.length ==
                                kSubscriptionFeatures.length) {
                              _allowedFeatures.clear();
                            } else {
                              _allowedFeatures
                                  .addAll(kAllSubscriptionFeatureKeys);
                            }
                          });
                        },
                        child: Text(t('select_all_label')),
                      ),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: kSubscriptionFeatures.map((feature) {
                          final selected =
                              _allowedFeatures.contains(feature.key);
                          return CheckboxListTile(
                            dense: true,
                            value: selected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _allowedFeatures.add(feature.key);
                                } else {
                                  _allowedFeatures.remove(feature.key);
                                }
                              });
                            },
                            activeColor: AppColors.cyan,
                            secondary: Icon(feature.icon, color: AppColors.cyan),
                            title: Text(t(feature.labelKey),
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppThemeColors.primaryText(context))),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(t('cancel')),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _savePlan,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSaving
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(t('save'),
                                style: TextStyle(color: Colors.white)),
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
  }

  Future<void> _savePlan() async {
    final t = AppLocalizations.of(context).t;
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _isSaving = true;
      });
      try {
        final body = {
          'name': _name,
          'price': _price,
          'duration': _duration,
          'features': _features,
          'discount': _discount,
          'free': _free,
          'allowedFeatures': _allowedFeatures.toList(),
        };
        final response = widget.plan == null
            ? await ApiClient.post('/api/admin/subscription-plans', body: body)
            : await ApiClient.put(
                '/api/admin/subscription-plans/${widget.plan!.id}',
                body: body);

        if (response.statusCode == 201 || response.statusCode == 200) {
          widget.onSave();
          Navigator.of(context).pop();
          showStylishSnackBar(context, t('plan_saved_successfully'));
        } else {
          final respBody =
              response.body.isNotEmpty ? json.decode(response.body) : null;
          showStylishSnackBar(
              context, respBody?['message'] ?? t('failed_to_save_plan'),
              isError: true);
        }
      } catch (e) {
        showStylishSnackBar(context, '${t('an_error_occurred')}: $e',
            isError: true);
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }
}

