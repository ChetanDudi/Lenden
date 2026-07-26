import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../utils/api_client.dart';
import '../../widgets/app_colors.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/responsive.dart';
import '../../widgets/wave_widget.dart' show DeepTopWaveClipper;
import '../../utils/display_currency_helper.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../widgets/premium_gate.dart';
import 'tabs/overview_tab.dart';
import 'tabs/income_expense_tab.dart';
import 'tabs/categories_tab.dart';
import 'tabs/groups_tab.dart';
import 'tabs/members_tab.dart';
import 'tabs/trends_tab.dart';
import 'tabs/charts_tab.dart';
import 'tabs/export_tab.dart';
import 'tabs/comparison_tab.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  static const _periods = ['today', 'weekly', '30d', '3m', 'quarterly', '6m', '1y', 'custom'];
  String _selectedPeriod = '3m';
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _isLoading = true;
  bool _hasError = false;
  bool _generatingPdf = false;
  bool _exportingCsv = false;
  Map<String, dynamic>? _report;

  late final TabController _tabController;
  final _fmt = NumberFormat('#,##0', 'en_IN');
  final _dateFmt = DateFormat('d MMM yyyy');
  DisplayCurrencyData? _displayCurrencyData;
  String _selectedDisplayCurrency = 'INR';
  String? _displayCurrencyError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 9, vsync: this);
    _fetchReport();
    _loadDisplayCurrencies();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDisplayCurrencies() async {
    try {
      final data = await DisplayCurrencyHelper.load();
      if (!mounted) return;
      setState(() {
        _displayCurrencyData = data;
        _displayCurrencyError = null;
        if (!data.currencies.any((item) => item['code'] == _selectedDisplayCurrency)) {
          _selectedDisplayCurrency = 'INR';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _displayCurrencyData = null;
        _selectedDisplayCurrency = 'INR';
        _displayCurrencyError = 'Currency conversion unavailable';
      });
    }
  }

  DateTimeRange _periodRange(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'today':
        return DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now);
      case 'weekly':
        return DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
      case '30d':
        return DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
      case 'quarterly':
        return DateTimeRange(start: now.subtract(const Duration(days: 90)), end: now);
      case '6m':
        return DateTimeRange(start: DateTime(now.year, now.month - 5, 1), end: now);
      case '1y':
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case 'custom':
        return DateTimeRange(
          start: _customStart ?? now.subtract(const Duration(days: 30)),
          end: _customEnd ?? now,
        );
      default: // 3m
        return DateTimeRange(start: DateTime(now.year, now.month - 2, 1), end: now);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _customStart ?? now.subtract(const Duration(days: 30)),
        end: _customEnd ?? now,
      ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.cyan),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _customStart = picked.start;
        _customEnd = picked.end;
        _selectedPeriod = 'custom';
      });
      _fetchReport();
    }
  }

  Future<void> _fetchReport() async {
    if (_selectedPeriod == 'custom' && (_customStart == null || _customEnd == null)) {
      await _pickCustomRange();
      return;
    }
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final range = _periodRange(_selectedPeriod);
      final start = range.start.toIso8601String().split('T')[0];
      final end = range.end.toIso8601String().split('T')[0];
      final resp = await ApiClient.get('/api/reports/summary?startDate=$start&endDate=$end');
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() { _report = json.decode(resp.body); _isLoading = false; });
      } else {
        setState(() { _hasError = true; _isLoading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  String _periodLabel(String p) {
    switch (p) {
      case 'today': return 'Today';
      case 'weekly': return '7 Days';
      case '30d': return '30 Days';
      case '3m': return '3 Months';
      case 'quarterly': return 'Quarter';
      case '6m': return '6 Months';
      case '1y': return 'This Year';
      case 'custom':
        if (_customStart != null && _customEnd != null) {
          return '${_dateFmt.format(_customStart!)} – ${_dateFmt.format(_customEnd!)}';
        }
        return 'Custom';
      default: return p;
    }
  }

  String _ca(num? v) {
    final amount = (v ?? 0).toDouble();
    if (_selectedDisplayCurrency == 'INR' || _displayCurrencyData == null ||
        !_displayCurrencyData!.canConvert('INR', _selectedDisplayCurrency)) {
      return '₹${_fmt.format(amount)}';
    }
    final converted = _displayCurrencyData!.convert(amount, 'INR', _selectedDisplayCurrency);
    final sym = _displayCurrencyData!.symbolFor(_selectedDisplayCurrency);
    return '$sym${_fmt.format(converted)}';
  }

  String _pf(num? v) {
    final amount = (v ?? 0).toDouble();
    if (_selectedDisplayCurrency == 'INR' || _displayCurrencyData == null ||
        !_displayCurrencyData!.canConvert('INR', _selectedDisplayCurrency)) {
      return 'Rs.${_fmt.format(amount)}';
    }
    final converted = _displayCurrencyData!.convert(amount, 'INR', _selectedDisplayCurrency);
    return '$_selectedDisplayCurrency ${_fmt.format(converted)}';
  }

  Future<void> _exportCsv() async {
    if (_report == null) return;
    setState(() => _exportingCsv = true);
    try {
      final ov    = _report!['overview']           as Map<String, dynamic>? ?? {};
      final cats  = (_report!['categories']        as List? ?? []).cast<Map<String, dynamic>>();
      final cps   = (_report!['topCounterparties'] as List? ?? []).cast<Map<String, dynamic>>();
      final trend = (_report!['monthlyTrend']      as List? ?? []).cast<Map<String, dynamic>>();
      final groups= (_report!['groupBreakdown']    as List? ?? []).cast<Map<String, dynamic>>();
      final adv   = _report!['advanced']           as Map<String, dynamic>? ?? {};

      final range = _periodRange(_selectedPeriod);
      final buf = StringBuffer();
      buf.writeln('LenDen Financial Report');
      buf.writeln('Period,${range.start.toIso8601String().split('T')[0]},${range.end.toIso8601String().split('T')[0]}');
      buf.writeln('Generated,${DateTime.now().toIso8601String()}');
      buf.writeln();
      buf.writeln('OVERVIEW');
      buf.writeln('Metric,Value');
      buf.writeln('Total Transactions,${ov['totalTransactions'] ?? 0}');
      buf.writeln('Net Balance,${ov['netBalance'] ?? 0}');
      buf.writeln('Total Lent,${ov['totalAmountLent'] ?? 0}');
      buf.writeln('Total Borrowed,${ov['totalAmountBorrowed'] ?? 0}');
      buf.writeln('Group Expenses,${ov['groupExpenseTotal'] ?? 0}');
      buf.writeln('Your Group Share,${ov['groupUserShare'] ?? 0}');
      buf.writeln('Cleared Transactions,${ov['clearedTransactions'] ?? 0}');
      buf.writeln('Pending Transactions,${ov['unclearedTransactions'] ?? 0}');
      buf.writeln('Pending Amount,${ov['pendingAmount'] ?? 0}');
      buf.writeln();
      buf.writeln('ADVANCED STATS');
      buf.writeln('Metric,Value');
      buf.writeln('Highest Transaction,${adv['highestTxn'] ?? 0}');
      buf.writeln('Lowest Transaction,${adv['lowestTxn'] ?? 0}');
      buf.writeln('Average Transaction,${adv['avgTxn'] ?? 0}');
      buf.writeln('Average Daily Spend,${adv['avgDailySpend'] ?? 0}');
      buf.writeln();
      buf.writeln('CATEGORY BREAKDOWN');
      buf.writeln('Category,Transactions,Amount,% of Total,vs Prev Period (%)');
      for (final c in cats) {
        buf.writeln('${c['category']},${c['count']},${c['amount']},${c['percentage'] ?? 0},${c['trend'] ?? 'N/A'}');
      }
      buf.writeln();
      buf.writeln('MONTHLY TREND');
      buf.writeln('Month,Lent,Borrowed,Group Expenses');
      for (final m in trend) {
        buf.writeln('${m['label']},${m['lent']},${m['borrowed']},${m['group']}');
      }
      buf.writeln();
      buf.writeln('TOP CONTACTS');
      buf.writeln('Email,Transactions,Net Amount');
      for (final cp in cps) {
        buf.writeln('"${cp['email']}",${cp['count']},${cp['netAmount']}');
      }
      buf.writeln();
      if (groups.isNotEmpty) {
        buf.writeln('GROUP BREAKDOWN');
        buf.writeln('Group,Members,Total Expenses,Your Share,Net Balance');
        for (final g in groups) {
          buf.writeln('"${g['title']}",${g['memberCount']},${g['totalExpenses']},${g['yourShare']},${g['netBalance']}');
        }
        buf.writeln();
      }
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/lenden_report_$ts.csv');
      await file.writeAsString(buf.toString());
      if (mounted) {
        await OpenFile.open(file.path);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV exported to ${file.path.split('/').last}'), backgroundColor: Colors.teal),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _downloadPdf() async {
    if (_report == null) return;
    final t = AppLocalizations.of(context).t;
    setState(() => _generatingPdf = true);
    try {
      final doc = pw.Document();
      final overview   = _report!['overview']           as Map<String, dynamic>? ?? {};
      final byType     = _report!['byType']             as Map<String, dynamic>? ?? {};
      final categories = (_report!['categories']        as List? ?? []).cast<Map<String, dynamic>>();
      final trend      = (_report!['monthlyTrend']      as List? ?? []).cast<Map<String, dynamic>>();
      final topCp      = (_report!['topCounterparties'] as List? ?? []).cast<Map<String, dynamic>>();
      final periodLabel = _periodLabel(_selectedPeriod);
      final now = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

      final cyan      = PdfColor.fromHex('#00BCD4');
      final darkBg    = PdfColor.fromHex('#0D1B2A');
      final lightGrey = PdfColor.fromHex('#F5F5F5');
      final textDark  = PdfColor.fromHex('#1A1A1A');
      final green     = PdfColor.fromHex('#4CAF50');
      final red       = PdfColor.fromHex('#F44336');

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: pw.BoxDecoration(color: darkBg, borderRadius: pw.BorderRadius.circular(12)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('LenDen', style: pw.TextStyle(color: PdfColors.white, fontSize: 28, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('Financial Report', style: pw.TextStyle(color: cyan, fontSize: 14)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(periodLabel, style: pw.TextStyle(color: PdfColors.white, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('Generated: $now', style: pw.TextStyle(color: PdfColors.grey, fontSize: 9)),
              ]),
            ]),
          ),
          pw.SizedBox(height: 20),
          pw.Text('Overview', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: textDark)),
          pw.SizedBox(height: 12),
          pw.Row(children: [
            _pdfStatCard('Total Transactions', '${overview['totalTransactions'] ?? 0}', cyan, darkBg),
            pw.SizedBox(width: 12),
            _pdfStatCard('Net Balance', _pf(overview['netBalance']),
                (overview['netBalance'] ?? 0) >= 0 ? green : red, darkBg),
          ]),
          pw.SizedBox(height: 12),
          pw.Row(children: [
            _pdfStatCard('Total Lent', _pf(overview['totalAmountLent']), green, darkBg),
            pw.SizedBox(width: 12),
            _pdfStatCard('Total Borrowed', _pf(overview['totalAmountBorrowed']), red, darkBg),
          ]),
          pw.SizedBox(height: 20),
          pw.Text('By Transaction Type', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: textDark)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1.5), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(1.5)},
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: lightGrey),
                children: ['Type', 'Count', 'Lent', 'Borrowed']
                    .map((h) => pw.Padding(padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: textDark))))
                    .toList(),
              ),
              for (final entry in [
                ['Quick',            byType['quick']?['count'],   byType['quick']?['amountLent'],  byType['quick']?['amountBorrowed']],
                ['Secure',           byType['secure']?['count'],  byType['secure']?['amountLent'], byType['secure']?['amountBorrowed']],
                ['Group (Expenses)', byType['group']?['count'],   byType['group']?['totalExpenses'], byType['group']?['yourShare']],
              ])
                pw.TableRow(children: [
                  for (final v in entry)
                    pw.Padding(padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(v == null ? '-' : (v is num ? _pf(v) : v.toString()),
                            style: pw.TextStyle(fontSize: 10, color: textDark)))
                ]),
            ],
          ),
          pw.SizedBox(height: 20),
          if (categories.isNotEmpty) ...[
            pw.Text('Spending by Category', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: textDark)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(2)},
              children: [
                pw.TableRow(decoration: pw.BoxDecoration(color: lightGrey),
                  children: ['Category', 'Txns', 'Amount']
                      .map((h) => pw.Padding(padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: textDark)))).toList()),
                for (final c in categories.take(9))
                  pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('${c['category']}'.capitalize(), style: pw.TextStyle(fontSize: 10, color: textDark))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('${c['count'] ?? 0}', style: pw.TextStyle(fontSize: 10, color: textDark))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(_pf(c['amount']), style: pw.TextStyle(fontSize: 10, color: textDark))),
                  ]),
              ],
            ),
            pw.SizedBox(height: 20),
          ],
          if (trend.isNotEmpty) ...[
            pw.Text('Monthly Trend', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: textDark)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {0: const pw.FlexColumnWidth(1.5), 1: const pw.FlexColumnWidth(2), 2: const pw.FlexColumnWidth(2), 3: const pw.FlexColumnWidth(2)},
              children: [
                pw.TableRow(decoration: pw.BoxDecoration(color: lightGrey),
                  children: ['Month', 'Lent', 'Borrowed', 'Group']
                      .map((h) => pw.Padding(padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))).toList()),
                for (final m in trend)
                  pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${m['label'] ?? ''}', style: pw.TextStyle(fontSize: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_pf(m['lent']), style: pw.TextStyle(fontSize: 10, color: green))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_pf(m['borrowed']), style: pw.TextStyle(fontSize: 10, color: red))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_pf(m['group']), style: pw.TextStyle(fontSize: 10, color: cyan))),
                  ]),
              ],
            ),
            pw.SizedBox(height: 20),
          ],
          if (topCp.isNotEmpty) ...[
            pw.Text('Top Contacts', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: textDark)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(2)},
              children: [
                pw.TableRow(decoration: pw.BoxDecoration(color: lightGrey),
                  children: ['Email', 'Transactions', 'Net Amount']
                      .map((h) => pw.Padding(padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)))).toList()),
                for (final cp in topCp)
                  pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${cp['email'] ?? '-'}', style: pw.TextStyle(fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${cp['count'] ?? 0}', style: pw.TextStyle(fontSize: 10))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_pf(cp['netAmount']), style: pw.TextStyle(fontSize: 10))),
                  ]),
              ],
            ),
          ],
          pw.SizedBox(height: 24),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),
          pw.Text('Generated by LenDen App — Confidential', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ],
      ));

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/lenden_report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf');
      await file.writeAsBytes(await doc.save());
      if (!mounted) return;
      setState(() => _generatingPdf = false);
      await OpenFile.open(file.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('pdf_downloaded')),
          backgroundColor: AppColors.cyan,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  pw.Widget _pdfStatCard(String label, String value, PdfColor accent, PdfColor bg) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: pw.TextStyle(color: PdfColors.grey, fontSize: 10)),
          pw.SizedBox(height: 6),
          pw.Text(value, style: pw.TextStyle(color: accent, fontSize: 18, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildCurrencySelector() {
    final currencies = _displayCurrencyData?.currencies ??
        const <Map<String, String>>[{'code': 'INR', 'symbol': '₹', 'label': ''}];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedDisplayCurrency,
            borderRadius: BorderRadius.circular(16),
            isDense: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            items: currencies.map((c) => DropdownMenuItem(
              value: c['code'],
              child: Text('${c['symbol']} ${c['code']}',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppThemeColors.primaryText(context))),
            )).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedDisplayCurrency = value);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context);

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: const DeepTopWaveClipper(),
              child: Container(height: context.sh(85), color: AppThemeColors.waveSolid(context)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 16, 0),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                      onPressed: () => Navigator.pop(context),
                      tooltip: t('back'),
                    ),
                    Expanded(
                      child: Text(t('reports_title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: context.sp(22), fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context))),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, color: AppThemeColors.primaryText(context)),
                      onPressed: _fetchReport,
                      tooltip: t('refresh'),
                    ),
                  ]),
                ),
                // Period chips
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: _periods.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final p = _periods[i];
                      final selected = p == _selectedPeriod;
                      return GestureDetector(
                        onTap: () {
                          if (p == 'custom') {
                            _pickCustomRange();
                          } else {
                            setState(() => _selectedPeriod = p);
                            _fetchReport();
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.cyan : AppThemeColors.cardBg(context),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: selected ? AppColors.cyan : AppThemeColors.border(context)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (p == 'custom') ...[
                              Icon(Icons.calendar_month_outlined, size: 13,
                                  color: selected ? Colors.white : AppThemeColors.secondaryText(context)),
                              const SizedBox(width: 4),
                            ],
                            Text(_periodLabel(p),
                                style: TextStyle(fontSize: context.sp(11),
                                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                    color: selected ? Colors.white : AppThemeColors.secondaryText(context))),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                // Currency selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(children: [
                    if (_displayCurrencyError != null)
                      Flexible(child: Text(_displayCurrencyError!,
                          style: TextStyle(fontSize: context.sp(11), color: Colors.orange))),
                    const Spacer(),
                    Text('Currency:', style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
                    const SizedBox(width: 8),
                    _buildCurrencySelector(),
                  ]),
                ),
                const SizedBox(height: 4),
                // TabBar
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: AppColors.cyan,
                  unselectedLabelColor: AppThemeColors.secondaryText(context),
                  indicatorColor: AppColors.cyan,
                  labelStyle: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold),
                  unselectedLabelStyle: TextStyle(fontSize: context.sp(12)),
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Income/Exp'),
                    Tab(text: 'Categories'),
                    Tab(text: 'Groups'),
                    Tab(text: 'Members'),
                    Tab(text: 'Trends'),
                    Tab(text: 'Charts'),
                    Tab(text: 'Export'),
                    Tab(text: 'Compare'),
                  ],
                ),
                // Body
                Expanded(
                  child: !session.hasFeature('reports')
                      ? const ReportsPremiumGate()
                      : _isLoading
                          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                          : _hasError
                              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
                                  const SizedBox(height: 12),
                                  Text(t('fetch_error_message'), style: TextStyle(color: AppThemeColors.secondaryText(context))),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: _fetchReport,
                                    icon: const Icon(Icons.refresh),
                                    label: Text(t('retry')),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: Colors.white),
                                  ),
                                ]))
                              : TabBarView(
                                  controller: _tabController,
                                  children: [
                                    OverviewTab(report: _report, ca: _ca),
                                    IncomeExpenseTab(report: _report, ca: _ca),
                                    CategoriesTab(report: _report, ca: _ca),
                                    GroupsTab(report: _report, ca: _ca),
                                    MembersTab(report: _report, ca: _ca),
                                    TrendsTab(report: _report, ca: _ca),
                                    ChartsTab(report: _report, ca: _ca),
                                    ExportTab(
                                      report: _report,
                                      isGeneratingPdf: _generatingPdf,
                                      isExportingCsv: _exportingCsv,
                                      onDownloadPdf: () => _downloadPdf(),
                                      onExportCsv: () => _exportCsv(),
                                      period: _selectedPeriod,
                                    ),
                                    ComparisonTab(report: _report, ca: _ca),
                                  ],
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

extension _StringX on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
