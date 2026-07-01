import 'package:flutter/material.dart';
import 'utils/theme_helper.dart';

class OtpInput extends StatefulWidget {
  final void Function(String) onChanged;
  final bool enabled;
  final bool autoFocus;
  final bool obscureText;
  final bool showVisibilityToggle;
  const OtpInput(
      {super.key,
      required this.onChanged,
      this.enabled = true,
      this.autoFocus = false,
      this.obscureText = false,
      this.showVisibilityToggle = false});

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isObscured = true;

  @override
  void initState() {
    super.initState();
    _isObscured = widget.obscureText;
    for (int i = 0; i < 6; i++) {
      _controllers[i].addListener(_onChanged);
    }
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNodes[0].requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    String code = _controllers.map((c) => c.text).join();
    widget.onChanged(code);
    for (int i = 0; i < 6; i++) {
      if (_controllers[i].text.length > 1) {
        _controllers[i].text = _controllers[i].text.characters.last;
      }
      if (_controllers[i].text.isNotEmpty && i < 5) {
        _focusNodes[i + 1].requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        return Container(
          width: 40,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              enabled: widget.enabled,
              autofocus: widget.autoFocus && i == 0,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 1,
              obscureText: widget.showVisibilityToggle
                  ? _isObscured
                  : widget.obscureText,
              obscuringCharacter: '*',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context)),
              decoration: const InputDecoration(
                counterText: '',
                filled: true,
                fillColor: Colors.transparent,
                border: InputBorder.none,
              ),
              onTap: () => _controllers[i].selection = TextSelection(
                  baseOffset: 0, extentOffset: _controllers[i].text.length),
            ),
          ),
        );
      }),
    );

    if (!widget.showVisibilityToggle) {
      return otpRow;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(child: otpRow),
        const SizedBox(width: 8),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: _isObscured ? 'Show PIN' : 'Hide PIN',
          onPressed: widget.enabled
              ? () => setState(() => _isObscured = !_isObscured)
              : null,
          icon: Icon(
            _isObscured
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: AppThemeColors.primaryText(context),
          ),
        ),
      ],
    );
  }
}
