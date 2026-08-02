import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/app_colors.dart';

class MyDisputesPage extends StatefulWidget {
  const MyDisputesPage({super.key});

  @override
  State<MyDisputesPage> createState() => _MyDisputesPageState();
}

class _MyDisputesPageState extends State<MyDisputesPage> {
  List<dynamic> _disputes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchDisputes();
  }

  Future<void> _fetchDisputes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/api/disputes/mine');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _disputes = data['disputes'] ?? [];
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load disputes.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'under_review':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _statusLabel(String status) =>
      status.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text('My Disputes',
            style: TextStyle(color: AppThemeColors.primaryText(context), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _disputes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.gavel_rounded, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('No disputes raised yet.',
                              style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchDisputes,
                      color: AppColors.cyan,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _disputes.length,
                        itemBuilder: (context, index) {
                          final d = _disputes[index];
                          final status = (d['status'] ?? 'open').toString();
                          final createdAt = DateTime.tryParse((d['createdAt'] ?? '').toString());
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text((d['reason'] ?? '').toString(),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold, fontSize: 16)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(_statusLabel(status),
                                          style: TextStyle(
                                              color: _statusColor(status),
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text((d['description'] ?? '').toString(),
                                    style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13)),
                                const SizedBox(height: 8),
                                Text(
                                  'Transaction type: ${(d['transactionType'] ?? '').toString()}'
                                  '${createdAt != null ? ' • ${DateFormat('MMM dd, yyyy').format(createdAt)}' : ''}',
                                  style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 11),
                                ),
                                if (d['resolution'] != null &&
                                    (d['resolution'] as String).isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppThemeColors.tinted(context, light: Color(0xFFF0F7FF), dark: Color(0xFF0A1929)),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'Admin resolution: ${d['resolution']}',
                                      style: TextStyle(
                                          fontSize: 12, color: AppThemeColors.primaryText(context)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
