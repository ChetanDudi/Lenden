import 'package:flutter/material.dart';
import '../user/digitise/subscriptions_page.dart';

void showSubscriptionPrompt(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return const SubscriptionPrompt(
        title: 'Go Premium!',
        subtitle:
            'You have reached your limit. Subscribe to enjoy unlimited access to all features.',
        showUseCoins: false,
      );
    },
  );
}

class SubscriptionPrompt extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showUseCoins;

  const SubscriptionPrompt({
    Key? key,
    required this.title,
    required this.subtitle,
    this.showUseCoins = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      contentPadding: EdgeInsets.zero,
      content: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFCE4EC),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: Color(0xFF00B4D8),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    child: const Text('Subscribe'),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SubscriptionsPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B4D8),
                    ),
                  ),
                  if (showUseCoins) ...[
                    const SizedBox(height: 8),
                    ElevatedButton(
                      child: const Text('Use Coins'),
                      onPressed: () {
                        Navigator.of(context).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
