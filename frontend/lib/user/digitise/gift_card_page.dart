import 'package:flutter/material.dart';
import '../../utils/api_client.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import 'dart:convert';

class GiftCardPage extends StatefulWidget {
  const GiftCardPage({Key? key}) : super(key: key);

  @override
  State<GiftCardPage> createState() => _GiftCardPageState();
}

class _GiftCardPageState extends State<GiftCardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> unscrachedCards = [];
  List<Map<String, dynamic>> scratchedCards = [];
  bool isLoading = true;
  bool isScratching = false;
  int unscrachedCount = 0;
  int scratchedCount = 0;

  // Color palette for gift cards
  static const List<List<Color>> cardGradients = [
    [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Indigo to Purple
    [Color(0xFF3B82F6), Color(0xFF06B6D4)], // Blue to Cyan
    [Color(0xFF10B981), Color(0xFF06B6D4)], // Green to Cyan
    [Color(0xFFF59E0B), Color(0xFFF97316)], // Amber to Orange
    [Color(0xFFEC4899), Color(0xFFF43F5E)], // Pink to Rose
    [Color(0xFF8B5CF6), Color(0xFFD946EF)], // Purple to Fuchsia
  ];

  LinearGradient _getCardGradient(int index) {
    final colors = cardGradients[index % cardGradients.length];
    return LinearGradient(
      colors: colors,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchGiftCards();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchGiftCards() async {
    if (mounted) {
      setState(() {
        isLoading = true;
      });
    }
    try {
      List<Map<String, dynamic>> nextUnscratched = [];
      List<Map<String, dynamic>> nextScratched = [];
      int nextUnscratchedCount = 0;
      int nextScratchedCount = 0;

      final unscrachedResponse = await ApiClient.get(
        '/api/gift-cards/unscratched',
      );

      final scratchedResponse = await ApiClient.get(
        '/api/gift-cards/scratched',
      );

      final countsResponse = await ApiClient.get(
        '/api/gift-cards/counts',
      );

      if (unscrachedResponse.statusCode == 200) {
        final unscrachedData = jsonDecode(unscrachedResponse.body);
        nextUnscratched =
            List<Map<String, dynamic>>.from(unscrachedData['cards'] ?? []);
      }
      if (scratchedResponse.statusCode == 200) {
        final scratchedData = jsonDecode(scratchedResponse.body);
        nextScratched =
            List<Map<String, dynamic>>.from(scratchedData['cards'] ?? []);
      }
      if (countsResponse.statusCode == 200) {
        final countsData = jsonDecode(countsResponse.body);
        nextUnscratchedCount = countsData['unscratched'] ?? 0;
        nextScratchedCount = countsData['scratched'] ?? 0;
      }

      if (mounted) {
        setState(() {
          unscrachedCards = nextUnscratched;
          scratchedCards = nextScratched;
          unscrachedCount = nextUnscratchedCount;
          scratchedCount = nextScratchedCount;
        });
      }
    } catch (e) {
      print('Error fetching gift cards: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _scratchCard(
      String cardId, int index, bool isUnscratched) async {
    try {
      setState(() {
        isScratching = true;
      });

      final response = await ApiClient.post(
        '/api/gift-cards/$cardId/scratch',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coinsAdded = data['coinsAdded'] ?? 0;
        final totalCoins = data['totalCoins'] ?? 0;

        // Update session with new coin count
        final session = Provider.of<SessionProvider>(context, listen: false);
        session.updateUserCoins(totalCoins);

        // Show success dialog with tricolor border and coins
        await showDialog(
          context: context,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.orange, width: 4),
                    bottom: BorderSide(color: Colors.green, width: 4),
                    left: BorderSide(color: Colors.orange, width: 2),
                    right: BorderSide(color: Colors.green, width: 2),
                  ),
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.withValues(alpha: 0.1),
                      Colors.green.withValues(alpha: 0.1)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Card Scratched! 🎉',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Icon(Icons.card_giftcard,
                          size: 60, color: Colors.amber),
                      const SizedBox(height: 20),
                      Text(
                        '+$coinsAdded LenDen Coins',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Total Coins: $totalCoins',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.grey[200],
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                            child: const Text(
                              'Close',
                              style: TextStyle(color: Colors.black87),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                            child: const Text('View Cards'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // Refresh gift cards after dialog is closed
        _fetchGiftCards();
      }
    } catch (e) {
      print('Error scratching card: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      setState(() {
        isScratching = false;
      });
    }
  }

  Widget _buildCardUI(
      Map<String, dynamic> card, bool isUnscratched, int index) {
    final giftCard = card['giftCard'] as Map<String, dynamic>? ?? {};
    final coins = card['coins'] ?? 0;
    final name = giftCard['name'] ?? 'Gift Card';
    final cardId = card['_id'] ?? '';

    return GestureDetector(
      onTap: isUnscratched ? () => _scratchCard(cardId, index, true) : null,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Container(
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: _getCardGradient(index),
          ),
          child: Stack(
            children: [
              // Center content
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isUnscratched)
                      Icon(
                        Icons.touch_app,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.8),
                      )
                    else
                      const Icon(
                        Icons.check_circle,
                        size: 48,
                        color: Colors.greenAccent,
                      ),
                    const SizedBox(height: 16),
                    Text(
                      isUnscratched ? 'Tap to Scratch' : 'Scratched',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Only show coins in scratched tab
                    if (!isUnscratched)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$coins Coins',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '?',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                            'Gift Cards',
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
                Transform.translate(
                  offset: const Offset(0, 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          labelColor: Colors.black,
                          indicatorColor: Colors.teal,
                          tabs: [
                            Tab(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.card_giftcard),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Unscratched ($unscrachedCount)',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Tab(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.done_all),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Scratched ($scratchedCount)',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            // Unscratched Cards Tab
                            unscrachedCards.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.card_giftcard,
                                          size: 80,
                                          color: Colors.grey[300],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No unscratched cards yet',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Create transactions to earn cards!',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : GridView.builder(
                                    padding: const EdgeInsets.all(16),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      childAspectRatio: 0.65,
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                    ),
                                    itemCount: unscrachedCards.length,
                                    itemBuilder: (context, index) =>
                                        _buildCardUI(
                                            unscrachedCards[index],
                                            true,
                                            index),
                                  ),
                            // Scratched Cards Tab
                            scratchedCards.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.done_all,
                                          size: 80,
                                          color: Colors.grey[300],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'No scratched cards yet',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : GridView.builder(
                                    padding: const EdgeInsets.all(16),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      childAspectRatio: 0.65,
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                    ),
                                    itemCount: scratchedCards.length,
                                    itemBuilder: (context, index) =>
                                        _buildCardUI(
                                            scratchedCards[index],
                                            false,
                                            index),
                                  ),
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
