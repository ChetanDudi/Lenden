import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/subscription_feature_catalog.dart';
import '../widgets/top_wave_clipper.dart';
import 'subscription_models.dart';

class AddEditSubscriptionPlanPage extends StatefulWidget {
  final SubscriptionPlan? plan;

  const AddEditSubscriptionPlanPage({super.key, this.plan});

  @override
  State<AddEditSubscriptionPlanPage> createState() =>
      _AddEditSubscriptionPlanPageState();
}

class _AddEditSubscriptionPlanPageState
    extends State<AddEditSubscriptionPlanPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers hold text independently of rebuilds.
  // Using controllers (not initialValue) so setState from checkbox toggles
  // never resets what the user typed.
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _discountCtrl;
  late final TextEditingController _freeCtrl;
  late final TextEditingController _featuresCtrl;

  late Set<String> _allowedFeatures;
  bool _isSaving = false;
  String? _featuresError;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _priceCtrl = TextEditingController(
        text: p != null ? p.price.toString() : '');
    _durationCtrl = TextEditingController(
        text: p != null ? p.duration.toString() : '');
    _discountCtrl = TextEditingController(
        text: p != null ? p.discount.toString() : '0');
    _freeCtrl = TextEditingController(
        text: p != null ? p.free.toString() : '0');
    _featuresCtrl = TextEditingController(
        text: p?.features.join(', ') ?? '');
    _allowedFeatures = Set<String>.from(p?.allowedFeatures ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _durationCtrl.dispose();
    _discountCtrl.dispose();
    _freeCtrl.dispose();
    _featuresCtrl.dispose();
    super.dispose();
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required FormFieldValidator<String> validator,
    TextInputType? keyboardType,
    int maxLines = 1,
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
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: AppThemeColors.cardBg(context),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
        ),
      ),
    );
  }

  Future<void> _savePlan() async {
    final t = AppLocalizations.of(context).t;
    if (_allowedFeatures.isEmpty) {
      setState(() => _featuresError =
          'Select at least one feature — a plan with no features is useless.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // Read values directly from controllers — no onSaved needed.
    final name = _nameCtrl.text.trim();
    final price = double.parse(_priceCtrl.text.trim());
    final duration = int.parse(_durationCtrl.text.trim());
    final discount = int.tryParse(_discountCtrl.text.trim()) ?? 0;
    final free = int.tryParse(_freeCtrl.text.trim()) ?? 0;
    final features = _featuresCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    setState(() => _isSaving = true);
    try {
      final body = {
        'name': name,
        'price': price,
        'duration': duration,
        'features': features,
        'discount': discount,
        'free': free,
        'allowedFeatures': _allowedFeatures.toList(),
      };
      final response = widget.plan == null
          ? await ApiClient.post('/api/admin/subscription-plans', body: body)
          : await ApiClient.put(
              '/api/admin/subscription-plans/${widget.plan!.id}',
              body: body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (!mounted) return;
        showStylishSnackBar(context, t('plan_saved_successfully'));
        Navigator.of(context).pop(true);
      } else {
        final respBody =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        if (mounted) {
          showStylishSnackBar(
              context, respBody?['message'] ?? t('failed_to_save_plan'),
              isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        showStylishSnackBar(context, '${t('an_error_occurred')}: $e',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final isEdit = widget.plan != null;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            isEdit
                                ? t('edit_plan_title')
                                : t('add_plan_title'),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                // Form body
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        _field(
                          label: t('plan_name_label'),
                          controller: _nameCtrl,
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? t('please_enter_a_name')
                                  : null,
                        ),
                        _field(
                          label: t('price_rupees_label'),
                          controller: _priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return t('please_enter_a_price');
                            final p = double.tryParse(v.trim());
                            if (p == null || p <= 0)
                              return t('please_enter_a_valid_price');
                            return null;
                          },
                        ),
                        _field(
                          label: t('duration_days_label'),
                          controller: _durationCtrl,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return t('please_enter_a_duration');
                            final p = int.tryParse(v.trim());
                            if (p == null || p <= 0)
                              return t('please_enter_a_valid_duration');
                            return null;
                          },
                        ),
                        _field(
                          label: t('discount_percent_label'),
                          controller: _discountCtrl,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return t('please_enter_a_discount');
                            final p = int.tryParse(v.trim());
                            if (p == null || p < 0 || p > 100)
                              return t('please_enter_a_valid_discount');
                            return null;
                          },
                        ),
                        _field(
                          label: t('free_days_label'),
                          controller: _freeCtrl,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return t('please_enter_free_days');
                            final p = int.tryParse(v.trim());
                            if (p == null || p < 0)
                              return t('please_enter_a_valid_free_days');
                            return null;
                          },
                        ),
                        _field(
                          label: t('features_comma_separated_label'),
                          controller: _featuresCtrl,
                          maxLines: 3,
                          validator: (_) => null,
                        ),
                        const SizedBox(height: 4),
                        // Feature selection header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              t('select_plan_features_label'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  if (_allowedFeatures.length ==
                                      kSubscriptionFeatures.length) {
                                    _allowedFeatures.clear();
                                  } else {
                                    _allowedFeatures
                                        .addAll(kAllSubscriptionFeatureKeys);
                                  }
                                  _featuresError = null;
                                });
                              },
                              icon: Icon(
                                _allowedFeatures.length ==
                                        kSubscriptionFeatures.length
                                    ? Icons.deselect_rounded
                                    : Icons.select_all_rounded,
                                size: 16,
                                color: AppColors.cyan,
                              ),
                              label: Text(
                                _allowedFeatures.length ==
                                        kSubscriptionFeatures.length
                                    ? 'Deselect All'
                                    : 'Select All',
                                style:
                                    const TextStyle(color: AppColors.cyan),
                              ),
                            ),
                          ],
                        ),
                        // Feature checkboxes
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
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
                                      if (_allowedFeatures.isNotEmpty) {
                                        _featuresError = null;
                                      }
                                    });
                                  },
                                  activeColor: AppColors.cyan,
                                  secondary: Icon(feature.icon,
                                      color: AppColors.cyan),
                                  title: Text(
                                    t(feature.labelKey),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          AppThemeColors.primaryText(context),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        if (_featuresError != null) ...[
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.error_outline,
                                size: 14, color: Colors.red),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(_featuresError!,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.red)),
                            ),
                          ]),
                        ],
                        const SizedBox(height: 24),
                        // Save button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _savePlan,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(
                                    t('save'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
