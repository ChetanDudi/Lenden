import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'utils/theme_helper.dart';

class OtpInput extends StatefulWidget {
  final void Function(String) onChanged;
  final bool enabled;
  final bool autoFocus;
  final bool obscureText;
  final bool showVisibilityToggle;
  const OtpInput({
    super.key,
    required this.onChanged,
    this.enabled = true,
    this.autoFocus = false,
    this.obscureText = false,
    this.showVisibilityToggle = false,
  });

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
      final idx = i;
      // Backspace on an empty box → clear the previous box and move focus back.
      // KeyRepeatEvent handles holding-backspace so the user can sweep back quickly.
      _focusNodes[i].onKeyEvent = (node, event) {
        if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            _controllers[idx].text.isEmpty &&
            idx > 0) {
          _controllers[idx - 1].clear();
          _focusNodes[idx - 1].requestFocus();
          _notifyValue();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }

    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNodes[0].requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  void _notifyValue() {
    widget.onChanged(_controllers.map((c) => c.text).join());
  }

  void _onFieldChanged(int i, String value) {
    // Paste / SMS autofill can deliver multiple digits at once.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int j = 0; j < 6; j++) {
        _controllers[j].text = j < digits.length ? digits[j] : '';
      }
      // Place cursor after the last filled box (or stay on the last box).
      final nxt = (digits.length - 1).clamp(0, 5);
      _focusNodes[nxt].requestFocus();
      _notifyValue();
      return;
    }

    // Single digit entered → advance to the next box.
    if (value.isNotEmpty && i < 5) {
      _focusNodes[i + 1].requestFocus();
    }
    _notifyValue();
  }

  Widget _buildBox(BuildContext context, int i) {
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
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          maxLength: 1,
          obscureText:
              widget.showVisibilityToggle ? _isObscured : widget.obscureText,
          obscuringCharacter: '*',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppThemeColors.primaryText(context),
          ),
          decoration: const InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.transparent,
            border: InputBorder.none,
          ),
          onChanged: (value) => _onFieldChanged(i, value),
          // Select all text on tap so typing a new digit replaces the old one.
          onTap: () => _controllers[i].selection = TextSelection(
              baseOffset: 0,
              extentOffset: _controllers[i].text.length),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final otpRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) => _buildBox(context, i)),
    );

    if (!widget.showVisibilityToggle) return otpRow;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        otpRow,
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: widget.enabled
                ? () => setState(() => _isObscured = !_isObscured)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isObscured
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 16,
                    color: AppThemeColors.secondaryText(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isObscured ? 'Show' : 'Hide',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeColors.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
