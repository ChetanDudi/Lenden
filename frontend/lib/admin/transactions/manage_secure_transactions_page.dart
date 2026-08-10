import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../utils/pickers.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/search_tab_bar.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../../utils/api_client.dart';
import '../../utils/http_interceptor.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class ManageTransactionsPage extends StatefulWidget {
  const ManageTransactionsPage({super.key});

  @override
  State<ManageTransactionsPage> createState() => _ManageTransactionsPageState();
}

class _ManageTransactionsPageState extends State<ManageTransactionsPage> {
  final TextEditingController _searchController = TextEditingController();
  static const List<String> _supportedCurrencies = [
    'INR',
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'CNY',
    'CAD',
    'AUD',
    'CHF',
    'RUB',
  ];

  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  bool _showAll = false;
  String? _error;
  String _searchQuery = '';
  String _currencyFilter = 'All';
  String _sortBy = 'latest';
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _filterCurrencyOptions {
    final values = {
      'All',
      ..._supportedCurrencies,
      ..._transactions.map((t) => t['currency']?.toString() ?? '').where((c) => c.isNotEmpty)
    }.toList()
      ..sort((a, b) {
        if (a == 'All') return -1;
        if (b == 'All') return 1;
        return a.compareTo(b);
      });
    return values;
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      _loading = true;
      _error = null;
      _showAll = false;
    });

    try {
      final params = <String, String>{};
      if (_searchQuery.trim().isNotEmpty) params['search'] = _searchQuery.trim();
      if (_currencyFilter != 'All') params['currency'] = _currencyFilter;
      if (_sortBy == 'amount_desc') {
        params['sortBy'] = 'amount';
        params['order'] = 'desc';
      } else if (_sortBy == 'amount_asc') {
        params['sortBy'] = 'amount';
        params['order'] = 'asc';
      } else {
        params['sortBy'] = 'date';
        params['order'] = 'desc';
      }

      final query = params.isNotEmpty
          ? '?${params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}'
          : '';
      final response = await ApiClient.get('/api/admin/transactions$query');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _transactions = List<Map<String, dynamic>>.from(data['transactions'] ?? []);
          _loading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        final data = jsonDecode(response.body);
        setState(() {
          _error = data['error']?.toString() ?? t('failed_to_load_transactions_msg');
          _loading = false;
        });
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      setState(() {
        _error = '${t('an_error_occurred_prefix')} $e';
        _loading = false;
      });
    }
  }

  void _showStylishSnackBar(String message, {bool isError = false}) =>
      showSnack(context, message, isError: isError);

  Future<void> _updateTransaction(
    String transactionId,
    Map<String, dynamic> updateData, {
    List<Uint8List> newPhotos = const [],
  }) async {
    try {
      final request = await HttpInterceptor.multipartRequest(
        'PUT',
        '/api/admin/transactions/$transactionId',
      );

      updateData.forEach((key, value) {
        if (value != null) {
          if (value is List || value is Map) {
            request.fields[key] = jsonEncode(value);
          } else {
            request.fields[key] = value.toString();
          }
        }
      });

      for (var i = 0; i < newPhotos.length; i++) {
        request.files.add(http.MultipartFile.fromBytes(
          'photos',
          newPhotos[i],
          filename: 'photo_$i.jpg',
        ));
      }

      final response = await request.send();
      final t = AppLocalizations.of(context).t;

      if (response.statusCode == 200) {
        _showStylishSnackBar(t('transaction_updated_successfully'));
        await _fetchTransactions();
      } else {
        final respStr = await response.stream.bytesToString();
        final data = jsonDecode(respStr);
        _showStylishSnackBar(
          data['message']?.toString() ?? t('failed_to_update_transaction'),
          isError: true,
        );
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      _showStylishSnackBar('${t('an_error_occurred_prefix')} $e', isError: true);
    }
  }

  Future<void> _deleteTransaction(String transactionId) async {
    try {
      final response =
          await ApiClient.delete('/api/admin/transactions/$transactionId');
      final t = AppLocalizations.of(context).t;

      if (response.statusCode == 200) {
        _showStylishSnackBar(t('transaction_deleted_successfully'));
        await _fetchTransactions();
      } else {
        final data = jsonDecode(response.body);
        _showStylishSnackBar(
          data['error']?.toString() ?? t('failed_to_delete_transaction'),
          isError: true,
        );
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      _showStylishSnackBar('${t('an_error_occurred_prefix')} $e', isError: true);
    }
  }

  String _displayValue(dynamic value) {
    final na = AppLocalizations.of(context).t('n_a');
    if (value == null) return na;
    if (value is String && value.trim().isEmpty) return na;
    if (value is Map || value is List) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return value.toString();
  }

  String _formatDate(dynamic value) {
    if (value == null) return AppLocalizations.of(context).t('n_a');
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return DateFormat('dd MMM yyyy, hh:mm a').format(parsed.toLocal());
  }

  String _formatDateOnly(dynamic value) {
    if (value == null) return AppLocalizations.of(context).t('n_a');
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return DateFormat('dd MMM yyyy').format(parsed.toLocal());
  }

  String _labelForKey(String key) {
    final buffer = StringBuffer();
    for (var i = 0; i < key.length; i++) {
      final char = key[i];
      if (i > 0 && char.toUpperCase() == char && char != '_') {
        buffer.write(' ');
      }
      buffer.write(char == '_' ? ' ' : char);
    }
    final label = buffer.toString().trim();
    if (label.isEmpty) return key;
    return label[0].toUpperCase() + label.substring(1);
  }

  bool _isDateOnlyField(String key) =>
      key == 'date' || key == 'expectedReturnDate';

  bool _isDateTimeField(String key) =>
      key == 'createdAt' || key == 'updatedAt' || key == 'paidAt';

  bool _shouldHideFromDialogs(String key) =>
      key == '_id' ||
      key == '__v' ||
      key == 'messageCounts' ||
      key == 'favourite';

  List<String> get _currencyOptions {
    final values = {
      ..._supportedCurrencies,
      ..._currencies.where((currency) => currency != 'All'),
    }.toList()
      ..sort();
    return values;
  }

  List<Map<String, dynamic>> _partialPaymentsFor(
    Map<String, dynamic> transaction,
  ) {
    final raw = transaction['partialPayments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Widget _buildDetailTile(String label, String value, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.cyan,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(value,
              style: TextStyle(
                  height: 1.35, color: AppThemeColors.primaryText(context))),
        ],
      ),
    );
  }

  List<String> _photosFor(Map<String, dynamic> transaction) {
    final raw = transaction['photos'];
    if (raw is! List) return const [];
    return raw
        .map((item) => item?.toString() ?? '')
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }

  Uint8List? _decodePhoto(String encoded) {
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  Future<List<Uint8List>> _pickAdditionalPhotos() async {
    final picker = ImagePicker();
    final result = await picker.pickMultiImage(
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (result.isEmpty) return const [];

    final byteList = <Uint8List>[];
    for (final file in result) {
      byteList.add(await file.readAsBytes());
    }
    return byteList;
  }

  Widget _buildPhotosSection({
    required List<dynamic> photos,
    required bool editable,
    void Function(int index)? onRemove,
    VoidCallback? onAdd,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _getNoteColor(3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).t('photos_label'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.cyan,
                  ),
                ),
              ),
              if (editable)
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(AppLocalizations.of(context).t('add')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (photos.isEmpty)
            Text(
              editable
                  ? AppLocalizations.of(context).t('no_photos_selected')
                  : AppLocalizations.of(context).t('no_photos_available'),
              style: TextStyle(color: AppThemeColors.secondaryText(context)),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: photos.asMap().entries.map((entry) {
                final photo = entry.value;
                Uint8List? bytes;
                if (photo is String) {
                  bytes = _decodePhoto(photo);
                } else if (photo is Uint8List) {
                  bytes = photo;
                }

                return Stack(
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x2200B4D8)),
                      ),
                      child: bytes == null
                          ? Center(
                              child: Text(
                                AppLocalizations.of(context).t('invalid_image'),
                                style: TextStyle(color: AppThemeColors.secondaryText(context)),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : Image.memory(bytes, fit: BoxFit.cover),
                    ),
                    if (editable)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () => onRemove?.call(entry.key),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildPartialPaymentsSection({
    required List<Map<String, dynamic>> payments,
    required bool editable,
    void Function(int index, Map<String, dynamic> payment)? onEdit,
    void Function(int index)? onRemove,
    VoidCallback? onAdd,
  }) {
    final t = AppLocalizations.of(context).t;
    if (payments.isEmpty && !editable) {
      return _buildDetailTile(
        t('partial_payment_history'),
        t('no_partial_payments_available'),
        _getNoteColor(4),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _getNoteColor(4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t('partial_payment_history'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.cyan,
                ),
              ),
              if (editable)
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: Text(t('add')),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (payments.isEmpty)
            Text(t('no_partial_payments_recorded'),
                style: TextStyle(color: AppThemeColors.primaryText(context))),
          ...payments.asMap().entries.map((entry) {
            final payment = entry.value;
            final amount = _displayValue(payment['amount']);
            final paidBy = _displayValue(payment['paidBy']);
            final paidAt = _formatDate(payment['paidAt']);
            final description = _displayValue(payment['description']);
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context).withAlpha(235),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x3300B4D8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${t('payment_number_prefix')} ${entry.key + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                      if (editable)
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => onEdit?.call(entry.key, payment),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                              onPressed: () => onRemove?.call(entry.key),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('${t('amount_colon')} $amount',
                      style: TextStyle(color: AppThemeColors.primaryText(context))),
                  Text('${t('paid_by_colon')} $paidBy',
                      style: TextStyle(color: AppThemeColors.primaryText(context))),
                  Text('${t('paid_at_colon')} $paidAt',
                      style: TextStyle(color: AppThemeColors.primaryText(context))),
                  if (description != t('n_a'))
                    Text('${t('description_colon')} $description',
                        style: TextStyle(color: AppThemeColors.primaryText(context))),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<DateTime?> _pickDate(
    BuildContext context,
    DateTime? initialDate,
  ) async {
    final now = DateTime.now();
    return showAppDatePicker(
      context: context,
      initialDate: initialDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _triBorder(
        radius: 14,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColors.secondaryText(context),
                  ),
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: options.contains(value) ? value : options.first,
                  isExpanded: true,
                  items: options
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: option,
                          child: Text(option,
                              style: TextStyle(
                                  color: AppThemeColors.primaryText(context))),
                        ),
                      )
                      .toList(),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _triBorder(
        radius: 14,
        child: Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            readOnly: readOnly,
            style: TextStyle(color: AppThemeColors.primaryText(context)),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getNoteColor(int index) {
    final lightColors = [
      const Color(0xFFFFF4E6),
      const Color(0xFFE8F5E9),
      const Color(0xFFFCE4EC),
      const Color(0xFFE3F2FD),
      const Color(0xFFFFF9C4),
      const Color(0xFFF3E5F5),
    ];
    final darkColors = [
      const Color(0xFF4A3F1F),
      const Color(0xFF1E3A26),
      const Color(0xFF4A2330),
      const Color(0xFF1B3A57),
      const Color(0xFF4A4420),
      const Color(0xFF3A2E45),
    ];
    return AppThemeColors.tinted(
      context,
      light: lightColors[index % lightColors.length],
      dark: darkColors[index % darkColors.length],
    );
  }

  Widget _triBorder({
    required Widget child,
    double radius = 18,
    EdgeInsets padding = const EdgeInsets.all(2),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }

  List<String> get _currencies {
    final values = _transactions
        .map((t) => (t['currency'] ?? '').toString().trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...values];
  }

  List<Map<String, dynamic>> get _visibleTransactions {
    if (_showAll || _transactions.length <= 5) return _transactions;
    return _transactions.take(5).toList();
  }

  Future<void> _showDeleteConfirmationDialog(
    Map<String, dynamic> transaction,
  ) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipPath(
                clipper: TopWaveClipper(),
                child: Container(
                  height: 70,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFE53935), Color(0xFFFF7043)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                child: Column(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.red, size: 44),
                    const SizedBox(height: 12),
                    Text(
                      t('delete_transaction_title'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${t('delete_transaction_confirm_message')} ${_displayValue(transaction['userEmail'])}.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppThemeColors.secondaryText(context),
                          fontSize: 15),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(t('cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(t('delete')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await _deleteTransaction(transaction['_id'].toString());
    }
  }

  Future<void> _showFullDetailsDialog(Map<String, dynamic> transaction) async {
    final partialPayments = _partialPaymentsFor(transaction);
    final photos = _photosFor(transaction);
    final detailEntries = transaction.entries
        .where(
          (entry) =>
              !_shouldHideFromDialogs(entry.key) &&
              entry.key != 'partialPayments' &&
              entry.key != 'photos',
        )
        .toList();

    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipPath(
                clipper: TopWaveClipper(),
                child: Container(
                  height: 70,
                  color: AppColors.cyan,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  children: [
                    Text(
                      t('full_transaction_details'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.55,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            ...detailEntries.asMap().entries.map((entry) {
                              final key = entry.value.key;
                              final value = entry.value.value;
                              final displayValue = _isDateOnlyField(key)
                                  ? _formatDateOnly(value)
                                  : _isDateTimeField(key)
                                      ? _formatDate(value)
                                      : _displayValue(value);
                              return _buildDetailTile(
                                _labelForKey(key),
                                displayValue,
                                _getNoteColor(entry.key),
                              );
                            }),
                            _buildPhotosSection(
                              photos: photos.map((p) => p.toString()).toList(),
                              editable: false,
                            ),
                            if ((transaction['isPartiallyPaid'] == true) ||
                                partialPayments.isNotEmpty)
                              _buildPartialPaymentsSection(
                                payments: partialPayments,
                                editable: false,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t('close')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditTransactionDialog(
      Map<String, dynamic> transaction) async {
    final textControllers = <String, TextEditingController>{};
    const excludedKeys = {
      '_id',
      '__v',
      'messageCounts',
      'partialPayments',
      'photos',
      'favourite',
      'createdAt',
      'updatedAt',
    };

    for (final entry in transaction.entries) {
      if (excludedKeys.contains(entry.key)) continue;
      if (entry.value is bool) continue;
      if (_isDateOnlyField(entry.key)) continue;
      if (entry.key == 'currency') continue;
      if (entry.key == 'userCleared' ||
          entry.key == 'counterpartyCleared' ||
          entry.key == 'isPartiallyPaid') {
        continue;
      }

      textControllers[entry.key] = TextEditingController(
        text: entry.value is Map || entry.value is List
            ? const JsonEncoder.withIndent('  ').convert(entry.value)
            : '${entry.value ?? ''}',
      );
    }

    String selectedCurrency =
        (transaction['currency']?.toString().trim().isNotEmpty ?? false)
            ? transaction['currency'].toString().trim()
            : (_currencyOptions.isNotEmpty ? _currencyOptions.first : '');
    String userClearedValue = '${transaction['userCleared'] == true}';
    String counterpartyClearedValue =
        '${transaction['counterpartyCleared'] == true}';
    String isPartiallyPaidValue = '${transaction['isPartiallyPaid'] == true}';
    DateTime? selectedDate =
        DateTime.tryParse('${transaction['date'] ?? ''}')?.toLocal();
    DateTime? selectedExpectedReturnDate =
        DateTime.tryParse('${transaction['expectedReturnDate'] ?? ''}')
            ?.toLocal();
    
    final List<Map<String, dynamic>> partialPayments = List<Map<String, dynamic>>.from(_partialPaymentsFor(transaction));
    final List<String> existingPhotos = _photosFor(transaction);
    final List<Uint8List> newPhotos = [];
    final t = AppLocalizations.of(context).t;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipPath(
                  clipper: TopWaveClipper(),
                  child: Container(
                    height: 70,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.cyan, Color(0xFF48CAE4)],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    children: [
                      Text(
                        t('edit_transaction_title'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.58,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildTextField(
                                label: t('created_at_label'),
                                controller: TextEditingController(text: _formatDate(transaction['createdAt'])),
                                readOnly: true,
                              ),
                              _buildTextField(
                                label: t('updated_at_label'),
                                controller: TextEditingController(text: _formatDate(transaction['updatedAt'])),
                                readOnly: true,
                              ),
                              if (_currencyOptions.isNotEmpty)
                                _buildDropdownField(
                                  label: t('currency'),
                                  value: selectedCurrency,
                                  options: _currencyOptions,
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      selectedCurrency = value;
                                    });
                                  },
                                ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _triBorder(
                                  radius: 14,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppThemeColors.cardBg(context),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      title: Text(t('date'),
                                          style: TextStyle(
                                              color: AppThemeColors.primaryText(context))),
                                      subtitle: Text(
                                        selectedDate == null
                                            ? t('select_date')
                                            : _formatDateOnly(
                                                selectedDate!.toIso8601String(),
                                              ),
                                        style: TextStyle(
                                            color: AppThemeColors.secondaryText(context)),
                                      ),
                                      trailing:
                                          const Icon(Icons.calendar_today),
                                      onTap: () async {
                                        final picked = await _pickDate(
                                          context,
                                          selectedDate,
                                        );
                                        if (picked == null) return;
                                        setDialogState(() {
                                          selectedDate = picked;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _triBorder(
                                  radius: 14,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppThemeColors.cardBg(context),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      title: Text(t('expected_return_date_label'),
                                          style: TextStyle(
                                              color: AppThemeColors.primaryText(context))),
                                      subtitle: Text(
                                        selectedExpectedReturnDate == null
                                            ? t('not_set')
                                            : _formatDateOnly(
                                                selectedExpectedReturnDate!
                                                    .toIso8601String(),
                                              ),
                                        style: TextStyle(
                                            color: AppThemeColors.secondaryText(context)),
                                      ),
                                      trailing:
                                          const Icon(Icons.event_available),
                                      onTap: () async {
                                        final picked = await _pickDate(
                                          context,
                                          selectedExpectedReturnDate,
                                        );
                                        if (picked == null) return;
                                        setDialogState(() {
                                          selectedExpectedReturnDate = picked;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              _buildDropdownField(
                                label: t('user_cleared_label'),
                                value: userClearedValue,
                                options: const ['true', 'false'],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    userClearedValue = value;
                                  });
                                },
                              ),
                              _buildDropdownField(
                                label: t('counterparty_cleared_label'),
                                value: counterpartyClearedValue,
                                options: const ['true', 'false'],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    counterpartyClearedValue = value;
                                  });
                                },
                              ),
                              _buildDropdownField(
                                label: t('is_partially_paid_label'),
                                value: isPartiallyPaidValue,
                                options: const ['true', 'false'],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    isPartiallyPaidValue = value;
                                  });
                                },
                              ),
                              _buildPhotosSection(
                                photos: [...existingPhotos, ...newPhotos],
                                editable: true,
                                onRemove: (index) {
                                  setDialogState(() {
                                    if (index < existingPhotos.length) {
                                      existingPhotos.removeAt(index);
                                    } else {
                                      newPhotos.removeAt(index - existingPhotos.length);
                                    }
                                  });
                                },
                                onAdd: () async {
                                  final photos =
                                      await _pickAdditionalPhotos();
                                  if (photos.isEmpty) return;
                                  setDialogState(() {
                                    newPhotos.addAll(photos);
                                  });
                                },
                              ),
                              ...textControllers.entries.map((entry) {
                                final isComplex =
                                    entry.value.text.trim().startsWith('{') ||
                                        entry.value.text.trim().startsWith('[');
                                final isNumberField = {
                                  'amount',
                                  'interestRate',
                                  'compoundingFrequency',
                                  'remainingAmount',
                                  'totalAmountWithInterest',
                                }.contains(entry.key);
                                return _buildTextField(
                                  label: _labelForKey(entry.key),
                                  controller: entry.value,
                                  keyboardType: isNumberField
                                      ? const TextInputType.numberWithOptions(
                                          decimal: true,
                                        )
                                      : TextInputType.text,
                                  maxLines: isComplex ? 5 : 1,
                                );
                              }),
                              _buildPartialPaymentsSection(
                                payments: partialPayments,
                                editable: true,
                                onAdd: () async {
                                  final newPayment = await _showEditPartialPaymentDialog(
                                    context: context,
                                    lenderEmail: transaction['role'] == 'lender' ? transaction['userEmail'] : transaction['counterpartyEmail'],
                                    borrowerEmail: transaction['role'] == 'borrower' ? transaction['userEmail'] : transaction['counterpartyEmail'],
                                  );
                                  if (newPayment != null) {
                                    setDialogState(() {
                                      partialPayments.add(newPayment);
                                    });
                                  }
                                },
                                onEdit: (index, payment) async {
                                  final updatedPayment = await _showEditPartialPaymentDialog(
                                    context: context,
                                    payment: payment,
                                    lenderEmail: transaction['role'] == 'lender' ? transaction['userEmail'] : transaction['counterpartyEmail'],
                                    borrowerEmail: transaction['role'] == 'borrower' ? transaction['userEmail'] : transaction['counterpartyEmail'],
                                  );
                                  if (updatedPayment != null) {
                                    setDialogState(() {
                                      partialPayments[index] = updatedPayment;
                                    });
                                  }
                                },
                                onRemove: (index) {
                                  setDialogState(() {
                                    partialPayments.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(t('cancel')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final updateData = <String, dynamic>{
                                  'currency': selectedCurrency,
                                  'userCleared': userClearedValue,
                                  'counterpartyCleared':
                                      counterpartyClearedValue,
                                  'isPartiallyPaid':
                                      isPartiallyPaidValue,
                                  'date': selectedDate?.toIso8601String(),
                                  'expectedReturnDate':
                                      selectedExpectedReturnDate
                                          ?.toIso8601String(),
                                  'photos': existingPhotos,
                                  'partialPayments': partialPayments,
                                };

                                for (final entry in textControllers.entries) {
                                  final text = entry.value.text.trim();
                                  updateData[entry.key] = text;
                                }

                                Navigator.pop(context);
                                _updateTransaction(
                                  transaction['_id'].toString(),
                                  updateData,
                                  newPhotos: newPhotos,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cyan,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(t('save')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final controller in textControllers.values) {
      controller.dispose();
    }
  }

  Future<Map<String, dynamic>?> _showEditPartialPaymentDialog({
    required BuildContext context,
    Map<String, dynamic>? payment,
    required String lenderEmail,
    required String borrowerEmail,
  }) async {
    final t = AppLocalizations.of(context).t;
    final amountController = TextEditingController(text: payment?['amount']?.toString() ?? '');
    final descriptionController = TextEditingController(text: payment?['description']?.toString() ?? '');
    DateTime? paidAt = DateTime.tryParse(payment?['paidAt']?.toString() ?? '');
    String? paidBy = payment?['paidBy'];

    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(dialogContext),
        title: Text(payment == null ? t('add_partial_payment_title') : t('edit_partial_payment_title'),
            style: TextStyle(color: AppThemeColors.primaryText(dialogContext))),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(labelText: t('amount_label')),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                DropdownButtonFormField<String>(
                  value: paidBy,
                  decoration: InputDecoration(labelText: t('paid_by_label')),
                  items: [
                    DropdownMenuItem(
                      value: 'lender',
                      child: Text('${t('lender')} ($lenderEmail)'),
                    ),
                    DropdownMenuItem(
                      value: 'borrower',
                      child: Text('${t('borrower')} ($borrowerEmail)'),
                    ),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      paidBy = value;
                    });
                  },
                ),
                TextField(
                  controller: descriptionController,
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(labelText: t('description_label')),
                ),
                ListTile(
                  title: Text(t('paid_at_label'), style: TextStyle(color: AppThemeColors.primaryText(context))),
                  subtitle: Text(paidAt == null
                      ? t('select_date_label')
                      : _formatDate(paidAt!.toIso8601String())),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await _pickDate(context, paidAt);
                    if (picked != null) {
                      setDialogState(() {
                        paidAt = picked;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, {
                'amount': double.tryParse(amountController.text) ?? 0,
                'paidBy': paidBy,
                'description': descriptionController.text,
                'paidAt': paidAt?.toIso8601String(),
              });
            },
            child: Text(t('save')),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final t = AppLocalizations.of(context).t;
    final total = _transactions.length;
    final visible = _visibleTransactions.length;
    final totalAmount = _transactions.fold<double>(
      0,
      (sum, item) =>
          sum +
          ((item['amount'] as num?)?.toDouble() ??
              double.tryParse('${item['amount']}') ??
              0),
    );

    final items = [
      (t('total_label'), '$total', Icons.receipt_long_rounded),
      (t('showing_label'), '$visible', Icons.visibility_rounded),
      (t('amount_label'), totalAmount.toStringAsFixed(2), Icons.payments_rounded),
    ];

    return Row(
      children: List.generate(items.length, (index) {
        final item = items[index];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == items.length - 1 ? 0 : 12),
            child: _triBorder(
              radius: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _getNoteColor(index),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(item.$3, color: AppColors.cyan),
                    const SizedBox(height: 6),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                    Text(
                      item.$1,
                      style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatusChip(Map<String, dynamic> transaction) {
    final bool userCleared = transaction['userCleared'] == true;
    final bool counterpartyCleared = transaction['counterpartyCleared'] == true;
    final bool isPartiallyPaid = transaction['isPartiallyPaid'] == true;

    String label;
    Color color;
    IconData icon;

    final t = AppLocalizations.of(context).t;
    if (userCleared && counterpartyCleared) {
      label = t('cleared_label');
      color = Colors.green;
      icon = Icons.check_circle_rounded;
    } else if (isPartiallyPaid) {
      label = t('partially_paid_label');
      color = Colors.orange;
      icon = Icons.donut_large_rounded;
    } else {
      label = t('pending');
      color = Colors.grey;
      icon = Icons.hourglass_empty_rounded;
    }

    return Chip(
      avatar: Icon(icon, color: Colors.white, size: 16),
      label: Text(label),
      backgroundColor: color,
      labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction, int index) {
    final t = AppLocalizations.of(context).t;
    final amount = _displayValue(transaction['amount']);
    final currency = _displayValue(transaction['currency']);
    final lender = _displayValue(transaction['userEmail']);
    final borrower = _displayValue(transaction['counterpartyEmail']);
    final createdAt = _formatDate(transaction['createdAt']);

    return _triBorder(
      radius: 18,
      padding: const EdgeInsets.all(1.5),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: () => _showFullDetailsDialog(transaction),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$amount $currency',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.cyan,
                      ),
                    ),
                    _buildStatusChip(transaction),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.arrow_upward_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(t('from_label'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(lender, overflow: TextOverflow.ellipsis)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.arrow_downward_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(t('to_label'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(borrower, overflow: TextOverflow.ellipsis)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded, color: Colors.grey[600], size: 16),
                    const SizedBox(width: 8),
                    Text(t('created_colon_label').replaceFirst('{date}', createdAt)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showFullDetailsDialog(transaction),
                      icon: const Icon(Icons.visibility_rounded),
                      label: Text(t('view_label')),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _showEditTransactionDialog(transaction),
                      icon: const Icon(Icons.edit_rounded),
                      label: Text(t('edit')),
                      style: TextButton.styleFrom(foregroundColor: Colors.orange),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _showDeleteConfirmationDialog(transaction),
                      icon: const Icon(Icons.delete_rounded),
                      label: Text(t('delete')),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final visibleTransactions = _visibleTransactions;
    final filteredTransactions = _transactions;

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
                decoration: BoxDecoration(
                  color: AppThemeColors.waveSolid(context),
                  gradient: AppThemeColors.isDark(context)
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.cyan, Color(0xFF48CAE4)],
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          t('manage_transactions_title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh, color: AppThemeColors.primaryText(context)),
                        onPressed: _fetchTransactions,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              child: Column(
                                children: [
                                  AppSearchBar(
                                    controller: _searchController,
                                    hintText: t('search_transactions_hint'),
                                    onChanged: (value) {
                                      setState(() => _searchQuery = value);
                                      _searchDebounceTimer?.cancel();
                                      _searchDebounceTimer = Timer(
                                        const Duration(milliseconds: 300),
                                        _fetchTransactions,
                                      );
                                    },
                                    margin: EdgeInsets.zero,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _triBorder(
                                          radius: 14,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: AppThemeColors.cardBg(context),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value: _currencyFilter,
                                                isExpanded: true,
                                                dropdownColor: AppThemeColors.cardBg(context),
                                                style: TextStyle(color: AppThemeColors.primaryText(context)),
                                                items: _filterCurrencyOptions
                                                    .map(
                                                      (currency) =>
                                                          DropdownMenuItem(
                                                        value: currency,
                                                        child: Text(currency),
                                                      ),
                                                    )
                                                    .toList(),
                                                onChanged: (value) {
                                                  setState(() => _currencyFilter = value!);
                                                  _fetchTransactions();
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _triBorder(
                                          radius: 14,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: AppThemeColors.cardBg(context),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value: _sortBy,
                                                isExpanded: true,
                                                dropdownColor: AppThemeColors.cardBg(context),
                                                style: TextStyle(color: AppThemeColors.primaryText(context)),
                                                items: [
                                                  DropdownMenuItem(
                                                    value: 'latest',
                                                    child: Text(t('latest_label')),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'amount_desc',
                                                    child: Text(t('amount_high')),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'amount_asc',
                                                    child: Text(t('amount_low')),
                                                  ),
                                                ],
                                                onChanged: (value) {
                                                  setState(() => _sortBy = value!);
                                                  _fetchTransactions();
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  _buildStatsRow(),
                                  const SizedBox(height: 16),
                                  if (filteredTransactions.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 80),
                                      child: Column(
                                        children: [
                                          Icon(Icons.receipt_long_outlined,
                                              size: 72, color: AppThemeColors.mutedText(context)),
                                          const SizedBox(height: 12),
                                          Text(
                                            t('no_transactions_found'),
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: AppThemeColors.mutedText(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else ...[
                                    ...visibleTransactions.asMap().entries.map(
                                          (entry) => _buildTransactionCard(
                                            entry.value,
                                            entry.key,
                                          ),
                                        ),
                                    if (!_showAll &&
                                        filteredTransactions.length > 5)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _showAll = true;
                                            });
                                          },
                                          child: Text(
                                            'View All (${filteredTransactions.length})',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.cyan,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
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

