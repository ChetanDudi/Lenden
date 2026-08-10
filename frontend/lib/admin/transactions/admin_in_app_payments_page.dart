import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import './widgets/in_app_tab.dart';

// ── Main page ─────────────────────────────────────────────────────────────────

class AdminInAppPaymentsPage extends StatefulWidget {
  const AdminInAppPaymentsPage({super.key});

  @override
  State<AdminInAppPaymentsPage> createState() => _AdminInAppPaymentsPageState();
}

class _AdminInAppPaymentsPageState extends State<AdminInAppPaymentsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, int> _catCounts = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kInAppCats.length, vsync: this);
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final res = await ApiClient.get('/api/admin/in-app-transactions/counts');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _catCounts = data.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text('In-App Transfers',
            style: TextStyle(
                color: AppThemeColors.primaryText(context),
                fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.cyan,
          labelColor: AppColors.cyan,
          unselectedLabelColor: AppThemeColors.secondaryText(context),
          indicatorWeight: 3,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: kInAppCats.map((c) {
            final count = _catCounts[c.key];
            final hasCount = count != null && count > 0;
            return Tab(
              icon: hasCount
                  ? Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(c.icon, size: 16),
                        Positioned(
                          top: -6,
                          right: -8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                            decoration: BoxDecoration(
                              color: c.color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              count > 99 ? '99+' : count.toString(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Icon(c.icon, size: 16),
              text: c.label,
            );
          }).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: kInAppCats.map((c) => InAppTab(cat: c, catCounts: _catCounts)).toList(),
      ),
    );
  }
}