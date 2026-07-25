import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class GoalsTab extends StatelessWidget {
  final List<Map<String, dynamic>> goals;
  final String Function(num?) ca;
  final Future<void> Function(Map<String, dynamic>) onCreateGoal;
  final Future<void> Function(String id, double amount) onAddToGoal;
  final Future<void> Function(String id) onDeleteGoal;

  const GoalsTab({
    super.key,
    required this.goals,
    required this.ca,
    required this.onCreateGoal,
    required this.onAddToGoal,
    required this.onDeleteGoal,
  });

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.isSubscribed) {
      return const PremiumTabGate(
        featureName: 'Savings Goals',
        description: 'Set multiple savings goals with deadlines, track progress, and get forecasts.',
        icon: Icons.savings_outlined,
        accentColor: Colors.teal,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Savings Goals',
              style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          const Spacer(),
          GestureDetector(
            onTap: () => _showAddGoalDialog(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add, size: 14, color: AppColors.cyan),
                const SizedBox(width: 4),
                Text('Add Goal', style: TextStyle(fontSize: context.sp(11), color: AppColors.cyan, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        if (goals.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppThemeColors.border(context)),
            ),
            child: Column(children: [
              const Text('🎯', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 10),
              Text('No savings goals yet', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
              const SizedBox(height: 4),
              Text('Tap "Add Goal" to create your first goal', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
            ]),
          )
        else
          for (final goal in goals) ...[
            _buildGoalCard(context, goal),
            const SizedBox(height: 12),
          ],
      ]),
    );
  }

  Widget _buildGoalCard(BuildContext context, Map<String, dynamic> goal) {
    final id          = goal['_id']          as String? ?? '';
    final name        = goal['name']         as String? ?? '';
    final emoji       = goal['emoji']        as String? ?? '🎯';
    final target      = (goal['targetAmount'] as num?)?.toDouble() ?? 0;
    final saved       = (goal['savedAmount']  as num?)?.toDouble() ?? 0;
    final isCompleted = goal['isCompleted']   as bool? ?? false;
    final colorHex    = goal['color']         as String? ?? '#00BCD4';
    final pct         = target > 0 ? (saved / target).clamp(0.0, 1.0) : 0.0;
    final remaining   = (target - saved).clamp(0.0, double.infinity);

    Color goalColor;
    try { goalColor = Color(int.parse(colorHex.replaceFirst('#', '0xFF'))); }
    catch (_) { goalColor = AppColors.cyan; }

    String? deadlineText;
    if (goal['deadline'] != null) {
      try {
        final d = DateTime.parse(goal['deadline'] as String);
        final days = d.difference(DateTime.now()).inDays;
        deadlineText = days < 0 ? 'Overdue by ${-days}d' : '$days days left';
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isCompleted ? Colors.green.withValues(alpha: 0.4) : goalColor.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            if (deadlineText != null)
              Text(deadlineText, style: TextStyle(fontSize: context.sp(10),
                  color: deadlineText.startsWith('Overdue') ? Colors.red : AppThemeColors.secondaryText(context))),
          ])),
          if (isCompleted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text('✓ Completed', style: TextStyle(fontSize: context.sp(10), color: Colors.green, fontWeight: FontWeight.bold)),
            )
          else
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'add')    _showAddSavingsDialog(context, id, name, target - saved);
                if (val == 'delete') onDeleteGoal(id);
              },
              icon: Icon(Icons.more_vert, size: 18, color: AppThemeColors.secondaryText(context)),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add',    child: Text('Add Savings')),
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(ca(saved),          style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: goalColor)),
          Text('of ${ca(target)}', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
        ]),
        const SizedBox(height: 6),
        Stack(children: [
          Container(height: 8, decoration: BoxDecoration(color: AppThemeColors.border(context), borderRadius: BorderRadius.circular(4))),
          FractionallySizedBox(
            widthFactor: pct,
            child: Container(height: 8, decoration: BoxDecoration(
              gradient: LinearGradient(colors: [goalColor.withValues(alpha: 0.6), goalColor]),
              borderRadius: BorderRadius.circular(4),
            )),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text('${(pct * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold, color: goalColor)),
          const Spacer(),
          if (!isCompleted) Text('${ca(remaining)} to go', style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        ]),
      ]),
    );
  }

  static const _emojiOptions = ['🎯', '💻', '🏠', '✈️', '🚗', '📱', '🎓', '💍', '🏖️', '💰'];

  void _showAddGoalDialog(BuildContext context) {
    final nameCtrl   = TextEditingController();
    final targetCtrl = TextEditingController();
    final savedCtrl  = TextEditingController();
    String selectedEmoji = '🎯';
    DateTime? deadline;
    String? nameError;
    String? targetError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: AppThemeColors.cardBg(context),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.cyan.withValues(alpha: 0.12), Colors.teal.withValues(alpha: 0.06)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.savings_outlined, color: AppColors.cyan, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('New Savings Goal',
                      style: TextStyle(fontSize: context.sp(16), fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context))),
                  Text('Set a target and track progress', style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
                ])),
              ]),
            ),

            Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Emoji picker row
              Text('Pick an icon',
                  style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.w600,
                      color: AppThemeColors.secondaryText(context))),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, children: _emojiOptions.map((e) =>
                  GestureDetector(
                    onTap: () => setD(() => selectedEmoji = e),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 8),
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: selectedEmoji == e
                            ? AppColors.cyan.withValues(alpha: 0.15)
                            : AppThemeColors.border(context).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: selectedEmoji == e
                            ? Border.all(color: AppColors.cyan, width: 1.5)
                            : null,
                      ),
                      child: Center(child: Text(e, style: const TextStyle(fontSize: 22))),
                    ),
                  ),
                ).toList()),
              ),
              const SizedBox(height: 14),

              // Goal name
              _goalField(context, nameCtrl, 'Goal name (e.g. New Laptop)',
                  Icons.label_outline_rounded, errorText: nameError),
              const SizedBox(height: 10),

              // Target amount
              _goalField(context, targetCtrl, 'Target amount',
                  Icons.flag_outlined,
                  prefixText: '₹ ',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  errorText: targetError),
              const SizedBox(height: 10),

              // Already saved
              _goalField(context, savedCtrl, 'Already saved (optional)',
                  Icons.savings_outlined,
                  prefixText: '₹ ',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]),
              const SizedBox(height: 10),

              // Deadline picker
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 90)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2040),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: Theme.of(ctx).colorScheme.copyWith(
                          primary: AppColors.cyan,
                          onPrimary: Colors.white,
                        ),
                        textButtonTheme: TextButtonThemeData(
                          style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) setD(() => deadline = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(color: deadline != null ? AppColors.cyan : AppThemeColors.border(context)),
                    borderRadius: BorderRadius.circular(12),
                    color: deadline != null ? AppColors.cyan.withValues(alpha: 0.06) : null,
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_month_outlined, size: 18,
                        color: deadline != null ? AppColors.cyan : AppThemeColors.secondaryText(context)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      deadline == null ? 'Set deadline (optional)' : DateFormat('d MMM yyyy').format(deadline!),
                      style: TextStyle(fontSize: context.sp(13),
                          color: deadline == null ? AppThemeColors.secondaryText(context) : AppThemeColors.primaryText(context)),
                    )),
                    if (deadline != null)
                      GestureDetector(
                        onTap: () => setD(() => deadline = null),
                        child: Icon(Icons.close, size: 16, color: AppThemeColors.secondaryText(context)),
                      ),
                  ]),
                ),
              ),
            ])),

            Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), child: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: AppThemeColors.border(context))),
                child: Text('Cancel', style: TextStyle(color: AppThemeColors.secondaryText(context))),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0),
                onPressed: () {
                  final name   = nameCtrl.text.trim();
                  final target = double.tryParse(targetCtrl.text);
                  bool valid   = true;
                  if (name.isEmpty) { setD(() => nameError = 'Enter a goal name'); valid = false; }
                  else { setD(() => nameError = null); }
                  if (target == null || target <= 0) { setD(() => targetError = 'Enter a valid target amount'); valid = false; }
                  else { setD(() => targetError = null); }
                  if (!valid) return;
                  Navigator.pop(ctx);
                  onCreateGoal({
                    'name': name,
                    'emoji': selectedEmoji,
                    'targetAmount': target,
                    'savedAmount': double.tryParse(savedCtrl.text) ?? 0,
                    if (deadline != null) 'deadline': deadline!.toIso8601String(),
                  });
                },
                child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold)),
              )),
            ])),
          ])),
        ),
      ),
    );
  }

  Widget _goalField(
    BuildContext context,
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    String? prefixText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: TextStyle(fontSize: context.sp(13), color: AppThemeColors.primaryText(context)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context)),
          prefixIcon: Icon(icon, size: 18, color: AppThemeColors.secondaryText(context)),
          prefixText: prefixText,
          errorText: errorText,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppThemeColors.border(context))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.cyan, width: 1.5)),
        ),
      );

  void _showAddSavingsDialog(BuildContext context, String id, String name, double maxAdd) {
    final ctrl = TextEditingController();
    String? amountError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: AppThemeColors.cardBg(context),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Teal header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.cyan.withValues(alpha: 0.12), Colors.teal.withValues(alpha: 0.06)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_circle_outline_rounded, color: AppColors.cyan, size: 26),
                ),
                const SizedBox(height: 12),
                Text('Add to Goal',
                    style: TextStyle(fontSize: context.sp(16), fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 4),
                Text(name,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: context.sp(12), color: AppColors.cyan, fontWeight: FontWeight.w600)),
                if (maxAdd > 0) ...[
                  const SizedBox(height: 4),
                  Text('${ca(maxAdd)} remaining to reach target',
                      style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
                ],
              ]),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                style: TextStyle(fontSize: context.sp(15), color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  hintText: 'Amount to add',
                  hintStyle: TextStyle(fontSize: context.sp(13), color: AppThemeColors.secondaryText(context)),
                  prefixIcon: const Icon(Icons.savings_outlined, size: 18, color: AppColors.cyan),
                  prefixText: '₹ ',
                  errorText: amountError,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppThemeColors.border(context))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.cyan, width: 1.5)),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: AppThemeColors.border(context)),
                  ),
                  child: Text('Cancel',
                      style: TextStyle(color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    final amt = double.tryParse(ctrl.text);
                    if (amt == null || amt <= 0) {
                      setD(() => amountError = 'Enter a valid amount');
                      return;
                    }
                    Navigator.pop(ctx);
                    onAddToGoal(id, amt);
                  },
                  child: const Text('Add Savings', style: TextStyle(fontWeight: FontWeight.bold)),
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
