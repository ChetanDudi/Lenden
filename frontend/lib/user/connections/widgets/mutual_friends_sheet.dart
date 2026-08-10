import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/avatar_helpers.dart' as ah;
import '../../../utils/api_client.dart';
import '../../../api_config.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';

class MutualFriendsSheet extends StatefulWidget {
  const MutualFriendsSheet({
    super.key,
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    required this.initials,
  });
  final String userId;
  final String displayName;
  final Color avatarColor;
  final String initials;

  @override
  State<MutualFriendsSheet> createState() => _MutualFriendsSheetState();
}

class _MutualFriendsSheetState extends State<MutualFriendsSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _mutuals = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.get('/api/friends/mutual?userId=${Uri.encodeComponent(widget.userId)}');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _mutuals = List<Map<String, dynamic>>.from(data['mutualFriends'] ?? []);
          _loading = false;
        });
      } else {
        setState(() {
          _error = AppLocalizations.of(context).t('could_not_load_mutual_friends');
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).t('network_error');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.6;
    final t = AppLocalizations.of(context).t;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppThemeColors.divider(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: widget.avatarColor,
                  child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                    Center(child: Text(widget.initials,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                    if (widget.userId.isNotEmpty)
                      Image.network(
                        '${ApiConfig.baseUrl}/api/users/${widget.userId}/profile-image',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                  ])),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('mutual_friends_title'),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppThemeColors.primaryText(context))),
                      Text('${t('you_and_prefix')} ${widget.displayName}',
                        style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: AppThemeColors.mutedText(context),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(color: AppColors.cyan),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          else if (_mutuals.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.people_outline, size: 48, color: AppThemeColors.divider(context)),
                const SizedBox(height: 8),
                Text(t('no_mutual_friends_found'),
                  style: TextStyle(color: AppThemeColors.secondaryText(context))),
              ]),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _mutuals.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                itemBuilder: (_, i) {
                  final m = _mutuals[i];
                  final mName = (m['name'] ?? '').toString();
                  final mUsername = (m['username'] ?? '').toString();
                  final mEmail = (m['email'] ?? '').toString();
                  final displayN = mName.isNotEmpty ? mName : mUsername;
                  final col = ah.avatarColor(displayN);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: col,
                          child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                            Center(child: Text(ah.initials(mName, mUsername),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                            if ((m['_id']?.toString() ?? '').isNotEmpty)
                              Image.network(
                                '${ApiConfig.baseUrl}/api/users/${m['_id']}/profile-image',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                          ])),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(displayN,
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppThemeColors.primaryText(context)),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (mUsername.isNotEmpty && mUsername != mName)
                                Text('@$mUsername',
                                  style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                              Text(mEmail,
                                style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context)),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(t('friend_label'),
                            style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
