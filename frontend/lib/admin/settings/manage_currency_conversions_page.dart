import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';

class ManageCurrencyConversionsPage extends StatefulWidget {
  const ManageCurrencyConversionsPage({super.key});

  @override
  State<ManageCurrencyConversionsPage> createState() =>
      _ManageCurrencyConversionsPageState();
}

class _ManageCurrencyConversionsPageState
    extends State<ManageCurrencyConversionsPage> {
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _symbolController = TextEditingController();
  final TextEditingController _labelController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _addingCurrency = false;
  bool _syncingLive = false;
  String? _error;
  String _baseCurrency = 'INR';
  String _quoteCurrency = 'USD';
  List<String> _supportedCurrencies = const ['INR', 'USD', 'EUR'];
  List<Map<String, dynamic>> _currencyDefinitions = [];
  List<Map<String, dynamic>> _matrix = [];
  String? _lastUpdatedAt;

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  @override
  void dispose() {
    _rateController.dispose();
    _codeController.dispose();
    _symbolController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _syncLiveRates() async {
    setState(() => _syncingLive = true);
    try {
      final res = await ApiClient.post('/api/admin/currency-conversions/sync-live-rates', body: {});
      final data = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : {};
      if (res.statusCode == 200) {
        setState(() {
          _supportedCurrencies = List<String>.from(data['supportedCurrencies'] ?? _supportedCurrencies);
          _matrix = List<Map<String, dynamic>>.from(data['matrix'] ?? _matrix);
        });
        _showMessage('${data['message'] ?? 'Live rates synced!'} (ECB rates, date: ${data['rateDate'] ?? 'today'})');
      } else {
        _showMessage(data['error']?.toString() ?? 'Failed to sync live rates.', isError: true);
      }
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _syncingLive = false);
    }
  }

  Future<void> _loadRates() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiClient.get('/api/admin/currency-conversions');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _supportedCurrencies = List<String>.from(
              data['supportedCurrencies'] ?? const ['INR', 'USD', 'EUR']);
          _currencyDefinitions = List<Map<String, dynamic>>.from(
              data['currencyDefinitions'] ?? const []);
          _matrix = List<Map<String, dynamic>>.from(data['matrix'] ?? const []);
          _lastUpdatedAt = data['latestUpdatedAt']?.toString();
          if (!_supportedCurrencies.contains(_baseCurrency)) {
            _baseCurrency =
                _supportedCurrencies.isNotEmpty ? _supportedCurrencies.first : 'INR';
          }
          if (!_supportedCurrencies.contains(_quoteCurrency)) {
            _quoteCurrency = _supportedCurrencies.length > 1
                ? _supportedCurrencies[1]
                : _baseCurrency;
          }
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load conversion matrix.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading conversions: $e';
        _loading = false;
      });
    }
  }

  Future<void> _saveRate() async {
    final rate = double.tryParse(_rateController.text.trim());
    if (_baseCurrency == _quoteCurrency) {
      _showMessage('Choose two different currencies.', isError: true);
      return;
    }
    if (rate == null || rate <= 0) {
      _showMessage('Enter a valid conversion rate.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await ApiClient.put(
        '/api/admin/currency-conversions',
        body: {
          'baseCurrency': _baseCurrency,
          'quoteCurrency': _quoteCurrency,
          'rate': rate,
        },
      );
      final data =
          res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : {};
      if (res.statusCode == 200) {
        _rateController.clear();
        _showMessage(data['message']?.toString() ?? 'Rate saved successfully.');
        await _loadRates();
      } else {
        _showMessage(
          data['error']?.toString() ?? 'Failed to save rate.',
          isError: true,
        );
      }
    } catch (e) {
      _showMessage('Error saving rate: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _addCurrency() async {
    final code = _codeController.text.trim().toUpperCase();
    final symbol = _symbolController.text.trim();
    final label = _labelController.text.trim();

    if (code.isEmpty || symbol.isEmpty) {
      _showMessage('Currency code and symbol are required.', isError: true);
      return;
    }

    setState(() => _addingCurrency = true);
    try {
      final res = await ApiClient.post(
        '/api/admin/currency-conversions/currencies',
        body: {
          'code': code,
          'symbol': symbol,
          'label': label,
        },
      );
      final data =
          res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : {};
      if (res.statusCode == 201) {
        _codeController.clear();
        _symbolController.clear();
        _labelController.clear();
        _showMessage(data['message']?.toString() ?? 'Currency added successfully.');
        await _loadRates();
      } else {
        _showMessage(
          data['error']?.toString() ?? 'Failed to add currency.',
          isError: true,
        );
      }
    } catch (e) {
      _showMessage('Error adding currency: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _addingCurrency = false);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) =>
      showSnack(context, message, isError: isError);

  String _prettyTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return 'No manual updates yet';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.day}/${date.month}/${date.year}  $hour:$minute $period';
  }

  List<Map<String, dynamic>> _pairsForBase(String baseCurrency) {
    return _matrix
        .where((row) => row['baseCurrency'] == baseCurrency)
        .toList(growable: false);
  }

  List<Color> _colorsForMode(String mode) {
    switch (mode) {
      case 'manual':
        return const [Color(0xFF7C9DFF), Color(0xFFA9B8FF)];
      case 'calculated':
        return const [Color(0xFF58C4DD), Color(0xFF89E0EF)];
      case 'identity':
        return const [Color(0xFF6BCB91), Color(0xFFA9E4A7)];
      default:
        return const [Color(0xFFFFB562), Color(0xFFFFD9A0)];
    }
  }

  Widget _tricolorCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFE),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 170,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF67D5EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.black87),
                      ),
                      const Expanded(
                        child: Text(
                          'Currency Conversions',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _loading ? null : _loadRates,
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _loadRates,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              _tricolorCard(
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFDFEFE),
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Manage latest manual conversion rates',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF175676),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Enter one direct rate and the system will derive the reverse pair automatically. Supported currencies: ${_supportedCurrencies.join(', ')}.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.blueGrey.shade700,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          _buildInfoChip(
                                            Icons.currency_exchange_rounded,
                                            '${_matrix.where((row) => row['available'] == true).length} available pairs',
                                          ),
                                          _buildInfoChip(
                                            Icons.schedule_rounded,
                                            _prettyTimestamp(_lastUpdatedAt),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: _syncingLive ? null : _syncLiveRates,
                                          icon: _syncingLive
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor: AlwaysStoppedAnimation(Colors.white),
                                                  ),
                                                )
                                              : const Icon(Icons.cloud_sync_rounded, size: 18),
                                          label: Text(
                                            _syncingLive ? 'Fetching live rates...' : 'Sync Live Rates (ECB)',
                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF175676),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 13),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(14),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _tricolorCard(
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFEFC),
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Add New Currency',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _codeController,
                                              textCapitalization:
                                                  TextCapitalization.characters,
                                              decoration: InputDecoration(
                                                labelText: 'Code',
                                                hintText: 'e.g. SGD',
                                                filled: true,
                                                fillColor:
                                                    const Color(0xFFF7FBFD),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: TextField(
                                              controller: _symbolController,
                                              decoration: InputDecoration(
                                                labelText: 'Symbol',
                                                hintText: 'e.g. S\$',
                                                filled: true,
                                                fillColor:
                                                    const Color(0xFFF7FBFD),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _labelController,
                                        decoration: InputDecoration(
                                          labelText: 'Label (optional)',
                                          hintText: 'Singapore Dollar',
                                          filled: true,
                                          fillColor: const Color(0xFFF7FBFD),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed:
                                              _addingCurrency ? null : _addCurrency,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF175676),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 14),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: _addingCurrency
                                              ? const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation(
                                                            Colors.white),
                                                  ),
                                                )
                                              : const Text(
                                                  'Add Currency',
                                                  style: TextStyle(
                                                      fontWeight: FontWeight.w700),
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _tricolorCard(
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFEFC),
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Add Or Update Rate',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildCurrencyDropdown(
                                              label: 'From',
                                              value: _baseCurrency,
                                              onChanged: (value) => setState(
                                                () => _baseCurrency = value!,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _buildCurrencyDropdown(
                                              label: 'To',
                                              value: _quoteCurrency,
                                              onChanged: (value) => setState(
                                                () => _quoteCurrency = value!,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      TextField(
                                        controller: _rateController,
                                        keyboardType: const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                        decoration: InputDecoration(
                                          labelText:
                                              '1 $_baseCurrency equals how many $_quoteCurrency?',
                                          prefixIcon: const Icon(
                                            Icons.calculate_outlined,
                                            color: AppColors.cyan,
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFFF7FBFD),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      if (_error != null)
                                        Text(
                                          _error!,
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: _saving ? null : _saveRate,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AppColors.cyan,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 14),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          child: _saving
                                              ? const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation(
                                                            Colors.white),
                                                  ),
                                                )
                                              : const Text(
                                                  'Save Conversion Rate',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _tricolorCard(
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFCFFFE),
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Conversion Matrix',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ..._currencyDefinitions.map(
                                        (currency) => Container(
                                          margin: const EdgeInsets.only(
                                              bottom: 10),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF5FBFE),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                                color: const Color(0xFFD9EEF5)),
                                          ),
                                          child: Row(
                                            children: [
                                              Text(
                                                '${currency['symbol'] ?? currency['code']} ${currency['code']}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF175676),
                                                ),
                                              ),
                                              const Spacer(),
                                              Text(
                                                (currency['label'] ?? '')
                                                    .toString()
                                                    .trim()
                                                    .isEmpty
                                                    ? 'Custom/Default currency'
                                                    : currency['label'].toString(),
                                                style: TextStyle(
                                                  color:
                                                      Colors.blueGrey.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ..._supportedCurrencies.map(
                                        (from) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: Container(
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F9FC),
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '$from base currency',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF175676),
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                SingleChildScrollView(
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  child: Row(
                                                    children:
                                                        _pairsForBase(from).map(
                                                      (pair) {
                                                      final to =
                                                          pair['quoteCurrency'];
                                                      final available =
                                                          pair['available'] ==
                                                              true;
                                                      final rate =
                                                          pair['rate'];
                                                      final mode =
                                                          pair['mode'] ??
                                                              'missing';
                                                      final colors =
                                                          _colorsForMode(mode);
                                                      return Container(
                                                        width: 170,
                                                        margin:
                                                            const EdgeInsets.only(
                                                                right: 12),
                                                        padding:
                                                            const EdgeInsets
                                                                .all(12),
                                                        decoration:
                                                            BoxDecoration(
                                                          gradient:
                                                              LinearGradient(
                                                            colors: colors,
                                                            begin: Alignment
                                                                .topLeft,
                                                            end: Alignment
                                                                .bottomRight,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(14),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              '$from -> $to',
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height: 6),
                                                            Text(
                                                              available
                                                                  ? rate
                                                                      .toString()
                                                                  : 'Not available',
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                color: Colors.white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height: 6),
                                                            Text(
                                                              mode
                                                                  .toString()
                                                                  .toUpperCase(),
                                                              style: const TextStyle(
                                                                fontSize: 11,
                                                                color: Colors.white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ),
                                              ],
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5EEF5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.cyan),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF355070),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencyDropdown({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      onChanged: onChanged,
      items: _supportedCurrencies
          .map(
            (currency) => DropdownMenuItem<String>(
              value: currency,
              child: Text(currency),
            ),
          )
          .toList(),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF7FBFD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
