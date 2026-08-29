import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/api_client.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/wave_widget.dart' show DeepTopWaveClipper;
import '../../l10n/app_localizations.dart';
import '../transaction/quick_transactions/quick_transactions_page.dart';
import '../transaction/secure_transactions/view_secure_transactions_page.dart';
import '../transaction/group_transactions/group_transaction_page.dart';
import '../support/notes_page.dart';
import '../connections/friends_page.dart';
import '../connections/counterparties_page.dart';
import '../community/community_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String t(String key) => AppLocalizations.of(context).t(key);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _closeFriends = [];
  List<Map<String, dynamic>> _closeCounterparties = [];
  List<Map<String, dynamic>> _bookmarkedNotes = [];
  List<Map<String, dynamic>> _starredCommunities = [];

  @override
  void initState() {
    super.initState();
    _fetchFavourites();
  }

  Future<void> _fetchFavourites() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/user/favourites');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _closeFriends = List<Map<String, dynamic>>.from(data['closeFriends'] ?? []);
          _closeCounterparties = List<Map<String, dynamic>>.from(data['closeCounterparties'] ?? []);
          _bookmarkedNotes = List<Map<String, dynamic>>.from(data['bookmarkedNotes'] ?? []);
          _starredCommunities = List<Map<String, dynamic>>.from(data['starredCommunities'] ?? []);
          _loading = false;
        });
      } else {
        setState(() { _error = t('failed_to_load_favourites'); _loading = false; });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = t('error_loading_favourites'); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Column(
        children: [
          Stack(
            children: [
              ClipPath(
                clipper: const DeepTopWaveClipper(),
                child: Container(
                  height: MediaQuery.of(context).padding.top + context.sh(70),
                  color: AppThemeColors.waveSolid(context),
                ),
              ),
              SafeArea(
                bottom: false,
                child: SizedBox(
                  height: context.sh(60),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        t('favourites'),
                        style: TextStyle(
                          color: AppThemeColors.primaryText(context),
                          fontSize: context.sp(20),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.refresh, color: AppThemeColors.primaryText(context)),
                        onPressed: _fetchFavourites,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                : _error != null
                    ? errorStateWidget(context, _error!, _fetchFavourites)
                    : RefreshIndicator(
                        onRefresh: _fetchFavourites,
                        color: AppColors.cyan,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, context.sh(24)),
                          children: [
                            _sectionCard(t('transactions'), [
                              _navRow(
                                icon: Icons.bolt,
                                iconColor: Colors.amber.shade700,
                                title: t('quick_transactions'),
                                subtitle: t('starred_quick_subtitle'),
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) =>
                                        QuickTransactionsPage(initialShowFavouritesOnly: true))),
                              ),
                              _navRow(
                                icon: Icons.shield_rounded,
                                iconColor: AppColors.cyan,
                                title: t('secure_transactions'),
                                subtitle: t('starred_secure_subtitle'),
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) =>
                                        UserTransactionsPage(initialShowFavouritesOnly: true))),
                              ),
                              _navRow(
                                icon: Icons.group_rounded,
                                iconColor: const Color(0xFF5C6BC0),
                                title: t('group_transactions'),
                                subtitle: t('starred_group_subtitle'),
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) =>
                                        GroupTransactionPage(initialShowFavouritesOnly: true))),
                              ),
                            ]),
                            _sectionCard(t('fav_section_people'), [
                              _navRow(
                                icon: Icons.star_rounded,
                                iconColor: Colors.amber,
                                title: t('close_friends'),
                                subtitle: _closeFriends.isEmpty
                                    ? t('no_close_friends')
                                    : '${_closeFriends.length} ${t('close_friends').toLowerCase()}',
                                badge: _closeFriends.length,
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) =>
                                        const FriendsPage(initialShowCloseOnly: true))).then((_) => _fetchFavourites()),
                              ),
                              _navRow(
                                icon: Icons.handshake_rounded,
                                iconColor: Colors.orange,
                                title: t('close_counterparties'),
                                subtitle: _closeCounterparties.isEmpty
                                    ? t('no_close_counterparties')
                                    : '${_closeCounterparties.length} ${t('close_counterparties').toLowerCase()}',
                                badge: _closeCounterparties.length,
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) =>
                                        const CounterpartiesPage(initialShowCloseOnly: true))).then((_) => _fetchFavourites()),
                              ),
                            ]),
                            _sectionCard(t('notes'), [
                              _navRow(
                                icon: Icons.bookmark_rounded,
                                iconColor: Colors.teal,
                                title: t('bookmarked_notes'),
                                subtitle: _bookmarkedNotes.isEmpty
                                    ? t('no_bookmarked_notes')
                                    : '${_bookmarkedNotes.length} ${t('bookmarked_notes').toLowerCase()}',
                                badge: _bookmarkedNotes.length,
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) =>
                                        NotesPage(initialShowBookmarkedOnly: true))),
                              ),
                            ]),
                            _sectionCard(t('communities_title'), [
                              _navRow(
                                icon: Icons.star_rounded,
                                iconColor: Colors.amber,
                                title: t('starred_communities'),
                                subtitle: _starredCommunities.isEmpty
                                    ? t('no_starred_communities')
                                    : '${_starredCommunities.length} ${t('starred_communities_subtitle')}',
                                badge: _starredCommunities.length,
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) =>
                                        const CommunityPage(initialShowStarredOnly: true)))
                                    .then((_) => _fetchFavourites()),
                              ),
                            ]),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeColors.divider(context).withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
            child: Row(children: [
              Container(
                width: 3, height: 13,
                decoration: BoxDecoration(
                  color: AppColors.cyan,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(title.toUpperCase(), style: TextStyle(
                fontSize: context.sp(10),
                fontWeight: FontWeight.bold,
                color: AppColors.cyan,
                letterSpacing: 1.0,
              )),
            ]),
          ),
          Divider(height: 1, color: AppThemeColors.divider(context).withValues(alpha: 0.5)),
          ...rows.asMap().entries.map((e) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (e.key > 0) Divider(
                height: 1, indent: 68,
                color: AppThemeColors.divider(context).withValues(alpha: 0.4)),
              e.value,
            ],
          )),
          const SizedBox(height: 4),
        ]),
      ),
    );
  }

  Widget _navRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: iconColor, size: context.sp(18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(subtitle, style: TextStyle(
                fontSize: context.sp(11),
                color: AppThemeColors.secondaryText(context),
              )),
              const SizedBox(height: 2),
              Text(title, style: TextStyle(
                fontSize: context.sp(14),
                fontWeight: FontWeight.w600,
                color: AppThemeColors.primaryText(context),
              )),
            ]),
          ),
          if (badge > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$badge', style: TextStyle(
                fontSize: context.sp(11),
                fontWeight: FontWeight.bold,
                color: iconColor,
              )),
            ),
            const SizedBox(width: 6),
          ],
          Icon(Icons.chevron_right_rounded,
              color: AppThemeColors.secondaryText(context), size: context.sp(18)),
        ]),
      ),
    );
  }
}

