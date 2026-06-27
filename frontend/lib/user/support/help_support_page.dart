import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../api_config.dart';
import '../../utils/api_client.dart';
import '../../session.dart';
import 'contact_page.dart';
import 'my_disputes_page.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class HelpSupportPage extends StatefulWidget {
  @override
  _HelpSupportPageState createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _queries = [];
  bool _isLoading = true;
  String? _error;
  IO.Socket? socket;
  bool _showAllQueries = false;
  String _searchTerm = '';

  static const _cyan = AppColors.cyan;
  static const _blue = AppColors.blue;

  @override
  void initState() {
    super.initState();
    _fetchUserQueries();
    _connectSocket();
  }

  @override
  void dispose() {
    _topicController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    socket?.disconnect();
    socket?.dispose();
    super.dispose();
  }

  void _connectSocket() {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    final token = session.token;
    if (token == null) return;

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
      socket?.onConnect((_) => print('Socket Connected: ${socket?.id}'));
      socket?.onDisconnect((_) => print('Socket Disconnected'));
      socket?.onConnectError((err) => print('Socket Connect Error: $err'));
      socket?.onError((err) => print('Socket Error: $err'));

      socket?.on('support_query_created', (data) {
        if (data['user'] != null &&
            data['user']['_id'] == session.user?['_id']) {
          setState(() => _queries.insert(0, data));
          _snack(t('query_created_message'), Colors.green);
        }
      });

      socket?.on('support_query_updated', (data) {
        setState(() {
          int i = _queries.indexWhere((q) => q['_id'] == data['_id']);
          if (i != -1) {
            _queries[i] = data;
          } else {
            _queries.add(data);
          }
          _queries.sort((a, b) => DateTime.parse(b['createdAt'])
              .compareTo(DateTime.parse(a['createdAt'])));
        });
        _snack(t('query_updated_message'), Colors.orange);
      });

      socket?.on('support_query_deleted', (data) {
        setState(() =>
            _queries.removeWhere((q) => q['_id'] == data['queryId']));
        _snack(t('query_deleted_message'), Colors.red);
      });
    } catch (e) {
      print('Error connecting to socket: $e');
    }
  }

  Future<void> _fetchUserQueries() async {
    final t = AppLocalizations.of(context).t;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.get('/api/support/queries/me');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _queries = data['queries'] ?? [];
          _isLoading = false;
        });
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _error = data['error'] ?? t('failed_to_load_queries_message');
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = t('an_error_occurred_message').replaceFirst('{error}', '$e');
        _isLoading = false;
      });
    }
  }

  Future<void> _submitQuery() async {
    final t = AppLocalizations.of(context).t;
    if (_topicController.text.isEmpty || _descriptionController.text.isEmpty) {
      _snack(t('fill_topic_and_description_message'), Colors.red);
      return;
    }
    try {
      final response = await ApiClient.post(
        '/api/support/queries',
        body: {
          'topic': _topicController.text,
          'description': _descriptionController.text,
        },
      );
      if (response.statusCode == 201) {
        _snack(t('query_submitted_successfully_message'), Colors.green);
        _topicController.clear();
        _descriptionController.clear();
      } else {
        final data = jsonDecode(response.body);
        _snack(data['error'] ?? t('failed_to_submit_query_message'), Colors.red);
      }
    } catch (e) {
      _snack(t('network_error_submitting_query_message'), Colors.red);
    }
  }

  void _snack(String message, Color color) =>
      showSnack(context, message, isError: color == Colors.red);

  Future<void> _editQuery(
      String queryId, String currentTopic, String currentDescription) async {
    final t = AppLocalizations.of(context).t;
    _topicController.text = currentTopic;
    _descriptionController.text = currentDescription;

    await showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppThemeColors.cardBg(dialogContext),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('edit_support_query_label'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: _cyan)),
              const SizedBox(height: 16),
              TextField(
                controller: _topicController,
                style: TextStyle(color: AppThemeColors.primaryText(dialogContext)),
                decoration: InputDecoration(
                  labelText: t('topic_label'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.topic, color: _cyan),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                style: TextStyle(color: AppThemeColors.primaryText(dialogContext)),
                decoration: InputDecoration(
                  labelText: t('description_label'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.description, color: _cyan),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _topicController.clear();
                      _descriptionController.clear();
                    },
                    child: Text(t('cancel')),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: Text(t('save')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cyan,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (_topicController.text.isEmpty ||
                          _descriptionController.text.isEmpty) {
                        _snack(t('fill_both_fields_message'), Colors.red);
                        return;
                      }
                      try {
                        final response = await ApiClient.put(
                          '/api/support/queries/$queryId',
                          body: {
                            'topic': _topicController.text,
                            'description': _descriptionController.text,
                          },
                        );
                        if (response.statusCode == 200) {
                          _snack(t('query_updated_successfully_message'), Colors.green);
                          Navigator.of(dialogContext).pop();
                          _topicController.clear();
                          _descriptionController.clear();
                        } else {
                          final data = response.body.isNotEmpty
                              ? jsonDecode(response.body)
                              : null;
                          _snack(data?['error'] ?? t('failed_to_update_query_message'),
                              Colors.red);
                        }
                      } catch (e) {
                        _snack(t('network_error_editing_query_message'), Colors.red);
                      }
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

  Future<void> _deleteQuery(String queryId) async {
    final t = AppLocalizations.of(context).t;
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.warning, color: Colors.red),
                const SizedBox(width: 8),
                Text(t('confirm_deletion_label'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(t('confirm_delete_query_message')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(t('cancel')),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete, color: Colors.white),
                label: Text(t('delete')),
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      final response = await ApiClient.delete('/api/support/queries/$queryId');
      if (response.statusCode == 200) {
        _snack(t('query_deleted_successfully_message'), Colors.green);
        setState(() => _queries.removeWhere((q) => q['_id'] == queryId));
      } else {
        final data =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        _snack(data?['error'] ?? t('failed_to_delete_query_message'), Colors.red);
      }
    } catch (e) {
      _snack(t('network_error_deleting_query_message'), Colors.red);
    }
  }

  String _formatDateTime(String s) =>
      DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(s));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final filtered = _searchTerm.isEmpty
        ? _queries
        : _queries
            .where((q) => (q['topic'] ?? '')
                .toString()
                .toLowerCase()
                .contains(_searchTerm.toLowerCase()))
            .toList();

    final displayed = _showAllQueries
        ? filtered
        : (filtered.length > 3 ? filtered.sublist(0, 3) : filtered);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(t('help_and_support_label'),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          // S-shape cyan wave
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _HelpWaveClipper(),
              child: Container(
                height: 115,
                color: _cyan,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick access card
                  tricolorBorder(
                    child: Container(
                      color: AppThemeColors.cardBg(context),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        leading: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _cyan.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.contact_support_rounded,
                              color: _cyan),
                        ),
                        title: Text(t('contact_support_label'),
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15, color: AppThemeColors.primaryText(context))),
                        subtitle: Text(t('send_a_message_to_our_team_message'),
                            style: const TextStyle(color: _blue, fontSize: 12)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded,
                            size: 16, color: _blue),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const ContactPage())),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // My Disputes card
                  tricolorBorder(
                    child: Container(
                      color: AppThemeColors.cardBg(context),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        leading: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.gavel_rounded,
                              color: Colors.deepOrange),
                        ),
                        title: Text(t('my_disputes_label'),
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15, color: AppThemeColors.primaryText(context))),
                        subtitle: Text(
                            t('track_disputes_raised_or_named_message'),
                            style: const TextStyle(color: _blue, fontSize: 12)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded,
                            size: 16, color: _blue),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const MyDisputesPage())),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Search bar
                  tricolorBorder(
                    radius: 14,
                    child: Container(
                      color: AppThemeColors.cardBg(context),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: AppThemeColors.primaryText(context)),
                        decoration: InputDecoration(
                          hintText: t('search_your_queries_hint'),
                          prefixIcon:
                              const Icon(Icons.search, color: _cyan),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          suffixIcon: _searchTerm.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(() {
                                    _searchTerm = '';
                                    _searchController.clear();
                                  }),
                                )
                              : null,
                        ),
                        onChanged: (v) => setState(() => _searchTerm = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit form
                  Text(t('submit_a_new_query_label'),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _blue)),
                  const SizedBox(height: 12),
                  tricolorBorder(
                    child: Container(
                      color: AppThemeColors.cardBg(context),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _topicController,
                            style: TextStyle(color: AppThemeColors.primaryText(context)),
                            decoration: InputDecoration(
                              labelText: t('topic_label'),
                              prefixIcon:
                                  const Icon(Icons.topic_outlined, color: _cyan),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: Color(0xFFE0E0E0))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: Color(0xFFE0E0E0))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: _cyan, width: 1.5)),
                              filled: true,
                              fillColor: AppThemeColors.scaffoldBg(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descriptionController,
                            maxLines: 4,
                            style: TextStyle(color: AppThemeColors.primaryText(context)),
                            decoration: InputDecoration(
                              labelText: t('description_label'),
                              alignLabelWithHint: true,
                              prefixIcon: const Padding(
                                padding: EdgeInsets.only(bottom: 60),
                                child: Icon(Icons.description_outlined,
                                    color: _cyan),
                              ),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: Color(0xFFE0E0E0))),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: Color(0xFFE0E0E0))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      const BorderSide(color: _cyan, width: 1.5)),
                              filled: true,
                              fillColor: AppThemeColors.scaffoldBg(context),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _submitQuery,
                              icon: const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 18),
                              label: Text(t('submit_query_label'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _cyan,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Queries section
                  Row(
                    children: [
                      Text(t('your_queries_label'),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _blue)),
                      const Spacer(),
                      if (_queries.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _cyan.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('${_queries.length}',
                              style: const TextStyle(
                                  color: _cyan,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(_error!,
                                  style:
                                      const TextStyle(color: Colors.red)))
                          : filtered.isEmpty
                              ? Center(
                                  child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(t('no_queries_found_message'),
                                      style: const TextStyle(color: Colors.grey)),
                                ))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: displayed.length,
                                  itemBuilder: (context, i) =>
                                      _buildQueryCard(displayed[i]),
                                ),

                  if (!_showAllQueries && filtered.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () =>
                              setState(() => _showAllQueries = true),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _cyan),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                              t('view_all_queries_count_message').replaceFirst('{count}', '${filtered.length}'),
                              style: const TextStyle(color: _cyan)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryCard(Map<String, dynamic> query) {
    final t = AppLocalizations.of(context).t;
    final isResolved = query['status'] == 'resolved';
    final hasReplies =
        query['replies'] != null && (query['replies'] as List).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: tricolorBorder(
        child: Container(
          color: AppThemeColors.scaffoldBg(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _cyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.question_answer_rounded,
                          color: _cyan, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        query['topic'] ?? '',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _blue),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isResolved
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel((query['status'] ?? 'pending').toString(), t),
                        style: TextStyle(
                          color: isResolved
                              ? Colors.green[700]
                              : Colors.orange[800],
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(query['description'] ?? '',
                    style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 13, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      t('submitted_date_message').replaceFirst('{date}', _formatDateTime(query['createdAt'])),
                      style:
                          TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
                if (hasReplies) _buildReplies(query['replies']),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!hasReplies)
                      TextButton.icon(
                        onPressed: () => _editQuery(
                            query['_id'], query['topic'], query['description']),
                        icon: const Icon(Icons.edit_outlined,
                            color: _blue, size: 16),
                        label: Text(t('edit'),
                            style: const TextStyle(color: _blue, fontSize: 13)),
                        style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4)),
                      ),
                    TextButton.icon(
                      onPressed: () => _deleteQuery(query['_id']),
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 16),
                      label: Text(t('delete'),
                          style: const TextStyle(color: Colors.red, fontSize: 13)),
                      style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4)),
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

  String _statusLabel(String status, String Function(String) t) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return t('resolved_status_label');
      case 'pending':
        return t('pending_status_label');
      default:
        return status.toUpperCase();
    }
  }

  Widget _buildReplies(List<dynamic> replies) {
    final t = AppLocalizations.of(context).t;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                    color: _cyan,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 6),
              Text(t('admin_replies_label'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _cyan)),
            ],
          ),
          const SizedBox(height: 8),
          ...replies.map<Widget>((reply) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.06),
                  border: Border.all(color: _cyan.withValues(alpha: 0.3)),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.admin_panel_settings,
                            size: 14, color: _blue),
                        const SizedBox(width: 4),
                        Text(t('admin_reply_label'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: _blue)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(reply['replyText'] ?? '',
                        style: TextStyle(
                            fontSize: 13, color: AppThemeColors.primaryText(context))),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 11, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(
                          t('replied_date_message').replaceFirst('{date}', _formatDateTime(reply['timestamp'])),
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _HelpWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.75);
    path.cubicTo(
      size.width * 0.25, size.height * 1.05,
      size.width * 0.75, size.height * 0.45,
      size.width, size.height * 0.75,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_) => false;
}
