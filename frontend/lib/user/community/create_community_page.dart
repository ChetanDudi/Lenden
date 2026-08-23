import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io' as dart_io;
import '../../widgets/app_colors.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';

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
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick community color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: temp,
            onColorChanged: (c) => temp = c,
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { setState(() => _color = temp); Navigator.pop(ctx); },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Community name is required'); return; }

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
        // Upload image if selected
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
        setState(() => _error = data['error'] ?? 'Failed to create community');
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
      appBar: AppBar(
        title: const Text('Create Community', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppThemeColors.cardBg(context),
        foregroundColor: AppThemeColors.primaryText(context),
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
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
                  Text('New Community', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                  const SizedBox(height: 4),
                  Text('A space that holds multiple groups', style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 13)),
                ])),
              ]),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), border: Border.all(color: Colors.red.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                GestureDetector(onTap: () => setState(() => _error = null), child: const Icon(Icons.close, color: Colors.red, size: 16)),
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
                labelText: 'Community Name *',
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
                labelText: 'Description (optional)',
                labelStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Color picker
          GestureDetector(
            onTap: _pickColor,
            child: _field(
              icon: Icons.palette_rounded,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(children: [
                  Text('Community Color', style: TextStyle(color: AppThemeColors.primaryText(context))),
                  const Spacer(),
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(color: _color, shape: BoxShape.circle, border: Border.all(color: AppThemeColors.border(context), width: 2)),
                  ),
                  const SizedBox(width: 4),
                ]),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Create button
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
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
                  : const Text('Create Community', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}
