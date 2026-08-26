import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../widgets/app_colors.dart';

class ImageCropPage extends StatefulWidget {
  final Uint8List imageBytes;
  const ImageCropPage({super.key, required this.imageBytes});

  @override
  State<ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<ImageCropPage> {
  final _repaintKey = GlobalKey();
  bool _saving = false;

  Future<void> _done() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
          _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) { Navigator.pop(context); return; }
      final ratio = MediaQuery.of(context).devicePixelRatio;
      final img = await boundary.toImage(pixelRatio: ratio.clamp(1.0, 3.0));
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (mounted) Navigator.pop(context, data?.buffer.asUint8List());
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
        ),
        leadingWidth: 80,
        title: const Text('Crop Photo',
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _saving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.cyan)))
                : TextButton(
                    onPressed: _done,
                    child: const Text('Done',
                        style: TextStyle(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.bold,
                            fontSize: 15))),
          ),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final size = constraints.maxWidth;
              return Stack(
                children: [
                  RepaintBoundary(
                    key: _repaintKey,
                    child: SizedBox.square(
                      dimension: size,
                      child: ClipRect(
                        child: InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 10.0,
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.cover,
                            width: size,
                            height: size,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Grid overlay (rule of thirds)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _GridPainter()),
                    ),
                  ),
                ],
              );
            },
          ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.only(
                bottom: 24 + MediaQuery.of(context).padding.bottom),
            child: const Text(
              'Pinch to zoom  •  Drag to reposition',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    for (int i = 1; i <= 2; i++) {
      canvas.drawLine(
          Offset(size.width * i / 3, 0),
          Offset(size.width * i / 3, size.height),
          linePaint);
      canvas.drawLine(
          Offset(0, size.height * i / 3),
          Offset(size.width, size.height * i / 3),
          linePaint);
    }
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
