import 'package:flutter/material.dart';
import 'dart:convert';
import '../api_config.dart';
import '../otp_input.dart';
import '../utils/api_client.dart';

class UserForgotPasswordPage extends StatefulWidget {
  final String? prefillEmail;
  const UserForgotPasswordPage({super.key, this.prefillEmail});

  @override
  State<UserForgotPasswordPage> createState() => _UserForgotPasswordPageState();
}

class _UserForgotPasswordPageState extends State<UserForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool _otpSent = false;
  bool _otpVerified = false;
  bool _isVerifyingOtp = false;
  bool _isResetting = false;
  String? _errorMessage;
  String? _userType; // 'user' or 'admin'
  int _secondsLeft = 0;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  late final FocusNode _otpFocusNode;
  late final FocusNode _newPasswordFocusNode;
  late final FocusNode _confirmPasswordFocusNode;
  String _forgotOtp = '';

  @override
  void initState() {
    super.initState();
    _otpFocusNode = FocusNode();
    _newPasswordFocusNode = FocusNode();
    _confirmPasswordFocusNode = FocusNode();
    if (widget.prefillEmail != null) {
      _emailController.text = widget.prefillEmail!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _otpFocusNode.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  void _sendOtp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final res = await _post('/api/users/send-reset-otp', {
      'email': _emailController.text,
    });
    if (res['status'] == 200) {
      setState(() {
        _otpSent = true;
        _userType = res['data']['userType'];
        _secondsLeft = 120;
        _errorMessage = null;
      });
      _startTimer();
      FocusScope.of(context).requestFocus(_otpFocusNode);
    } else {
      setState(() {
        _errorMessage = res['data']['error'] ?? 'Failed to send OTP.';
      });
    }
    setState(() {
      _isLoading = false;
    });
  }

  void _startTimer() {
    _secondsLeft = 120;
    Future.doWhile(() async {
      if (_secondsLeft > 0 && mounted && !_otpVerified) {
        await Future.delayed(const Duration(seconds: 1));
        setState(() {
          _secondsLeft--;
        });
        return true;
      }
      return false;
    });
  }

  void _verifyOtp() async {
    setState(() {
      _isVerifyingOtp = true;
      _errorMessage = null;
    });
    final res = await _post('/api/users/verify-reset-otp', {
      'email': _emailController.text,
      'otp': _otpController.text,
    });
    if (res['status'] == 200) {
      setState(() {
        _otpVerified = true;
        _errorMessage = null;
      });
      FocusScope.of(context).requestFocus(_newPasswordFocusNode);
    } else {
      setState(() {
        _errorMessage = res['data']['error'] ?? 'OTP verification failed.';
      });
    }
    setState(() {
      _isVerifyingOtp = false;
    });
  }

  void _resendOtp() {
    _sendOtp();
    _otpController.clear();
    setState(() {
      _otpVerified = false;
    });
  }

  void _resetPassword() async {
    setState(() {
      _isResetting = true;
      _errorMessage = null;
    });
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
        _isResetting = false;
      });
      return;
    }
    final res = await _post('/api/users/reset-password', {
      'email': _emailController.text,
      'userType': _userType,
      'newPassword': _newPasswordController.text,
    });
    if (res['status'] == 200) {
      setState(() {
        _errorMessage = null;
      });
      _showSuccessDialog('Password Reset Successful',
          'Your password has been reset successfully!');
    } else {
      setState(() {
        _errorMessage = res['data']['error'] ?? 'Failed to reset password.';
      });
    }
    setState(() {
      _isResetting = false;
    });
  }

  void _verifyOtpWithOtp(String otp) async {
    setState(() {
      _isVerifyingOtp = true;
      _errorMessage = null;
    });
    final res = await _post('/api/users/verify-reset-otp', {
      'email': _emailController.text,
      'otp': otp,
    });
    if (res['status'] == 200) {
      setState(() {
        _otpVerified = true;
        _errorMessage = null;
      });
      FocusScope.of(context).requestFocus(_newPasswordFocusNode);
    } else {
      setState(() {
        _errorMessage = res['data']['error'] ?? 'OTP verification failed.';
      });
    }
    setState(() {
      _isVerifyingOtp = false;
    });
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    try {
      print('🌐 Making API call to: ${ApiConfig.baseUrl + path}');
      print('📤 Request body: ${jsonEncode(body)}');

      final response = await ApiClient.post(path, body: body)
          .timeout(const Duration(minutes: 2));

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response headers: ${response.headers}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return {'status': response.statusCode, 'data': data};
      } else if (response.statusCode == 404) {
        return {
          'status': 404,
          'data': {'error': 'API endpoint not found'}
        };
      } else if (response.statusCode == 500) {
        return {
          'status': 500,
          'data': {'error': 'Server error'}
        };
      } else {
        final data = jsonDecode(response.body);
        return {'status': response.statusCode, 'data': data};
      }
    } catch (e) {
      print('❌ API call error: $e');
      if (e.toString().contains('SocketException')) {
        return {
          'status': 0,
          'data': {'error': 'No internet connection'}
        };
      } else if (e.toString().contains('HandshakeException')) {
        return {
          'status': 0,
          'data': {'error': 'SSL/TLS connection failed'}
        };
      } else {
        return {
          'status': 500,
          'data': {'error': e.toString()}
        };
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: const Color(0xFFE0F7FA),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle, color: Color(0xFF00B4D8), size: 60),
            SizedBox(height: 12),
            Text('Password Reset Successful',
                style: TextStyle(
                    color: Color(0xFF0077B5),
                    fontWeight: FontWeight.bold,
                    fontSize: 22),
                textAlign: TextAlign.center),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 16, color: Colors.black87),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: const Text('Login',
                style: TextStyle(
                    color: Color(0xFF00B4D8),
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      body: Stack(
        children: [
          // Top blue shape
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 120,
                color: const Color(0xFF00B4D8),
                child: SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          Navigator.pushReplacementNamed(context, '/');
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Bottom blue shape
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: BottomWaveClipper(),
              child: Container(
                height: 90,
                color: const Color(0xFF00B4D8),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28.0, vertical: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 60),
                    const Text('Forgot Password',
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text('Reset your password securely',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _emailController,
                        enabled: !_otpSent,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_otpSent)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _sendOtp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B4D8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Send OTP'),
                        ),
                      ),
                    if (_otpSent && !_otpVerified) ...[
                      const SizedBox(height: 16),
                      OtpInput(
                        onChanged: (val) => _forgotOtp = val,
                        enabled: true,
                        autoFocus: true,
                      ),
                      const SizedBox(height: 8),
                      if (_secondsLeft > 0)
                        Text(
                            'OTP expires in  ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.grey)),
                      if (_secondsLeft == 0)
                        TextButton(
                            onPressed: _resendOtp,
                            child: const Text('Resend OTP')),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isVerifyingOtp || _forgotOtp.length != 6
                              ? null
                              : () => _verifyOtpWithOtp(_forgotOtp),
                          child: _isVerifyingOtp
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Verify OTP'),
                        ),
                      ),
                    ],
                    if (_otpVerified) ...[
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _newPasswordController,
                          focusNode: _newPasswordFocusNode,
                          obscureText: _obscureNewPassword,
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 18),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureNewPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(() =>
                                  _obscureNewPassword = !_obscureNewPassword),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _confirmPasswordController,
                          focusNode: _confirmPasswordFocusNode,
                          obscureText: _obscureConfirmPassword,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 18),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(() =>
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isResetting ? null : _resetPassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B4D8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isResetting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Change Password'),
                        ),
                      ),
                    ],
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(_errorMessage!,
                          style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Add TopWaveClipper and BottomWaveClipper from login_page.dart here
class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.25, size.height, size.width * 0.5, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.4, size.width, size.height * 0.7);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.moveTo(0, 0);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.6,
        size.width * 0.5, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.75, 0, size.width, size.height * 0.4);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
// ... Add _buildOtpInput widget placeholder for now ...
