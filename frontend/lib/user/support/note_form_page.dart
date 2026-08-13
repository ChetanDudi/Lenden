import 'package:flutter/material.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_colors.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/wave_widget.dart' show DeepTopWaveClipper;
import '../../l10n/app_localizations.dart';

class NoteFormPage extends StatefulWidget {
  final Map<String, dynamic>? note; // null = create mode
  const NoteFormPage({super.key, this.note});

  @override
  State<NoteFormPage> createState() => _NoteFormPageState();
}

class _NoteFormPageState extends State<NoteFormPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  bool _saving = false;
  bool _titleError = false;

  bool get _isEdit => widget.note != null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.note?['title'] ?? '');
    _contentCtrl = TextEditingController(text: widget.note?['content'] ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    final content = _contentCtrl.text.trim();
    setState(() {
      _saving = true;
      _titleError = false;
    });
    try {
      final body = {'title': title, 'content': content};
      final res = _isEdit
          ? await ApiClient.put('/api/notes/${widget.note!['_id']}', body: body)
          : await ApiClient.post('/api/notes', body: body);
      if (!mounted) return;
      final success = _isEdit ? res.statusCode == 200 : res.statusCode == 201;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEdit ? 'Note updated successfully' : 'Note created successfully',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true);
      } else {
        setState(() => _saving = false);
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // Wave header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: const DeepTopWaveClipper(),
              child: Container(
                height: 160,
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header row with back button and title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            _isEdit ? t('edit_note') : t('new_note'),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      // Spacer to balance back button and keep title centred
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                // Form card
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppThemeColors.border(context),
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title field with char count
                          TextField(
                            controller: _titleCtrl,
                            maxLength: 50,
                            style: TextStyle(color: AppThemeColors.primaryText(context)),
                            onChanged: (_) {
                              if (_titleError) setState(() => _titleError = false);
                            },
                            decoration: InputDecoration(
                              labelText: t('title'),
                              labelStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                              hintStyle: TextStyle(color: AppThemeColors.mutedText(context)),
                              counterStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                              errorText: _titleError ? 'Title is required' : null,
                              filled: true,
                              fillColor: AppThemeColors.surfaceBg(context),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: _titleError ? Colors.red : AppThemeColors.border(context),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: _titleError ? Colors.red : AppColors.cyan,
                                  width: 1.5,
                                ),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.red),
                              ),
                              focusedErrorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.red, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Content field (multiline, expands)
                          TextField(
                            controller: _contentCtrl,
                            minLines: 8,
                            maxLines: null,
                            keyboardType: TextInputType.multiline,
                            style: TextStyle(color: AppThemeColors.primaryText(context)),
                            decoration: InputDecoration(
                              labelText: t('enter_note'),
                              labelStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                              hintStyle: TextStyle(color: AppThemeColors.mutedText(context)),
                              alignLabelWithHint: true,
                              filled: true,
                              fillColor: AppThemeColors.surfaceBg(context),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: AppThemeColors.border(context)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          // Save button — full width, cyan, height 52
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cyan,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppColors.cyan.withValues(alpha: 0.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              onPressed: _saving ? null : _save,
                              child: _saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Text(
                                      _isEdit ? t('update_label') : t('create'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
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
}
