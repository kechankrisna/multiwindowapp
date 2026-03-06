/// Sealed state class representing what the secondary/sub display should show.
/// Serialises to/from JSON for transport over MethodChannel.
sealed class SubDisplayState {
  const SubDisplayState();

  Map<String, dynamic> toJson();

  factory SubDisplayState.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'order_summary' => OrderSummaryState.fromJson(json),
      'payment_prompt' => PaymentPromptState.fromJson(json),
      _ => const IdleState(),
    };
  }
}

/// Sub-display shows a welcome/idle screen. No data required.
final class IdleState extends SubDisplayState {
  const IdleState();

  @override
  Map<String, dynamic> toJson() => {'type': 'idle'};
}

/// Sub-display shows an order summary with a running item list and total.
final class OrderSummaryState extends SubDisplayState {
  const OrderSummaryState({required this.items, required this.total});

  /// Each item: `{'name': String, 'qty': int, 'price': double}`
  final List<Map<String, dynamic>> items;
  final double total;

  factory OrderSummaryState.fromJson(Map<String, dynamic> json) =>
      OrderSummaryState(
        items: List<Map<String, dynamic>>.from(
          (json['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map)),
        ),
        total: (json['total'] as num).toDouble(),
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'order_summary',
        'items': items,
        'total': total,
      };
}

/// Sub-display shows the final amount due and a payment prompt.
final class PaymentPromptState extends SubDisplayState {
  const PaymentPromptState({required this.total});

  final double total;

  factory PaymentPromptState.fromJson(Map<String, dynamic> json) =>
      PaymentPromptState(total: (json['total'] as num).toDouble());

  @override
  Map<String, dynamic> toJson() => {'type': 'payment_prompt', 'total': total};
}
