import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class ExportTab extends StatelessWidget {
  final Map<String, dynamic>? report;
  final bool isGeneratingPdf;
  final bool isExportingCsv;
  final VoidCallback onDownloadPdf;
  final VoidCallback onExportCsv;
  final String period;

  const ExportTab({
    super.key,
    required this.report,
    required this.isGeneratingPdf,
    required this.isExportingCsv,
    required this.onDownloadPdf,
    required this.onExportCsv,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.isSubscribed) {
      return const PremiumTabGate(
        featureName: 'Export Reports',
        description: 'Download your financial data as PDF or CSV for any period.',
        icon: Icons.picture_as_pdf_outlined,
        accentColor: AppColors.cyan,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.cyan.withValues(alpha: 0.12), Colors.deepPurple.withValues(alpha: 0.06)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
          ),
          child: Column(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.download_rounded, color: AppColors.cyan, size: 28),
            ),
            const SizedBox(height: 12),
            Text('Export Your Report',
                style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 4),
            Text('Period: ${_periodLabel(period)}',
                style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
          ]),
        ),
        const SizedBox(height: 24),

        // PDF export
        _exportCard(
          context,
          icon: Icons.picture_as_pdf_rounded,
          color: Colors.red.shade400,
          title: 'PDF Report',
          subtitle: 'Formatted report with charts, stats and transaction breakdown',
          buttonLabel: isGeneratingPdf ? 'Generating PDF…' : 'Download PDF',
          loading: isGeneratingPdf,
          enabled: report != null && !isGeneratingPdf,
          onTap: onDownloadPdf,
        ),
        const SizedBox(height: 16),

        // CSV export
        _exportCard(
          context,
          icon: Icons.table_chart_outlined,
          color: Colors.teal,
          title: 'CSV Spreadsheet',
          subtitle: 'Raw transaction data in comma-separated format, compatible with Excel',
          buttonLabel: isExportingCsv ? 'Exporting…' : 'Export CSV',
          loading: isExportingCsv,
          enabled: report != null && !isExportingCsv,
          onTap: onExportCsv,
        ),
        const SizedBox(height: 24),

        // Info note
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppThemeColors.border(context)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 16, color: AppThemeColors.secondaryText(context)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Exported files are saved to your device\'s Downloads folder. '
              'You can share them via email, WhatsApp, or any other app.',
              style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.5),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _exportCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required bool loading,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            Text(subtitle, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.4)),
          ])),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: enabled ? onTap : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: color.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(buttonLabel,
                    style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

  String _periodLabel(String p) {
    switch (p) {
      case 'today':     return 'Today';
      case 'weekly':    return 'This Week';
      case '30d':       return 'Last 30 Days';
      case '3m':        return 'Last 3 Months';
      case 'quarterly': return 'This Quarter';
      case '6m':        return 'Last 6 Months';
      case '1y':        return 'This Year';
      case 'custom':    return 'Custom Period';
      default:          return p;
    }
  }
}
