import 'package:flutter/material.dart';
import 'dart:convert';
import '../../utils/api_client.dart';

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

  // Show a stylish popup for success/error messages
  void _showStylishPopup(String message, {bool isError = false}) {
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
            Text(isError ? 'Error' : 'Success',
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
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Submit app rating to backend
  Future<void> _submitAppRating() async {
    if (_selectedAppRating == 0) {
      _showStylishPopup('Please select a rating.', isError: true);
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await ApiClient.post(
        '/api/rating',
        body: {
          'rating': _selectedAppRating,
        },
      );
      if (response.statusCode == 200) {
        _showStylishPopup('App rating submitted!');
        setState(() {
          _hasAppRated = true;
        });
      } else {
        _showStylishPopup('Error: ${response.body}', isError: true);
      }
    } catch (e) {
      _showStylishPopup('Error: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _submitFeedback() async {
    if (_feedbackController.text.isEmpty) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await ApiClient.post(
        '/api/feedback',
        body: {'feedback': _feedbackController.text},
      );
      if (response.statusCode == 200) {
        _showStylishPopup('Feedback submitted!');
        _feedbackController.clear();
        await _fetchUserFeedbacks();
      } else {
        final body =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        _showStylishPopup('Error: ${body?['error'] ?? response.body}',
            isError: true);
      }
    } catch (e) {
      _showStylishPopup('Error: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildAppRatingStars() {
    // If user has rated, show stars filled according to their previous rating and disable interaction
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final isFilled = index < _selectedAppRating;
        return IconButton(
          icon: Icon(
            isFilled ? Icons.star : Icons.star_border,
            color: Colors.amber,
          ),
          onPressed: _hasAppRated
              ? null
              : () {
                  setState(() {
                    _selectedAppRating = index + 1;
                  });
                },
        );
      }),
    );
  }

  Future<void> _fetchUserFeedbacks() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await ApiClient.get('/api/feedback/my');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _userFeedbacks =
              List<Map<String, dynamic>>.from(data['feedbacks'] ?? []);
        });
      }
      // Also fetch app rating status
      final ratingRes = await ApiClient.get('/api/rating/my');
      if (ratingRes.statusCode == 200) {
        final ratingData = jsonDecode(ratingRes.body);
        setState(() {
          // If user has already rated, set _hasAppRated and show their previous rating
          if (ratingData['rating'] != null) {
            _hasAppRated = true;
            _selectedAppRating = ratingData['rating'];
          } else {
            _hasAppRated = false;
            _selectedAppRating = 0;
          }
        });
      }
    } catch (e) {
      // ignore error
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildFeedbackList() {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_userFeedbacks.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 16),
          Icon(Icons.feedback_outlined, color: Colors.grey, size: 48),
          const SizedBox(height: 8),
          const Text('No feedbacks yet.',
              style: TextStyle(fontSize: 18, color: Colors.grey)),
        ],
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _userFeedbacks.length,
      itemBuilder: (context, index) {
        final feedback = _userFeedbacks[index];
        return Container(
          margin: const EdgeInsets.symmetric(
              vertical: 12, horizontal: 4), // More margin for boundary
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Colors.blueAccent.withValues(alpha: 0.3),
                width: 2), // Add visible boundary
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF00B4D8),
                  child: Icon(Icons.feedback, color: Colors.white),
                  radius: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if ((feedback['rating'] ?? 0) > 0)
                            Row(
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 20),
                                const SizedBox(width: 4),
                                Text('${feedback['rating']} ★',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          const Spacer(),
                          Builder(
                            builder: (context) {
                              String dateStr = '';
                              String timeStr = '';
                              if (feedback['createdAt'] != null) {
                                DateTime dt;
                                try {
                                  dt = DateTime.parse(
                                      feedback['createdAt'].toString());
                                  dateStr =
                                      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                                  timeStr =
                                      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                } catch (e) {
                                  dateStr = feedback['createdAt']
                                      .toString()
                                      .substring(0, 10);
                                  timeStr = feedback['createdAt']
                                      .toString()
                                      .substring(11, 16);
                                }
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(dateStr,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey)),
                                  Text(timeStr,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey)),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        feedback['feedback'] ?? '',
                        style: const TextStyle(
                            fontSize: 16, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Fetch user's previous app rating immediately on page load
    _fetchUserAppRating();
  }

  // Fetch only user's app rating (not feedbacks)
  Future<void> _fetchUserAppRating() async {
    setState(() {
      _isLoading = true;
    });
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
    } catch (e) {
      // ignore error
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      body: Stack(
        children: [
          // Top blue wave
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 120,
                color: const Color(0xFF00B4D8),
              ),
            ),
          ),
          // Main content
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        IconButton(
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.black),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                        const Expanded(
                          child: Text(
                            'Feedback',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 28.0,
                          right: 28.0,
                          top: 24.0,
                          bottom: 100.0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 20),
                            const Text('Feedback',
                                style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            const Text('Share your experience and rate the app',
                                style:
                                    TextStyle(fontSize: 16, color: Colors.grey),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 32),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 10),
                                  const Text('Rate the app:',
                                      style: TextStyle(fontSize: 18)),
                                  _buildAppRatingStars(),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _isLoading || _hasAppRated
                                              ? null
                                              : _submitAppRating,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF00B4D8),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(24)),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white))
                                              : Text(
                                                  _hasAppRated
                                                      ? 'App Rated'
                                                      : 'Submit App Rating',
                                                  style: const TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _feedbackController,
                                    maxLines: 3,
                                    decoration: const InputDecoration(
                                      labelText: 'Your feedback/suggestions',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed:
                                        _isLoading ? null : _submitFeedback,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.deepPurple,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(24)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white))
                                        : const Text('Submit Feedback',
                                            style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.white)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextButton(
                              onPressed: () async {
                                setState(() {
                                  _showFeedbacks = !_showFeedbacks;
                                });
                                if (_showFeedbacks) await _fetchUserFeedbacks();
                              },
                              child: Text(_showFeedbacks
                                  ? 'Hide Your Feedbacks'
                                  : 'View Your Feedbacks'),
                            ),
                            if (_showFeedbacks)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: _buildFeedbackList(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom blue wave (always at the very bottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipPath(
              clipper: BottomWaveClipper(),
              child: Container(
                height: 70,
                color: const Color(0xFF00B4D8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Blue wave clippers

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(
        size.width / 2, size.height, size.width, size.height - 30);
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
    path.moveTo(0, 30);
    path.quadraticBezierTo(size.width / 2, 0, size.width, 30);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
