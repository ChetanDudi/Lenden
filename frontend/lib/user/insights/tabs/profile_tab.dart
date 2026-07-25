import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';

class ProfileTab extends StatelessWidget {
  final Map<String, dynamic>? financialPersonality;
  final List<Map<String, dynamic>> personalTimeline;
  final String Function(num?) ca;

  const ProfileTab({
    super.key,
    required this.financialPersonality,
    required this.personalTimeline,
    required this.ca,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(children: [
        _buildPersonalityCard(context),
        const SizedBox(height: 20),
        _buildTimeline(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildPersonalityCard(BuildContext context) {
    final p = financialPersonality;
    if (p == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: _cardBox(context),
        child: Center(child: Text('Not enough data yet to determine your financial personality.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: context.sp(13)))),
      );
    }

    final type    = p['type']        as String? ?? 'Balanced';
    final emoji   = p['emoji']       as String? ?? '⚖️';
    final tagline = p['tagline']     as String? ?? '';
    final rawDesc = p['description'] as String? ?? '';
    final traits  = (p['traits'] as List? ?? []).cast<String>();
    final color   = _personalityColor(type);

    // Guard against backend sending "Infinity%" when no budget limit is set
    final desc = rawDesc.contains('Infinity') || rawDesc.contains('NaN')
        ? 'You have no budget limit set yet — so we can\'t calculate how much over you are. Set a monthly budget to get accurate spending insights.'
        : rawDesc;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your Money Personality',
                style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context),
                    letterSpacing: 0.5)),
            Text(type,
                style: TextStyle(fontSize: context.sp(22), fontWeight: FontWeight.bold, color: color)),
            if (tagline.isNotEmpty)
              Text(tagline,
                  style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context),
                      fontStyle: FontStyle.italic)),
          ])),
        ]),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(desc,
              style: TextStyle(fontSize: context.sp(13), color: AppThemeColors.primaryText(context), height: 1.5)),
        ],
        if (traits.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: traits.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(t, style: TextStyle(fontSize: context.sp(11), color: color, fontWeight: FontWeight.w600)),
            )).toList(),
          ),
        ],
      ]),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    if (personalTimeline.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardBox(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Financial Journey',
            style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
        Text('Your last ${personalTimeline.length} months at a glance',
            style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 16),
        ...personalTimeline.asMap().entries.map((entry) {
          final i    = entry.key;
          final m    = entry.value;
          final isLast = i == personalTimeline.length - 1;
          final status = m['status'] as String? ?? 'no_budget';
          final label  = m['label']  as String? ?? '';
          final month  = m['month']  as String? ?? '';
          final spent  = (m['spent'] as num?)?.toDouble();
          final limit  = (m['limit'] as num?)?.toDouble();
          final isInactive = status == 'no_budget' && (spent == null || spent == 0);
          final color  = isInactive ? Colors.grey : _statusColor(status);
          final icon   = isInactive ? Icons.remove_circle_outline : _statusIcon(status);

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 32, child: Column(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withValues(alpha: 0.5)),
                      ),
                      child: Icon(icon, size: 14, color: color),
                    ),
                    if (!isLast)
                      Expanded(child: Center(
                        child: Container(width: 2, color: AppThemeColors.border(context)),
                      )),
                  ],
                )),
                const SizedBox(width: 12),
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(month,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: context.sp(13),
                              color: AppThemeColors.primaryText(context))),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(label,
                            style: TextStyle(fontSize: context.sp(10), color: color, fontWeight: FontWeight.bold)),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    if (isInactive)
                      Text('No transactions recorded',
                          style: TextStyle(fontSize: context.sp(11),
                              color: AppThemeColors.secondaryText(context).withValues(alpha: 0.5),
                              fontStyle: FontStyle.italic))
                    else if (spent != null)
                      Text(
                        limit != null && limit > 0
                            ? '${ca(spent)} spent of ${ca(limit)} limit'
                            : '${ca(spent)} spent · no limit set',
                        style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context)),
                      ),
                    if (!isInactive && limit != null && limit > 0 && spent != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (spent / limit).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: AppThemeColors.border(context),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ],
                  ]),
                )),
              ],
            ),
          );
        }),
      ]),
    );
  }

  Color _personalityColor(String type) {
    switch (type.toLowerCase()) {
      case 'super saver':        return Colors.teal;
      case 'heavy spender':      return Colors.red;
      case 'subscription lover': return Colors.deepPurple;
      case 'weekend shopper':    return Colors.orange;
      case 'foodie':             return Colors.amber.shade700;
      case 'explorer':           return Colors.blue;
      default:                   return AppColors.cyan;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'good':        return Colors.teal;
      case 'near_limit':  return Colors.orange;
      case 'overspent':   return Colors.red;
      default:            return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'good':        return Icons.check_circle_outline;
      case 'near_limit':  return Icons.warning_amber_rounded;
      case 'overspent':   return Icons.cancel_outlined;
      default:            return Icons.radio_button_unchecked;
    }
  }

  BoxDecoration _cardBox(BuildContext context) => BoxDecoration(
    color: AppThemeColors.cardBg(context),
    borderRadius: BorderRadius.circular(20),
    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
  );
}
