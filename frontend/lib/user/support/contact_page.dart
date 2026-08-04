import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_widgets.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  static const _sky = AppColors.cyan;
  static const _deepBlue = Color(0xFF0077B6);

  bool _loading = true;
  String? _fetchError;
  Map<String, dynamic> _config = _fallbackConfig();

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;
  bool _nameLocked = false;
  bool _emailLocked = false;
  List<Map<String, dynamic>> _myMessages = [];
  bool _loadingMessages = false;

  static const List<String> _categories = [
    'Account & Profile',
    'Payments & Transactions',
    'Groups & Expenses',
    'Lending & Borrowing',
    'Security & Privacy',
    'Technical Issue',
    'Feature Request',
    'Billing & Subscriptions',
    'General Inquiry',
    'Other',
  ];
  String _selectedCategory = 'General Inquiry';
  String _categoryFilter = 'All';

  String _categoryLabel(String cat, String Function(String) t) {
    const keys = {
      'All': 'all_label',
      'Account & Profile': 'category_account_profile_label',
      'Payments & Transactions': 'category_payments_transactions_label',
      'Groups & Expenses': 'category_groups_expenses_label',
      'Lending & Borrowing': 'category_lending_borrowing_label',
      'Security & Privacy': 'category_security_privacy_label',
      'Technical Issue': 'category_technical_issue_label',
      'Feature Request': 'category_feature_request_label',
      'Billing & Subscriptions': 'category_billing_subscriptions_label',
      'General Inquiry': 'general_inquiry',
      'Other': 'category_other_label',
    };
    final key = keys[cat];
    return key != null ? t(key) : cat;
  }

  String _statusLabel(String status, String Function(String) t) {
    const keys = {
      'new': 'status_new_label',
      'read': 'status_read_label',
      'replied': 'status_replied_label',
      'closed': 'status_closed_label',
    };
    final key = keys[status];
    return key != null ? t(key) : status;
  }

  @override
  void initState() {
    super.initState();
    _loadContactInfo();
    _loadMyMessages();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromSession());
  }

  void _prefillFromSession() {
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    if (user == null) return;
    final name = (user['name'] as String? ?? '').trim();
    final email = (user['email'] as String? ?? '').trim();
    setState(() {
      if (name.isNotEmpty) {
        _nameCtrl.text = name;
        _nameLocked = true;
      }
      if (email.isNotEmpty) {
        _emailCtrl.text = email;
        _emailLocked = true;
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  static Map<String, dynamic> _fallbackConfig() => {
        'heroTitle': 'Contact Us',
        'heroDescription':
            'We would love to hear from you! Reach out through any of the following channels.',
        'email': {
          'label': 'Email',
          'value': 'chetandudi791@gmail.com',
          'url': 'mailto:chetandudi791@gmail.com',
          'enabled': true,
        },
        'whatsapp': {
          'label': 'WhatsApp',
          'value': '+91-XXXXXXXXXX',
          'url': '',
          'enabled': true,
        },
        'instagram': {
          'label': 'Instagram',
          'value': '_Chetan_Dudi',
          'url': '',
          'enabled': true,
        },
        'facebook': {
          'label': 'Facebook',
          'value': 'Lenden App',
          'url': '',
          'enabled': true,
        },
      };

  Future<void> _loadContactInfo() async {
    try {
      final response = await ApiClient.get('/api/contact-info');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _config = data;
          _loading = false;
        });
      } else {
        setState(() {
          _fetchError = AppLocalizations.of(context).t('failed_to_load_contact_details_message');
          _loading = false;
        });
      }
    } catch (_) {
      setState(() {
        _fetchError = AppLocalizations.of(context).t('network_error_simple_message');
        _loading = false;
      });
    }
  }

  Future<void> _loadMyMessages() async {
    setState(() => _loadingMessages = true);
    try {
      final response = await ApiClient.get('/api/contact-messages/mine');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _myMessages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
        });
      }
    } catch (_) {
      // Silently fail — not critical
    } finally {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  List<Map<String, dynamic>> get _visibleMessages => _categoryFilter == 'All'
      ? _myMessages
      : _myMessages
          .where((m) => (m['category'] as String?) == _categoryFilter)
          .toList();

  String _formatMsgTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('MMM dd, yyyy • h:mm a').format(dt.toLocal());
  }

  Future<void> _openChannel(Map<String, dynamic> channel, String fallback) async {
    final rawUrl = (channel['url'] ?? '').toString().trim();
    final value = (channel['value'] ?? '').toString().trim();
    final target = rawUrl.isNotEmpty ? rawUrl : '$fallback$value';
    if (target.isEmpty) return;
    final uri = Uri.tryParse(target);
    if (uri == null) {
      _snack(AppLocalizations.of(context).t('invalid_contact_link_message'));
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _snack(AppLocalizations.of(context).t('could_not_open_contact_option_message'));
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _snack(AppLocalizations.of(context).t('copied_to_clipboard_message'));
  }

  void _snack(String message) {
    if (!mounted) return;
    showSnack(context, message);
  }

  Future<void> _submitMessage() async {
    if (!_formKey.currentState!.validate()) return;
    final t = AppLocalizations.of(context).t;
    setState(() => _submitting = true);
    try {
      final response = await ApiClient.post(
        '/api/contact-message',
        body: {
          'name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'subject': _subjectCtrl.text.trim().isEmpty
              ? 'General Inquiry'
              : _subjectCtrl.text.trim(),
          'message': _messageCtrl.text.trim(),
          'category': _selectedCategory,
        },
      );
      if (response.statusCode == 201) {
        _subjectCtrl.clear();
        _messageCtrl.clear();
        setState(() {
          _submitted = true;
          _submitting = false;
          _selectedCategory = 'General Inquiry';
        });
        _loadMyMessages();
      } else {
        final body = jsonDecode(response.body);
        _snack(body['error'] ?? t('failed_to_send_try_again_message'));
        setState(() => _submitting = false);
      }
    } catch (_) {
      _snack(t('network_error_check_connection_message'));
      setState(() => _submitting = false);
    }
  }

  List<_ChannelEntry> _buildChannels() {
    final defs = [
      _ChannelEntry(
        key: 'email',
        icon: Icons.email_rounded,
        tint: _sky,
        fallbackPrefix: 'mailto:',
      ),
      _ChannelEntry(
        key: 'whatsapp',
        faIcon: FontAwesomeIcons.whatsapp,
        tint: const Color(0xFF25D366),
        fallbackPrefix: 'https://wa.me/',
      ),
      _ChannelEntry(
        key: 'phone',
        icon: Icons.phone_rounded,
        tint: const Color(0xFF34A853),
        fallbackPrefix: 'tel:',
      ),
      _ChannelEntry(
        key: 'instagram',
        faIcon: FontAwesomeIcons.instagram,
        tint: const Color(0xFFE1306C),
        fallbackPrefix: 'https://instagram.com/',
      ),
      _ChannelEntry(
        key: 'facebook',
        icon: Icons.facebook_rounded,
        tint: const Color(0xFF1877F2),
        fallbackPrefix: 'https://facebook.com/',
      ),
      _ChannelEntry(
        key: 'twitter',
        faIcon: FontAwesomeIcons.xTwitter,
        tint: const Color(0xFF000000),
        fallbackPrefix: 'https://twitter.com/',
      ),
      _ChannelEntry(
        key: 'linkedin',
        faIcon: FontAwesomeIcons.linkedin,
        tint: const Color(0xFF0A66C2),
        fallbackPrefix: 'https://linkedin.com/company/',
      ),
      _ChannelEntry(
        key: 'youtube',
        faIcon: FontAwesomeIcons.youtube,
        tint: const Color(0xFFFF0000),
        fallbackPrefix: 'https://youtube.com/',
      ),
    ];

    return defs.where((e) {
      final ch = _config[e.key];
      if (ch == null) return false;
      final enabled = ch['enabled'];
      if (enabled == false) return false;
      return (ch['label'] ?? '').toString().trim().isNotEmpty;
    }).map((e) {
      e.channel = Map<String, dynamic>.from(_config[e.key] ?? {});
      return e;
    }).toList();
  }

  static const _faqItems = [
    _FaqItem(qKey: 'faq_refund_q', aKey: 'faq_refund_a'),
    _FaqItem(qKey: 'faq_data_safety_q', aKey: 'faq_data_safety_a'),
    _FaqItem(qKey: 'faq_payment_time_q', aKey: 'faq_payment_time_a'),
    _FaqItem(qKey: 'faq_delete_account_q', aKey: 'faq_delete_account_a'),
    _FaqItem(qKey: 'faq_fraud_q', aKey: 'faq_fraud_a'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppThemeColors.primaryText(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          t('contact_us_title'),
          style: TextStyle(
            color: AppThemeColors.primaryText(context),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Top wave — same clipper & colour as user dashboard
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                height: (MediaQuery.of(context).padding.top + kToolbarHeight) * 1.5,
                color: AppColors.cyan,
              ),
            ),
          ),
          _loading
              ? const Center(child: CircularProgressIndicator(color: _sky))
              : SafeArea(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final t = AppLocalizations.of(context).t;
    final channels = _buildChannels();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero card ──────────────────────────────────────────
          tricolorBorder(
            radius: 26,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: _sky,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 54,
                      height: 54,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.support_agent_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    (_config['heroTitle'] ?? 'Contact Us').toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (_config['heroDescription'] ?? '').toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppThemeColors.secondaryText(context),
                    ),
                  ),
                  if (_fetchError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _fetchError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _sky.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: _sky.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 15, color: _deepBlue),
                        const SizedBox(width: 6),
                        Text(
                          t('typically_responds_24h_message'),
                          style: TextStyle(
                            fontSize: 12,
                            color: _deepBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 26),

          // ── Contact channels ───────────────────────────────────
          _sectionLabel(t('reach_out_label')),
          const SizedBox(height: 12),
          ...channels.map(
            (ch) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: tricolorBorder(
                radius: 22,
                child: _ChannelCard(
                  entry: ch,
                  onTap: () => _openChannel(ch.channel, ch.fallbackPrefix),
                  onCopy: (ch.key == 'email' || ch.key == 'phone')
                      ? () => _copyToClipboard(
                          (ch.channel['value'] ?? '').toString())
                      : null,
                ),
              ),
            ),
          ),

          const SizedBox(height: 26),

          // ── Send a message form ────────────────────────────────
          _sectionLabel(t('send_a_message_label')),
          const SizedBox(height: 12),
          tricolorBorder(
            radius: 24,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(22),
              ),
              child: _submitted ? _buildSuccess() : _buildForm(),
            ),
          ),

          const SizedBox(height: 26),

          // ── My Messages ────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _sectionLabel(t('my_messages_label'))),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18, color: _sky),
                onPressed: _loadMyMessages,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: t('refresh_label'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Category filter chips for My Messages
          Builder(builder: (_) {
            final usedCats = <String>['All',
              ..._categories.where(
                (c) => _myMessages.any((m) => (m['category'] as String?) == c),
              )];
            return SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: usedCats.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final cat = usedCats[i];
                  final active = _categoryFilter == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _categoryFilter = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: active
                            ? _deepBlue
                            : _deepBlue.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: active
                              ? _deepBlue
                              : _deepBlue.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        _categoryLabel(cat, t),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : _deepBlue,
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          }),
          const SizedBox(height: 12),
          if (_loadingMessages)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(color: _sky)),
            )
          else if (_visibleMessages.isEmpty)
            tricolorBorder(
              radius: 20,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(
                    _myMessages.isEmpty
                        ? t('no_messages_yet_below_message')
                        : t('no_messages_in_category_message'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppThemeColors.mutedText(context), fontSize: 13),
                  ),
                ),
              ),
            )
          else
            ..._visibleMessages.map(_buildMyMessageCard),

          const SizedBox(height: 26),

          // ── FAQ section ────────────────────────────────────────
          _sectionLabel(t('frequently_asked_label')),
          const SizedBox(height: 12),
          tricolorBorder(
            radius: 24,
            child: Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: _faqItems.asMap().entries.map((e) {
                  return _FaqTileWidget(
                    item: e.value,
                    isLast: e.key == _faqItems.length - 1,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyMessageCard(Map<String, dynamic> msg) {
    final t = AppLocalizations.of(context).t;
    final status = (msg['status'] as String?) ?? 'new';
    final subject = (msg['subject'] as String?) ?? t('general_inquiry');
    final message = (msg['message'] as String?) ?? '';
    final replyNote = (msg['replyNote'] as String?) ?? '';
    final category = (msg['category'] as String?) ?? '';
    final createdAt = msg['createdAt'] as String?;
    final hasReply = replyNote.isNotEmpty;

    const statusColors = {
      'new': Colors.blue,
      'read': Colors.grey,
      'replied': Colors.green,
      'closed': Colors.red,
    };
    final statusColor = statusColors[status] ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: tricolorBorder(
        radius: 20,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppThemeColors.scaffoldBg(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      subject,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      _statusLabel(status, t),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (category.isNotEmpty) ...[
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: _sky.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: _sky.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    _categoryLabel(category, t),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _sky),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, color: AppThemeColors.secondaryText(context)),
              ),
              if (createdAt != null) ...[
                const SizedBox(height: 5),
                Text(
                  _formatMsgTime(createdAt),
                  style: TextStyle(
                      fontSize: 11, color: AppThemeColors.mutedText(context)),
                ),
              ],
              if (hasReply) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppThemeColors.tinted(context,
                        light: const Color(0xFFE8F8FC),
                        dark: const Color(0xFF14323A)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _sky.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.reply_rounded,
                              size: 14, color: _sky),
                          const SizedBox(width: 6),
                          Text(
                            t('admin_reply_label'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _sky,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        replyNote,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppThemeColors.secondaryText(context),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_deepBlue, _sky],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppThemeColors.primaryText(context),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final t = AppLocalizations.of(context).t;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF138808).withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF138808),
            size: 40,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          t('message_sent_label'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppThemeColors.primaryText(context),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t('thanks_for_reaching_out_message'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppThemeColors.secondaryText(context),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => setState(() => _submitted = false),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(t('send_another_message_label')),
          style: TextButton.styleFrom(foregroundColor: _sky),
        ),
      ],
    );
  }

  Widget _buildForm() {
    final t = AppLocalizations.of(context).t;
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _field(
            controller: _nameCtrl,
            label: t('your_name_label'),
            icon: Icons.person_outline_rounded,
            readOnly: _nameLocked,
            validator: (v) => (v?.trim().isEmpty ?? true)
                ? t('please_enter_your_name_message')
                : null,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _emailCtrl,
            label: t('email_address_label'),
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            readOnly: _emailLocked,
            validator: (v) {
              if (v?.trim().isEmpty ?? true) {
                return t('please_enter_your_email_message');
              }
              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+').hasMatch(v!.trim())) {
                return t('enter_a_valid_email_message');
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _field(
            controller: _subjectCtrl,
            label: t('subject_optional_label'),
            icon: Icons.subject_rounded,
          ),
          const SizedBox(height: 16),
          // Category selector
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              t('category_label'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppThemeColors.secondaryText(context),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = _categories[i];
                final selected = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? _sky
                          : _sky.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? _sky
                            : _sky.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      _categoryLabel(cat, t),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : _sky,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _field(
            controller: _messageCtrl,
            label: t('message'),
            icon: Icons.message_outlined,
            maxLines: 4,
            validator: (v) {
              if (v?.trim().isEmpty ?? true) {
                return t('please_enter_your_message_message');
              }
              if ((v?.trim().length ?? 0) < 10) {
                return t('message_too_short_message');
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submitMessage,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _submitting ? t('sending') : t('send_message_label'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _sky,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _sky.withValues(alpha: 0.55),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    final lockedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: AppThemeColors.divider(context)),
    );
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      readOnly: readOnly,
      validator: validator,
      style: TextStyle(
        fontSize: 14,
        color: readOnly
            ? AppThemeColors.mutedText(context)
            : AppThemeColors.primaryText(context),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color: AppThemeColors.secondaryText(context), fontSize: 13),
        prefixIcon: Icon(icon,
            size: 20,
            color: readOnly ? AppThemeColors.mutedText(context) : _sky),
        suffixIcon: readOnly
            ? Icon(Icons.lock_outline_rounded,
                size: 16, color: AppThemeColors.mutedText(context))
            : null,
        filled: true,
        fillColor: readOnly
            ? AppThemeColors.surfaceBg(context)
            : AppThemeColors.scaffoldBg(context),
        border: readOnly ? lockedBorder : OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppThemeColors.border(context)),
        ),
        enabledBorder: readOnly ? lockedBorder : OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppThemeColors.border(context)),
        ),
        focusedBorder: readOnly ? lockedBorder : OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _sky, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade400, width: 1.8),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: maxLines > 1 ? 14 : 0,
        ),
      ),
    );
  }

}

// ── Channel Entry ─────────────────────────────────────────────────────────────

class _ChannelEntry {
  final String key;
  final IconData? icon;
  final IconData? faIcon;
  final Color tint;
  final String fallbackPrefix;
  Map<String, dynamic> channel = {};

  _ChannelEntry({
    required this.key,
    this.icon,
    this.faIcon,
    required this.tint,
    required this.fallbackPrefix,
  });
}

class _ChannelCard extends StatelessWidget {
  final _ChannelEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onCopy;

  const _ChannelCard({
    required this.entry,
    required this.onTap,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final label = (entry.channel['label'] ?? '').toString();
    final value = (entry.channel['value'] ?? '').toString();

    return Material(
      color: AppThemeColors.cardBg(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: entry.tint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: entry.faIcon != null
                    ? Center(
                        child: FaIcon(entry.faIcon,
                            color: entry.tint, size: 22))
                    : Icon(entry.icon, color: entry.tint, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppThemeColors.secondaryText(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              if (onCopy != null)
                IconButton(
                  icon: Icon(Icons.copy_rounded,
                      size: 18, color: AppThemeColors.mutedText(context)),
                  onPressed: onCopy,
                  constraints:
                      const BoxConstraints(maxWidth: 36, maxHeight: 36),
                  padding: EdgeInsets.zero,
                  tooltip: AppLocalizations.of(context).t('copy_label'),
                ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: entry.tint.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── FAQ ───────────────────────────────────────────────────────────────────────

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
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
  bool shouldReclip(_WaveClipper oldClipper) => false;
}

class _FaqItem {
  final String qKey;
  final String aKey;

  const _FaqItem({required this.qKey, required this.aKey});
}

class _FaqTileWidget extends StatefulWidget {
  final _FaqItem item;
  final bool isLast;

  const _FaqTileWidget({required this.item, this.isLast = false});

  @override
  State<_FaqTileWidget> createState() => _FaqTileWidgetState();
}

class _FaqTileWidgetState extends State<_FaqTileWidget>
    with SingleTickerProviderStateMixin {
  static const _sky = AppColors.cyan;
  static const _deepBlue = Color(0xFF0077B6);

  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _expand;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _expand = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _sky.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: AnimatedRotation(
                    turns: _expanded ? 0.125 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: _sky,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).t(widget.item.qKey),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _expanded
                          ? _deepBlue
                          : AppThemeColors.primaryText(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizeTransition(
          sizeFactor: _expand,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(58, 0, 18, 14),
            child: Text(
              AppLocalizations.of(context).t(widget.item.aKey),
              style: TextStyle(
                fontSize: 13,
                color: AppThemeColors.secondaryText(context),
                height: 1.6,
              ),
            ),
          ),
        ),
        if (!widget.isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: AppThemeColors.divider(context),
            indent: 18,
            endIndent: 18,
          ),
      ],
    );
  }
}
