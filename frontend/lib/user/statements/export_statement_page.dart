import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../../utils/share_utils.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';

class ExportStatementPage extends StatefulWidget {
  const ExportStatementPage({super.key});

  @override
  State<ExportStatementPage> createState() => _ExportStatementPageState();
}

class _ExportStatementPageState extends State<ExportStatementPage> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 90));
  DateTime _toDate = DateTime.now();
  String _type = 'all';
  bool _exporting = false;

  final List<Map<String, String>> _typeOptions = const [
    {'value': 'all', 'label': 'All Transactions'},
    {'value': 'secure', 'label': 'Secure Transactions Only'},
    {'value': 'quick', 'label': 'Quick Transactions Only'},
    {'value': 'group', 'label': 'Group Expenses Only'},
  ];

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _export() async {
    if (_fromDate.isAfter(_toDate)) {
      showSnack(context, 'Start date must be before end date.', isError: true);
      return;
    }
    setState(() => _exporting = true);
    try {
      final from = DateFormat('yyyy-MM-dd').format(_fromDate);
      final to = DateFormat('yyyy-MM-dd').format(_toDate);
      final res = await ApiClient.get('/api/statements/export?from=$from&to=$to&type=$_type');
      if (res.statusCode == 200) {
        final ok = await shareTextFile(
          content: res.body,
          filename: 'lenden-statement-$from-to-$to.csv',
          subject: 'LenDen Transaction Statement',
        );
        if (!ok && mounted) {
          showSnack(context, 'Could not share the statement file.', isError: true);
        }
      } else {
        showSnack(context, 'Failed to generate statement.', isError: true);
      }
    } catch (e) {
      showSnack(context, 'Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text('Export Statement',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tricolorBorder(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Download a CSV statement of your transactions for a date range.',
                        style: TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Date Range', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('From'),
                    subtitle: Text(DateFormat('MMM dd, yyyy').format(_fromDate)),
                    trailing: const Icon(Icons.calendar_today_rounded, size: 18),
                    onTap: () => _pickDate(true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('To'),
                    subtitle: Text(DateFormat('MMM dd, yyyy').format(_toDate)),
                    trailing: const Icon(Icons.calendar_today_rounded, size: 18),
                    onTap: () => _pickDate(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Include', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _typeOptions
                  .map((opt) => DropdownMenuItem(value: opt['value'], child: Text(opt['label']!)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _exporting ? null : _export,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.download_rounded, color: Colors.white),
                label: Text(_exporting ? 'Exporting...' : 'Export & Share CSV',
                    style: const TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
