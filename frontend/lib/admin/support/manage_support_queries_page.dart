import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../session.dart';
import '../../api_config.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class ManageSupportQueriesPage extends StatefulWidget {
  @override
  _ManageSupportQueriesPageState createState() =>
      _ManageSupportQueriesPageState();
}

class _ManageSupportQueriesPageState extends State<ManageSupportQueriesPage> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _queries = [];
  List<Map<String, dynamic>> _admins = [];
  Map<String, dynamic>? _currentAdmin;
  bool _isLoading = true;
  String? _error;
  IO.Socket? socket;
  String _searchTerm = ''; // Add search term
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  String _assignmentFilter = 'all';
  String _supportLane = 'all';
  Map<String, dynamic> _summary = const {};

  @override
  void initState() {
    super.initState();
    _fetchAllQueries();
    _loadAdmins();
    _connectSocket();
  }

  @override
  void dispose() {
    _searchController.dispose();
    socket?.disconnect();
    socket?.dispose();
    super.dispose();
  }

  void _connectSocket() {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final token = session.token;

    if (token == null) {
      return;
    }

    try {
      socket = IO.io(
        ApiConfig.baseUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableForceNew()
            .disableAutoConnect()
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .build(),
      );

      socket?.connect();

      socket?.on('support_query_created', (data) {
        setState(() {
          _queries.insert(0, data);
          _queries.sort((a, b) => DateTime.parse(b['createdAt'])
              .compareTo(DateTime.parse(a['createdAt'])));
        });
        _showStylishSnackBar(AppLocalizations.of(context).t('new_query_created'), Colors.green);
      });

      socket?.on('support_query_updated', (data) {
        final updatedQuery = data;
        setState(() {
          int index =
              _queries.indexWhere((q) => q['_id'] == updatedQuery['_id']);
          if (index != -1) {
            _queries[index] = updatedQuery;
          } else {
            _queries.add(updatedQuery);
          }
          _queries.sort((a, b) => DateTime.parse(b['createdAt'])
              .compareTo(DateTime.parse(a['createdAt'])));
        });
        _showStylishSnackBar(AppLocalizations.of(context).t('query_updated'), Colors.orange);
      });

      socket?.on('support_query_deleted', (data) {
        final deletedQueryId = data['queryId'];
        setState(() {
          _queries.removeWhere((q) => q['_id'] == deletedQueryId);
        });
        _showStylishSnackBar(AppLocalizations.of(context).t('query_deleted'), Colors.red);
      });

      // Optionally, join a room for admin-specific updates if needed
      // socket?.emit('join_admin_room', {'adminId': session.user?['_id']});
    } catch (_) {}
  }

  Future<void> _fetchAllQueries({String? searchTerm}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final path = '/api/admin/support/queries' +
          '?searchTerm=${Uri.encodeComponent(searchTerm ?? _searchTerm)}'
              '&status=${Uri.encodeComponent(_statusFilter)}'
              '&priority=${Uri.encodeComponent(_priorityFilter)}'
              '&assigned=${Uri.encodeComponent(_assignmentFilter)}';
      final response = await ApiClient.get(path);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _queries = data['queries'] ?? [];
          _summary = data['summary'] is Map
              ? Map<String, dynamic>.from(data['summary'])
              : const {};
          _currentAdmin = data['currentAdmin'] is Map
              ? Map<String, dynamic>.from(data['currentAdmin'])
              : null;
          _isLoading = false;
        });
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _error = data['error'] ?? 'Failed to load queries.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'An error occurred: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAdmins() async {
    try {
      final response = await ApiClient.get('/api/admin/admins');
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          _admins = List<Map<String, dynamic>>.from(
            (data['admins'] ?? []).map((item) => Map<String, dynamic>.from(item)),
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _replyToQuery(String queryId, String replyText) async {
    final t = AppLocalizations.of(context).t;
    if (replyText.isEmpty) {
      _showStylishSnackBar(t('reply_cannot_be_empty'), Colors.red);
      return;
    }

    final session = Provider.of<SessionProvider>(context, listen: false);
    final token = session.token;

    if (token == null) {
      _showStylishSnackBar(t('authentication_token_not_found'), Colors.red);
      return;
    }

    try {
      final response = await ApiClient.post(
        '/api/admin/support/queries/$queryId/reply',
        body: {'replyText': replyText},
      );

      if (response.statusCode == 200) {
        _showStylishSnackBar(t('reply_added_successfully'), Colors.green);
        final updatedQuery = jsonDecode(response.body)['query'];
        setState(() {
          int index =
              _queries.indexWhere((q) => q['_id'] == updatedQuery['_id']);
          if (index != -1) {
            _queries[index] = updatedQuery;
          }
        });
      } else {
        final data = jsonDecode(response.body);
        _showStylishSnackBar(
            data['error'] ?? t('failed_to_add_reply'), Colors.red);
      }
    } catch (e) {
      _showStylishSnackBar(t('network_error_adding_reply'), Colors.red);
    }
  }

  Future<void> _editReply(
      String queryId, String replyId, String newReplyText) async {
    final t = AppLocalizations.of(context).t;
    if (newReplyText.isEmpty) {
      _showStylishSnackBar(t('reply_cannot_be_empty'), Colors.red);
      return;
    }

    final session = Provider.of<SessionProvider>(context, listen: false);
    final token = session.token;

    if (token == null) {
      _showStylishSnackBar(t('authentication_token_not_found'), Colors.red);
      return;
    }

    try {
      final response = await ApiClient.put(
        '/api/admin/support/queries/$queryId/replies/$replyId',
        body: {'replyText': newReplyText},
      );

      if (response.statusCode == 200) {
        _showStylishSnackBar(t('reply_updated_successfully'), Colors.green);
        final updatedQuery = jsonDecode(response.body)['query'];
        setState(() {
          int index =
              _queries.indexWhere((q) => q['_id'] == updatedQuery['_id']);
          if (index != -1) {
            _queries[index] = updatedQuery;
          }
        });
      } else {
        final data = jsonDecode(response.body);
        _showStylishSnackBar(
            data['error'] ?? t('failed_to_update_reply'), Colors.red);
      }
    } catch (e) {
      _showStylishSnackBar(t('network_error_editing_reply'), Colors.red);
    }
  }

  Future<void> _deleteReply(String queryId, String replyId) async {
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.delete(
          '/api/admin/support/queries/$queryId/replies/$replyId');

      if (response.statusCode == 200) {
        _showStylishSnackBar(t('reply_deleted_successfully'), Colors.green);
        final updatedQuery = jsonDecode(response.body)['query'];
        setState(() {
          int index =
              _queries.indexWhere((q) => q['_id'] == updatedQuery['_id']);
          if (index != -1) {
            _queries[index] = updatedQuery;
          }
        });
      } else {
        final data = jsonDecode(response.body);
        _showStylishSnackBar(
            data['error'] ?? t('failed_to_delete_reply'), Colors.red);
      }
    } catch (e) {
      _showStylishSnackBar(t('network_error_deleting_reply'), Colors.red);
    }
  }

  Future<void> _updateQueryStatus(String queryId, String status) async {
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.patch(
        '/api/admin/support/queries/$queryId/status',
        body: {'status': status},
      );

      if (response.statusCode == 200) {
        _showStylishSnackBar(
            t('query_status_updated_successfully'), Colors.green);
        final updatedQuery = jsonDecode(response.body)['query'];
        setState(() {
          int index =
              _queries.indexWhere((q) => q['_id'] == updatedQuery['_id']);
          if (index != -1) {
            _queries[index] = updatedQuery;
          }
        });
      } else {
        final data = jsonDecode(response.body);
        _showStylishSnackBar(
            data['error'] ?? t('failed_to_update_status'), Colors.red);
      }
    } catch (e) {
      _showStylishSnackBar(t('network_error_updating_status'), Colors.red);
    }
  }

  Future<void> _updateWorkflow(
    String queryId, {
    String? priority,
    String? assignedAdminId,
    String? internalNote,
  }) async {
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.patch(
        '/api/admin/support/queries/$queryId/workflow',
        body: {
          if (priority != null) 'priority': priority,
          if (assignedAdminId != null) 'assignedAdminId': assignedAdminId,
          if (internalNote != null) 'internalNote': internalNote,
        },
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final updated = data['query'];
        setState(() {
          final index = _queries.indexWhere((q) => q['_id'] == updated['_id']);
          if (index != -1) {
            _queries[index] = updated;
          }
        });
        _showStylishSnackBar(
          data['message'] ?? t('support_workflow_updated'),
          Colors.green,
        );
      } else {
        _showStylishSnackBar(
          data['error'] ?? t('failed_to_update_support_workflow'),
          Colors.red,
        );
      }
    } catch (e) {
      _showStylishSnackBar(
        t('network_error_updating_support_workflow'),
        Colors.red,
      );
    }
  }

  Future<void> _exportQueries() async {
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.get('/api/admin/support/queries/export');
      if (response.statusCode == 200) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppThemeColors.cardBg(context),
            title: Text(t('support_export_csv'),
                style: TextStyle(color: AppThemeColors.primaryText(context))),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: SelectableText(response.body,
                    style: TextStyle(color: AppThemeColors.primaryText(context))),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t('close')),
              ),
            ],
          ),
        );
      } else {
        _showStylishSnackBar(t('failed_export_support_queries'), Colors.red);
      }
    } catch (_) {
      _showStylishSnackBar(t('network_error_exporting_queries'), Colors.red);
    }
  }

  void _showStylishSnackBar(String message, Color color) =>
      showSnack(context, message, isError: color == Colors.red);

  String _formatDateTime(String dateTimeString) {
    final dateTime = DateTime.parse(dateTimeString);
    return DateFormat('MMM d, yyyy h:mm a').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    // Filter queries by search term if present
    List<dynamic> filteredQueries = _searchTerm.isEmpty
        ? _queries
        : _queries
            .where((q) => (q['topic'] ?? '')
                .toString()
                .toLowerCase()
                .contains(_searchTerm.toLowerCase()))
            .toList();

    if (_supportLane == 'open') {
      filteredQueries =
          filteredQueries.where((q) => (q['status'] ?? '') == 'open').toList();
    } else if (_supportLane == 'mine') {
      final adminId = _currentAdmin?['_id']?.toString();
      filteredQueries = filteredQueries
          .where((q) => q['assignedAdmin'] is Map && q['assignedAdmin']['_id']?.toString() == adminId)
          .toList();
    } else if (_supportLane == 'critical') {
      filteredQueries = filteredQueries
          .where((q) => (q['priority'] ?? '') == 'critical')
          .toList();
    } else if (_supportLane == 'resolved') {
      filteredQueries = filteredQueries
          .where((q) => (q['status'] ?? '') == 'resolved')
          .toList();
    }

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: AppThemeColors.iconOnWave(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            t('manage_support_queries'),
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                                color: AppThemeColors.iconOnWave(context)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: InputDecoration(
                      labelText: t('search_by_topic'),
                      prefixIcon: Icon(Icons.search, color: AppColors.cyan),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                      filled: true,
                      fillColor: AppThemeColors.cardBg(context),
                      suffixIcon: _searchTerm.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: AppThemeColors.secondaryText(context)),
                              onPressed: () {
                                setState(() {
                                  _searchTerm = '';
                                  _searchController.clear();
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchTerm = value;
                      });
                    },
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.support_agent, color: AppColors.cyan),
                      SizedBox(width: 8),
                      Text(
                        t('all_support_queries'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppThemeColors.isDark(context)
                              ? AppThemeColors.primaryText(context)
                              : const Color(0xFF0077B5),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _exportQueries,
                        icon: const Icon(Icons.download_rounded),
                        label: Text(t('export_csv')),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildSummaryChip(t('open'), '${_summary['open'] ?? 0}'),
                      _buildSummaryChip(t('in_progress'), '${_summary['inProgress'] ?? 0}'),
                      _buildSummaryChip(t('critical'), '${_summary['critical'] ?? 0}'),
                      _buildSummaryChip(t('assigned_to_me'), '${_summary['assignedToMe'] ?? 0}'),
                      _buildSummaryChip(t('overdue'), '${_summary['overdue'] ?? 0}'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildLaneChip('all', t('all')),
                      _buildLaneChip('open', t('open')),
                      _buildLaneChip('mine', t('assigned_to_me')),
                      _buildLaneChip('critical', t('critical')),
                      _buildLaneChip('resolved', t('resolved')),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _statusFilter,
                          decoration: InputDecoration(
                            labelText: t('status'),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: AppThemeColors.cardBg(context),
                          ),
                          items: [
                            DropdownMenuItem(value: 'all', child: Text(t('all'))),
                            DropdownMenuItem(value: 'open', child: Text(t('open'))),
                            DropdownMenuItem(value: 'in_progress', child: Text(t('in_progress'))),
                            DropdownMenuItem(value: 'resolved', child: Text(t('resolved'))),
                            DropdownMenuItem(value: 'closed', child: Text(t('closed'))),
                          ],
                          onChanged: (value) {
                            setState(() => _statusFilter = value ?? 'all');
                            _fetchAllQueries();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _priorityFilter,
                          decoration: InputDecoration(
                            labelText: t('priority'),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: AppThemeColors.cardBg(context),
                          ),
                          items: [
                            DropdownMenuItem(value: 'all', child: Text(t('all'))),
                            DropdownMenuItem(value: 'low', child: Text(t('low'))),
                            DropdownMenuItem(value: 'normal', child: Text(t('normal'))),
                            DropdownMenuItem(value: 'high', child: Text(t('high'))),
                            DropdownMenuItem(value: 'critical', child: Text(t('critical'))),
                          ],
                          onChanged: (value) {
                            setState(() => _priorityFilter = value ?? 'all');
                            _fetchAllQueries();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _assignmentFilter,
                          decoration: InputDecoration(
                            labelText: t('assigned'),
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: AppThemeColors.cardBg(context),
                          ),
                          items: [
                            DropdownMenuItem(value: 'all', child: Text(t('all'))),
                            DropdownMenuItem(value: 'mine', child: Text(t('mine'))),
                            DropdownMenuItem(value: 'unassigned', child: Text(t('unassigned'))),
                          ],
                          onChanged: (value) {
                            setState(() => _assignmentFilter = value ?? 'all');
                            _fetchAllQueries();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 8),
                Expanded(
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(_error!,
                                  style: TextStyle(color: Colors.red)))
                          : filteredQueries.isEmpty
                              ? Center(child: Text(t('no_support_queries_found'),
                                  style: TextStyle(color: AppThemeColors.secondaryText(context))))
                              : ListView.builder(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  itemCount: filteredQueries.length,
                                  itemBuilder: (context, index) {
                                    final query = filteredQueries[index];
                                    return _buildQueryCard(query);
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.black;
    }
  }

  Widget _buildSummaryChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: AppThemeColors.isDark(context)
              ? AppThemeColors.primaryText(context)
              : const Color(0xFF0077B5),
        ),
      ),
    );
  }

  Widget _buildLaneChip(String value, String label) {
    final selected = _supportLane == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _supportLane = value),
      backgroundColor: AppThemeColors.cardBg(context),
      selectedColor: AppColors.cyan.withValues(alpha: 0.16),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected
            ? (AppThemeColors.isDark(context)
                ? AppThemeColors.primaryText(context)
                : const Color(0xFF0077B5))
            : AppThemeColors.primaryText(context),
      ),
    );
  }

  Widget _buildQueryCard(Map<String, dynamic> query) {
    final t = AppLocalizations.of(context).t;
    final assignedAdmin = query['assignedAdmin'] is Map
        ? Map<String, dynamic>.from(query['assignedAdmin'])
        : null;
    final internalNotes = (query['internalNotes'] as List?) ?? const [];
    final isOverdue = query['isOverdue'] == true;
    return Card(
      margin: EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 6,
      color: AppThemeColors.cardBg(context),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.question_answer, color: AppColors.cyan),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    query['topic'],
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.isDark(context)
                            ? AppThemeColors.primaryText(context)
                            : const Color(0xFF0077B5)),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _getStatusColor(query['status']).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    query['status'].toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(query['status']),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (isOverdue) ...[
                  SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      t('overdue'),
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.person, size: 18, color: AppThemeColors.secondaryText(context)),
                SizedBox(width: 6),
                Text(
                  '${t('user_label')}: ${query['user']?['email'] ?? query['user']?['username'] ?? t('unknown')}',
                  style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 14),
                ),
              ],
            ),
            SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${t('priority')}: ${(query['priority'] ?? 'normal').toString().toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${t('assigned')}: ${(assignedAdmin?['email'] ?? t('unassigned')).toString()}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(query['description'],
                style: TextStyle(fontSize: 16, color: AppThemeColors.primaryText(context))),
            SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: AppThemeColors.secondaryText(context)),
                SizedBox(width: 4),
                Text(
                  '${t('submitted')}: ${_formatDateTime(query['createdAt'])}',
                  style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: (query['priority'] ?? 'normal').toString(),
                    decoration: InputDecoration(
                      labelText: t('priority'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: 'low', child: Text(t('low'))),
                      DropdownMenuItem(value: 'normal', child: Text(t('normal'))),
                      DropdownMenuItem(value: 'high', child: Text(t('high'))),
                      DropdownMenuItem(value: 'critical', child: Text(t('critical'))),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _updateWorkflow(query['_id'], priority: value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: assignedAdmin?['_id']?.toString() ?? '',
                    decoration: InputDecoration(
                      labelText: t('assign_to'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: '', child: Text(t('unassigned'))),
                      ..._admins.map(
                        (admin) => DropdownMenuItem(
                          value: admin['_id'].toString(),
                          child: Text((admin['email'] ?? '').toString()),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      _updateWorkflow(
                        query['_id'],
                        assignedAdminId: value ?? '',
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _showInternalNoteDialog(query['_id']),
                icon: const Icon(Icons.sticky_note_2_outlined),
                label: Text(t('add_internal_note')),
              ),
            ),
            if (internalNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                t('internal_notes'),
                style: TextStyle(fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
              ),
              const SizedBox(height: 8),
              ...internalNotes.take(3).map<Widget>((note) {
                final noteMap = note is Map
                    ? Map<String, dynamic>.from(note)
                    : <String, dynamic>{};
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppThemeColors.surfaceBg(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (noteMap['noteText'] ?? '').toString(),
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${noteMap['admin'] is Map ? (noteMap['admin']['email'] ?? '') : ''} • ${noteMap['timestamp'] != null ? _formatDateTime(noteMap['timestamp']) : ''}',
                        style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context)),
                      ),
                    ],
                  ),
                );
              }),
            ],
            if (query['replies'] != null && query['replies'].isNotEmpty)
              _buildReplies(query['_id'].toString(), query['replies']),
            SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                DropdownButton<String>(
                  value: query['status'],
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      _updateQueryStatus(query['_id'], newValue);
                    }
                  },
                  items: <String>['open', 'in_progress', 'resolved', 'closed']
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value.toUpperCase()),
                    );
                  }).toList(),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.isDark(context)
                          ? AppThemeColors.primaryText(context)
                          : const Color(0xFF0077B5)),
                  dropdownColor: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => _showReplyDialog(query['_id']),
                  icon: Icon(Icons.reply, size: 18),
                  label: Text(t('reply')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplies(String queryId, List<dynamic> replies) {
    final t = AppLocalizations.of(context).t;
    return Padding(
      padding: const EdgeInsets.only(top: 18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t('reply')}:',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.cyan),
          ),
          SizedBox(height: 10),
          ...replies.map<Widget>((reply) {
            return Container(
              margin: EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppThemeColors.isDark(context)
                    ? AppThemeColors.surfaceBg(context)
                    : Colors.blue[50],
                border: Border.all(color: AppColors.cyan, width: 1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.admin_panel_settings,
                          size: 16,
                          color: AppThemeColors.isDark(context)
                              ? AppThemeColors.primaryText(context)
                              : const Color(0xFF0077B5)),
                      SizedBox(width: 4),
                      Text(
                        '${t('administrator')}: ${reply['admin']?['email'] ?? t('unknown')}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppThemeColors.isDark(context)
                                ? AppThemeColors.primaryText(context)
                                : const Color(0xFF0077B5)),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    reply['replyText'],
                    style: TextStyle(fontSize: 15, color: AppThemeColors.primaryText(context)),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 13, color: AppThemeColors.secondaryText(context)),
                      SizedBox(width: 3),
                      Text(
                        '${t('replied')}: ${_formatDateTime(reply['timestamp'])}',
                        style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 11),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit,
                            size: 18,
                            color: AppThemeColors.isDark(context)
                                ? AppThemeColors.primaryText(context)
                                : const Color(0xFF0077B5)),
                        onPressed: () => _showEditReplyDialog(
                            queryId, reply['_id'], reply['replyText']),
                        tooltip: t('edit_reply'),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete,
                            size: 18, color: Colors.red[700]),
                        onPressed: () => _deleteReply(queryId, reply['_id']),
                        tooltip: t('delete_reply'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  void _showReplyDialog(String queryId) {
    final t = AppLocalizations.of(context).t;
    final TextEditingController replyController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: AppThemeColors.cardBg(context),
        child: Container(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('add_reply'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: AppColors.cyan)),
              SizedBox(height: 16),
              TextField(
                controller: replyController,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  labelText: t('your_reply'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: Icon(Icons.reply, color: AppColors.cyan),
                ),
                maxLines: 3,
              ),
              SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t('cancel')),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: Icon(Icons.send, color: Colors.white),
                    label: Text(t('send_reply')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      _replyToQuery(queryId, replyController.text);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditReplyDialog(
      String queryId, String replyId, String currentReplyText) {
    final t = AppLocalizations.of(context).t;
    final TextEditingController editReplyController =
        TextEditingController(text: currentReplyText);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: AppThemeColors.cardBg(context),
        child: Container(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('edit_reply'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: AppColors.cyan)),
              SizedBox(height: 16),
              TextField(
                controller: editReplyController,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  labelText: t('edit_your_reply'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: Icon(Icons.edit, color: AppColors.cyan),
                ),
                maxLines: 3,
              ),
              SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t('cancel')),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: Icon(Icons.save, color: Colors.white),
                    label: Text(t('save_changes')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      _editReply(queryId, replyId, editReplyController.text);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInternalNoteDialog(String queryId) {
    final t = AppLocalizations.of(context).t;
    final TextEditingController noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: AppThemeColors.cardBg(context),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('add_internal_note'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: AppColors.cyan)),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  labelText: t('internal_note_admins_only'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.sticky_note_2, color: AppColors.cyan),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t('cancel')),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      _updateWorkflow(queryId, internalNote: noteController.text);
                      Navigator.of(context).pop();
                    },
                    child: Text(t('add_note')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
