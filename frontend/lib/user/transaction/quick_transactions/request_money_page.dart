import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_widgets.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/transaction_constants.dart';

class RequestMoneyPage extends StatefulWidget {
  final String? prefillEmail;

  const RequestMoneyPage({super.key, this.prefillEmail});

  @override
  State<RequestMoneyPage> createState() => _RequestMoneyPageState();
}

class _RequestMoneyPageState extends State<RequestMoneyPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final _emailController = TextEditingController();
  String _currency = 'INR';
  bool _isLoading = false;
  String? _userEmail;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _suggestions = [];

  String get _symbol => txCurrencySymbol(_currency);

  @override
  void initState() {
    super.initState();
    _userEmail = Provider.of<SessionProvider>(context, listen: false).user?['email'];
    if (widget.prefillEmail != null) _emailController.text = widget.prefillEmail!;
    _emailController.addListener(_updateSuggestions);
    _loadFriends();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    _emailController.removeListener(_updateSuggestions);
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() => _friends = List<Map<String, dynamic>>.from(data['friends'] ?? []));
          _updateSuggestions();
        }
      }
    } catch (_) {}
  }

  void _updateSuggestions() {
    final q = _emailController.text.trim().toLowerCase();
    if (q.isEmpty) { setState(() => _suggestions = []); return; }
    setState(() => _suggestions = _friends.where((f) {
      final email = (f['email'] ?? '').toString().toLowerCase();
      final name = (f['name'] ?? f['username'] ?? '').toString().toLowerCase();
      return email.contains(q) || name.contains(q);
    }).take(5).toList());
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context).t;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.post('/api/quick-transactions', body: {
        'amount': _amountController.text,
        'currency': _currency,
        'description': _descController.text.isEmpty ? t('request_money_default_desc') : _descController.text,
        'counterpartyEmail': _emailController.text.trim(),
        'role': 'lender',
        'category': 'personal',
        'date': DateTime.now().toIso8601String(),
        'time': TimeOfDay.now().format(context),
      });
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        showSnack(context, t('request_sent_success'));
        Navigator.pop(context, jsonDecode(res.body));
      } else {
        final err = jsonDecode(res.body)['error'] ?? res.body;
        showSnack(context, err.toString(), isError: true);
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _field({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
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
                  colors: [Color(0xFF43A047), Color(0xFF66BB6A)],
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
                  const Icon(Icons.call_received_rounded, color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('request_money_title'),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text(t('request_money_subtitle'),
                            style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info banner
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF43A047).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Color(0xFF43A047), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(t('request_money_info'),
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF43A047))),
                            ),
                          ],
                        ),
                      ),

                      // Currency
                      _field(
                        child: DropdownButtonFormField<String>(
                          value: _currency,
                          items: kTxCurrencies.map((c) => DropdownMenuItem(
                            value: c['code'], child: Text('${c['symbol']} ${c['code']}'),
                          )).toList(),
                          onChanged: (v) => setState(() => _currency = v ?? 'INR'),
                          decoration: InputDecoration(
                            labelText: t('currency'),
                            prefixIcon: const Icon(Icons.currency_exchange, color: Color(0xFF43A047)),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Amount
                      _field(
                        child: TextFormField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '${t('amount')} ($_symbol)',
                            prefixIcon: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(_symbol,
                                  style: const TextStyle(color: Color(0xFF43A047), fontSize: 20, fontWeight: FontWeight.bold)),
                            ),
                            border: InputBorder.none,
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return t('please_enter_an_amount');
                            if (double.tryParse(v) == null || double.parse(v) <= 0) {
                              return t('please_enter_an_amount');
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Note
                      _field(
                        child: TextFormField(
                          controller: _descController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: t('note_optional_label'),
                            prefixIcon: const Icon(Icons.note_outlined, color: Color(0xFF43A047)),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Request from email
                      _field(
                        child: TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: t('request_from_email_label'),
                            prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF43A047)),
                            border: InputBorder.none,
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return t('please_enter_counterparty_email');
                            if (v.trim() == _userEmail) return t('counterparty_cannot_be_same_as_your_email');
                            return null;
                          },
                        ),
                      ),
                      if (_suggestions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _suggestions.map((f) {
                            final email = (f['email'] ?? '').toString();
                            final name = (f['name'] ?? f['username'] ?? '').toString();
                            return ActionChip(
                              label: Text(name.isNotEmpty ? '$name ($email)' : email, style: const TextStyle(fontSize: 12)),
                              onPressed: () => setState(() {
                                _emailController.text = email;
                                _suggestions = [];
                              }),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),

            // Submit button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: AppThemeColors.surfaceBg(context),
                border: Border(top: BorderSide(color: AppThemeColors.divider(context))),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white),
                  label: Text(_isLoading ? t('loading') : t('send_request_label'),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
