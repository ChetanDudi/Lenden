import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';

class ReferralSettingsPage extends StatefulWidget {
  const ReferralSettingsPage({super.key});

  @override
  State<ReferralSettingsPage> createState() => _ReferralSettingsPageState();
}

class _ReferralSettingsPageState extends State<ReferralSettingsPage> {
  final TextEditingController _inviteBaseUrlController = TextEditingController();
  final TextEditingController _inviterRewardController = TextEditingController();
  final TextEditingController _refereeRewardController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _shareOptions = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _inviteBaseUrlController.dispose();
    _inviterRewardController.dispose();
    _refereeRewardController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get('/api/admin/referral-config');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _inviteBaseUrlController.text = (data['inviteBaseUrl'] ?? '').toString();
          _inviterRewardController.text = (data['inviterRewardCoins'] ?? 20).toString();
          _refereeRewardController.text = (data['refereeRewardCoins'] ?? 10).toString();
          _shareOptions = List<dynamic>.from(data['shareOptions'] ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        _showMsg('Failed to load referral settings.', isError: true);
      }
    } catch (_) {
      setState(() => _loading = false);
      _showMsg('Network error while loading referral settings.', isError: true);
    }
  }

  Future<void> _saveConfig() async {
    final inviter = int.tryParse(_inviterRewardController.text.trim());
    final referee = int.tryParse(_refereeRewardController.text.trim());
    if (inviter == null || inviter < 0 || referee == null || referee < 0) {
      _showMsg('Reward coins must be non-negative integers.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'inviteBaseUrl': _inviteBaseUrlController.text.trim(),
        'inviterRewardCoins': inviter,
        'refereeRewardCoins': referee,
        'shareOptions': _shareOptions
            .asMap()
            .entries
            .map(
              (e) => {
                'key': (e.value['key'] ?? '').toString().trim().toLowerCase(),
                'label': (e.value['label'] ?? '').toString().trim(),
                'icon': (e.value['icon'] ?? '').toString().trim().toLowerCase(),
                'urlTemplate': (e.value['urlTemplate'] ?? '').toString().trim(),
                'enabled': e.value['enabled'] != false,
                'sortOrder': e.key + 1,
              },
            )
            .toList(),
      };
      final res = await ApiClient.put('/api/admin/referral-config', body: payload);
      setState(() => _saving = false);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _showMsg('Referral settings saved.');
        await _loadConfig();
      } else {
        final data = jsonDecode(res.body);
        _showMsg(data['error']?.toString() ?? 'Failed to save referral settings.', isError: true);
      }
    } catch (_) {
      setState(() => _saving = false);
      _showMsg('Network error while saving referral settings.', isError: true);
    }
  }

  Future<void> _editOption({Map<String, dynamic>? existing, int? index}) async {
    final keyCtrl = TextEditingController(text: (existing?['key'] ?? '').toString());
    final labelCtrl = TextEditingController(text: (existing?['label'] ?? '').toString());
    final iconCtrl = TextEditingController(text: (existing?['icon'] ?? '').toString());
    final templateCtrl = TextEditingController(text: (existing?['urlTemplate'] ?? '').toString());
    bool enabled = existing?['enabled'] != false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: Text(existing == null ? 'Add Share Option' : 'Edit Share Option'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: 'Key')),
                  TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Label')),
                  TextField(controller: iconCtrl, decoration: const InputDecoration(labelText: 'Icon name')),
                  TextField(
                    controller: templateCtrl,
                    decoration: const InputDecoration(labelText: 'URL Template'),
                  ),
                  SwitchListTile(
                    value: enabled,
                    onChanged: (v) => setLocalState(() => enabled = v),
                    title: const Text('Enabled'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Use placeholders: {message}, {inviteLink}, {subject}. Use copy:{message} for copy option.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final item = {
                    'key': keyCtrl.text.trim().toLowerCase(),
                    'label': labelCtrl.text.trim(),
                    'icon': iconCtrl.text.trim().toLowerCase(),
                    'urlTemplate': templateCtrl.text.trim(),
                    'enabled': enabled,
                  };
                  Navigator.pop(context, item);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    keyCtrl.dispose();
    labelCtrl.dispose();
    iconCtrl.dispose();
    templateCtrl.dispose();

    if (result == null) return;
    if ((result['key'] ?? '').toString().isEmpty ||
        (result['label'] ?? '').toString().isEmpty ||
        (result['urlTemplate'] ?? '').toString().isEmpty) {
      _showMsg('Key, label, and URL template are required.', isError: true);
      return;
    }

    setState(() {
      if (index != null) {
        _shareOptions[index] = result;
      } else {
        _shareOptions.add(result);
      }
    });
  }

  void _showMsg(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF00B4D8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 140,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                  ),
                ),
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
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Referral Settings',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Invite Link', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _inviteBaseUrlController,
                                    decoration: const InputDecoration(
                                      labelText: 'Invite Base URL',
                                      hintText: 'https://your-domain.com/app',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Referral Reward Coins', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _inviterRewardController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Inviter Reward Coins'),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _refereeRewardController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Referee Reward Coins'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Share Options', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                      ElevatedButton.icon(
                                        onPressed: () => _editOption(),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Add'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_shareOptions.isEmpty)
                                    const Text('No share options configured.')
                                  else
                                    ..._shareOptions.asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final opt = entry.value;
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${opt['label']} (${opt['key']})',
                                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                                  ),
                                                  Text(
                                                    '${opt['icon']} | ${opt['urlTemplate']}',
                                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                                                  ),
                                                  Text(
                                                    (opt['enabled'] != false) ? 'Enabled' : 'Disabled',
                                                    style: TextStyle(
                                                      color: (opt['enabled'] != false) ? Colors.green : Colors.orange,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: i == 0
                                                  ? null
                                                  : () {
                                                      setState(() {
                                                        final temp = _shareOptions[i - 1];
                                                        _shareOptions[i - 1] = _shareOptions[i];
                                                        _shareOptions[i] = temp;
                                                      });
                                                    },
                                              icon: const Icon(Icons.arrow_upward),
                                            ),
                                            IconButton(
                                              onPressed: i == _shareOptions.length - 1
                                                  ? null
                                                  : () {
                                                      setState(() {
                                                        final temp = _shareOptions[i + 1];
                                                        _shareOptions[i + 1] = _shareOptions[i];
                                                        _shareOptions[i] = temp;
                                                      });
                                                    },
                                              icon: const Icon(Icons.arrow_downward),
                                            ),
                                            IconButton(
                                              onPressed: () => _editOption(existing: opt, index: i),
                                              icon: const Icon(Icons.edit),
                                            ),
                                            IconButton(
                                              onPressed: () => setState(() => _shareOptions.removeAt(i)),
                                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _saving ? null : _saveConfig,
                                icon: _saving
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.save),
                                label: Text(_saving ? 'Saving...' : 'Save Referral Settings'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00B4D8),
                                  foregroundColor: Colors.white,
                                ),
                              ),
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

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }
}
