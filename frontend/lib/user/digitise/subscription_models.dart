class SubscriptionPlan {
  final String id;
  final String name;
  final double price;
  final int duration;
  final List<String> features;
  final bool isAvailable;
  final int discount;
  final int free;
  final List<String> allowedFeatures;

  SubscriptionPlan(
      {required this.id,
      required this.name,
      required this.price,
      required this.duration,
      required this.features,
      required this.isAvailable,
      required this.discount,
      required this.free,
      this.allowedFeatures = const []});

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['_id'],
      name: json['name'],
      price: json['price'].toDouble(),
      duration: json['duration'],
      features: List<String>.from(json['features']),
      isAvailable: json['isAvailable'],
      discount: json['discount'] ?? 0,
      free: json['free'] ?? 0,
      allowedFeatures: List<String>.from(json['allowedFeatures'] ?? []),
    );
  }
}

class PremiumBenefit {
  final String id;
  final String text;

  PremiumBenefit({required this.id, required this.text});

  factory PremiumBenefit.fromJson(Map<String, dynamic> json) {
    return PremiumBenefit(
      id: json['_id'],
      text: json['text'],
    );
  }
}

class Faq {
  final String id;
  final String question;
  final String answer;

  Faq({required this.id, required this.question, required this.answer});

  factory Faq.fromJson(Map<String, dynamic> json) {
    return Faq(
      id: json['_id'],
      question: json['question'],
      answer: json['answer'],
    );
  }
}
