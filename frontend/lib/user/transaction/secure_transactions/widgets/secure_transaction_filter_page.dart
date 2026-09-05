import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../../widgets/app_colors.dart';
import '../../../../../utils/theme_helper.dart';
import '../../../../../utils/transaction_constants.dart';

const kSecureCategories = kTxCategories;

class SecureTransactionFilterPage extends StatefulWidget {
  final List<Map<String, String>> counterpartyOptions;

  const SecureTransactionFilterPage({
    super.key,
    required this.counterpartyOptions,
  });

  @override
  State<SecureTransactionFilterPage> createState() =>
      _SecureTransactionFilterPageState();
}

class _SecureTransactionFilterPageState
    extends State<SecureTransactionFilterPage> {
  // Existing filters
  String _role = 'All';
  String _clearance = 'All';
  String _interestType = 'All';
  bool _favouritesOnly = false;

  // New filters
  String _category = 'all';
  String _counterparty = 'all';
  String _sortBy = 'Created';
  bool _sortAsc = false;
  DateTime? _startDate;
  DateTime? _endDate;

  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _role != 'All' || _clearance != 'All' || _interestType != 'All' ||
      _favouritesOnly || _category != 'all' || _counterparty != 'all' ||
      _startDate != null || _endDate != null ||
      _minCtrl.text.isNotEmpty || _maxCtrl.text.isNotEmpty;

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(IconData icon, String label, {Color? color}) {
    final c = color ?? AppColors.cyan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 0, 10),
      child: Row(children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, size: 14, color: c),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.3, color: AppThemeColors.secondaryText(context))),
      ]),
    );
  }

  Widget _tileGroup(List<_STileData> tiles, {Color? accent}) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(
        children: tiles.asMap().entries.map((entry) {
          final i = entry.key;
          final tile = entry.value;
          final isFirst = i == 0;
          final isLast = i == tiles.length - 1;
          return Column(children: [
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: isFirst ? const Radius.circular(15) : Radius.zero,
                bottom: isLast ? const Radius.circular(15) : Radius.zero,
              ),
              child: _optionTile(
                icon: tile.icon,
                label: tile.label,
                subtitle: tile.subtitle,
                selected: tile.selected,
                onTap: tile.onTap,
                accent: accent ?? tile.accent ?? AppColors.cyan,
              ),
            ),
            if (!isLast) Divider(height: 1, indent: 66, color: AppThemeColors.border(context)),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
    Color accent = AppColors.cyan,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.14) : AppThemeColors.surfaceBg(context),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 20, color: selected ? accent : AppThemeColors.secondaryText(context)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppThemeColors.primaryText(context))),
            if (subtitle != null) ...[
              const SizedBox(height: 1),
              Text(subtitle, style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
            ],
          ])),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: selected
                ? Icon(Icons.check_circle_rounded, color: accent, size: 22, key: const ValueKey('c'))
                : Icon(Icons.circle_outlined, color: AppThemeColors.border(context), size: 22, key: const ValueKey('e')),
          ),
        ]),
      ),
    );
  }

  String _counterpartyLabel(String email) {
    if (email == 'all') return 'All People';
    final match = widget.counterpartyOptions.firstWhere(
      (o) => o['email'] == email, orElse: () => {'label': email});
    return match['label'] ?? email;
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? now) : (_endDate ?? now),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) _startDate = picked;
      else _endDate = picked;
    });
  }

  Future<void> _showCounterpartyPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SecureCounterpartySheet(
        options: widget.counterpartyOptions,
        selected: _counterparty,
      ),
    );
    if (selected == null) return;
    setState(() => _counterparty = selected);
  }

  Widget _categoryChip(String key, String label, IconData icon) {
    final selected = _category == key;
    return GestureDetector(
      onTap: () => setState(() => _category = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple.withValues(alpha: 0.12) : AppThemeColors.surfaceBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.deepPurple.withValues(alpha: 0.5) : AppThemeColors.border(context),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: selected ? Colors.deepPurple : AppThemeColors.secondaryText(context)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? Colors.deepPurple : AppThemeColors.primaryText(context))),
        ]),
      ),
    );
  }

  Widget _datePickerRow() {
    final fmt = DateFormat('dd MMM yyyy');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(children: [
        _dateTile(
          label: 'Start Date',
          value: _startDate != null ? fmt.format(_startDate!) : 'Any',
          icon: Icons.calendar_today_rounded,
          color: Colors.purple,
          onTap: () => _pickDate(true),
          onClear: _startDate != null ? () => setState(() => _startDate = null) : null,
        ),
        Divider(height: 14, color: AppThemeColors.border(context)),
        _dateTile(
          label: 'End Date',
          value: _endDate != null ? fmt.format(_endDate!) : 'Any',
          icon: Icons.event_rounded,
          color: Colors.purple,
          onTap: () => _pickDate(false),
          onClear: _endDate != null ? () => setState(() => _endDate = null) : null,
        ),
      ]),
    );
  }

  Widget _dateTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(11)),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppThemeColors.primaryText(context))),
        ])),
        if (onClear != null)
          IconButton(onPressed: onClear, icon: const Icon(Icons.close, size: 18), padding: EdgeInsets.zero, constraints: const BoxConstraints())
        else
          Icon(Icons.keyboard_arrow_right_rounded, color: AppThemeColors.secondaryText(context)),
      ]),
    );
  }

  Widget _amountField(TextEditingController ctrl, String hint, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.surfaceBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.pink),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ]),
    );
  }

  void _reset() {
    setState(() {
      _role = 'All'; _clearance = 'All'; _interestType = 'All';
      _favouritesOnly = false; _category = 'all'; _counterparty = 'all';
      _sortBy = 'Created'; _sortAsc = false;
      _startDate = null; _endDate = null;
      _minCtrl.clear(); _maxCtrl.clear();
    });
  }

  void _apply() {
    Navigator.of(context).pop({
      'role': _role,
      'clearance': _clearance,
      'interestType': _interestType,
      'favourites': _favouritesOnly,
      'category': _category,
      'counterparty': _counterparty,
      'sort_by': _sortBy,
      'sort_asc': _sortAsc,
      'start_date': _startDate,
      'end_date': _endDate,
      'min_amount': _minCtrl.text.isNotEmpty ? double.tryParse(_minCtrl.text) : null,
      'max_amount': _maxCtrl.text.isNotEmpty ? double.tryParse(_maxCtrl.text) : null,
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cpLabel = _counterpartyLabel(_counterparty);

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppThemeColors.cardBg(context),
        foregroundColor: AppThemeColors.primaryText(context),
        elevation: 0,
        title: const Text('Secure Filters', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_hasActiveFilters)
            TextButton(
              onPressed: _reset,
              child: const Text('Reset', style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [

                // ── Role ────────────────────────────────────────────────
                _sectionHeader(Icons.swap_vert_circle_outlined, 'Transaction Type', color: Colors.blue),
                _tileGroup([
                  _STileData(icon: Icons.all_inclusive_rounded, label: 'All Transactions', selected: _role == 'All', accent: Colors.blue,
                    onTap: () => setState(() => _role = 'All')),
                  _STileData(icon: Icons.trending_up_rounded, label: 'You Lent', subtitle: 'You are the lender', selected: _role == 'Lending', accent: Colors.green,
                    onTap: () => setState(() => _role = 'Lending')),
                  _STileData(icon: Icons.trending_down_rounded, label: 'You Borrowed', subtitle: 'You are the borrower', selected: _role == 'Borrowing', accent: Colors.orange,
                    onTap: () => setState(() => _role = 'Borrowing')),
                ]),
                const SizedBox(height: 20),

                // ── Clearance ────────────────────────────────────────────
                _sectionHeader(Icons.verified_rounded, 'Clearance Status', color: Colors.teal),
                _tileGroup([
                  _STileData(icon: Icons.all_inclusive_rounded, label: 'All', selected: _clearance == 'All', accent: Colors.teal,
                    onTap: () => setState(() => _clearance = 'All')),
                  _STileData(icon: Icons.task_alt_rounded, label: 'Totally Cleared', subtitle: 'Both sides settled', selected: _clearance == 'Totally Cleared', accent: Colors.teal,
                    onTap: () => setState(() => _clearance = 'Totally Cleared')),
                  _STileData(icon: Icons.pending_rounded, label: 'Partially Cleared', subtitle: 'One side settled', selected: _clearance == 'Partially Cleared', accent: Colors.amber,
                    onTap: () => setState(() => _clearance = 'Partially Cleared')),
                  _STileData(icon: Icons.unpublished_rounded, label: 'Totally Uncleared', subtitle: 'Nothing settled yet', selected: _clearance == 'Totally Uncleared', accent: Colors.red,
                    onTap: () => setState(() => _clearance = 'Totally Uncleared')),
                ]),
                const SizedBox(height: 20),

                // ── Interest ─────────────────────────────────────────────
                _sectionHeader(Icons.percent_rounded, 'Interest Type', color: Colors.orange),
                _tileGroup([
                  _STileData(icon: Icons.all_inclusive_rounded, label: 'All Types', selected: _interestType == 'All', accent: Colors.orange,
                    onTap: () => setState(() => _interestType = 'All')),
                  _STileData(icon: Icons.block_rounded, label: 'No Interest', subtitle: 'Interest-free loans', selected: _interestType == 'none', accent: Colors.grey,
                    onTap: () => setState(() => _interestType = 'none')),
                  _STileData(icon: Icons.functions_rounded, label: 'Simple Interest', selected: _interestType == 'simple', accent: Colors.blue,
                    onTap: () => setState(() => _interestType = 'simple')),
                  _STileData(icon: Icons.trending_up_rounded, label: 'Compound Interest', selected: _interestType == 'compound', accent: Colors.orange,
                    onTap: () => setState(() => _interestType = 'compound')),
                ]),
                const SizedBox(height: 20),

                // ── Sort ─────────────────────────────────────────────────
                _sectionHeader(Icons.sort_rounded, 'Sort By', color: Colors.green),
                _tileGroup([
                  _STileData(icon: Icons.schedule_rounded, label: 'Newest Created', subtitle: 'Most recently created first', selected: _sortBy == 'Created' && !_sortAsc, accent: Colors.green,
                    onTap: () => setState(() { _sortBy = 'Created'; _sortAsc = false; })),
                  _STileData(icon: Icons.history_rounded, label: 'Oldest Created', subtitle: 'Earliest created first', selected: _sortBy == 'Created' && _sortAsc, accent: Colors.green,
                    onTap: () => setState(() { _sortBy = 'Created'; _sortAsc = true; })),
                  _STileData(icon: Icons.event_rounded, label: 'Transaction Date', selected: _sortBy == 'Transaction Date', accent: Colors.green,
                    onTap: () => setState(() => _sortBy = 'Transaction Date')),
                  _STileData(icon: Icons.arrow_downward_rounded, label: 'Amount: High → Low', selected: _sortBy == 'Amount' && !_sortAsc, accent: Colors.green,
                    onTap: () => setState(() { _sortBy = 'Amount'; _sortAsc = false; })),
                  _STileData(icon: Icons.arrow_upward_rounded, label: 'Amount: Low → High', selected: _sortBy == 'Amount' && _sortAsc, accent: Colors.green,
                    onTap: () => setState(() { _sortBy = 'Amount'; _sortAsc = true; })),
                ]),
                const SizedBox(height: 20),

                // ── Date Range ───────────────────────────────────────────
                _sectionHeader(Icons.date_range_rounded, 'Transaction Date Range', color: Colors.purple),
                _datePickerRow(),
                const SizedBox(height: 20),

                // ── Amount Range ─────────────────────────────────────────
                _sectionHeader(Icons.currency_rupee_rounded, 'Amount Range', color: Colors.pink),
                Container(
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppThemeColors.border(context)),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Expanded(child: _amountField(_minCtrl, 'Min Amount', Icons.remove_circle_outline)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.swap_horiz_rounded, color: AppThemeColors.secondaryText(context)),
                    ),
                    Expanded(child: _amountField(_maxCtrl, 'Max Amount', Icons.add_circle_outline)),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Counterparty ─────────────────────────────────────────
                _sectionHeader(Icons.people_alt_outlined, 'Counterparty', color: Colors.indigo),
                GestureDetector(
                  onTap: _showCounterpartyPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _counterparty != 'all' ? Colors.indigo.withValues(alpha: 0.4) : AppThemeColors.border(context),
                        width: _counterparty != 'all' ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: _counterparty != 'all' ? Colors.indigo.withValues(alpha: 0.12) : AppThemeColors.surfaceBg(context),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(Icons.people_alt_outlined, size: 20,
                          color: _counterparty != 'all' ? Colors.indigo : AppThemeColors.secondaryText(context)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Selected Person', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                        const SizedBox(height: 2),
                        Text(cpLabel, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppThemeColors.primaryText(context))),
                      ])),
                      Icon(Icons.keyboard_arrow_down_rounded, color: AppThemeColors.secondaryText(context)),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Category ─────────────────────────────────────────────
                _sectionHeader(Icons.category_rounded, 'Category', color: Colors.deepPurple),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppThemeColors.border(context)),
                  ),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    _categoryChip('all', 'All', Icons.apps_rounded),
                    ...kSecureCategories.map((c) => _categoryChip(
                        c['key'] as String, c['label'] as String, c['icon'] as IconData)),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Favourites ───────────────────────────────────────────
                _sectionHeader(Icons.favorite_border_rounded, 'Favourites', color: Colors.red),
                Container(
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppThemeColors.border(context)),
                  ),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    secondary: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: _favouritesOnly ? Colors.red.withValues(alpha: 0.12) : AppThemeColors.surfaceBg(context),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(_favouritesOnly ? Icons.favorite : Icons.favorite_border,
                        size: 20, color: _favouritesOnly ? Colors.red : AppThemeColors.secondaryText(context)),
                    ),
                    title: const Text('Favourites Only', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Show only starred transactions', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                    value: _favouritesOnly,
                    activeColor: Colors.red,
                    onChanged: (v) => setState(() => _favouritesOnly = v),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // ── Bottom actions ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              border: Border(top: BorderSide(color: AppThemeColors.border(context))),
            ),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _reset,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.cyan),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Reset', style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _STileData {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  const _STileData({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.accent,
  });
}

class _SecureCounterpartySheet extends StatelessWidget {
  final List<Map<String, String>> options;
  final String selected;

  const _SecureCounterpartySheet({required this.options, required this.selected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 18),
        decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(24)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Container(width: 44, height: 4, decoration: BoxDecoration(color: AppThemeColors.border(context), borderRadius: BorderRadius.circular(2))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Container(width: 38, height: 38,
                decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.people_alt_outlined, color: AppColors.cyan, size: 20)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Filter by Person', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ]),
          ),
          Divider(height: 1, color: AppThemeColors.border(context)),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              itemCount: options.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) {
                final item = options[i];
                final email = item['email'] ?? 'all';
                final label = item['label'] ?? email;
                final isSelected = selected == email;
                final isAll = email == 'all';
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).pop(email),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.cyan.withValues(alpha: 0.08) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isSelected ? AppColors.cyan.withValues(alpha: 0.4) : Colors.transparent),
                    ),
                    child: Row(children: [
                      Container(width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: isAll ? AppColors.cyan.withValues(alpha: 0.10) : const Color(0xFF3B82F6).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(isAll ? Icons.groups_rounded : Icons.person_rounded,
                          color: isAll ? AppColors.cyan : const Color(0xFF3B82F6), size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: AppThemeColors.primaryText(context)))),
                      if (isSelected) Icon(Icons.check_circle_rounded, color: AppColors.cyan, size: 20),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
