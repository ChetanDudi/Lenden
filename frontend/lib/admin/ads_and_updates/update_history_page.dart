import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../utils/theme_helper.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';

class AdminUpdateHistoryPage extends StatefulWidget {
  final Map<String, dynamic> update;

  const AdminUpdateHistoryPage({super.key, required this.update});

  @override
  State<AdminUpdateHistoryPage> createState() => _AdminUpdateHistoryPageState();
}

class _AdminUpdateHistoryPageState extends State<AdminUpdateHistoryPage> {
  late final List<Map<String, dynamic>> _versions;
  final Set<int> _expanded = {};

  static const _sky = AppColors.cyan;
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _green = Color(0xFF22C55E);
  static const Color _red = Color(0xFFD32F2F);
  static const Color _orange = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _versions = _buildVersionTimeline(widget.update);
    // Expand first (latest) by default
    if (_versions.isNotEmpty) _expanded.add(0);
  }

  // Reconstruct full version timeline.
  // editHistory[i] = content BEFORE edit i+1, .editedAt = when edit i+1 happened.
  //
  //  versions[0]         = original     (content=editHistory[0], date=publishedAt)
  //  versions[1..N-1]    = intermediate (content=editHistory[i], date=editHistory[i-1].editedAt)
  //  versions[N]         = current      (content=doc fields,     date=lastEditedAt)
  //
  // We then reverse so newest is at the top of the timeline list.
  List<Map<String, dynamic>> _buildVersionTimeline(Map<String, dynamic> doc) {
    final rawHistory = ((doc['editHistory'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .toList();

    final List<Map<String, dynamic>> chronological = [];

    if (rawHistory.isEmpty) {
      chronological.add(_versionEntry(
        label: 'Published',
        date: doc['publishedAt'],
        src: doc,
        isCurrent: true,
        isOriginal: true,
      ));
      return chronological;
    }

    // Original version
    chronological.add(_versionEntry(
      label: 'Original',
      date: doc['publishedAt'],
      src: rawHistory[0],
      isCurrent: false,
      isOriginal: true,
    ));

    // Intermediate versions
    for (int i = 1; i < rawHistory.length; i++) {
      chronological.add(_versionEntry(
        label: 'Edit $i',
        date: rawHistory[i - 1]['editedAt'],
        src: rawHistory[i],
        isCurrent: false,
        isOriginal: false,
      ));
    }

    // Current (latest) version
    chronological.add(_versionEntry(
      label: 'Latest',
      date: rawHistory.last['editedAt'],
      src: doc,
      isCurrent: true,
      isOriginal: false,
    ));

    // Newest first
    return chronological.reversed.toList();
  }

  Map<String, dynamic> _versionEntry({
    required String label,
    required dynamic date,
    required Map<String, dynamic> src,
    required bool isCurrent,
    required bool isOriginal,
  }) =>
      {
        'label': label,
        'date': date,
        'isCurrent': isCurrent,
        'isOriginal': isOriginal,
        'title': src['title'] ?? '',
        'body': src['body'] ?? '',
        'summary': src['summary'] ?? '',
        'versionTag': src['versionTag'] ?? '',
        'category': src['category'] ?? 'general',
        'importance': src['importance'] ?? 'normal',
        'tags': src['tags'] ?? [],
        'platforms': src['platforms'] ?? ['all'],
        'targetAudience': src['targetAudience'] ?? 'all',
        'status': src['status'] ?? 'published',
      };

  Color _accentFor(Map<String, dynamic> ver) {
    if (ver['isCurrent'] == true) return _sky;
    if (ver['isOriginal'] == true) return _green;
    final imp = (ver['importance'] ?? 'normal').toString();
    if (imp == 'critical') return _red;
    if (imp == 'important') return _orange;
    return _amber;
  }

  Color _labelColor(Map<String, dynamic> ver) => _accentFor(ver);
  Color _dotColor(Map<String, dynamic> ver) => _accentFor(ver);

  String _formatDateTime(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year}  $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppThemeColors.isDark(context);
    final updateTitle = (widget.update['title'] ?? '').toString();
    final realEdits = (widget.update['editHistory'] as List? ?? []).length;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // ── Wave header ──
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(160),
                decoration: BoxDecoration(
                  color: AppThemeColors.waveSolid(context),
                  gradient: isDark
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.cyan, Color(0xFF0096C7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── App bar row ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back,
                            color: AppThemeColors.primaryText(context)),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit History',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                            Text(
                              updateTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppThemeColors.mutedText(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ── Summary strip ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _summaryPill(
                          Icons.history_edu_rounded, '$realEdits edit${realEdits == 1 ? '' : 's'}', _sky),
                      const SizedBox(width: 8),
                      _summaryPill(
                          Icons.layers_rounded, '${_versions.length} version${_versions.length == 1 ? '' : 's'}', _amber),
                      const SizedBox(width: 8),
                      _summaryPill(
                          Icons.star_rounded, 'Latest', _green),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ── Expand/collapse all ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'Timeline',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          if (_expanded.length == _versions.length) {
                            _expanded.clear();
                          } else {
                            _expanded.addAll(
                                List.generate(_versions.length, (i) => i));
                          }
                        }),
                        icon: Icon(
                          _expanded.length == _versions.length
                              ? Icons.unfold_less_rounded
                              : Icons.unfold_more_rounded,
                          size: 16,
                          color: _sky,
                        ),
                        label: Text(
                          _expanded.length == _versions.length
                              ? 'Collapse all'
                              : 'Expand all',
                          style: const TextStyle(
                              color: _sky, fontWeight: FontWeight.w700),
                        ),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ── Timeline list ──
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    itemCount: _versions.length,
                    itemBuilder: (ctx, index) {
                      return _buildTimelineItem(ctx, index, isDark);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
      BuildContext context, int index, bool isDark) {
    final ver = _versions[index];
    final isLast = index == _versions.length - 1;
    final isExpanded = _expanded.contains(index);
    final accent = _accentFor(ver);
    final dotColor = _dotColor(ver);
    final isCurrent = ver['isCurrent'] == true;
    final isOriginal = ver['isOriginal'] == true;
    final label = (ver['label'] ?? '').toString();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Timeline rail ──
          SizedBox(
            width: 48,
            child: Column(
              children: [
                // Dot
                Container(
                  width: isCurrent ? 18 : 14,
                  height: isCurrent ? 18 : 14,
                  margin: EdgeInsets.only(top: isCurrent ? 18 : 20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.40),
                        blurRadius: isCurrent ? 10 : 6,
                        spreadRadius: isCurrent ? 2 : 0,
                      ),
                    ],
                  ),
                  child: isCurrent
                      ? const Icon(Icons.star_rounded,
                          size: 10, color: Colors.white)
                      : isOriginal
                          ? const Icon(Icons.fiber_new_rounded,
                              size: 9, color: Colors.white)
                          : null,
                ),
                // Connector
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            dotColor.withValues(alpha: 0.5),
                            _dotColor(_versions[index + 1])
                                .withValues(alpha: 0.5),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── Version card ──
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14, top: 10),
              child: GestureDetector(
                onTap: () => setState(() {
                  if (isExpanded) {
                    _expanded.remove(index);
                  } else {
                    _expanded.add(index);
                  }
                }),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isCurrent
                          ? accent.withValues(alpha: 0.40)
                          : AppThemeColors.divider(context),
                      width: isCurrent ? 1.5 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: isCurrent ? 0.08 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left-accent top bar
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [accent, accent.withValues(alpha: 0.3)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                        ),
                        // Header row (always visible)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          child: Row(
                            children: [
                              // Label badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: accent
                                      .withValues(alpha: isDark ? 0.18 : 0.10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _labelColor(ver),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (ver['title'] ?? '').toString(),
                                  maxLines: isExpanded ? 3 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppThemeColors.primaryText(context),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: AppThemeColors.mutedText(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Date line (always visible)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(14, 0, 14, 10),
                          child: Row(
                            children: [
                              Icon(
                                isOriginal
                                    ? Icons.publish_rounded
                                    : Icons.edit_calendar_rounded,
                                size: 12,
                                color: AppThemeColors.mutedText(context),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDateTime(ver['date']),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppThemeColors.mutedText(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Expanded detail
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 220),
                          crossFadeState: isExpanded
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          firstChild: _buildExpandedBody(context, ver, accent, isDark),
                          secondChild: const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedBody(BuildContext context,
      Map<String, dynamic> ver, Color accent, bool isDark) {
    final summary = (ver['summary'] ?? '').toString().trim();
    final body = (ver['body'] ?? '').toString().trim();
    final versionTag = (ver['versionTag'] ?? '').toString().trim();
    final category = (ver['category'] ?? 'general').toString();
    final importance = (ver['importance'] ?? 'normal').toString();
    final status = (ver['status'] ?? 'published').toString();
    final targetAudience = (ver['targetAudience'] ?? 'all').toString();
    final platforms = ((ver['platforms'] as List?) ?? ['all'])
        .map((p) => p.toString())
        .toList();
    final tags = ((ver['tags'] as List?) ?? [])
        .map((t) => t.toString())
        .where((t) => t.trim().isNotEmpty)
        .toList();

    final importanceColor = importance == 'critical'
        ? _red
        : importance == 'important'
            ? _orange
            : const Color(0xFF22C55E);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(
              color: AppThemeColors.divider(context), height: 1),
          const SizedBox(height: 12),
          // ── Metadata chips ──
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (versionTag.isNotEmpty)
                _chip(
                  icon: Icons.code_rounded,
                  label: 'v$versionTag',
                  color: _sky,
                  bg: _sky.withValues(alpha: isDark ? 0.14 : 0.09),
                ),
              _chip(
                icon: Icons.category_outlined,
                label: category.replaceAll('_', ' '),
                color: AppThemeColors.secondaryText(context),
                bg: AppThemeColors.tinted(context,
                    light: const Color(0xFFEEF2FF),
                    dark: const Color(0xFF1E2A3A)),
              ),
              _chip(
                icon: importance == 'critical'
                    ? Icons.warning_amber_rounded
                    : importance == 'important'
                        ? Icons.priority_high
                        : Icons.check_circle_outline,
                label: importance,
                color: importanceColor,
                bg: importanceColor.withValues(alpha: isDark ? 0.14 : 0.09),
              ),
              _chip(
                icon: Icons.event_note_rounded,
                label: status,
                color: status == 'published'
                    ? _green
                    : status == 'draft'
                        ? _amber
                        : _sky,
                bg: (status == 'published'
                        ? _green
                        : status == 'draft'
                            ? _amber
                            : _sky)
                    .withValues(alpha: isDark ? 0.14 : 0.09),
              ),
              _chip(
                icon: Icons.people_outline_rounded,
                label: targetAudience,
                color: AppThemeColors.secondaryText(context),
                bg: AppThemeColors.tinted(context,
                    light: const Color(0xFFF0F4FF),
                    dark: const Color(0xFF1B2A3A)),
              ),
              _chip(
                icon: Icons.devices_rounded,
                label: platforms.join(', '),
                color: AppThemeColors.secondaryText(context),
                bg: AppThemeColors.tinted(context,
                    light: const Color(0xFFF0F4FF),
                    dark: const Color(0xFF1B2A3A)),
              ),
            ],
          ),
          // ── Summary ──
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionLabel('Summary', Icons.short_text_rounded, accent),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                      color: accent.withValues(alpha: 0.6), width: 3),
                ),
                color: accent.withValues(alpha: isDark ? 0.06 : 0.04),
              ),
              child: Text(
                summary,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  height: 1.5,
                  color: AppThemeColors.secondaryText(context),
                ),
              ),
            ),
          ],
          // ── Body ──
          if (body.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionLabel('Content', Icons.article_outlined, accent),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(context,
                    light: const Color(0xFFF8FAFC),
                    dark: const Color(0xFF1A2535)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppThemeColors.divider(context)),
              ),
              child: Text(
                body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: AppThemeColors.primaryText(context),
                ),
              ),
            ),
          ],
          // ── Tags ──
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionLabel('Tags', Icons.label_outline_rounded, accent),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: tags
                  .map((tag) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _sky.withValues(
                              alpha: isDark ? 0.12 : 0.07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _sky.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? _sky.withValues(alpha: 0.9)
                                : _sky.withValues(alpha: 0.85),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, IconData icon, Color accent) => Row(
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.3,
            ),
          ),
        ],
      );

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
}
