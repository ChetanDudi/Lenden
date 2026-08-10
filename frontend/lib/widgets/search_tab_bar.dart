import 'package:flutter/material.dart';
import 'app_colors.dart';
import '../utils/theme_helper.dart';

// ── AppSearchBar ─────────────────────────────────────────────────────────────
//
// Usage:
//   AppSearchBar(
//     controller: _ctrl,
//     hintText: 'Search…',
//     onChanged: (v) => setState(() => query = v),      // live filter
//     onSubmit: _doSearch,  isLoading: _searching,      // submit-style
//   )
//
// • When text is non-empty a ✕ clear button replaces the trailing widget.
// • When text is empty and onSubmit != null a ➤ send button is shown.
// • isLoading shows a spinner instead of the send button.

class AppSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isLoading;

  /// Called when the user taps the send button or presses Enter.
  /// When non-null a send button is shown while the field is empty.
  final VoidCallback? onSubmit;

  /// Live-change callback (debounce in the caller if needed).
  final ValueChanged<String>? onChanged;

  final EdgeInsetsGeometry margin;
  final FocusNode? focusNode;

  const AppSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.isLoading = false,
    this.onSubmit,
    this.onChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                textInputAction: onSubmit != null
                    ? TextInputAction.search
                    : TextInputAction.done,
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(
                      color: AppThemeColors.mutedText(context), fontSize: 13),
                  prefixIcon:
                      Icon(Icons.search, color: AppThemeColors.mutedText(context)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: onChanged,
                onSubmitted: onSubmit != null ? (_) => onSubmit!() : null,
              ),
            ),
            _Trailing(
              controller: controller,
              isLoading: isLoading,
              onSubmit: onSubmit,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _Trailing extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onChanged;

  const _Trailing({
    required this.controller,
    required this.isLoading,
    required this.onSubmit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (ctx, value, _) {
        if (value.text.isNotEmpty) {
          return IconButton(
            icon: Icon(Icons.close,
                color: AppThemeColors.mutedText(ctx), size: 18),
            onPressed: () {
              controller.clear();
              onChanged?.call('');
            },
          );
        }
        if (isLoading) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (onSubmit != null) {
          return IconButton(
            icon: const Icon(Icons.send_rounded, color: AppColors.cyan),
            onPressed: onSubmit,
          );
        }
        return const SizedBox(width: 8);
      },
    );
  }
}

// ── AppTabItem ────────────────────────────────────────────────────────────────

class AppTabItem {
  final String label;
  final IconData? icon;

  /// When > 0 appended as " (n)" in the tab label.
  final int? count;

  const AppTabItem({required this.label, this.icon, this.count});
}

// ── AppTabBar ─────────────────────────────────────────────────────────────────
//
// Usage:
//   AppTabBar(
//     controller: _tabController,
//     tabs: [
//       AppTabItem(label: 'All', icon: Icons.list, count: _items.length),
//       AppTabItem(label: 'Pending', icon: Icons.pending),
//     ],
//   )

class AppTabBar extends StatelessWidget {
  final TabController controller;
  final List<AppTabItem> tabs;

  /// Vertical-only margin by default so the bar stretches edge-to-edge.
  final EdgeInsetsGeometry margin;

  /// Set to true for pages with 5+ tabs that need horizontal scrolling.
  /// Defaults to false so tabs fill the full width equally.
  final bool isScrollable;

  const AppTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.margin = const EdgeInsets.symmetric(vertical: 4),
    this.isScrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: controller,
        isScrollable: isScrollable,
        tabAlignment: isScrollable ? TabAlignment.start : TabAlignment.fill,
        labelPadding: isScrollable
            ? const EdgeInsets.symmetric(horizontal: 20, vertical: 0)
            : EdgeInsets.zero,
        indicator: BoxDecoration(
          color: AppColors.cyan,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: AppThemeColors.secondaryText(context),
        labelStyle:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(4),
        tabs: tabs.map((item) {
          final hasCount = item.count != null && item.count! > 0;
          final labelText =
              hasCount ? '${item.label} (${item.count})' : item.label;
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 15),
                  const SizedBox(width: 4),
                ],
                Text(labelText),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
