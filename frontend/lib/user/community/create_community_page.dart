import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io' as dart_io;
import '../../widgets/app_colors.dart';
import '../../widgets/wave_widget.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive.dart';
import '../../l10n/app_localizations.dart';

class CreateCommunityPage extends StatefulWidget {
  const CreateCommunityPage({Key? key}) : super(key: key);

  @override
  State<CreateCommunityPage> createState() => _CreateCommunityPageState();
}

class _CreateCommunityPageState extends State<CreateCommunityPage> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  Color _color = const Color(0xFF00B4D8);
  XFile? _image;
  bool _creating = false;
  String? _error;

  static const List<Color> _presetColors = [
    Color(0xFF00B4D8), Color(0xFF0096C7), Color(0xFF023E8A), Color(0xFF2196F3),
    Color(0xFF3F51B5), Color(0xFF673AB7), Color(0xFF9C27B0), Color(0xFFE91E63),
    Color(0xFFF44336), Color(0xFFFF5722), Color(0xFFFF9800), Color(0xFFFFC107),
    Color(0xFF4CAF50), Color(0xFF009688), Color(0xFF8BC34A), Color(0xFF607D8B),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String get _colorHex => '#${_color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null && mounted) setState(() => _image = picked);
  }

  Future<void> _pickColor() async {
    Color temp = _color;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(24, 20, 24, 32 + MediaQuery.of(ctx).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // drag handle
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),

            // Header
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: temp.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.palette_rounded, color: temp, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLocalizations.of(ctx).t('pick_community_color_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(ctx))),
                Text(AppLocalizations.of(ctx).t('pick_community_color_desc'),
                  style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
              ])),
              // Selected color preview
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: temp,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: temp.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))],
                  border: Border.all(color: AppThemeColors.border(ctx), width: 2),
                ),
              ),
            ]),

            const SizedBox(height: 20),

            // Preset color grid
            Text('PRESETS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppThemeColors.mutedText(ctx), letterSpacing: 1.4)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8, crossAxisSpacing: 10, mainAxisSpacing: 10,
              ),
              itemCount: _presetColors.length,
              itemBuilder: (_, i) {
                final c = _presetColors[i];
                final selected = temp.toARGB32() == c.toARGB32();
                return GestureDetector(
                  onTap: () => setSheet(() => temp = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: selected ? 2.5 : 0,
                      ),
                      boxShadow: selected
                          ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(0, 2))]
                          : [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)],
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                        : null,
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Custom color row
            GestureDetector(
              onTap: () async {
                Color custom = temp;
                final picked = await showDialog<Color>(
                  context: ctx,
                  builder: (dCtx) => AlertDialog(
                    backgroundColor: AppThemeColors.cardBg(dCtx),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text(AppLocalizations.of(dCtx).t('custom_color_label'), style: TextStyle(color: AppThemeColors.primaryText(dCtx), fontWeight: FontWeight.bold)),
                    content: SingleChildScrollView(
                      child: ColorPicker(
                        pickerColor: custom,
                        onColorChanged: (c) => custom = c,
                        pickerAreaHeightPercent: 0.65,
                        enableAlpha: false,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx),
                        child: Text(AppLocalizations.of(dCtx).t('cancel'), style: TextStyle(color: AppThemeColors.secondaryText(dCtx))),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(dCtx, custom),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        child: Text(AppLocalizations.of(dCtx).t('select')),
                      ),
                    ],
                  ),
                );
                if (picked != null) setSheet(() => temp = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppThemeColors.surfaceBg(ctx),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppThemeColors.border(ctx)),
                ),
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppThemeColors.border(ctx),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.colorize_rounded, size: 17, color: AppThemeColors.secondaryText(ctx)),
                  ),
                  const SizedBox(width: 12),
                  Text(AppLocalizations.of(ctx).t('custom_color_row'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: AppThemeColors.primaryText(ctx))),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, color: AppThemeColors.mutedText(ctx), size: 20),
                ]),
              ),
            ),

            const SizedBox(height: 20),

            // Apply button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: temp,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: temp.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _color = temp);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
                ),
                child: Text(AppLocalizations.of(ctx).t('apply_color_btn'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = AppLocalizations.of(context).t('please_enter_community_name')); return; }

    setState(() { _creating = true; _error = null; });
    try {
      final res = await ApiClient.post('/api/communities', body: {
        'name': name,
        'description': _descCtrl.text.trim(),
        'color': _colorHex,
      });
      final data = jsonDecode(res.body);
      if (res.statusCode == 201) {
        final communityId = data['community']?['_id']?.toString() ?? '';
        if (_image != null && communityId.isNotEmpty) {
          try {
            await ApiClient.postMultipart(
              '/api/communities/$communityId/image',
              files: [ApiMultipartFile(field: 'image', filename: 'community.jpg', path: _image!.path)],
            );
          } catch (_) {}
        }
        if (mounted) Navigator.pop(context, data['community']);
      } else {
        setState(() => _error = data['error'] ?? AppLocalizations.of(context).t('failed_to_create_community'));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Widget _field({required IconData icon, required Widget child, Color? iconColor}) {
    final ic = iconColor ?? AppColors.cyan;
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: ic.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: ic, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
        const SizedBox(width: 8),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // Top wave
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: const DeeperTopWaveClipper(),
              child: Container(
                height: context.sh(70),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppThemeColors.waveGradient(context),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          // Header row
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).t('create_community_btn'),
                    style: const TextStyle(
                      color: Colors.white, fontSize: 22,
                      fontWeight: FontWeight.bold, letterSpacing: 0.5,
                      shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
                    ),
                  ),
                ),
              ]),
            ),
          ),
          // Scrollable content
          Positioned(
            top: 80, left: 0, right: 0, bottom: 0,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue, Color(0xFF7B2FBE)]),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(19)),
              child: Row(children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Stack(children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        gradient: _image == null
                            ? LinearGradient(colors: [_color.withValues(alpha: 0.7), _color])
                            : null,
                        borderRadius: BorderRadius.circular(16),
                        image: _image != null
                            ? DecorationImage(image: FileImage(dart_io.File(_image!.path)), fit: BoxFit.cover)
                            : null,
                        boxShadow: [BoxShadow(color: _color.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: _image == null ? const Icon(Icons.hub_rounded, color: Colors.white, size: 28) : null,
                    ),
                    Positioned(right: 0, bottom: 0,
                      child: Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(color: AppColors.cyan, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                        child: const Icon(Icons.camera_alt_rounded, size: 10, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLocalizations.of(context).t('new_community_heading'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context))),
                  const SizedBox(height: 4),
                  Text(AppLocalizations.of(context).t('new_community_subheading'),
                    style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 13)),
                ])),
              ]),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Container(width: 34, height: 34,
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18)),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500))),
                GestureDetector(onTap: () => setState(() => _error = null),
                  child: const Icon(Icons.close_rounded, color: Colors.red, size: 16)),
              ]),
            ),
          ],

          const SizedBox(height: 24),

          // Name
          _field(
            icon: Icons.hub_rounded,
            child: TextField(
              controller: _nameCtrl,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).t('community_name_required_label'),
                labelStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Description
          _field(
            icon: Icons.notes_rounded,
            child: TextField(
              controller: _descCtrl,
              maxLines: 2,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).t('description_optional_label'),
                labelStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Color picker field
          GestureDetector(
            onTap: _pickColor,
            child: Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppThemeColors.border(context)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                // Icon box tinted with selected color
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: _color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.palette_rounded, color: _color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLocalizations.of(context).t('community_color_section'), style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
                  const SizedBox(height: 2),
                  Text(_colorHex, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppThemeColors.primaryText(context), letterSpacing: 0.5)),
                ])),
                // Color swatch
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: _color.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2))],
                    border: Border.all(color: AppThemeColors.border(context), width: 1.5),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: AppThemeColors.mutedText(context), size: 18),
              ]),
            ),
          ),

          const SizedBox(height: 32),

          // Create button
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_color, AppColors.blue]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: _color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: ElevatedButton(
              onPressed: _creating ? null : _create,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _creating
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(AppLocalizations.of(context).t('create_community_btn'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ]),
            ),
          ),
        ],
      ),
    );
  }
}
