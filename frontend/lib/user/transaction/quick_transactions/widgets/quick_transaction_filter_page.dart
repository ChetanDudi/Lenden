import 'package:flutter/material.dart';
import '../../../../widgets/app_colors.dart';
import '../../../../utils/theme_helper.dart';
import '../../../../l10n/app_localizations.dart';

const kQuickTransactionCategories = [
  {'key': 'food',          'label': 'Food',          'icon': Icons.restaurant_rounded},
  {'key': 'transport',     'label': 'Transport',     'icon': Icons.directions_car_rounded},
  {'key': 'accommodation', 'label': 'Stay',          'icon': Icons.hotel_rounded},
  {'key': 'entertainment', 'label': 'Fun',           'icon': Icons.sports_esports_rounded},
  {'key': 'shopping',      'label': 'Shopping',      'icon': Icons.shopping_cart_rounded},
  {'key': 'utilities',     'label': 'Utilities',     'icon': Icons.electrical_services_rounded},
  {'key': 'medical',       'label': 'Medical',       'icon': Icons.local_hospital_rounded},
  {'key': 'education',     'label': 'Education',     'icon': Icons.school_rounded},
  {'key': 'personal',      'label': 'Personal',      'icon': Icons.person_rounded},
  {'key': 'rent',          'label': 'Rent',          'icon': Icons.home_rounded},
  {'key': 'business',      'label': 'Business',      'icon': Icons.business_center_rounded},
  {'key': 'travel',        'label': 'Travel',        'icon': Icons.flight_rounded},
  {'key': 'other',         'label': 'Other',         'icon': Icons.more_horiz_rounded},
];

class QuickTransactionFilterPage extends StatefulWidget {
  final List<Map<String, String>> counterpartyOptions;

  const QuickTransactionFilterPage({
    super.key,
    required this.counterpartyOptions,
  });

  @override
  State<QuickTransactionFilterPage> createState() =>
      _QuickTransactionFilterPageState();
}

class _QuickTransactionFilterPageState
    extends State<QuickTransactionFilterPage> {
  String _status = 'all';
  String _role = 'all';
  String _date = 'all';
  String _counterparty = 'all';
  String _category = 'all';
  bool _favouritesOnly = false;

  String _counterpartyLabel(String value) {
    final t = AppLocalizations.of(context).t;
    final match = widget.counterpartyOptions.firstWhere(
      (item) => item['email'] == value,
      orElse: () => {'label': t('all_people_label')},
    );
    return match['label'] ?? t('all_people_label');
  }

  Widget _buildCategoryChip(String key, String label, IconData icon) {
    final selected = _category == key;
    return GestureDetector(
      onTap: () => setState(() => _category = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple : AppThemeColors.surfaceBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.deepPurple : AppThemeColors.border(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : Colors.deepPurple),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppThemeColors.primaryText(context),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Color? backgroundColor,
  }) {
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
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: backgroundColor ?? AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.cyan),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppThemeColors.secondaryText(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceRow({
    required String label,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    final selected = groupValue == value;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppThemeColors.tinted(context,
                  light: const Color(0xFFE9F8FC), dark: const Color(0xFF173238))
              : AppThemeColors.surfaceBg(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.cyan : AppThemeColors.border(context),
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              activeColor: AppColors.cyan,
              onChanged: onChanged,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCounterpartyPicker() async {
    final t = AppLocalizations.of(context).t;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 18),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(sheetContext),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppThemeColors.border(sheetContext),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppThemeColors.surfaceBg(sheetContext),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.people_alt_outlined,
                              color: AppColors.cyan,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              t('choose_counterparty_title'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppThemeColors.primaryText(sheetContext),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.45,
                      child: ListView.builder(
                        itemCount: widget.counterpartyOptions.length,
                        itemBuilder: (context, index) {
                          final item = widget.counterpartyOptions[index];
                          final email = item['email'] ?? 'all';
                          final label = item['label'] ?? t('all_people_label');
                          final selected = _counterparty == email;
                          final isAll = email == 'all';
                          return InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.of(sheetContext).pop(email),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppThemeColors.tinted(context,
                                        light: const Color(0xFFEAF9FD),
                                        dark: const Color(0xFF173238))
                                    : AppThemeColors.cardBg(context),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.cyan
                                      : AppThemeColors.border(context),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Radio<String>(
                                    value: email,
                                    groupValue: _counterparty,
                                    activeColor: AppColors.cyan,
                                    onChanged: (_) =>
                                        Navigator.of(sheetContext).pop(email),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: isAll
                                          ? AppThemeColors.tinted(context,
                                              light: const Color(0xFFEDF7FA),
                                              dark: const Color(0xFF173238))
                                          : AppThemeColors.tinted(context,
                                              light: const Color(0xFFF4F7FF),
                                              dark: const Color(0xFF1E2233)),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      isAll
                                          ? Icons.groups_rounded
                                          : Icons.person_rounded,
                                      color: isAll
                                          ? AppColors.cyan
                                          : const Color(0xFF3B82F6),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Text(
                                            label,
                                            maxLines: 1,
                                            softWrap: false,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: selected
                                                  ? FontWeight.w800
                                                  : FontWeight.w700,
                                              color: AppThemeColors.primaryText(
                                                  context),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          isAll
                                              ? t('show_every_person_in_quick_transactions_message')
                                              : t('filter_quick_transactions_for_counterparty_message'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppThemeColors.secondaryText(
                                                context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    setState(() => _counterparty = selected);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppThemeColors.cardBg(context),
        foregroundColor: AppThemeColors.primaryText(context),
        elevation: 0,
        title: Text(
          t('quick_transaction_filters_title'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _buildSection(
                    icon: Icons.check_circle_outline_rounded,
                    title: t('status_label'),
                    subtitle: t('choose_transaction_status_message'),
                    backgroundColor: AppThemeColors.tinted(context,
                        light: const Color(0xFFFFFCF7),
                        dark: const Color(0xFF2A2620)),
                    child: Column(
                      children: [
                        _buildChoiceRow(
                          label: t('all_transactions_label'),
                          value: 'all',
                          groupValue: _status,
                          onChanged: (value) =>
                              setState(() => _status = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: t('cleared_only_label'),
                          value: 'cleared',
                          groupValue: _status,
                          onChanged: (value) =>
                              setState(() => _status = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: t('not_cleared_label'),
                          value: 'not_cleared',
                          groupValue: _status,
                          onChanged: (value) =>
                              setState(() => _status = value ?? 'all'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    icon: Icons.swap_vert_circle_outlined,
                    title: t('role_label'),
                    subtitle: t('focus_on_lent_or_borrowed_message'),
                    backgroundColor: AppThemeColors.tinted(context,
                        light: const Color(0xFFF7FAFF),
                        dark: const Color(0xFF1E2233)),
                    child: Column(
                      children: [
                        _buildChoiceRow(
                          label: t('all_roles_label'),
                          value: 'all',
                          groupValue: _role,
                          onChanged: (value) =>
                              setState(() => _role = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: t('you_lent_label'),
                          value: 'lent',
                          groupValue: _role,
                          onChanged: (value) =>
                              setState(() => _role = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: t('you_borrowed_label'),
                          value: 'borrowed',
                          groupValue: _role,
                          onChanged: (value) =>
                              setState(() => _role = value ?? 'all'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    icon: Icons.date_range_rounded,
                    title: t('date_range_label'),
                    subtitle: t('pick_quick_date_window_message'),
                    backgroundColor: AppThemeColors.tinted(context,
                        light: const Color(0xFFF7FBF8),
                        dark: const Color(0xFF1A2A1E)),
                    child: Column(
                      children: [
                        _buildChoiceRow(
                          label: t('all_time_label'),
                          value: 'all',
                          groupValue: _date,
                          onChanged: (value) =>
                              setState(() => _date = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: t('today'),
                          value: 'today',
                          groupValue: _date,
                          onChanged: (value) =>
                              setState(() => _date = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: t('this_week'),
                          value: 'week',
                          groupValue: _date,
                          onChanged: (value) =>
                              setState(() => _date = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: t('this_month'),
                          value: 'month',
                          groupValue: _date,
                          onChanged: (value) =>
                              setState(() => _date = value ?? 'all'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    icon: Icons.people_alt_outlined,
                    title: t('counterparty_label'),
                    subtitle: t('pick_person_cleaner_list_view_message'),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _showCounterpartyPicker,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppThemeColors.surfaceBg(context),
                          borderRadius: BorderRadius.circular(18),
                          border:
                              Border.all(color: AppThemeColors.border(context)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppThemeColors.tinted(context,
                                    light: const Color(0xFFEAF7FB),
                                    dark: const Color(0xFF173238)),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.people_alt_outlined,
                                color: AppColors.cyan,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t('selected_person_label'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          AppThemeColors.secondaryText(context),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      _counterpartyLabel(_counterparty),
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color:
                                            AppThemeColors.primaryText(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppThemeColors.surfaceBg(context),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppThemeColors.secondaryText(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    icon: Icons.category_rounded,
                    title: 'Category',
                    subtitle: 'Filter by transaction category',
                    backgroundColor: AppThemeColors.tinted(context,
                        light: const Color(0xFFF5F0FF),
                        dark: const Color(0xFF1E1A2A)),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildCategoryChip('all', 'All', Icons.apps_rounded),
                        ...kQuickTransactionCategories.map((cat) => _buildCategoryChip(
                              cat['key'] as String,
                              cat['label'] as String,
                              cat['icon'] as IconData,
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    icon: Icons.favorite_border_rounded,
                    title: t('favourite_filter_label'),
                    subtitle: t('enable_disable_control_shown_in_front_message'),
                    backgroundColor: AppThemeColors.tinted(context,
                        light: const Color(0xFFFFF8FA),
                        dark: const Color(0xFF2A1E22)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppThemeColors.surfaceBg(context),
                        borderRadius: BorderRadius.circular(18),
                        border:
                            Border.all(color: AppThemeColors.border(context)),
                      ),
                      child: Row(
                        children: [
                          Switch(
                            value: _favouritesOnly,
                            activeColor: AppColors.cyan,
                            onChanged: (value) =>
                                setState(() => _favouritesOnly = value),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                t('show_favourites_only_label'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppThemeColors.primaryText(context),
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
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              color: AppThemeColors.cardBg(context),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _status = 'all';
                          _role = 'all';
                          _date = 'all';
                          _counterparty = 'all';
                          _category = 'all';
                          _favouritesOnly = false;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.cyan),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        t('reset_label'),
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop({
                          'status': _status,
                          'role': _role,
                          'date': _date,
                          'counterparty': _counterparty,
                          'category': _category,
                          'favourites': _favouritesOnly,
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        t('apply_filters_label'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
