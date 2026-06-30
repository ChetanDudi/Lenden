import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({Key? key}) : super(key: key);

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final TextEditingController _feedbackController = TextEditingController();
  int _selectedAppRating = 0;
  bool _hasAppRated = false;
  bool _showFeedbacks = false;
  List<Map<String, dynamic>> _userFeedbacks = [];
  bool _isLoading = false;

  static const _cyan = AppColors.cyan;
  static const _blue = Color(0xFF0077B6);

  @override
  void initState() {
    super.initState();
    _fetchUserAppRating();
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  void _showStylishPopup(String message, {bool isError = false}) {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isError ? Colors.red[50] : Colors.green[50],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? Colors.red : Colors.green),
            const SizedBox(width: 8),
            Text(isError ? t('error') : t('success'),
                style: TextStyle(
                  color: isError ? Colors.red : Colors.green,
                  fontWeight: FontWeight.bold,
                )),
          ],
        ),
        content: Text(message,
            style: TextStyle(
                color: isError ? Colors.red[900] : Colors.green[900],
                fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _submitAppRating() async {
    final t = AppLocalizations.of(context).t;
    if (_selectedAppRating == 0) {
      _showStylishPopup(t('please_select_rating_message'), isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.post(
        '/api/rating',
        body: {'rating': _selectedAppRating},
      );
      if (response.statusCode == 200) {
        _showStylishPopup(t('app_rating_submitted_message'));
        setState(() => _hasAppRated = true);
      } else {
        _showStylishPopup(t('error_colon_label').replaceFirst('{error}', response.body), isError: true);
      }
    } catch (e) {
      _showStylishPopup(t('error_colon_label').replaceFirst('{error}', '$e'), isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitFeedback() async {
    final t = AppLocalizations.of(context).t;
    if (_feedbackController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.post(
        '/api/feedback',
        body: {'feedback': _feedbackController.text},
      );
      if (response.statusCode == 200) {
        _showStylishPopup(t('feedback_submitted_message'));
        _feedbackController.clear();
        await _fetchUserFeedbacks();
      } else {
        final body =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        _showStylishPopup(t('error_colon_label').replaceFirst('{error}', '${body?['error'] ?? response.body}'),
            isError: true);
      }
    } catch (e) {
      _showStylishPopup(t('error_colon_label').replaceFirst('{error}', '$e'), isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchUserAppRating() async {
    setState(() => _isLoading = true);
    try {
      final ratingRes = await ApiClient.get('/api/rating/my');
      if (ratingRes.statusCode == 200) {
        final ratingData = jsonDecode(ratingRes.body);
        setState(() {
          if (ratingData['rating'] != null) {
            _hasAppRated = true;
            _selectedAppRating = ratingData['rating'];
          } else {
            _hasAppRated = false;
            _selectedAppRating = 0;
          }
        });
      }
    } catch (_) {
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchUserFeedbacks() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.get('/api/feedback/my');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _userFeedbacks =
              List<Map<String, dynamic>>.from(data['feedbacks'] ?? []);
        });
      }
      final ratingRes = await ApiClient.get('/api/rating/my');
      if (ratingRes.statusCode == 200) {
        final ratingData = jsonDecode(ratingRes.body);
        setState(() {
          if (ratingData['rating'] != null) {
            _hasAppRated = true;
            _selectedAppRating = ratingData['rating'];
          } else {
            _hasAppRated = false;
            _selectedAppRating = 0;
          }
        });
      }
    } catch (_) {
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _tricolorBorder({required Widget child, double radius = 16}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: child,
      ),
    );
  }

  Widget _buildAppRatingStars() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final isFilled = index < _selectedAppRating;
        return IconButton(
          icon: Icon(
            isFilled ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 32,
          ),
          onPressed: _hasAppRated
              ? null
              : () => setState(() => _selectedAppRating = index + 1),
        );
      }),
    );
  }

  Widget _buildFeedbackList() {
    final t = AppLocalizations.of(context).t;
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_userFeedbacks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Icon(Icons.feedback_outlined, color: Colors.grey, size: 48),
            const SizedBox(height: 8),
            Text(t('no_feedbacks_yet_message'),
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _userFeedbacks.length,
      itemBuilder: (context, index) {
        final feedback = _userFeedbacks[index];
        String dateStr = '';
        String timeStr = '';
        if (feedback['createdAt'] != null) {
          try {
            final dt = DateTime.parse(feedback['createdAt'].toString());
            dateStr =
                '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
            timeStr =
                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          } catch (_) {
            dateStr = feedback['createdAt'].toString().substring(0, 10);
            timeStr = feedback['createdAt'].toString().substring(11, 16);
          }
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _tricolorBorder(
            child: Container(
              color: AppThemeColors.scaffoldBg(context),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.feedback_rounded,
                        color: _cyan, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if ((feedback['rating'] ?? 0) > 0)
                              Row(
                                children: [
                                  const Icon(Icons.star,
                                      color: Colors.amber, size: 16),
                                  const SizedBox(width: 3),
                                  Text('${feedback['rating']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                ],
                              ),
                            const Spacer(),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(dateStr,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                                Text(timeStr,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          feedback['feedback'] ?? '',
                          style: TextStyle(
                              fontSize: 14,
                              color: AppThemeColors.primaryText(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(t('feedback'),
            style: TextStyle(
                color: AppThemeColors.primaryText(context), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        foregroundColor: AppThemeColors.primaryText(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          // Top S-shape wave — half height
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                height: 75,
                color: _cyan,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t('share_experience_rate_app_message'),
                    style: const TextStyle(fontSize: 15, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // ── Rate the app card ──────────────────────────────────────
                  _tricolorBorder(
                    child: Container(
                      color: AppThemeColors.cardBg(context),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: _cyan.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.star_rounded,
                                    color: _cyan, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Text(t('rate_the_app_label'),
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: _blue)),
                            ],
                          ),
                          _buildAppRatingStars(),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading || _hasAppRated ? null : _submitAppRating,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _cyan,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    _cyan.withValues(alpha: 0.4),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : Text(
                                      _hasAppRated
                                          ? t('app_rated_check_label')
                                          : t('submit_rating_label'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Feedback text field ────────────────────────────────────
                  _tricolorBorder(
                    child: Container(
                      color: AppThemeColors.cardBg(context),
                      child: TextField(
                        controller: _feedbackController,
                        maxLines: 4,
                        style: TextStyle(
                            color: AppThemeColors.primaryText(context)),
                        decoration: InputDecoration(
                          hintText: t('your_feedback_suggestions_hint'),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 68),
                            child: Icon(Icons.feedback_outlined, color: _cyan),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Submit feedback button ─────────────────────────────────
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submitFeedback,
                      icon: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 18),
                      label: Text(t('submit_feedback_label'),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cyan,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── View feedbacks toggle ──────────────────────────────────
                  OutlinedButton.icon(
                    onPressed: () async {
                      setState(() => _showFeedbacks = !_showFeedbacks);
                      if (_showFeedbacks) await _fetchUserFeedbacks();
                    },
                    icon: Icon(
                        _showFeedbacks
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: _cyan),
                    label: Text(
                      _showFeedbacks
                          ? t('hide_your_feedbacks_label')
                          : t('view_your_feedbacks_label'),
                      style: const TextStyle(color: _cyan),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _cyan),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  if (_showFeedbacks) ...[
                    const SizedBox(height: 16),
                    _buildFeedbackList(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
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
