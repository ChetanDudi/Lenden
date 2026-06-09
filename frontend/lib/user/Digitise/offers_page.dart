import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/api_client.dart';
import '../../session.dart';

class UserOffersPage extends StatefulWidget {
  const UserOffersPage({super.key});

  @override
  State<UserOffersPage> createState() => _UserOffersPageState();
}

class _UserOffersPageState extends State<UserOffersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _offers = [];
  List<dynamic> _claimHistory = [];
  bool _loadingOffers = true;
  bool _loadingHistory = true;
  final Set<String> _accepting = {};
  String _sortBy = 'endsAt';
  String _order = 'asc';
  String _claimStatus = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchOffers();
    _fetchHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showMsg(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        content: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isError ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle,
                  color: isError ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _countdownLabel(int remainingMs) {
    if (remainingMs <= 0) return 'Ended';
    final mins = (remainingMs / (1000 * 60)).floor();
    final days = mins ~/ (60 * 24);
    final hours = (mins % (60 * 24)) ~/ 60;
    final minutes = mins % 60;
    if (days > 0) return '$days d $hours h left';
    if (hours > 0) return '$hours h $minutes m left';
    return '$minutes m left';
  }

  Color _urgencyColor(int remainingMs) {
    if (remainingMs <= 0) return Colors.grey;
    final hours = remainingMs / (1000 * 60 * 60);
    if (hours <= 6) return Colors.red;
    if (hours <= 24) return Colors.orange;
    return Colors.green;
  }

  Future<void> _fetchOffers() async {
    setState(() => _loadingOffers = true);
    final path =
        '/api/offers/available?sortBy=$_sortBy&order=$_order&claimStatus=$_claimStatus';
    final res = await ApiClient.get(path);
    if (!mounted) return;
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _offers = List<dynamic>.from(data['items'] ?? []);
        _loadingOffers = false;
      });
      return;
    }
    setState(() => _loadingOffers = false);
    _showMsg('Failed to fetch offers', isError: true);
  }

  Future<void> _fetchHistory() async {
    setState(() => _loadingHistory = true);
    final res = await ApiClient.get('/api/offers/my-claims?includeRevoked=true');
    if (!mounted) return;
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _claimHistory = List<dynamic>.from(data['items'] ?? []);
        _loadingHistory = false;
      });
      return;
    }
    setState(() => _loadingHistory = false);
    _showMsg('Failed to fetch claim history', isError: true);
  }

  Future<void> _acceptOffer(Map<String, dynamic> offer) async {
    final offerId = offer['_id'].toString();
    final offerVersion = (offer['version'] ?? 1).toString();
    setState(() => _accepting.add(offerId));
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final res = await ApiClient.post(
        '/api/offers/$offerId/accept',
        body: {'idempotencyKey': 'offer-$offerId-v$offerVersion-$now'},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final session = Provider.of<SessionProvider>(context, listen: false);
        if (body['totalCoins'] != null) {
          session.updateUserCoins(body['totalCoins']);
        } else {
          await session.loadFreebieCounts();
        }
        final msg = body['alreadyAccepted'] == true
            ? 'Already accepted for this version.'
            : 'Offer accepted: +${body['coinsAwarded']} LenDen coins';
        _showMsg(msg);
        await _fetchOffers();
        await _fetchHistory();
      } else {
        String msg = 'Failed to accept offer';
        try {
          msg = (jsonDecode(res.body)['error'] ?? msg).toString();
        } catch (_) {}
        _showMsg(msg, isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      _showMsg('Network error. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _accepting.remove(offerId));
    }
  }

  Widget _buildFilterBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DropdownButton<String>(
              value: _claimStatus,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'unclaimed', child: Text('Unclaimed')),
                DropdownMenuItem(value: 'claimed', child: Text('Claimed')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _claimStatus = v);
                _fetchOffers();
              },
            ),
            DropdownButton<String>(
              value: _sortBy,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'endsAt', child: Text('Deadline')),
                DropdownMenuItem(value: 'coins', child: Text('Coins')),
                DropdownMenuItem(value: 'createdAt', child: Text('Newest')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _sortBy = v);
                _fetchOffers();
              },
            ),
            DropdownButton<String>(
              value: _order,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'asc', child: Text('Asc')),
                DropdownMenuItem(value: 'desc', child: Text('Desc')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _order = v);
                _fetchOffers();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTab() {
    if (_loadingOffers) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎁', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const CircularProgressIndicator(color: Color(0xFF00B4D8)),
            const SizedBox(height: 12),
            Text('Loading surprises...',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    if (_offers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎁', style: TextStyle(fontSize: 64)),
            SizedBox(height: 12),
            Text('No offers found.', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchOffers,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.62,
          crossAxisSpacing: 20,
          mainAxisSpacing: 28,
        ),
        itemCount: _offers.length,
        itemBuilder: (context, index) {
          final offer = _offers[index] as Map<String, dynamic>;
          return _GiftBoxCard(
            offer: offer,
            isAccepting: _accepting.contains(offer['_id'].toString()),
            onAccept: _acceptOffer,
            paletteIndex: index,
            countdownLabel:
                _countdownLabel((offer['timeRemainingMs'] ?? 0) as int),
            urgencyColor:
                _urgencyColor((offer['timeRemainingMs'] ?? 0) as int),
          );
        },
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_loadingHistory) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎁', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const CircularProgressIndicator(color: Color(0xFF7C3AED)),
            const SizedBox(height: 12),
            Text('Loading history...', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }
    if (_claimHistory.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('📭', style: TextStyle(fontSize: 64)),
            SizedBox(height: 12),
            Text('No claimed offers yet.', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchHistory,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.62,
          crossAxisSpacing: 20,
          mainAxisSpacing: 28,
        ),
        itemCount: _claimHistory.length,
        itemBuilder: (context, index) {
          final claim = _claimHistory[index] as Map<String, dynamic>;
          return _ClaimedGiftBoxCard(claim: claim, paletteIndex: index);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _TopWaveClipper(),
              child: Container(
                height: 160,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
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
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            '🎁  Special Offers',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 8),
                    ],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF7C3AED),
                    unselectedLabelColor: Colors.black54,
                    indicatorColor: const Color(0xFF7C3AED),
                    tabs: const [
                      Tab(text: 'Active Offers'),
                      Tab(text: 'Claim History'),
                    ],
                  ),
                ),
                if (_tabController.index == 0) _buildFilterBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildActiveTab(),
                      _buildHistoryTab(),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// 3D Gift Box Card
// ─────────────────────────────────────────────────────────────────────────────

class _GiftBoxCard extends StatefulWidget {
  final Map<String, dynamic> offer;
  final bool isAccepting;
  final void Function(Map<String, dynamic>) onAccept;
  final int paletteIndex;
  final String countdownLabel;
  final Color urgencyColor;

  const _GiftBoxCard({
    required this.offer,
    required this.isAccepting,
    required this.onAccept,
    required this.paletteIndex,
    required this.countdownLabel,
    required this.urgencyColor,
  });

  @override
  State<_GiftBoxCard> createState() => _GiftBoxCardState();
}

class _GiftBoxCardState extends State<_GiftBoxCard>
    with TickerProviderStateMixin {
  late AnimationController _openCtrl;
  late AnimationController _sparkleCtrl;
  late AnimationController _idleCtrl;

  late Animation<double> _lidAngle;
  late Animation<double> _contentFade;
  late Animation<double> _contentSlide;
  late Animation<double> _idleY;

  bool _isOpen = false;

  // Each palette: [front, dark-side, ribbon, shine]
  static const List<List<Color>> _palettes = [
    [Color(0xFFE53935), Color(0xFFB71C1C), Color(0xFFFFD600), Color(0xFFFF8A80)],
    [Color(0xFF8E24AA), Color(0xFF4A148C), Color(0xFFFF80AB), Color(0xFFCE93D8)],
    [Color(0xFF1565C0), Color(0xFF0D47A1), Color(0xFFFFCA28), Color(0xFF82B1FF)],
    [Color(0xFF2E7D32), Color(0xFF1B5E20), Color(0xFFFFEB3B), Color(0xFFA5D6A7)],
    [Color(0xFFE65100), Color(0xFFBF360C), Color(0xFFFFD740), Color(0xFFFFCC80)],
    [Color(0xFF00695C), Color(0xFF004D40), Color(0xFFFF6FD8), Color(0xFF80CBC4)],
  ];

  List<Color> get _p => _palettes[widget.paletteIndex % _palettes.length];
  Color get _front => _p[0];
  Color get _side => _p[1];
  Color get _ribbon => _p[2];
  Color get _shine => _p[3];

  static const List<List<String>> _sparkleSets = [
    ['⭐', '✨', '🌟', '💫', '✨', '⭐', '💥', '🎊'],
    ['💜', '✨', '🌟', '💫', '⭐', '🎉', '💜', '✨'],
    ['💙', '⭐', '✨', '💫', '🌟', '🎊', '💙', '✨'],
    ['💚', '🌟', '✨', '⭐', '💫', '🎉', '💚', '🌿'],
    ['🧡', '✨', '⭐', '💫', '🌟', '🎊', '🧡', '🔥'],
    ['💎', '✨', '🌟', '💫', '⭐', '🎉', '💎', '✨'],
  ];

  List<String> get _sparkles =>
      _sparkleSets[widget.paletteIndex % _sparkleSets.length];

  @override
  void initState() {
    super.initState();

    _openCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _sparkleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _lidAngle = Tween<double>(begin: 0, end: math.pi * 0.9).animate(
      CurvedAnimation(
        parent: _openCtrl,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );
    _contentFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _openCtrl,
        curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
      ),
    );
    _contentSlide = Tween<double>(begin: 18, end: 0).animate(
      CurvedAnimation(
        parent: _openCtrl,
        curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
      ),
    );

    // Idle: subtle hop up and settle, then long pause
    _idleY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -10.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -10.0, end: 0.0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 25,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 57),
    ]).animate(_idleCtrl);

    Future.delayed(
        Duration(milliseconds: 400 + widget.paletteIndex * 350), () {
      if (mounted && !_isOpen) _idleCtrl.repeat();
    });
  }

  @override
  void dispose() {
    _openCtrl.dispose();
    _sparkleCtrl.dispose();
    _idleCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_isOpen) {
      _idleCtrl.stop();
      setState(() => _isOpen = true);
      _openCtrl.forward();
      _sparkleCtrl.forward(from: 0);
    } else {
      setState(() => _isOpen = false);
      _openCtrl.reverse().then((_) {
        if (mounted && !_isOpen) _idleCtrl.repeat();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_openCtrl, _sparkleCtrl, _idleCtrl]),
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(0, _isOpen ? 0 : _idleY.value),
          child: GestureDetector(
            onTap: _toggle,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                _buildBoxStack(),
                ..._buildSparkleWidgets(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBoxStack() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Lid
        _buildLid(),
        // Box body
        Expanded(child: _buildBody()),
        // 3D bottom edge
        _buildBottomEdge(),
      ],
    );
  }

  Widget _buildLid() {
    return Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.005)
        ..rotateX(-_lidAngle.value),
      alignment: Alignment.bottomCenter,
      child: Stack(
        children: [
          // Lid face
          Container(
            height: 58,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_shine, _front],
              ),
              boxShadow: [
                BoxShadow(
                  color: _side.withValues(alpha: 0.55),
                  offset: const Offset(0, 5),
                  blurRadius: 10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              child: Stack(
                children: [
                  // Ribbon on lid
                  Center(
                    child: Container(
                      width: 16,
                      decoration: BoxDecoration(
                        color: _ribbon.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  // Shine stripe
                  Positioned(
                    top: 0,
                    left: 0,
                    bottom: 0,
                    child: Container(
                      width: 22,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.3),
                            Colors.transparent,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                  // Bow
                  Center(child: _buildBow()),
                ],
              ),
            ),
          ),
          // Lid right-side 3D edge
          Positioned(
            right: -10,
            top: 4,
            bottom: 0,
            child: Container(
              width: 10,
              decoration: BoxDecoration(
                color: _side.withValues(alpha: 0.7),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBow() {
    return SizedBox(
      height: 58,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left loop
          Transform.rotate(
            angle: -0.35,
            child: Container(
              width: 24,
              height: 17,
              decoration: BoxDecoration(
                color: _ribbon,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(14),
                ),
                boxShadow: [
                  BoxShadow(
                      color: _side.withValues(alpha: 0.3),
                      blurRadius: 3,
                      offset: const Offset(1, 2)),
                ],
              ),
            ),
          ),
          // Knot
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: _ribbon,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: _side.withValues(alpha: 0.3),
                    blurRadius: 2,
                    offset: const Offset(0, 1)),
              ],
            ),
          ),
          // Right loop
          Transform.rotate(
            angle: 0.35,
            child: Container(
              width: 24,
              height: 17,
              decoration: BoxDecoration(
                color: _ribbon,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomRight: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                      color: _side.withValues(alpha: 0.3),
                      blurRadius: 3,
                      offset: const Offset(-1, 2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final claimed = widget.offer['claimed'] == true;

    return Stack(
      children: [
        // Main body face
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_front, _side],
            ),
          ),
          child: Stack(
            children: [
              // Shine stripe top-left
              Positioned(
                top: 0,
                left: 0,
                bottom: 0,
                child: Container(
                  width: 18,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
              // Ribbon vertical
              Center(
                child: Container(
                  width: 16,
                  decoration: BoxDecoration(
                    color: _ribbon.withValues(alpha: 0.85),
                  ),
                ),
              ),
              // Ribbon horizontal
              Align(
                alignment: const Alignment(0, -0.35),
                child: Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: _ribbon.withValues(alpha: 0.85),
                  ),
                ),
              ),
              // Content or hint
              _isOpen
                  ? FadeTransition(
                      opacity: _contentFade,
                      child: AnimatedBuilder(
                        animation: _contentSlide,
                        builder: (ctx, ch) => Transform.translate(
                          offset: Offset(0, _contentSlide.value),
                          child: ch,
                        ),
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(10, 10, 10, 6),
                          child: _buildOpenContent(claimed),
                        ),
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            color: Colors.white.withValues(alpha: 0.9),
                            size: 30,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap to\nopen!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(
                                    color: _side,
                                    blurRadius: 4,
                                    offset: const Offset(0, 1)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ],
          ),
        ),
        // Right 3D side edge
        Positioned(
          right: -10,
          top: 0,
          bottom: 0,
          child: Container(
            width: 10,
            decoration: BoxDecoration(
              color: _side.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomEdge() {
    return Container(
      height: 10,
      margin: const EdgeInsets.only(right: 0),
      decoration: BoxDecoration(
        color: _side,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
        boxShadow: [
          BoxShadow(
            color: _side.withValues(alpha: 0.6),
            offset: const Offset(0, 6),
            blurRadius: 10,
            spreadRadius: -2,
          ),
        ],
      ),
    );
  }

  Widget _buildOpenContent(bool claimed) {
    final endsAt = DateTime.tryParse('${widget.offer['endsAt']}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Offer name
        Text(
          widget.offer['name']?.toString() ?? 'Offer',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
            height: 1.2,
            shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
        const SizedBox(height: 7),
        // Coins
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: _ribbon.withValues(alpha: 0.6), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🪙', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Text(
                '+${widget.offer['coins']}',
                style: TextStyle(
                  color: _ribbon,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  shadows: [
                    Shadow(color: _side, blurRadius: 3),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        // Countdown
        Row(
          children: [
            Icon(Icons.timer_outlined,
                size: 11,
                color: widget.urgencyColor.withValues(alpha: 0.95)),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                widget.countdownLabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        // Deadline date
        if (endsAt != null) ...[
          const SizedBox(height: 2),
          Text(
            'Until ${endsAt.toLocal().toString().substring(0, 10)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 9,
            ),
          ),
        ],
        if ((widget.offer['description'] ?? '').toString().trim().isNotEmpty)
          ...[
          const SizedBox(height: 4),
          Text(
            widget.offer['description'].toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 10,
            ),
          ),
        ],
        const SizedBox(height: 8),
        // CTA Button
        claimed
            ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                      width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 13, color: Colors.white),
                    SizedBox(width: 4),
                    Text('Claimed!',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            : SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.isAccepting
                      ? null
                      : () => widget.onAccept(widget.offer),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _front,
                    elevation: 3,
                    shadowColor: _side.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: widget.isAccepting
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _front),
                        )
                      : Text(
                          '🎉 Claim!',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: _front,
                          ),
                        ),
                ),
              ),
      ],
    );
  }

  List<Widget> _buildSparkleWidgets() {
    if (_sparkleCtrl.value <= 0 || _sparkleCtrl.value >= 1) return [];

    final t = _sparkleCtrl.value;
    final positions = [
      const Offset(-70, -55),
      const Offset(70, -55),
      const Offset(-50, -80),
      const Offset(50, -80),
      const Offset(-85, -15),
      const Offset(85, -15),
      const Offset(-30, -95),
      const Offset(30, -95),
    ];

    return List.generate(
      math.min(positions.length, _sparkles.length),
      (i) {
        final dx = positions[i].dx * t;
        final dy = positions[i].dy * t;
        final opacity = t < 0.6 ? (t / 0.6) : (1.0 - t) / 0.4;
        final scale = t < 0.4 ? (t / 0.4) : 1.0;

        return Positioned(
          top: 30,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Transform.translate(
              offset: Offset(dx, dy),
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: scale,
                  child: Center(
                    child: Text(
                      _sparkles[i],
                      style: TextStyle(
                        fontSize: i.isEven ? 18 : 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Claimed / History Gift Box Card — already open, no tap needed
// ─────────────────────────────────────────────────────────────────────────────

class _ClaimedGiftBoxCard extends StatelessWidget {
  final Map<String, dynamic> claim;
  final int paletteIndex;

  const _ClaimedGiftBoxCard({required this.claim, required this.paletteIndex});

  static const List<List<Color>> _palettes = [
    [Color(0xFFE53935), Color(0xFFB71C1C), Color(0xFFFFD600), Color(0xFFFF8A80)],
    [Color(0xFF8E24AA), Color(0xFF4A148C), Color(0xFFFF80AB), Color(0xFFCE93D8)],
    [Color(0xFF1565C0), Color(0xFF0D47A1), Color(0xFFFFCA28), Color(0xFF82B1FF)],
    [Color(0xFF2E7D32), Color(0xFF1B5E20), Color(0xFFFFEB3B), Color(0xFFA5D6A7)],
    [Color(0xFFE65100), Color(0xFFBF360C), Color(0xFFFFD740), Color(0xFFFFCC80)],
    [Color(0xFF00695C), Color(0xFF004D40), Color(0xFFFF6FD8), Color(0xFF80CBC4)],
  ];

  // Revoked boxes use a muted grey palette
  static const List<Color> _revokedPalette = [
    Color(0xFF757575), Color(0xFF424242), Color(0xFFBDBDBD), Color(0xFFE0E0E0),
  ];

  List<Color> get _p {
    if (claim['revoked'] == true) return _revokedPalette;
    return _palettes[paletteIndex % _palettes.length];
  }

  Color get _front => _p[0];
  Color get _side => _p[1];
  Color get _ribbon => _p[2];
  Color get _shine => _p[3];

  @override
  Widget build(BuildContext context) {
    final offer = (claim['offer'] ?? {}) as Map<String, dynamic>;
    final revoked = claim['revoked'] == true;
    final claimedAt = DateTime.tryParse('${claim['claimedAt']}');

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildOpenLid(),
            Expanded(child: _buildBody(offer, revoked, claimedAt)),
            _buildBottomEdge(),
          ],
        ),
      ],
    );
  }

  // Lid shown rotated back (already open position)
  Widget _buildOpenLid() {
    return Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.005)
        ..rotateX(-math.pi * 0.88),
      alignment: Alignment.bottomCenter,
      child: Stack(
        children: [
          Container(
            height: 58,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_shine, _front],
              ),
              boxShadow: [
                BoxShadow(
                  color: _side.withValues(alpha: 0.4),
                  offset: const Offset(0, 3),
                  blurRadius: 6,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: 16,
                      decoration:
                          BoxDecoration(color: _ribbon.withValues(alpha: 0.9)),
                    ),
                  ),
                  Positioned(
                    top: 0, left: 0, bottom: 0,
                    child: Container(
                      width: 22,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.3),
                            Colors.transparent,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                  Center(child: _buildBow()),
                ],
              ),
            ),
          ),
          Positioned(
            right: -10, top: 4, bottom: 0,
            child: Container(
              width: 10,
              decoration: BoxDecoration(
                color: _side.withValues(alpha: 0.7),
                borderRadius: const BorderRadius.only(topRight: Radius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBow() {
    return SizedBox(
      height: 58,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: -0.35,
            child: Container(
              width: 24, height: 17,
              decoration: BoxDecoration(
                color: _ribbon,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14), bottomLeft: Radius.circular(4),
                  topRight: Radius.circular(4), bottomRight: Radius.circular(14),
                ),
              ),
            ),
          ),
          Container(
            width: 11, height: 11,
            decoration: BoxDecoration(color: _ribbon, shape: BoxShape.circle),
          ),
          Transform.rotate(
            angle: 0.35,
            child: Container(
              width: 24, height: 17,
              decoration: BoxDecoration(
                color: _ribbon,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4), bottomLeft: Radius.circular(14),
                  topRight: Radius.circular(14), bottomRight: Radius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
      Map<String, dynamic> offer, bool revoked, DateTime? claimedAt) {
    return Stack(
      children: [
        // Main face
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_front, _side],
            ),
          ),
          child: Stack(
            children: [
              // Shine stripe
              Positioned(
                top: 0, left: 0, bottom: 0,
                child: Container(
                  width: 18,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
              // Ribbon vertical
              Center(
                child: Container(
                  width: 16,
                  decoration: BoxDecoration(
                      color: _ribbon.withValues(alpha: 0.85)),
                ),
              ),
              // Ribbon horizontal
              Align(
                alignment: const Alignment(0, -0.35),
                child: Container(
                  height: 16,
                  decoration: BoxDecoration(
                      color: _ribbon.withValues(alpha: 0.85)),
                ),
              ),
              // Content always visible
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: _buildContent(offer, revoked, claimedAt),
              ),
            ],
          ),
        ),
        // Right 3D edge
        Positioned(
          right: -10, top: 0, bottom: 0,
          child: Container(
            width: 10,
            decoration: BoxDecoration(color: _side.withValues(alpha: 0.85)),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomEdge() {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: _side,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
        boxShadow: [
          BoxShadow(
            color: _side.withValues(alpha: 0.6),
            offset: const Offset(0, 6),
            blurRadius: 10,
            spreadRadius: -2,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
      Map<String, dynamic> offer, bool revoked, DateTime? claimedAt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: revoked
                ? Colors.red.withValues(alpha: 0.85)
                : Colors.green.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                revoked ? Icons.cancel_rounded : Icons.check_circle_rounded,
                size: 11,
                color: Colors.white,
              ),
              const SizedBox(width: 3),
              Text(
                revoked ? 'Revoked' : 'Claimed ✓',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Offer name
        Text(
          (offer['name'] ?? 'Offer').toString(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
            height: 1.2,
            shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
          ),
        ),
        const SizedBox(height: 6),
        // Coins awarded
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _ribbon.withValues(alpha: 0.6), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🪙', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                '+${claim['coinsAwarded'] ?? 0}',
                style: TextStyle(
                  color: _ribbon,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  shadows: [Shadow(color: _side, blurRadius: 3)],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        // Claimed date
        Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 11, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                claimedAt != null
                    ? claimedAt.toLocal().toString().substring(0, 10)
                    : '-',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        // Version
        const SizedBox(height: 2),
        Text(
          'v${claim['offerVersion'] ?? '-'}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 9,
          ),
        ),
        // Revoke reason
        if (revoked) ...[
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Colors.red.withValues(alpha: 0.4), width: 1),
            ),
            child: Text(
              claim['revokedReason']?.toString() ?? 'Offer updated',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 9,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.25, size.height * 0.5,
      size.width * 0.5, size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.75, size.height * 0.3,
      size.width, size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
