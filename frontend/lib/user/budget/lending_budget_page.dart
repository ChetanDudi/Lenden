import 'package:flutter/material.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';

class LendingBudgetPage extends StatefulWidget {
  const LendingBudgetPage({super.key});

  @override
  State<LendingBudgetPage> createState() => _LendingBudgetPageState();
}

class _LendingBudgetPageState extends State<LendingBudgetPage> {
  String t(String key) => AppLocalizations.of(context).t(key);
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _budget;
  final TextEditingController _limitController = TextEditingController();
  double _alertThreshold = 80;

  @override
  void initState() {
    super.initState();
    _fetchBudget();
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _fetchBudget() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get('/api/lending-budget');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _budget = data;
          _limitController.text = data['monthlyLimit'] != null
              ? data['monthlyLimit'].toString()
              : '';
          _alertThreshold = (data['alertThresholdPercent'] ?? 80).toDouble();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveBudget() async {
    setState(() => _saving = true);
    try {
      final text = _limitController.text.trim();
      final monthlyLimit = text.isEmpty ? null : double.tryParse(text);
      if (text.isNotEmpty && monthlyLimit == null) {
        showSnack(context, 'Enter a valid number for the monthly limit.', isError: true);
        setState(() => _saving = false);
        return;
      }
      final res = await ApiClient.put('/api/lending-budget', body: {
        'monthlyLimit': monthlyLimit,
        'alertThresholdPercent': _alertThreshold.round(),
      });
      if (res.statusCode == 200) {
        showSnack(context, 'Lending budget updated.');
        _fetchBudget();
      } else {
        showSnack(context, 'Failed to update lending budget.', isError: true);
      }
    } catch (e) {
      showSnack(context, 'Error: $e', isError: true);
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthlyLimit = _budget?['monthlyLimit'] as num?;
    final currentMonthLent = (_budget?['currentMonthLent'] as num?) ?? 0;
    final percentUsed = (_budget?['percentUsed'] as num?)?.toDouble();
    final isOverLimit = _budget?['isOverLimit'] == true;
    final isNearLimit = _budget?['isNearLimit'] == true;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(t('monthly_lending_budget'),
            style: TextStyle(color: AppThemeColors.primaryText(context), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tricolorBorder(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('this_month'),
                              style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13)),
                          const SizedBox(height: 6),
                          Text(
                            '₹${currentMonthLent.toStringAsFixed(0)}'
                            '${monthlyLimit != null ? ' / ₹${monthlyLimit.toStringAsFixed(0)}' : ' lent'}',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 14),
                          if (monthlyLimit != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: ((percentUsed ?? 0) / 100).clamp(0.0, 1.0),
                                minHeight: 12,
                                backgroundColor: Colors.grey[200],
                                color: isOverLimit
                                    ? Colors.red
                                    : isNearLimit
                                        ? Colors.orange
                                        : AppColors.cyan,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isOverLimit
                                  ? 'You have exceeded your monthly lending budget.'
                                  : isNearLimit
                                      ? 'You are nearing your monthly lending budget (${percentUsed?.toStringAsFixed(0)}% used).'
                                      : '${percentUsed?.toStringAsFixed(0)}% of your budget used.',
                              style: TextStyle(
                                color: isOverLimit
                                    ? Colors.red
                                    : isNearLimit
                                        ? Colors.orange[800]
                                        : AppThemeColors.mutedText(context),
                                fontSize: 13,
                                fontWeight: isOverLimit || isNearLimit
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ] else
                            Text('No monthly limit set. Set one below to track your lending.',
                                style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Set Monthly Limit',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(
                    'Get warned when your total lending this month approaches this amount. Leave empty to disable.',
                    style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _limitController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Monthly limit (₹)',
                      prefixIcon: const Icon(Icons.currency_rupee_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Alert threshold: ${_alertThreshold.round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Slider(
                    value: _alertThreshold,
                    min: 50,
                    max: 100,
                    divisions: 10,
                    activeColor: AppColors.cyan,
                    label: '${_alertThreshold.round()}%',
                    onChanged: (v) => setState(() => _alertThreshold = v),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveBudget,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(t('save'), style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
