import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';

class DueDateCalendarPage extends StatefulWidget {
  const DueDateCalendarPage({super.key});

  @override
  State<DueDateCalendarPage> createState() => _DueDateCalendarPageState();
}

class _DueDateCalendarPageState extends State<DueDateCalendarPage> {
  bool _loading = true;
  String? _error;
  Map<String, List<Map<String, dynamic>>> _itemsByDay = {};
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  @override
  void initState() {
    super.initState();
    _fetchDueDates();
  }

  String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _fetchDueDates() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/calendar/due-dates');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final item in items) {
          final dt = DateTime.tryParse((item['date'] ?? '').toString());
          if (dt == null) continue;
          final key = _dayKey(DateTime(dt.year, dt.month, dt.day));
          grouped.putIfAbsent(key, () => []).add(item);
        }
        setState(() {
          _itemsByDay = grouped;
          _loading = false;
        });
      } else {
        setState(() { _error = 'Failed to load due dates. Please try again.'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Failed to load due dates. Please try again.'; _loading = false; });
    }
  }

  List<DateTime> _gridDays() {
    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final leading = firstOfMonth.weekday % 7; // Sunday = 0
    final gridStart = firstOfMonth.subtract(Duration(days: leading));
    return List.generate(42, (i) => gridStart.add(Duration(days: i)));
  }

  Color _dotColor(Map<String, dynamic> item) {
    if (item['type'] == 'recurring_template') return Colors.purple;
    final cleared = item['cleared'] == true;
    if (cleared) return Colors.green;
    final date = DateTime.tryParse((item['date'] ?? '').toString());
    if (date != null && date.isBefore(DateTime.now())) return Colors.red;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final days = _gridDays();
    final today = DateTime.now();
    final selectedItems = _itemsByDay[_dayKey(_selectedDay)] ?? [];

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text('Due Date Calendar',
            style: TextStyle(color: AppThemeColors.primaryText(context), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? errorStateWidget(context, _error!, _fetchDueDates)
              : RefreshIndicator(
              onRefresh: _fetchDueDates,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left_rounded),
                              onPressed: () => setState(() {
                                _focusedMonth =
                                    DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                              }),
                            ),
                            Text(DateFormat('MMMM yyyy').format(_focusedMonth),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.chevron_right_rounded),
                              onPressed: () => setState(() {
                                _focusedMonth =
                                    DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                              .map((d) => Expanded(
                                    child: Center(
                                      child: Text(d,
                                          style: TextStyle(
                                              color: AppThemeColors.mutedText(context),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12)),
                                    ),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 4),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7),
                          itemCount: days.length,
                          itemBuilder: (context, index) {
                            final day = days[index];
                            final inMonth = day.month == _focusedMonth.month;
                            final isToday = day.year == today.year &&
                                day.month == today.month &&
                                day.day == today.day;
                            final isSelected = day.year == _selectedDay.year &&
                                day.month == _selectedDay.month &&
                                day.day == _selectedDay.day;
                            final dayItems = _itemsByDay[_dayKey(day)] ?? [];

                            return GestureDetector(
                              onTap: () => setState(() => _selectedDay = day),
                              child: Container(
                                margin: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.cyan
                                      : isToday
                                          ? AppColors.cyan.withValues(alpha: 0.15)
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        color: !inMonth
                                            ? Colors.grey[400]
                                            : isSelected
                                                ? Colors.white
                                                : AppThemeColors.primaryText(context),
                                        fontWeight:
                                            isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (dayItems.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: dayItems
                                              .take(3)
                                              .map((item) => Container(
                                                    margin: const EdgeInsets.symmetric(horizontal: 1),
                                                    width: 5,
                                                    height: 5,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: isSelected
                                                          ? Colors.white
                                                          : _dotColor(item),
                                                    ),
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(DateFormat('EEEE, MMM dd, yyyy').format(_selectedDay),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  if (selectedItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No due dates on this day.',
                            style: TextStyle(color: AppThemeColors.mutedText(context))),
                      ),
                    )
                  else
                    ...selectedItems.map((item) {
                      final isTemplate = item['type'] == 'recurring_template';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppThemeColors.cardBg(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border(left: BorderSide(color: _dotColor(item), width: 4)),
                        ),
                        child: Row(
                            children: [
                              Icon(
                                isTemplate ? Icons.repeat_rounded : Icons.event_rounded,
                                color: _dotColor(item),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item['currency'] ?? ''} ${item['amount']} • ${item['counterpartyEmail'] ?? ''}',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                    Text(
                                      isTemplate
                                          ? 'Recurring (${item['frequency']})'
                                          : (item['cleared'] == true ? 'Cleared' : 'Due • ${item['role']}'),
                                      style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
