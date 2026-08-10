import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../utils/pickers.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';

class EditSubscriptionDialog extends StatefulWidget {
  final dynamic subscription;
  final VoidCallback onSave;

  const EditSubscriptionDialog({super.key, required this.subscription, required this.onSave});

  @override
  State<EditSubscriptionDialog> createState() => _EditSubscriptionDialogState();
}

class _EditSubscriptionDialogState extends State<EditSubscriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _subscriptionPlan;
  late int _duration;
  late double _price;
  late int _discount;
  late int _free;
  late DateTime _endDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _subscriptionPlan = widget.subscription['subscriptionPlan'];
    _duration = widget.subscription['duration'];
    _price = widget.subscription['price'].toDouble();
    _discount = widget.subscription['discount'];
    _free = widget.subscription['free'];
    _endDate = DateTime.parse(widget.subscription['endDate']);
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _endDate) {
      setState(() {
        _endDate = picked;
      });
    }
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
                    t('edit_subscription_title'),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context)),
                  ),
                  SizedBox(height: 20),
                  _buildStylishTextField(
                    label: t('subscription_plan_label'),
                    initialValue: _subscriptionPlan,
                    validator: (value) =>
                        value!.isEmpty ? t('please_enter_a_plan_name') : null,
                    onSaved: (value) => _subscriptionPlan = value!,
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
                    label: t('price_label'),
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
                  SizedBox(height: 16),
                  Text(t('end_date_label'),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context))),
                  SizedBox(height: 8),
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
                      child: ListTile(
                        title: Text(
                            '${_endDate.toLocal().toString().substring(0, 10)}',
                            style: TextStyle(
                                color: AppThemeColors.primaryText(context))),
                        trailing:
                            Icon(Icons.calendar_today, color: AppColors.cyan),
                        onTap: () => _selectEndDate(context),
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
                        onPressed: _isSaving ? null : _saveSubscription,
                        child: _isSaving
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(t('save')),
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

  void _saveSubscription() async {
    final t = AppLocalizations.of(context).t;
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() => _isSaving = true);
      try {
        final response = await ApiClient.put(
          '/api/admin/subscriptions/${widget.subscription['_id']}',
          body: {
            'subscriptionPlan': _subscriptionPlan,
            'duration': _duration,
            'price': _price,
            'discount': _discount,
            'free': _free,
            'endDate': _endDate.toIso8601String(),
          },
        );
        if (response.statusCode == 200) {
          widget.onSave();
          Navigator.of(context).pop();
          showSnack(context, t('subscription_updated_successfully'));
        } else {
          final body =
              response.body.isNotEmpty ? json.decode(response.body) : null;
          showSnack(
              context, body?['message'] ?? t('failed_to_update_subscription'),
              isError: true);
        }
      } catch (e) {
        showSnack(context, '${t('an_error_occurred')}: $e', isError: true);
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }
}

// Grants a brand-new subscription to a user (by email), unlike
// EditSubscriptionDialog which only edits a subscription that already exists.
// Useful for support/compensation cases — e.g. "give this user 7 free premium
// days" — for a user who has never subscribed before.
class GrantSubscriptionDialog extends StatefulWidget {
  final VoidCallback onSave;

  const GrantSubscriptionDialog({super.key, required this.onSave});

  @override
  State<GrantSubscriptionDialog> createState() => _GrantSubscriptionDialogState();
}

class _GrantSubscriptionDialogState extends State<GrantSubscriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _planNameController = TextEditingController();
  final _durationController = TextEditingController(text: '30');
  final _priceController = TextEditingController(text: '0');
  final _discountController = TextEditingController(text: '0');
  final _freeController = TextEditingController(text: '0');

  bool _isSaving = false;
  bool _isLoadingPlans = false;
  List<dynamic> _plans = [];
  String? _selectedPlanId;

  @override
  void initState() {
    super.initState();
    _fetchPlans();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _planNameController.dispose();
    _durationController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _freeController.dispose();
    super.dispose();
  }

  Future<void> _fetchPlans() async {
    setState(() => _isLoadingPlans = true);
    try {
      final response = await ApiClient.get('/api/admin/subscription-plans');
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _plans = List<dynamic>.from(json.decode(response.body) as List);
        });
      }
    } catch (_) {
      // Plan list is a convenience; the admin can still fill fields manually.
    } finally {
      if (mounted) setState(() => _isLoadingPlans = false);
    }
  }

  void _applyPlan(dynamic plan) {
    setState(() {
      _selectedPlanId = plan['_id']?.toString();
      _planNameController.text = (plan['name'] ?? '').toString();
      _durationController.text = '${(plan['duration'] as num?)?.toInt() ?? 30}';
      _priceController.text = '${(plan['price'] as num?)?.toDouble() ?? 0}';
      _discountController.text = '${(plan['discount'] as num?)?.toInt() ?? 0}';
      _freeController.text = '${(plan['free'] as num?)?.toInt() ?? 0}';
    });
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    FormFieldValidator<String>? validator,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextFormField(
          controller: controller,
          style: TextStyle(color: AppThemeColors.primaryText(context)),
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: AppThemeColors.cardBg(context),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          keyboardType: keyboardType,
          validator: validator,
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
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            color: AppThemeColors.tinted(context,
                light: const Color(0xFFE8F5E9), dark: const Color(0xFF1B3A26)),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('grant_subscription_label'),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('grant_subscription_subtitle'),
                    style: TextStyle(
                        fontSize: 12.5, color: AppThemeColors.secondaryText(context)),
                  ),
                  const SizedBox(height: 20),
                  _buildField(
                    label: t('user_email_label'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? t('please_enter_an_email') : null,
                  ),
                  if (_isLoadingPlans)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_plans.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppThemeColors.cardBg(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButtonFormField<String>(
                            value: _selectedPlanId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: t('select_existing_plan_optional_label'),
                              border: InputBorder.none,
                            ),
                            dropdownColor: AppThemeColors.cardBg(context),
                            items: _plans
                                .map((plan) => DropdownMenuItem<String>(
                                      value: plan['_id']?.toString(),
                                      child: Text(
                                        '${plan['name']} (₹${plan['price']})',
                                        style: TextStyle(color: AppThemeColors.primaryText(context)),
                                      ),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              final plan = _plans.firstWhere((p) => p['_id']?.toString() == value,
                                  orElse: () => null);
                              if (plan != null) _applyPlan(plan);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                  _buildField(
                    label: t('subscription_plan_label'),
                    controller: _planNameController,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? t('please_enter_a_plan_name') : null,
                  ),
                  _buildField(
                    label: t('duration_days_label'),
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed <= 0) return t('please_enter_a_valid_duration');
                      return null;
                    },
                  ),
                  _buildField(
                    label: t('price_label'),
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) return t('please_enter_a_valid_price');
                      return null;
                    },
                  ),
                  _buildField(
                    label: t('discount_percent_label'),
                    controller: _discountController,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed < 0 || parsed > 100) {
                        return t('please_enter_a_valid_discount');
                      }
                      return null;
                    },
                  ),
                  _buildField(
                    label: t('free_days_label'),
                    controller: _freeController,
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) return t('please_enter_a_valid_free_days');
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(t('cancel')),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _grantSubscription,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(t('grant_label'), style: const TextStyle(color: Colors.white)),
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

  Future<void> _grantSubscription() async {
    final t = AppLocalizations.of(context).t;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final response = await ApiClient.post(
        '/api/admin/subscriptions/grant',
        body: {
          'userEmail': _emailController.text.trim(),
          if (_selectedPlanId != null) 'planId': _selectedPlanId,
          'subscriptionPlan': _planNameController.text.trim(),
          'duration': int.parse(_durationController.text),
          'price': double.parse(_priceController.text),
          'discount': int.parse(_discountController.text),
          'free': int.parse(_freeController.text),
        },
      );
      if (response.statusCode == 201) {
        widget.onSave();
        if (mounted) Navigator.of(context).pop();
        if (mounted) showSnack(context, t('subscription_granted_successfully'));
      } else {
        final body = response.body.isNotEmpty ? json.decode(response.body) : null;
        if (mounted) {
          showSnack(context, body?['message'] ?? t('failed_to_grant_subscription'), isError: true);
        }
      }
    } catch (e) {
      if (mounted) showSnack(context, '${t('an_error_occurred')}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
