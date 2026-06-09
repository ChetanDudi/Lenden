import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/api_client.dart';

class AdminContentAnalyticsPage extends StatefulWidget {
  const AdminContentAnalyticsPage({super.key});

  @override
  State<AdminContentAnalyticsPage> createState() =>
      _AdminContentAnalyticsPageState();
}

class _AdminContentAnalyticsPageState extends State<AdminContentAnalyticsPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _topAds = [];
  List<Map<String, dynamic>> _topUpdates = [];
  List<Map<String, dynamic>> _moderationQueue = [];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ApiClient.get('/api/admin/content-analytics');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(
            (data['error'] ?? 'Failed to load analytics').toString());
      }

      setState(() {
        _summary = Map<String, dynamic>.from(data['summary'] ?? {});
        _topAds = List<Map<String, dynamic>>.from(
          (data['topAds'] ?? []).map((item) => Map<String, dynamic>.from(item)),
        );
        _topUpdates = List<Map<String, dynamic>>.from(
          (data['topUpdates'] ?? [])
              .map((item) => Map<String, dynamic>.from(item)),
        );
        _moderationQueue = List<Map<String, dynamic>>.from(
          (data['moderationQueue'] ?? [])
              .map((item) => Map<String, dynamic>.from(item)),
        );
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _TopWaveClipper(),
              child: Container(
                height: 165,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                      ),
                      const Expanded(
                        child: Text(
                          'Content Analytics',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _loadAnalytics,
                        icon: const Icon(Icons.refresh, color: Colors.black),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadAnalytics,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.only(top: 100),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF00B4D8),
                              ),
                            ),
                          )
                        else if (_error != null)
                          _buildMessageCard(_error!, true)
                        else ...[
                          _buildSummarySection(),
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            title: 'Top Ads',
                            subtitle:
                                'Best performing ads by clicks and reach.',
                            child: _topAds.isEmpty
                                ? _buildEmpty('No ad analytics available yet.')
                                : Column(
                                    children:
                                        _topAds.map(_buildTopAdTile).toList(),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            title: 'Top Updates',
                            subtitle: 'Most-read updates across users.',
                            child: _topUpdates.isEmpty
                                ? _buildEmpty(
                                    'No update analytics available yet.')
                                : Column(
                                    children: _topUpdates
                                        .map(_buildTopUpdateTile)
                                        .toList(),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            title: 'Moderation Queue',
                            subtitle:
                                'Reported or frequently hidden ads that may need review.',
                            child: _moderationQueue.isEmpty
                                ? _buildEmpty('No moderation items right now.')
                                : Column(
                                    children: _moderationQueue
                                        .map(_buildModerationTile)
                                        .toList(),
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    final cards = [
      _summaryCard('Ads', '${_summary['totalAds'] ?? 0}', Icons.ondemand_video),
      _summaryCard('Active Ads', '${_summary['activeAds'] ?? 0}',
          Icons.play_circle_fill),
      _summaryCard('Ad Views', '${_summary['totalImpressions'] ?? 0}',
          Icons.remove_red_eye),
      _summaryCard(
          'Ad CTR', '${_summary['averageCtr'] ?? 0}%', Icons.ads_click),
      _summaryCard('Reports', '${_summary['totalReports'] ?? 0}', Icons.report),
      _summaryCard('Updates', '${_summary['totalUpdates'] ?? 0}',
          Icons.campaign_outlined),
      _summaryCard('Published', '${_summary['publishedUpdates'] ?? 0}',
          Icons.publish_outlined),
      _summaryCard(
          'Reads', '${_summary['totalReads'] ?? 0}', Icons.visibility_outlined),
      _summaryCard('Critical', '${_summary['criticalUpdates'] ?? 0}',
          Icons.priority_high),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 24) / 3;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cards
                .map(
                  (card) => SizedBox(
                    width: cardWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: card,
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget _summaryCard(String label, String value, IconData icon) {
    return SizedBox(
      width: 110,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFF00B4D8)),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF00B4D8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildTopAdTile(Map<String, dynamic> ad) {
    final stats = Map<String, dynamic>.from((ad['stats'] ?? {}) as Map);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFEAF5FF),
        child: Icon(
          (ad['mediaKind'] ?? 'none').toString() == 'video'
              ? Icons.play_circle_outline
              : Icons.image_outlined,
          color: const Color(0xFF00B4D8),
        ),
      ),
      title: Text(
        (ad['title'] ?? '').toString(),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        'Clicks ${stats['clicks'] ?? 0} • Views ${stats['impressions'] ?? 0} • CTR ${stats['ctr'] ?? 0}%',
      ),
      trailing: Text(
        '${stats['reports'] ?? 0} reports',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildTopUpdateTile(Map<String, dynamic> update) {
    final stats = Map<String, dynamic>.from((update['stats'] ?? {}) as Map);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFEAF5FF),
        child: Icon(Icons.campaign_outlined, color: Color(0xFF00B4D8)),
      ),
      title: Text(
        (update['title'] ?? '').toString(),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${(update['status'] ?? 'published').toString()} • ${(update['importance'] ?? 'normal').toString()}',
      ),
      trailing: Text(
        '${stats['readCount'] ?? 0} reads',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildModerationTile(Map<String, dynamic> ad) {
    final stats = Map<String, dynamic>.from((ad['stats'] ?? {}) as Map);
    final moderation =
        Map<String, dynamic>.from((ad['moderation'] ?? {}) as Map);
    final reports = List<Map<String, dynamic>>.from(
      (moderation['recentReports'] ?? [])
          .map((item) => Map<String, dynamic>.from(item)),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBFF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (ad['title'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${stats['reports'] ?? 0} reports',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Hidden ${stats['hides'] ?? 0} times • Audience ${(ad['audience'] ?? 'nonsubscribed').toString()}',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (reports.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...reports.map(
              (report) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${(report['reason'] ?? '').toString().trim().isEmpty ? 'No reason provided' : report['reason']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageCard(String message, bool isError) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? Colors.redAccent : Colors.green.shade800,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.5,
      size.width * 0.5,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
