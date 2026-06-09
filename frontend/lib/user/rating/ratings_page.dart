import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../../widgets/subscription_prompt.dart';

// Widget to display 5 stars with filled stars according to value
class _StarDisplay extends StatelessWidget {
  final double value;
  const _StarDisplay({required this.value});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < value.round() ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 32,
        );
      }),
    );
  }
}

// Widget for interactive star input
class _StarInput extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _StarInput({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (index) {
        final filled = value >= index + 1;
        return GestureDetector(
          onTap: () => onChanged((index + 1).toDouble()),
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 28,
          ),
        );
      }),
    );
  }
}

// Widget to show ratings given by this user
class _YourRatingsList extends StatelessWidget {
  final List<dynamic> userRatings;
  const _YourRatingsList({required this.userRatings});
  @override
  Widget build(BuildContext context) {
    if (userRatings.isEmpty) {
      return const Text('No ratings given yet.',
          style: TextStyle(color: Colors.grey));
    }
    return Column(
      children: List.generate(userRatings.length, (idx) {
        final r = userRatings[idx];
        return Card(
          color: Colors.white.withOpacity(0.9),
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: SizedBox(
              width: 100,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _StarDisplay(value: (r['rating'] ?? 0).toDouble()),
              ),
            ),
            title: Text('To: ${r['rateeName'] ?? r['ratee'] ?? "User"}',
                style: const TextStyle(color: Color(0xFF023E8A))),
            subtitle: Text('Rating: ${r['rating']}',
                style: const TextStyle(color: Color(0xFF0077B6))),
          ),
        );
      }),
    );
  }
}

// Widget to show ratings received by this user
class _RatingsReceivedList extends StatelessWidget {
  final List<dynamic> userRatings;
  const _RatingsReceivedList({required this.userRatings});
  @override
  Widget build(BuildContext context) {
    if (userRatings.isEmpty) {
      return const Text('No ratings yet.',
          style: TextStyle(color: Color(0xFF023E8A)));
    }
    return Column(
      children: List.generate(userRatings.length, (idx) {
        final r = userRatings[idx];
        return Card(
          color: Colors.white.withOpacity(0.9),
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: SizedBox(
              width: 100,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _StarDisplay(value: (r['rating'] ?? 0).toDouble()),
              ),
            ),
            title: Text('From: ${r['raterName'] ?? r['rater']}',
                style: const TextStyle(color: Color(0xFF023E8A))),
            subtitle: Text('Rating: ${r['rating']}',
                style: const TextStyle(color: Color(0xFF0077B6))),
          ),
        );
      }),
    );
  }
}

class RatingsPage extends StatefulWidget {
  const RatingsPage({super.key});

  @override
  State<RatingsPage> createState() => _RatingsPageState();
}

class _RatingsPageState extends State<RatingsPage> {
  // Activity log for ratings
  List<dynamic> ratingActivities = [];
  // Search user rating by username/email
  Future<void> _searchUserRating() async {
    final input = _searchController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _searchError = 'Please enter a username or email.';
        _searchedAvgRating = null;
        _searchedName = null;
        _searchedUsername = null;
        _searchedEmail = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
      _searchedAvgRating = null;
      _searchedName = null;
      _searchedUsername = null;
      _searchedEmail = null;
    });
    try {
      final res =
          await ApiClient.get('/api/ratings/user-avg?usernameOrEmail=$input');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _searchedAvgRating = (data['avgRating'] ?? 0).toDouble();
          _searchedName = data['name'] ?? '';
          _searchedUsername = data['username'] ?? '';
          _searchedEmail = data['email'] ?? '';
        });
      } else {
        final err = json.decode(res.body);
        setState(() {
          _searchError = err['error'] ?? 'User not found.';
        });
      }
    } catch (e) {
      setState(() {
        _searchError = 'Error searching user.';
      });
    }
    setState(() {
      _searching = false;
    });
  }

  // For searching other user's avg rating
  final _searchController = TextEditingController();
  String? _searchError;
  double? _searchedAvgRating;
  String? _searchedName;
  String? _searchedUsername;
  String? _searchedEmail;
  bool _searching = false;
  bool _showGiven = false;
  bool _showReceived = false;
  double? avgRating;
  List<dynamic> ratingsGiven = [];
  List<dynamic> ratingsReceived = [];
  bool loading = true;
  String? error;
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  double _selectedRating = 5;
  String? _submitError;
  bool _submitting = false;
  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    fetchRatings();
    fetchRatingActivities();
  }

  Future<void> fetchRatingActivities() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final res = await ApiClient.get(
        '/api/activities?type=user_rated,user_rating_received&limit=10');
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      setState(() {
        ratingActivities = data['activities'] ?? [];
      });
    }
  }

  Future<void> fetchRatings() async {
    setState(() {
      loading = true;
      error = null;
    });
    final session = Provider.of<SessionProvider>(context, listen: false);
    final res = await ApiClient.get('/api/ratings/me');
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      setState(() {
        avgRating = data['avgRating']?.toDouble();
        ratingsGiven = data['ratingsGiven'] ?? [];
        ratingsReceived = data['ratingsReceived'] ?? [];
        loading = false;
      });
    } else {
      setState(() {
        error = 'Failed to load ratings.';
        loading = false;
      });
    }
  }

  Future<void> submitRating() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final session = Provider.of<SessionProvider>(context, listen: false);
    final res = await ApiClient.post(
      '/api/ratings',
      body: {
        'usernameOrEmail': _usernameController.text.trim(),
        'rating': _selectedRating,
      },
    );
    if (res.statusCode == 201) {
      setState(() {
        _showSuccess = true;
        _usernameController.clear();
        _selectedRating = 5;
      });
      fetchRatings();
    } else {
      setState(() {
        _submitError =
            json.decode(res.body)['error'] ?? 'Failed to submit rating.';
      });
    }
    setState(() {
      _submitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 140,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Transform.rotate(
              angle: 3.1416,
              child: CustomPaint(
                painter: _WavyPainter(),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Ratings',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: SingleChildScrollView(
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  vertical: 32, horizontal: 0),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 24, horizontal: 20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.07),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              width: 430,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Consumer<SessionProvider>(
                                    builder: (context, session, child) {
                                      if (session.isSubscribed) {
                                        return Column(
                                          children: [
                                            Text('Search User Rating',
                                                style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF0077B6))),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller:
                                                        _searchController,
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          'Enter username or email',
                                                      prefixIcon: const Icon(
                                                          Icons.search),
                                                      border:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                      ),
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                    ),
                                                    onSubmitted: (_) =>
                                                        _searchUserRating(),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                ElevatedButton(
                                                  onPressed: _searching
                                                      ? null
                                                      : _searchUserRating,
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        const Color(0xFF00B4D8),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 14,
                                                        horizontal: 16),
                                                  ),
                                                  child: _searching
                                                      ? const SizedBox(
                                                          width: 18,
                                                          height: 18,
                                                          child:
                                                              CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2))
                                                      : const Text('Search'),
                                                ),
                                              ],
                                            ),
                                            if (_searchError != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8),
                                                child: _StylishPopup(
                                                  message: _searchError!,
                                                  color: Colors.red,
                                                ),
                                              ),
                                            if (_searchedAvgRating != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 12, bottom: 8),
                                                child: Column(
                                                  children: [
                                                    Text(
                                                      _searchedName != null &&
                                                              _searchedName!
                                                                  .isNotEmpty
                                                          ? '${_searchedName!} (@${_searchedUsername ?? ''})'
                                                          : _searchedUsername ??
                                                              '',
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                          color: Color(
                                                              0xFF023E8A)),
                                                    ),
                                                    if (_searchedEmail != null)
                                                      Text(_searchedEmail!,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 13,
                                                                  color: Colors
                                                                      .grey)),
                                                    const SizedBox(height: 6),
                                                    _StarDisplay(
                                                        value:
                                                            _searchedAvgRating ??
                                                                0),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      _searchedAvgRating!
                                                          .toStringAsFixed(2),
                                                      style: const TextStyle(
                                                          fontSize: 22,
                                                          color:
                                                              Color(0xFF023E8A),
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        );
                                      } else {
                                        return Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(22),
                                            gradient: const LinearGradient(
                                              colors: [
                                                Colors.orange,
                                                Colors.white,
                                                Colors.green
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFCE4EC),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Column(
                                              children: [
                                                Text(
                                                  'Subscribe to Search User Ratings',
                                                  style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF0077B6)),
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  'Unlock the ability to search for other users\' ratings by subscribing to our premium plan.',
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 10),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    showSubscriptionPrompt(
                                                        context);
                                                  },
                                                  child: const Text(
                                                      'Subscribe Now'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        const Color(0xFF00B4D8),
                                                  ),
                                                )
                                              ],
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                  Divider(
                                      thickness: 1.2,
                                      color: Colors.blueGrey[100]),
                                  const SizedBox(height: 10),
                                  // Your Average Rating Section
                                  Text('Your Average Rating',
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF023E8A))),
                                  const SizedBox(height: 10),
                                  _StarDisplay(value: avgRating ?? 0),
                                  const SizedBox(height: 6),
                                  Text(
                                      avgRating != null
                                          ? avgRating!.toStringAsFixed(2)
                                          : '-',
                                      style: const TextStyle(
                                          fontSize: 28,
                                          color: Color(0xFF023E8A),
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 24),
                                  Divider(
                                      thickness: 1.2,
                                      color: Colors.blueGrey[100]),
                                  const SizedBox(height: 10),
                                  // Stylish input for rating another user
                                  Text('Rate Another User',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0077B6))),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8F6FA),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                          color: const Color(0xFF90E0EF),
                                          width: 1.2),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (_showSuccess)
                                          _StylishPopup(
                                              message:
                                                  'Your rating has been stored.',
                                              color: Colors.green),
                                        Form(
                                          key: _formKey,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              TextFormField(
                                                controller: _usernameController,
                                                decoration: InputDecoration(
                                                  labelText:
                                                      'Username or Email',
                                                  prefixIcon: const Icon(
                                                      Icons.person_outline),
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                ),
                                                validator: (val) =>
                                                    val == null || val.isEmpty
                                                        ? 'Required'
                                                        : null,
                                              ),
                                              const SizedBox(height: 16),
                                              Row(
                                                children: [
                                                  const Text('Rating:'),
                                                  _StarInput(
                                                    value: _selectedRating,
                                                    onChanged: (val) =>
                                                        setState(() =>
                                                            _selectedRating =
                                                                val),
                                                  ),
                                                  Text(_selectedRating
                                                      .toStringAsFixed(1)),
                                                ],
                                              ),
                                              if (_submitError != null)
                                                _StylishPopup(
                                                    message: _submitError!,
                                                    color: Colors.red),
                                              const SizedBox(height: 12),
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton(
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        const Color(0xFF00B4D8),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 14),
                                                  ),
                                                  onPressed: _submitting
                                                      ? null
                                                      : submitRating,
                                                  child: _submitting
                                                      ? const SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child:
                                                              CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2))
                                                      : const Text(
                                                          'Submit Rating',
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  // Your Ratings Section (if any)
                                  Divider(
                                      thickness: 1.2,
                                      color: Colors.blueGrey[100]),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Ratings You Gave',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0077B6))),
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _showGiven = !_showGiven;
                                          });
                                        },
                                        child:
                                            Text(_showGiven ? 'Hide' : 'View'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (_showGiven)
                                    _YourRatingsList(
                                      userRatings: ratingsGiven,
                                    ),
                                  const SizedBox(height: 28),
                                  Divider(
                                      thickness: 1.2,
                                      color: Colors.blueGrey[100]),
                                  const SizedBox(height: 10),
                                  // Ratings Received Section
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Ratings Received',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF023E8A))),
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _showReceived = !_showReceived;
                                          });
                                        },
                                        child: Text(
                                            _showReceived ? 'Hide' : 'View'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (_showReceived)
                                    _RatingsReceivedList(
                                        userRatings: ratingsReceived),
                                  // --- Recent Rating Activities ---
                                  if (ratingActivities.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Text('Recent Rating Activities',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0077B6))),
                                    ...ratingActivities.map((activity) => Card(
                                          color: Colors.white.withOpacity(0.95),
                                          elevation: 2,
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          child: ListTile(
                                            leading: Icon(
                                              activity['type'] == 'user_rated'
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: Colors.amber,
                                              size: 32,
                                            ),
                                            title: Text(activity['title'] ?? '',
                                                style: TextStyle(
                                                    color: Color(0xFF023E8A))),
                                            subtitle: Text(
                                                activity['description'] ?? '',
                                                style: TextStyle(
                                                    color: Color(0xFF0077B6))),
                                            trailing: activity['metadata'] !=
                                                        null &&
                                                    activity['metadata']
                                                            ['rating'] !=
                                                        null
                                                ? Text(
                                                    '${activity['metadata']['rating']} ★',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.amber))
                                                : null,
                                          ),
                                        ))
                                  ],
                                ],
                              ),
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

// Blue wavy painter for background
class _WavyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00B4D8).withOpacity(0.2)
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, size.height * 0.15);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.10,
        size.width * 0.5, size.height * 0.18);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.26, size.width, size.height * 0.18);
    path.lineTo(size.width, 0);
    path.lineTo(0, 0);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Stylish popup widget
class _StylishPopup extends StatelessWidget {
  final String message;
  final Color color;
  const _StylishPopup({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, color: color, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.5,
      size.width * 0.5,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
