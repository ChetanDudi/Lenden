import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../support/notes_page.dart';
import '../../profile/profile_page.dart';
import '../transactions/manage_secure_transactions_page.dart';
import '../manage_users/user_management_page.dart';
import '../transactions/manage_group_transactions_page.dart';
import '../transactions/manage_quick_transactions_page.dart';
import '../track_users/track_user_activity_page.dart';
import '../support/manage_contact_page.dart';
import '../support/manage_support_queries_page.dart';
import '../../widgets/notification_icon.dart';
import '../../utils/theme_helper.dart';
import '../digitise/manage_subscriptions_page.dart';
import '../digitise/manage_gift_cards_page.dart';
import '../digitise/manage_referral_settings_page.dart';
import '../digitise/manage_offers_page.dart';
import '../ads_and_updates/content_analytics_page.dart';
import '../manage_users/admin_roles_page.dart';
import '../settings/manage_currency_conversions_page.dart';
import '../ads_and_updates/manage_updates_page.dart';
import '../ads_and_updates/manage_ads_page.dart';
import '../audit/audit_logs_page.dart';
import '../support/contact_messages_page.dart';
import '../disputes/manage_disputes_page.dart';
import '../disputes/fraud_alerts_page.dart';
import '../../utils/responsive.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int _imageRefreshKey = 0; // Key to force avatar rebuild
  bool _useCompactAdminOptions = true;
  bool _showOverviewPanel = false;
  bool _loadingOverview = false;
  bool _expandHealthAlerts = false; // Toggle for health alerts expansion
  String? _overviewError;
  Map<String, dynamic>? _dashboardSummary;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, GlobalKey> _sectionKeys = {
    'manage_users': GlobalKey(),
    'manage_transactions': GlobalKey(),
    'notes': GlobalKey(),
    'manage_groups': GlobalKey(),
    'track_user_activity': GlobalKey(),
    'manage_subscription': GlobalKey(),
    'manage_gift_cards': GlobalKey(),
    'referral_settings': GlobalKey(),
    'manage_offers': GlobalKey(),
    'contact_settings': GlobalKey(),
    'app_ratings': GlobalKey(),
    'user_feedbacks': GlobalKey(),
    'support_queries': GlobalKey(),
    'content_analytics': GlobalKey(),
    'contact_messages': GlobalKey(),
    'audit_logs': GlobalKey(),
  };

  @override
  void initState() {
    super.initState();

    // Listen to session changes to refresh profile image
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = Provider.of<SessionProvider>(context, listen: false);
      session.addListener(_onSessionChanged);
      _loadDashboardSummary();
    });
  }

  @override
  void dispose() {
    final session = Provider.of<SessionProvider>(context, listen: false);
    session.removeListener(_onSessionChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    setState(() {
      _imageRefreshKey++;
    });
    _loadDashboardSummary();
  }

  Future<void> _loadDashboardSummary() async {
    if (!mounted) return;
    setState(() {
      _loadingOverview = true;
      _overviewError = null;
    });

    try {
      final response = await ApiClient.get('/api/admin/dashboard-summary');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(
          (data['message'] ?? 'Failed to load admin overview').toString(),
        );
      }

      if (!mounted) return;
      setState(() {
        _dashboardSummary = data['summary'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(data['summary'])
            : data['summary'] is Map
                ? Map<String, dynamic>.from(data['summary'])
                : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _overviewError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingOverview = false;
        });
      }
    }
  }

  Future<void> _clearPendingUsers() async {
    try {
      final response = await ApiClient.patch(
        '/api/admin/users/clear-pending',
        body: const {},
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(
          (data['message'] ?? 'Failed to clear pending users').toString(),
        );
      }
      if (!mounted) return;
      final modifiedCount = (data['modifiedCount'] ?? 0) as num;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          content: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  (modifiedCount > 0 ? AppColors.cyan : Colors.green)
                      .withValues(alpha: 0.14),
                  Colors.white,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(
                  modifiedCount > 0
                      ? Icons.verified_user_rounded
                      : Icons.auto_awesome_rounded,
                  color: modifiedCount > 0
                      ? AppColors.cyan
                      : Colors.green,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    (data['message'] ?? 'No pending users were left to review')
                        .toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      _loadDashboardSummary();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  void _openSectionById(String? sectionId) {
    if (sectionId == null || sectionId.isEmpty) return;

    switch (sectionId) {
      case 'manage_users':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserManagementPage()),
        );
        return;
      case 'manage_transactions':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ManageTransactionsPage()),
        );
        return;
      case 'manage_groups':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ManageGroupTransactionsPage()),
        );
        return;
      case 'manage_quick_transactions':
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const ManageQuickTransactionsPage()),
        );
        return;
      case 'support_queries':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ManageSupportQueriesPage()),
        );
        return;
      case 'content_analytics':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AdminContentAnalyticsPage(),
          ),
        );
        return;
    }

    final targetContext = _sectionKeys[sectionId]?.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );
    }
  }

  Map<String, dynamic> get _adminPermissions {
    final sessionUser =
        Provider.of<SessionProvider>(context, listen: false).user;
    if (sessionUser?['permissions'] is Map) {
      return Map<String, dynamic>.from(sessionUser!['permissions']);
    }
    return const <String, dynamic>{};
  }

  bool get _isSuperAdmin =>
      Provider.of<SessionProvider>(context, listen: false)
          .user?['isSuperAdmin'] ==
      true;

  bool _hasPermission(String key) {
    if (_isSuperAdmin) return true;
    return _adminPermissions[key] != false;
  }

  List<_AdminDashboardItem> _dashboardItems(BuildContext context) => [
        _AdminDashboardItem(
          id: 'manage_users',
          permissionKey: 'canManageUsers',
          icon: Icons.people_alt_rounded,
          label: 'Manage Users',
          caption: 'Review and control user accounts',
          actionLabel: 'Users',
          backgroundColor: const Color(0xFFEDEBFA),
          iconColor: const Color(0xFF304E96),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserManagementPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'manage_transactions',
          permissionKey: 'canManageTransactions',
          icon: Icons.receipt_long_rounded,
          label: 'Manage Secure Transactions',
          caption: 'Inspect and control secure records',
          actionLabel: 'Secure',
          backgroundColor: const Color(0xFFE8F4EC),
          iconColor: const Color(0xFF1E6B3B),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ManageTransactionsPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'notes',
          permissionKey: 'canManageSettings',
          icon: Icons.route_rounded,
          label: 'Notes',
          caption: 'Open internal notes and references',
          actionLabel: 'Notes',
          backgroundColor: const Color(0xFFF5EAF4),
          iconColor: const Color(0xFF8A2F7B),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminNotesPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'manage_groups',
          permissionKey: 'canManageTransactions',
          icon: Icons.group_work_rounded,
          label: 'Manage Groups',
          caption: 'Handle group activity and expenses',
          actionLabel: 'Groups',
          backgroundColor: const Color(0xFFF3F2E8),
          iconColor: const Color(0xFF8B7A30),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ManageGroupTransactionsPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'manage_quick_transactions',
          permissionKey: 'canManageTransactions',
          icon: Icons.flash_on_rounded,
          label: 'Manage Quick Transactions',
          caption: 'Inspect and manage quick transaction records',
          actionLabel: 'Quick',
          backgroundColor: const Color(0xFFE8F0FE),
          iconColor: const Color(0xFF1A56DB),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ManageQuickTransactionsPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'track_user_activity',
          permissionKey: 'canManageUsers',
          icon: Icons.insights_rounded,
          label: 'Track User Activity',
          caption: 'Monitor user-side platform behaviour',
          actionLabel: 'Track',
          backgroundColor: const Color(0xFFE8F2FB),
          iconColor: const Color(0xFF1D5D91),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TrackUserActivityPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'manage_subscription',
          permissionKey: 'canManageSettings',
          icon: Icons.tune_rounded,
          label: 'Manage Subscription',
          caption: 'Adjust admin-side product controls',
          actionLabel: 'Subscription',
          backgroundColor: const Color(0xFFEAF6F0),
          iconColor: const Color(0xFF296D4E),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AdminFeaturesPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'manage_gift_cards',
          permissionKey: 'canManageDigitise',
          icon: Icons.card_giftcard_rounded,
          label: 'Manage Gift Cards',
          caption: 'Create and control gift card inventory',
          actionLabel: 'Cards',
          backgroundColor: const Color(0xFFFCEFE4),
          iconColor: const Color(0xFF9B5B21),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ManageGiftCardsPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'referral_settings',
          permissionKey: 'canManageDigitise',
          icon: Icons.share_rounded,
          label: 'Referral Settings',
          caption: 'Tune referral rewards and flows',
          actionLabel: 'Referral',
          backgroundColor: const Color(0xFFEAF0FF),
          iconColor: const Color(0xFF405FB5),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ReferralSettingsPage(),
              ),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'manage_offers',
          permissionKey: 'canManageDigitise',
          icon: Icons.local_offer_rounded,
          label: 'Manage Offers',
          caption: 'Publish and update admin offers',
          actionLabel: 'Offers',
          backgroundColor: const Color(0xFFF4EAF0),
          iconColor: const Color(0xFF8C2C62),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManageOffersPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'contact_settings',
          permissionKey: 'canManageSettings',
          icon: Icons.contact_phone_rounded,
          label: 'Contact Settings',
          caption: 'Update support and contact details',
          actionLabel: 'Contact',
          backgroundColor: const Color(0xFFE8F7FA),
          iconColor: const Color(0xFF0B8FAC),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManageContactPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'support_queries',
          permissionKey: 'canManageSupport',
          icon: Icons.support_agent_rounded,
          label: 'Help & Support',
          caption: 'Resolve support queues and user issues',
          actionLabel: 'Support',
          backgroundColor: const Color(0xFFEAF8F6),
          iconColor: const Color(0xFF11806A),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ManageSupportQueriesPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'manage_disputes',
          permissionKey: 'canManageSupport',
          icon: Icons.gavel_rounded,
          label: 'Manage Disputes',
          caption: 'Review and resolve transaction disputes',
          actionLabel: 'Disputes',
          backgroundColor: const Color(0xFFFCEEE6),
          iconColor: const Color(0xFFD2691E),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManageDisputesPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'fraud_alerts',
          permissionKey: 'canManageTransactions',
          icon: Icons.security_rounded,
          label: 'Fraud Alerts',
          caption: 'Automated anomaly and fraud detection',
          actionLabel: 'Alerts',
          backgroundColor: const Color(0xFFFDEAEA),
          iconColor: const Color(0xFFB71C1C),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FraudAlertsPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'content_analytics',
          permissionKey: 'canManageContent',
          icon: Icons.query_stats_rounded,
          label: 'Content Analytics',
          caption: 'Track admin content performance and moderation',
          actionLabel: 'Analytics',
          backgroundColor: const Color(0xFFEAF1FF),
          iconColor: const Color(0xFF3157B7),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminContentAnalyticsPage(),
              ),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'app_ratings',
          permissionKey: 'canManageContent',
          icon: Icons.star_rounded,
          label: 'App Ratings',
          caption: 'Review ratings coming from the app',
          actionLabel: 'Ratings',
          backgroundColor: const Color(0xFFF7F2E8),
          iconColor: const Color(0xFF8B6E24),
          onTap: () {
            Navigator.pushNamed(context, '/admin/ratings');
          },
        ),
        _AdminDashboardItem(
          id: 'user_feedbacks',
          permissionKey: 'canManageContent',
          icon: Icons.feedback_rounded,
          label: 'User Feedbacks',
          caption: 'Read submitted feedback and issues',
          actionLabel: 'Feedback',
          backgroundColor: const Color(0xFFEAF5F8),
          iconColor: const Color(0xFF236D86),
          onTap: () {
            Navigator.pushNamed(context, '/admin/feedbacks');
          },
        ),
        _AdminDashboardItem(
          id: 'contact_messages',
          permissionKey: 'canManageSupport',
          icon: Icons.contact_mail_rounded,
          label: 'Contact Messages',
          caption: 'View and respond to contact form submissions',
          actionLabel: 'Messages',
          backgroundColor: const Color(0xFFE8F3FF),
          iconColor: const Color(0xFF1A5FAB),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ContactMessagesPage()),
            );
          },
        ),
        _AdminDashboardItem(
          id: 'audit_logs',
          permissionKey: 'canViewAuditLogs',
          icon: Icons.history_rounded,
          label: 'Audit Logs',
          caption: 'Review all admin actions and changes',
          actionLabel: 'Logs',
          backgroundColor: const Color(0xFFF0EAF8),
          iconColor: const Color(0xFF5B2D8E),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AuditLogsPage()),
            );
          },
        ),
      ].where((item) {
        if (item.permissionKey == null) return true;
        return _hasPermission(item.permissionKey!);
      }).toList();

  String _normalizeSearch(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  bool _isSubsequence(String query, String target) {
    int qi = 0;
    for (int i = 0; i < target.length && qi < query.length; i++) {
      if (target[i] == query[qi]) {
        qi++;
      }
    }
    return qi == query.length;
  }

  int _matchScore(String query, String label) {
    final normalizedQuery = _normalizeSearch(query);
    final normalizedLabel = _normalizeSearch(label);
    if (normalizedQuery.isEmpty) return -1;
    if (normalizedLabel == normalizedQuery) return 100;
    if (normalizedLabel.startsWith(normalizedQuery)) return 80;
    if (normalizedLabel.contains(normalizedQuery)) return 70;

    final queryWords = normalizedQuery.split(' ').where((w) => w.isNotEmpty);
    int score = 0;
    for (final word in queryWords) {
      if (normalizedLabel.contains(word)) {
        score += 20;
      } else if (_isSubsequence(word, normalizedLabel.replaceAll(' ', ''))) {
        score += 8;
      }
    }

    if (_isSubsequence(
      normalizedQuery.replaceAll(' ', ''),
      normalizedLabel.replaceAll(' ', ''),
    )) {
      score += 12;
    }

    return score;
  }

  void _performSearch(String query) {
    final items = _dashboardItems(context);
    if (query.trim().isEmpty) return;

    _AdminDashboardItem? bestMatch;
    int bestScore = -1;

    for (final item in items) {
      final score = _matchScore(query, item.label);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = item;
      }
    }

    if (bestMatch != null && bestScore >= 8) {
      final targetContext = _sectionKeys[bestMatch.id]?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.15,
        );
      }
    }
  }

  // Helper function to get admin's profile image
  ImageProvider _getAdminAvatar() {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final user = session.user;
    final gender = user?['gender'] ?? 'Other';
    final imageUrl = user?['profileImage'];

    if (imageUrl != null &&
        imageUrl is String &&
        imageUrl.trim().isNotEmpty &&
        imageUrl != 'null') {
      // Add cache busting parameter for real-time updates
      final cacheBustingUrl =
          '$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      return NetworkImage(cacheBustingUrl);
    } else {
      return AssetImage(
        gender == 'Male'
            ? 'assets/Male.png'
            : gender == 'Female'
                ? 'assets/Female.png'
                : 'assets/Other.png',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboardItems = _dashboardItems(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pushReplacementNamed(context, '/');
        }
      },
      child: Scaffold(
        drawer: Drawer(
          width: 200,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: AppColors.cyan),
                child: Text('Menu',
                    style: TextStyle(color: Colors.white, fontSize: 24)),
              ),
              ListTile(
                leading: const Icon(Icons.dashboard),
                title: const Text('Dashboard'),
                onTap: () {
                  Navigator.of(context).pop(); // Close drawer
                },
              ),
              if (_hasPermission('canManageSettings'))
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Settings'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.pushNamed(context, '/admin/settings');
                  },
                ),
              if (_hasPermission('canManageSettings'))
                ListTile(
                  leading: const Icon(Icons.currency_exchange_rounded),
                  title: const Text('Currency Rates'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const ManageCurrencyConversionsPage(),
                      ),
                    );
                  },
                ),
              if (_hasPermission('canManageSupport'))
                ListTile(
                  leading: const Icon(Icons.help_center),
                  title: const Text('Help & Support'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ManageSupportQueriesPage()));
                  },
                ),
              if (_hasPermission('canManageContent'))
                ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: const Text('Updates'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageUpdatesPage(),
                      ),
                    );
                  },
                ),
              if (_hasPermission('canManageContent'))
                ListTile(
                  leading: const Icon(Icons.ondemand_video_outlined),
                  title: const Text('Ads'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ManageAdsPage()),
                    );
                  },
                ),
              if (_hasPermission('canManageContent'))
                ListTile(
                  leading: const Icon(Icons.query_stats_outlined),
                  title: const Text('Content Analytics'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminContentAnalyticsPage(),
                      ),
                    );
                  },
                ),
              if (_isSuperAdmin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Admin Roles'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminRolesPage(),
                      ),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () => _confirmLogout(context),
              ),
            ],
          ),
        ),
        backgroundColor: AppThemeColors.scaffoldBg(context),
        body: Stack(
          children: [
            // Main content area
            SafeArea(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
                child: Column(
                  children: [
                    Container(
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
                        decoration: BoxDecoration(
                          color: AppThemeColors.cardBg(context),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) {
                            if (value.trim().length >= 2) {
                              _performSearch(value);
                            }
                          },
                          onSubmitted: _performSearch,
                          decoration: InputDecoration(
                            hintText: 'Search admin sections',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: AppColors.cyan,
                            ),
                            suffixIcon: _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildOverviewSection(),
                    const SizedBox(height: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Admin Options',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Switch between detailed cards or compact admin grid.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppThemeColors.secondaryText(context),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.center,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.orange,
                                    Colors.white,
                                    Colors.green
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppThemeColors.cardBg(context),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildAdminLayoutChip(
                                      label: 'Single View',
                                      selected: !_useCompactAdminOptions,
                                      onTap: () {
                                        setState(() {
                                          _useCompactAdminOptions = false;
                                        });
                                      },
                                    ),
                                    _buildAdminLayoutChip(
                                      label: 'Grid View',
                                      selected: _useCompactAdminOptions,
                                      onTap: () {
                                        setState(() {
                                          _useCompactAdminOptions = true;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildAdminOptionsLayout(dashboardItems),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Top blue shape (background)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipPath(
                clipper: TopWaveClipper(),
                child: Container(
                  height: context.sh(78),
                  color: AppThemeColors.waveSolid(context),
                ),
              ),
            ),
            // Header buttons overlay (on top)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  height: 60,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.black),
                            onPressed: () async {
                              final popped =
                                  await Navigator.of(context).maybePop();
                              if (!popped && context.mounted) {
                                Navigator.pushReplacementNamed(context, '/');
                              }
                            },
                          ),
                          Builder(
                            builder: (context) => IconButton(
                              icon: const Icon(Icons.menu, color: Colors.black),
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          NotificationIcon(),
                          GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => const ProfilePage()),
                              );
                              final session = Provider.of<SessionProvider>(
                                  context,
                                  listen: false);
                              await session.forceRefreshProfile();
                              setState(() {
                                _imageRefreshKey++;
                              });
                            },
                            child: CircleAvatar(
                              key: ValueKey(_imageRefreshKey),
                              radius: 16,
                              backgroundColor: Colors.white,
                              backgroundImage: _getAdminAvatar(),
                              onBackgroundImageError:
                                  (exception, stackTrace) {},
                              child: _getAdminAvatar() is AssetImage
                                  ? Icon(
                                      Icons.person,
                                      color: Colors.grey[400],
                                      size: 20,
                                    )
                                  : null,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout,
                                color: Colors.black, size: 28),
                            tooltip: 'Logout',
                            onPressed: () => _confirmLogout(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard(
    BuildContext context, {
    required _AdminDashboardItem item,
    required bool showCaption,
  }) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: item.onTap,
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: item.backgroundColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SizedBox(
              height: 150,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      child: Icon(
                        item.icon,
                        color: item.iconColor,
                        size: 22,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      item.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.actionLabel,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: item.iconColor,
                      ),
                    ),
                    if (showCaption) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewSection() {
    final sessionUser =
        Provider.of<SessionProvider>(context, listen: false).user;
    final summary = _dashboardSummary ?? const <String, dynamic>{};
    final admin = summary['admin'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(summary['admin'])
        : summary['admin'] is Map
            ? Map<String, dynamic>.from(summary['admin'])
            : <String, dynamic>{};
    final cards = (summary['cards'] as List?)
            ?.map((item) => Map<String, dynamic>.from(item as Map))
            .toList() ??
        const <Map<String, dynamic>>[];
    final health = summary['systemHealth'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(summary['systemHealth'])
        : summary['systemHealth'] is Map
            ? Map<String, dynamic>.from(summary['systemHealth'])
            : <String, dynamic>{};
    final priorityItems = (summary['priorityItems'] as List?)
            ?.map((item) => Map<String, dynamic>.from(item as Map))
            .toList() ??
        const <Map<String, dynamic>>[];
    final adminName =
        (admin['name'] ?? sessionUser?['name'] ?? 'Admin').toString();
    final adminRoleText =
        ((admin['isSuperAdmin'] ?? sessionUser?['isSuperAdmin']) == true)
            ? 'Superadmin control is active for this session.'
            : 'Admin control is active for this session.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFFF6B00),
                          Color(0xFFF4A000),
                          Color(0xFFFF8C42),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        'Welcome back, $adminName',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      adminRoleText,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showOverviewPanel = !_showOverviewPanel;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Colors.orange, Colors.white, Colors.green],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cyan.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showOverviewPanel
                              ? Icons.visibility_off_rounded
                              : Icons.auto_awesome_mosaic_rounded,
                          color: AppColors.cyan,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _showOverviewPanel ? 'Hide Box' : 'Open Box',
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _showOverviewPanel
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Container(
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
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF8FD),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Admin Snapshot',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _showOverviewPanel = false;
                            });
                          },
                          icon: const Icon(
                            Icons.keyboard_arrow_up_rounded,
                            color: AppColors.cyan,
                          ),
                          label: const Text(
                            'Hide',
                            style: TextStyle(
                              color: AppColors.cyan,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_loadingOverview)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: CircularProgressIndicator(
                            color: AppColors.cyan,
                          ),
                        ),
                      )
                    else if (_overviewError != null)
                      _buildOverviewMessage(
                        _overviewError!,
                        onRetry: _loadDashboardSummary,
                      )
                    else ...[
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.0,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                        ),
                        itemCount: cards.length,
                        itemBuilder: (context, index) {
                          final card = cards[index];
                          final colors = [
                            const Color(0xFFEDEBFA),
                            const Color(0xFFE8F4EC),
                            const Color(0xFFF3F2E8),
                            const Color(0xFFEAF8F6),
                          ];
                          final backgroundColor = colors[index % colors.length];
                          return _buildOverviewCard(
                            label: (card['label'] ?? '').toString(),
                            value: (card['value'] ?? 0).toString(),
                            helper: (card['helper'] ?? '').toString(),
                            backgroundColor: backgroundColor,
                            onTap: () => _openSectionById(
                              card['sectionId']?.toString(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildHealthChip(
                                  'Unread Admin Alerts',
                                  (health['unreadAdminNotifications'] ?? 0)
                                      .toString(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildHealthChip(
                                  'Reported Ads',
                                  (health['reportedAds'] ?? 0).toString(),
                                ),
                              ),
                            ],
                          ),
                          if (_expandHealthAlerts) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildHealthChip(
                                    'Draft Updates',
                                    (health['draftUpdates'] ?? 0).toString(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildHealthChip(
                                    'Scheduled Updates',
                                    (health['scheduledUpdates'] ?? 0)
                                        .toString(),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildHealthChip(
                                    'Superadmins',
                                    (health['superAdmins'] ?? 0).toString(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(child: SizedBox.shrink()),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.orange,
                                    Colors.white,
                                    Colors.green
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () {
                                    setState(() {
                                      _expandHealthAlerts =
                                          !_expandHealthAlerts;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _expandHealthAlerts
                                              ? 'Show Less'
                                              : 'View More Alerts',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.cyan,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          _expandHealthAlerts
                                              ? Icons.keyboard_arrow_up_rounded
                                              : Icons
                                                  .keyboard_arrow_down_rounded,
                                          color: AppColors.cyan,
                                          size: 18,
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
                    ],
                  ],
                ),
              ),
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        Text(
          'Priority Queue',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingOverview)
          const SizedBox.shrink()
        else if (_overviewError != null)
          const Text(
            'Overview is unavailable right now, but admin tools are still available below.',
            style: TextStyle(color: Colors.grey),
          )
        else if (priorityItems.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'Nothing urgent is waiting right now. You can continue with regular admin tasks below.',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Column(
            children: priorityItems
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildPriorityCard(item),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildOverviewCard({
    required String label,
    required String value,
    required String helper,
    required Color backgroundColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.cyan,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        helper,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHealthChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF24657A),
        ),
      ),
    );
  }

  Widget _buildOverviewMessage(
    String message, {
    required VoidCallback onRetry,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.deepOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityCard(Map<String, dynamic> item) {
    final tone = (item['tone'] ?? 'info').toString();
    final toneColor = tone == 'critical'
        ? Colors.redAccent
        : tone == 'warning'
            ? Colors.orange
            : AppColors.cyan;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openSectionById(item['sectionId']?.toString()),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: toneColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.priority_high_rounded,
                    color: toneColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['title'] ?? '').toString(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (item['description'] ?? '').toString(),
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      (item['count'] ?? 0).toString(),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: toneColor,
                      ),
                    ),
                    if ((item['id'] ?? '') == 'pending-users')
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const UserManagementPage(
                                    initialStatusFilter: 'Pending',
                                  ),
                                ),
                              );
                            },
                            child: const Text('Review'),
                          ),
                          TextButton(
                            onPressed: _clearPendingUsers,
                            child: const Text('Review All'),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminOptionsLayout(List<_AdminDashboardItem> items) {
    if (_useCompactAdminOptions) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final itemWidth = (width - 16) / 2;

          return Wrap(
            spacing: 16,
            runSpacing: 24,
            children: items.map((item) {
              return SizedBox(
                key: _sectionKeys[item.id],
                width: itemWidth,
                child: _buildDashboardCard(
                  context,
                  item: item,
                  showCaption: false,
                ),
              );
            }).toList(),
          );
        },
      );
    }

    return Column(
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: SizedBox(
            key: _sectionKeys[item.id],
            width: double.infinity,
            child: _buildDashboardCard(
              context,
              item: item,
              showCaption: true,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAdminLayoutChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? AppColors.cyan : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.cyan,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: ClipPath(
                  clipper: LogoutDialogWaveClipper(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.cyan, Color(0xFF0096CC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      'Are you sure?',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Do you want to logout?',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.only(right: 8),
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[100],
                                foregroundColor: Colors.grey[700],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey[300]!),
                                ),
                                padding: EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.close, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'NO',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.only(left: 8),
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cyan,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.symmetric(vertical: 16),
                                elevation: 2,
                                shadowColor:
                                    AppColors.cyan.withValues(alpha: 0.3),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.logout, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'YES',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) {
      await Provider.of<SessionProvider>(context, listen: false).logout();
      Navigator.pushReplacementNamed(context, '/login');
    }
  }
}

class _AdminDashboardItem {
  final String id;
  final String? permissionKey;
  final IconData icon;
  final String label;
  final String caption;
  final String actionLabel;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _AdminDashboardItem({
    required this.id,
    this.permissionKey,
    required this.icon,
    required this.label,
    required this.caption,
    required this.actionLabel,
    required this.backgroundColor,
    required this.iconColor,
    required this.onTap,
  });
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.25, size.height, size.width * 0.5, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.4, size.width, size.height * 0.7);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}


class LogoutDialogWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);

    // Create wavy effect
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.8, size.width * 0.5, size.height);
    path.quadraticBezierTo(
        size.width * 0.25, size.height * 0.8, 0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
