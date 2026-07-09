class MembershipPlanModel {
  final String? id;
  final String category;
  final String name;
  final String subtitle;
  final double price;
  final String? priceLabel;
  final int credits;
  final int validityDays;
  final String? badge;
  final List<String> features;
  final int order;
  final bool isActive;

  const MembershipPlanModel({
    this.id,
    required this.category,
    required this.name,
    required this.subtitle,
    required this.price,
    this.priceLabel,
    required this.credits,
    required this.validityDays,
    this.badge,
    this.features = const [],
    this.order = 0,
    this.isActive = true,
  });

  factory MembershipPlanModel.fromFirestore(String id, Map<String, dynamic> data) {
    return MembershipPlanModel(
      id: id,
      category: data['category'] ?? '',
      name: data['name'] ?? '',
      subtitle: data['subtitle'] ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      priceLabel: data['priceLabel'],
      credits: (data['credits'] as num?)?.toInt() ?? 0,
      validityDays: (data['validityDays'] as num?)?.toInt() ?? 0,
      badge: data['badge'],
      features: List<String>.from(data['features'] ?? []),
      order: (data['order'] as num?)?.toInt() ?? 0,
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'category': category,
        'name': name,
        'subtitle': subtitle,
        'price': price,
        if (priceLabel != null) 'priceLabel': priceLabel,
        'credits': credits,
        'validityDays': validityDays,
        if (badge != null) 'badge': badge,
        'features': features,
        'order': order,
        'isActive': isActive,
      };
}
