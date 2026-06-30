import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import 'subscription_models.dart';

// Premium Benefits Tab
class PremiumBenefitsTab extends StatefulWidget {
  @override
  _PremiumBenefitsTabState createState() => _PremiumBenefitsTabState();
}

class _PremiumBenefitsTabState extends State<PremiumBenefitsTab> {
  List<PremiumBenefit> _benefits = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchBenefits();
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

  Future<void> _fetchBenefits() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.get('/api/admin/premium-benefits');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _benefits =
              data.map((item) => PremiumBenefit.fromJson(item)).toList();
          _isLoading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        setState(() {
          _error = (body?['message'] ?? t('failed_to_load_benefits_message'))
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
                        onPressed: _fetchBenefits,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(t('retry')),
                      ),
                    ],
                  ),
                )
              : _benefits.isEmpty
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
                            t('add_first_premium_benefit'),
                            style: TextStyle(
                                fontSize: 14,
                                color: AppThemeColors.mutedText(context)),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: _benefits.length,
                      itemBuilder: (context, index) {
                        final benefit = _benefits[index];
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
                            child: ListTile(
                              leading: Icon(Icons.check_circle,
                                  color: AppColors.cyan, size: 32),
                              title: Text(benefit.text,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color:
                                          AppThemeColors.primaryText(context))),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon:
                                        Icon(Icons.edit, color: AppColors.cyan),
                                    onPressed: () =>
                                        _showBenefitDialog(benefit: benefit),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteBenefit(benefit.id),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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
            onPressed: () => _showBenefitDialog(),
            icon: Icon(Icons.add),
            label: Text(t('add_benefit_title')),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
      ),
    );
  }

  void _showBenefitDialog({PremiumBenefit? benefit}) {
    showDialog(
      context: context,
      builder: (context) {
        return BenefitDialog(benefit: benefit, onSave: _fetchBenefits);
      },
    );
  }

  Future<void> _deleteBenefit(String id) async {
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
                  t('delete_benefit_title'),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(dialogContext)),
                ),
                SizedBox(height: 12),
                Text(
                  t('confirm_delete_benefit'),
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
          await ApiClient.delete('/api/admin/premium-benefits/$id');
      if (response.statusCode == 200) {
        _fetchBenefits();
        showStylishSnackBar(context, t('benefit_deleted_successfully'));
      } else {
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        showStylishSnackBar(
            context, body?['message'] ?? t('failed_to_delete_benefit'),
            isError: true);
      }
    }
  }
}

class BenefitDialog extends StatefulWidget {
  final PremiumBenefit? benefit;
  final VoidCallback onSave;

  BenefitDialog({this.benefit, required this.onSave});

  @override
  _BenefitDialogState createState() => _BenefitDialogState();
}

class _BenefitDialogState extends State<BenefitDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _text;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _text = widget.benefit?.text ?? '';
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
                light: const Color(0xFFE8F5E9), dark: const Color(0xFF1E3A26)),
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
                    widget.benefit == null
                        ? t('add_benefit_title')
                        : t('edit_benefit_title'),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context)),
                  ),
                  SizedBox(height: 20),
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
                      child: TextFormField(
                        initialValue: _text,
                        style: TextStyle(
                            color: AppThemeColors.primaryText(context)),
                        decoration: InputDecoration(
                          labelText: t('benefit_text_label'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppThemeColors.cardBg(context),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        maxLines: 3,
                        validator: (value) => value!.isEmpty
                            ? t('please_enter_benefit_text')
                            : null,
                        onSaved: (value) => _text = value!,
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
                        onPressed: _isSaving ? null : _saveBenefit,
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

  Future<void> _saveBenefit() async {
    final t = AppLocalizations.of(context).t;
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _isSaving = true;
      });
      try {
        final body = {'text': _text};
        final response = widget.benefit == null
            ? await ApiClient.post('/api/admin/premium-benefits', body: body)
            : await ApiClient.put(
                '/api/admin/premium-benefits/${widget.benefit!.id}',
                body: body);

        if (response.statusCode == 201 || response.statusCode == 200) {
          widget.onSave();
          Navigator.of(context).pop();
          showStylishSnackBar(context, t('benefit_saved_successfully'));
        } else {
          final respBody =
              response.body.isNotEmpty ? json.decode(response.body) : null;
          showStylishSnackBar(
              context, respBody?['message'] ?? t('failed_to_save_benefit'),
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

