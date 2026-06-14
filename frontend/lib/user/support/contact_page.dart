import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../session.dart';
import '../../utils/api_client.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  static const _sky = Color(0xFF00B4D8);
  static const _deepBlue = Color(0xFF0077B6);
  static const _bg = Color(0xFFFAF9F6);

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
          _fetchError = 'Failed to load contact details.';
          _loading = false;
        });
      }
    } catch (_) {
      setState(() {
        _fetchError = 'Network error.';
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
      _snack('Invalid contact link.');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) _snack('Could not open this contact option.');
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _snack('Copied to clipboard');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _submitMessage() async {
    if (!_formKey.currentState!.validate()) return;
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
        _snack(body['error'] ?? 'Failed to send. Please try again.');
        setState(() => _submitting = false);
      }
    } catch (_) {
      _snack('Network error. Please check your connection.');
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
    _FaqItem(
      q: 'How do I request a refund for a transaction?',
      a: 'Go to your transaction history, tap the transaction, and select "Report Issue". Our support team reviews it within 24–48 hours.',
    ),
    _FaqItem(
      q: 'Is my financial data safe on LenDen?',
      a: 'Yes. All data is encrypted in transit and at rest. We follow industry-standard security practices to keep your account and transactions secure.',
    ),
    _FaqItem(
      q: 'How long does a payment take to process?',
      a: 'Most payments are instant. In some cases it may take up to 24 hours depending on your bank\'s processing time.',
    ),
    _FaqItem(
      q: 'How do I close or delete my LenDen account?',
      a: 'Go to Settings → Privacy & Security → Account Management. You can deactivate or permanently delete your account there.',
    ),
    _FaqItem(
      q: 'What should I do if I suspect unauthorized activity?',
      a: 'Immediately contact us via email or WhatsApp with details. You can also lock your account from Settings. We treat all fraud reports with top priority.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Contact Us',
          style: TextStyle(
            color: Colors.white,
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
                color: const Color(0xFF00B4D8),
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
    final channels = _buildChannels();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero card ──────────────────────────────────────────
          _tricolorBorder(
            radius: 26,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
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
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B1F33),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (_config['heroDescription'] ?? '').toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Colors.blueGrey.shade600,
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
                          'Typically responds within 24 hours',
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
          _sectionLabel('Reach Out'),
          const SizedBox(height: 12),
          ...channels.map(
            (ch) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _tricolorBorder(
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
          _sectionLabel('Send a Message'),
          const SizedBox(height: 12),
          _tricolorBorder(
            radius: 24,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: _submitted ? _buildSuccess() : _buildForm(),
            ),
          ),

          const SizedBox(height: 26),

          // ── My Messages ────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _sectionLabel('My Messages')),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18, color: _sky),
                onPressed: _loadMyMessages,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Refresh',
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
                        cat,
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
            _tricolorBorder(
              radius: 20,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: Text(
                    _myMessages.isEmpty
                        ? 'No messages yet. Send us one below!'
                        : 'No messages in this category.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            ..._visibleMessages.map(_buildMyMessageCard),

          const SizedBox(height: 26),

          // ── FAQ section ────────────────────────────────────────
          _sectionLabel('Frequently Asked'),
          const SizedBox(height: 12),
          _tricolorBorder(
            radius: 24,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
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
    final status = (msg['status'] as String?) ?? 'new';
    final subject = (msg['subject'] as String?) ?? 'General Inquiry';
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
      child: _tricolorBorder(
        radius: 20,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFFFAF9F6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      subject,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF0B1F33),
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
                      status[0].toUpperCase() + status.substring(1),
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
                    category,
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
                style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
              ),
              if (createdAt != null) ...[
                const SizedBox(height: 5),
                Text(
                  _formatMsgTime(createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
              if (hasReply) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F8FC),
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
                          const Text(
                            'Admin Reply',
                            style: TextStyle(
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
                          color: Colors.blueGrey.shade700,
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
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0B1F33),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
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
        const Text(
          'Message Sent!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0B1F33),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Thanks for reaching out. We\'ll get back to you within 24 hours.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.blueGrey.shade600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => setState(() => _submitted = false),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Send another message'),
          style: TextButton.styleFrom(foregroundColor: _sky),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _field(
            controller: _nameCtrl,
            label: 'Your Name',
            icon: Icons.person_outline_rounded,
            readOnly: _nameLocked,
            validator: (v) =>
                (v?.trim().isEmpty ?? true) ? 'Please enter your name' : null,
          ),
          const SizedBox(height: 12),
          _field(
            controller: _emailCtrl,
            label: 'Email Address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            readOnly: _emailLocked,
            validator: (v) {
              if (v?.trim().isEmpty ?? true) return 'Please enter your email';
              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+').hasMatch(v!.trim())) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _field(
            controller: _subjectCtrl,
            label: 'Subject (optional)',
            icon: Icons.subject_rounded,
          ),
          const SizedBox(height: 16),
          // Category selector
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Category',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey.shade600,
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
                      cat,
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
            label: 'Message',
            icon: Icons.message_outlined,
            maxLines: 4,
            validator: (v) {
              if (v?.trim().isEmpty ?? true) return 'Please enter your message';
              if ((v?.trim().length ?? 0) < 10) {
                return 'Message is too short (min. 10 characters)';
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
                _submitting ? 'Sending…' : 'Send Message',
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
      borderSide: BorderSide(color: Colors.blueGrey.shade100),
    );
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      readOnly: readOnly,
      validator: validator,
      style: TextStyle(
        fontSize: 14,
        color: readOnly ? Colors.blueGrey.shade500 : const Color(0xFF0B1F33),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
        prefixIcon: Icon(icon, size: 20, color: readOnly ? Colors.blueGrey.shade300 : _sky),
        suffixIcon: readOnly
            ? Icon(Icons.lock_outline_rounded, size: 16, color: Colors.blueGrey.shade300)
            : null,
        filled: true,
        fillColor: readOnly ? Colors.blueGrey.shade50 : _bg,
        border: readOnly ? lockedBorder : OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.blueGrey.shade200),
        ),
        enabledBorder: readOnly ? lockedBorder : OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.blueGrey.shade200),
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

  Widget _tricolorBorder({required Widget child, double radius = 24}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: child,
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
      color: Colors.white,
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B1F33),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blueGrey.shade600,
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
                      size: 18, color: Colors.blueGrey.shade400),
                  onPressed: onCopy,
                  constraints:
                      const BoxConstraints(maxWidth: 36, maxHeight: 36),
                  padding: EdgeInsets.zero,
                  tooltip: 'Copy',
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
  final String q;
  final String a;

  const _FaqItem({required this.q, required this.a});
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
  static const _sky = Color(0xFF00B4D8);
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
                    widget.item.q,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _expanded ? _deepBlue : const Color(0xFF0B1F33),
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
              widget.item.a,
              style: TextStyle(
                fontSize: 13,
                color: Colors.blueGrey.shade600,
                height: 1.6,
              ),
            ),
          ),
        ),
        if (!widget.isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.blueGrey.shade100,
            indent: 18,
            endIndent: 18,
          ),
      ],
    );
  }
}
