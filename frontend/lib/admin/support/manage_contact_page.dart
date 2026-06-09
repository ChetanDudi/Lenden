import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';

class ManageContactPage extends StatefulWidget {
  const ManageContactPage({super.key});

  @override
  State<ManageContactPage> createState() => _ManageContactPageState();
}

class _ManageContactPageState extends State<ManageContactPage> {
  final TextEditingController _heroTitleController = TextEditingController();
  final TextEditingController _heroDescriptionController =
      TextEditingController();
  final Map<String, TextEditingController> _controllers = {
    'emailLabel': TextEditingController(),
    'emailValue': TextEditingController(),
    'emailUrl': TextEditingController(),
    'facebookLabel': TextEditingController(),
    'facebookValue': TextEditingController(),
    'facebookUrl': TextEditingController(),
    'whatsappLabel': TextEditingController(),
    'whatsappValue': TextEditingController(),
    'whatsappUrl': TextEditingController(),
    'instagramLabel': TextEditingController(),
    'instagramValue': TextEditingController(),
    'instagramUrl': TextEditingController(),
  };

  bool _loading = true;
  bool _saving = false;
  final Map<String, bool> _enabled = {
    'email': true,
    'facebook': true,
    'whatsapp': true,
    'instagram': true,
  };

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _heroTitleController.dispose();
    _heroDescriptionController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    try {
      final response = await ApiClient.get('/api/admin/contact-info');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _heroTitleController.text = (data['heroTitle'] ?? '').toString();
        _heroDescriptionController.text =
            (data['heroDescription'] ?? '').toString();
        _fillChannel('email', data['email']);
        _fillChannel('facebook', data['facebook']);
        _fillChannel('whatsapp', data['whatsapp']);
        _fillChannel('instagram', data['instagram']);
      } else {
        _showMessage('Failed to load contact information.', isError: true);
      }
    } catch (_) {
      _showMessage('Network error while loading contact information.',
          isError: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _fillChannel(String key, dynamic raw) {
    final data = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    _controllers['${key}Label']!.text = (data['label'] ?? '').toString();
    _controllers['${key}Value']!.text = (data['value'] ?? '').toString();
    _controllers['${key}Url']!.text = (data['url'] ?? '').toString();
    _enabled[key] = data['enabled'] != false;
  }

  Future<void> _saveConfig() async {
    if (_heroTitleController.text.trim().isEmpty ||
        _heroDescriptionController.text.trim().isEmpty) {
      _showMessage('Title and description are required.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'heroTitle': _heroTitleController.text.trim(),
        'heroDescription': _heroDescriptionController.text.trim(),
        'email': _channelPayload('email'),
        'facebook': _channelPayload('facebook'),
        'whatsapp': _channelPayload('whatsapp'),
        'instagram': _channelPayload('instagram'),
      };

      final response =
          await ApiClient.put('/api/admin/contact-info', body: payload);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _showMessage('Contact information saved.');
        await _loadConfig();
      } else {
        final data = response.body.isNotEmpty
            ? jsonDecode(response.body) as Map<String, dynamic>
            : <String, dynamic>{};
        _showMessage(
          (data['error'] ?? 'Failed to save contact information.').toString(),
          isError: true,
        );
      }
    } catch (_) {
      _showMessage('Network error while saving contact information.',
          isError: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Map<String, dynamic> _channelPayload(String key) => {
        'label': _controllers['${key}Label']!.text.trim(),
        'value': _controllers['${key}Value']!.text.trim(),
        'url': _controllers['${key}Url']!.text.trim(),
        'enabled': _enabled[key] == true,
      };

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFB3261E) : const Color(0xFF0B8FAC),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String keyName,
    required Color tint,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: tint.withOpacity(0.15),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enabled[keyName] == true,
                activeColor: tint,
                onChanged: (value) {
                  setState(() {
                    _enabled[keyName] = value;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controllers['${keyName}Label'],
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controllers['${keyName}Value'],
            decoration: const InputDecoration(labelText: 'Display value'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controllers['${keyName}Url'],
            decoration: const InputDecoration(
              labelText: 'Action URL',
              hintText: 'mailto:, https://, tel:, or custom link',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 170,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF003049), Color(0xFF00B4D8)],
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const Expanded(
                        child: Text(
                          'Contact Settings',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _saving ? null : _saveConfig,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('Save'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFE6F7FB),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF003049)
                                        .withOpacity(0.08),
                                    blurRadius: 22,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF003049),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: const Text(
                                      'Public Contact Screen',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  TextField(
                                    controller: _heroTitleController,
                                    decoration: const InputDecoration(
                                      labelText: 'Hero title',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextField(
                                    controller: _heroDescriptionController,
                                    maxLines: 3,
                                    decoration: const InputDecoration(
                                      labelText: 'Hero description',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            _sectionCard(
                              title: 'Email',
                              subtitle: 'Primary support inbox',
                              icon: Icons.email_outlined,
                              keyName: 'email',
                              tint: const Color(0xFF0B8FAC),
                            ),
                            _sectionCard(
                              title: 'Facebook',
                              subtitle: 'Community or page link',
                              icon: Icons.facebook_rounded,
                              keyName: 'facebook',
                              tint: const Color(0xFF1877F2),
                            ),
                            _sectionCard(
                              title: 'WhatsApp',
                              subtitle: 'Chat or support number',
                              icon: Icons.chat_bubble_outline_rounded,
                              keyName: 'whatsapp',
                              tint: const Color(0xFF25D366),
                            ),
                            _sectionCard(
                              title: 'Instagram',
                              subtitle: 'Social profile',
                              icon: Icons.camera_alt_outlined,
                              keyName: 'instagram',
                              tint: const Color(0xFFE95950),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
