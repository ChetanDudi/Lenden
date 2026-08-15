import 'package:flutter/material.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_colors.dart';
import '../../utils/theme_helper.dart';
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
  bool _contentError = false;

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
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      setState(() {
        _titleError = title.isEmpty;
        _contentError = content.isEmpty;
      });
      return;
    }
    setState(() {
      _saving = true;
      _titleError = false;
      _contentError = false;
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
        if (mounted) setState(() => _saving = false);
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final hasContent = _contentCtrl.text.isNotEmpty;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppThemeColors.scaffoldBg(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded,
              color: AppThemeColors.primaryText(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit ? t('edit_note') : t('new_note'),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppThemeColors.primaryText(context),
          ),
        ),
        centerTitle: true,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.cyan),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _save,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
                child: Text(
                  _isEdit ? t('update_label') : t('save'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
              height: 1, color: AppThemeColors.border(context)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title field ──────────────────────────────────────────────
            TextField(
              controller: _titleCtrl,
              maxLength: 50,
              textCapitalization: TextCapitalization.sentences,
              autofocus: !_isEdit,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context),
              ),
              decoration: InputDecoration(
                hintText: t('title'),
                hintStyle: TextStyle(
                  color: _titleError
                      ? Colors.red.shade300
                      : AppThemeColors.mutedText(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
                counterStyle: TextStyle(
                    color: AppThemeColors.mutedText(context), fontSize: 11),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) {
                if (_titleError) setState(() => _titleError = false);
              },
            ),
            if (_titleError) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.error_outline_rounded,
                    size: 13, color: Colors.red.shade500),
                const SizedBox(width: 4),
                Text('Title is required',
                    style: TextStyle(
                        fontSize: 12, color: Colors.red.shade500)),
              ]),
            ],
            const SizedBox(height: 4),
            Divider(
              color: _titleError ? Colors.red.shade400 : AppThemeColors.border(context),
              height: 1,
            ),
            const SizedBox(height: 10),

            // ── Content header row (label + clear button) ────────────────
            Row(
              children: [
                Text(
                  'Note content',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: AppThemeColors.mutedText(context),
                  ),
                ),
                const Spacer(),
                if (hasContent)
                  GestureDetector(
                    onTap: () {
                      _contentCtrl.clear();
                      setState(() {});
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear_all_rounded,
                            size: 15,
                            color: Colors.red.shade400),
                        const SizedBox(width: 3),
                        Text(
                          'Clear all',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (_contentError) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.error_outline_rounded,
                    size: 13, color: Colors.red.shade500),
                const SizedBox(width: 4),
                Text('Note content is required',
                    style: TextStyle(
                        fontSize: 12, color: Colors.red.shade500)),
              ]),
            ],
            const SizedBox(height: 6),

            // ── Content field — fills remaining space ────────────────────
            Expanded(
              child: TextField(
                controller: _contentCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  fontSize: 15,
                  color: AppThemeColors.primaryText(context),
                  height: 1.65,
                ),
                decoration: InputDecoration(
                  hintText: _contentError
                      ? 'Note content is required...'
                      : t('enter_note'),
                  hintStyle: TextStyle(
                    color: _contentError
                        ? Colors.red.shade300
                        : AppThemeColors.mutedText(context),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) {
                  setState(() {
                    if (_contentError && _contentCtrl.text.isNotEmpty) {
                      _contentError = false;
                    }
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
