import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/api_client.dart';
import '../utils/responsive.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class BudgetLimitBanner extends StatefulWidget {
  final String type;
  final VoidCallback? onViewMessages;
  final VoidCallback? onTap;
  final int refreshTrigger;

  const BudgetLimitBanner({
    super.key,
    required this.type,
    this.onViewMessages,
    this.onTap,
    this.refreshTrigger = 0,
  });

  @override
  State<BudgetLimitBanner> createState() => _BudgetLimitBannerState();
}

class _BudgetLimitBannerState extends State<BudgetLimitBanner>
    with SingleTickerProviderStateMixin {
  double? _spent;
  double? _limit;
  double  _overallCap  = 0;
  double  _quickLimit  = 0;
  double  _secureLimit = 0;
  double  _groupLimit  = 0;
  bool    _loaded      = false;
  bool    _error       = false;

  late final AnimationController _pulse;
  late final Animation<double>   _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 0.75).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _fetch();
  }

  @override
  void didUpdateWidget(covariant BudgetLimitBanner old) {
    super.didUpdateWidget(old);
    if (old.refreshTrigger != widget.refreshTrigger) _fetch();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await ApiClient.get('/api/budget/status');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data   = json.decode(res.body) as Map<String, dynamic>;
        final limits = data['limits'] as Map? ?? {};
        final spent  = data['spent']  as Map? ?? {};
        setState(() {
          _spent       = (spent[widget.type]   as num?)?.toDouble();
          _limit       = (limits[widget.type]  as num?)?.toDouble();
          _overallCap  = (limits['overall']    as num? ?? 0).toDouble();
          _quickLimit  = (limits['quick']      as num? ?? 0).toDouble();
          _secureLimit = (limits['secure']     as num? ?? 0).toDouble();
          _groupLimit  = (limits['group']      as num? ?? 0).toDouble();
          _loaded = true;
        });
      } else {
        setState(() { _loaded = true; _error = true; });
      }
    } catch (_) {
      if (mounted) setState(() { _loaded = true; _error = true; });
    }
  }

  // Headroom = overall cap minus every OTHER type's set limit
  double get _availableFromOverall {
    if (_overallCap <= 0) return 0;
    double others = 0;
    if (widget.type != 'quick')  others += _quickLimit;
    if (widget.type != 'secure') others += _secureLimit;
    if (widget.type != 'group')  others += _groupLimit;
    return (_overallCap - others).clamp(0.0, double.infinity);
  }

  Color _color(double ratio) {
    if (ratio >= 1.0)  return Colors.red.shade600;
    if (ratio >= 0.85) return Colors.orange.shade700;
    return Colors.teal;
  }

  Color get _typeColor {
    switch (widget.type) {
      case 'quick':  return Colors.amber.shade700;
      case 'secure': return Colors.teal;
      case 'group':  return Colors.deepPurple;
      default:       return Colors.teal;
    }
  }

  IconData _icon() {
    switch (widget.type) {
      case 'quick':  return Icons.flash_on_outlined;
      case 'secure': return Icons.shield_outlined;
      case 'group':  return Icons.group_outlined;
      default:       return Icons.account_balance_wallet_outlined;
    }
  }

  String _label() {
    switch (widget.type) {
      case 'quick':  return 'Quick';
      case 'secure': return 'Secure';
      case 'group':  return 'Group';
      default:       return widget.type;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return _buildSkeleton(context);
    if (_error)   return const SizedBox.shrink();

    final hasOwnLimit = _limit != null && _limit! > 0;

    // No own limit set — show overall cap headroom if available
    if (!hasOwnLimit) {
      if (_overallCap <= 0) return const SizedBox.shrink();
      return _buildOverallHint(context);
    }

    // Own limit is set — show full progress strip
    final spent    = _spent ?? 0;
    final limit    = _limit!;
    final ratio    = spent / limit;
    final pct      = ratio.clamp(0.0, 1.0);
    final exceeded = spent > limit;
    final remaining = (limit - spent).clamp(0.0, double.infinity);
    final color    = _color(ratio);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: exceeded ? 0.45 : 0.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_icon(), color: color, size: 15),
          const SizedBox(width: 6),
          Text('${_label()} Budget',
              style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.w700, color: color)),
          const Spacer(),
          Text(
            exceeded
                ? '₹${spent.toStringAsFixed(0)} / ₹${limit.toStringAsFixed(0)}'
                : '₹${remaining.toStringAsFixed(0)} left',
            style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: color),
          ),
          if (exceeded) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onViewMessages,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('Messages',
                    style: TextStyle(
                        fontSize: context.sp(9),
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: AppThemeColors.border(context),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text('Spent: ₹${spent.toStringAsFixed(0)}',
              style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
          const Spacer(),
          Text('Limit: ₹${limit.toStringAsFixed(0)}',
              style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        ]),
        Builder(builder: (_) {
          final now = DateTime.now();
          final daysElapsed = now.day;
          final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
          if (daysElapsed < 1 || exceeded) return const SizedBox.shrink();
          final dailyRate = spent / daysElapsed;
          final projected = dailyRate * daysInMonth;
          if (projected <= limit) return const SizedBox.shrink();
          final remaining = (limit - spent).clamp(0.0, double.infinity);
          final daysToExceed = dailyRate > 0 ? (remaining / dailyRate).ceil() : 0;
          final exceedDate = now.add(Duration(days: daysToExceed));
          final monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
          final dateStr = '${exceedDate.day} ${monthNames[exceedDate.month - 1]}';
          final label = AppLocalizations.of(context).t('budget_velocity_label')
              .replaceAll('{rate}', dailyRate.toStringAsFixed(0))
              .replaceAll('{date}', dateStr);
          return Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(label,
              style: TextStyle(fontSize: context.sp(10), color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
          );
        }),
      ]),
      ),
    );
  }

  Widget _buildOverallHint(BuildContext context) {
    final available = _availableFromOverall;
    final color = _typeColor;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(Icons.account_balance_wallet_outlined, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No ${_label()} budget limit set',
                style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.w600,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 2),
            Text(
              available > 0
                  ? '₹${available.toStringAsFixed(0)} available from Overall Cap'
                  : 'No headroom left in Overall Cap',
              style: TextStyle(
                fontSize: context.sp(11),
                fontWeight: FontWeight.bold,
                color: available > 0 ? color : Colors.red.shade600,
              ),
            ),
          ])),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Set limit',
                style: TextStyle(fontSize: context.sp(10), color: color, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppThemeColors.border(context).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppThemeColors.border(context)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _skeletonBox(context, width: 15, height: 15, radius: 4),
              const SizedBox(width: 8),
              _skeletonBox(context, width: 90, height: 12, radius: 4),
              const Spacer(),
              _skeletonBox(context, width: 60, height: 12, radius: 4),
            ]),
            const SizedBox(height: 8),
            _skeletonBox(context, width: double.infinity, height: 5, radius: 3),
            const SizedBox(height: 6),
            Row(children: [
              _skeletonBox(context, width: 70, height: 10, radius: 3),
              const Spacer(),
              _skeletonBox(context, width: 70, height: 10, radius: 3),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _skeletonBox(BuildContext context,
      {required double width, required double height, required double radius}) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        color: AppThemeColors.secondaryText(context).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
