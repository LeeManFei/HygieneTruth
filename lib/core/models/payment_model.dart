class PaymentModel {
  final String id;
  final String restaurantId;
  final String restaurantName;
  final String? ownerId;
  final double amount;
  final String currency;
  final String paymentMethod;
  final String paymentReference;
  final String status;
  final String? statutoryCitation;
  final String? invoiceUrl;
  final String? receiptUrl;
  final String? receiptNumber;
  final String? stripeChargeId;
  final String? stripeCustomerId;
  final String paidAt;
  final String createdAt;
  final Map<String, dynamic> metadata;

  const PaymentModel({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    this.ownerId,
    required this.amount,
    this.currency = 'MYR',
    required this.paymentMethod,
    required this.paymentReference,
    this.status = 'succeeded',
    this.statutoryCitation,
    this.invoiceUrl,
    this.receiptUrl,
    this.receiptNumber,
    this.stripeChargeId,
    this.stripeCustomerId,
    required this.paidAt,
    required this.createdAt,
    this.metadata = const {},
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id']?.toString() ?? '',
      restaurantId: json['restaurant_id']?.toString() ?? '',
      restaurantName: json['restaurant_name']?.toString() ?? '',
      ownerId: json['owner_id']?.toString(),
      amount: (json['amount'] is num) ? (json['amount'] as num).toDouble() : double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      currency: json['currency']?.toString() ?? 'MYR',
      paymentMethod: json['payment_method']?.toString() ?? 'FPX Online Banking',
      paymentReference: json['payment_reference']?.toString() ?? '',
      status: json['status']?.toString() ?? 'succeeded',
      statutoryCitation: json['statutory_citation']?.toString(),
      invoiceUrl: json['invoice_url']?.toString(),
      receiptUrl: json['receipt_url']?.toString(),
      receiptNumber: json['receipt_number']?.toString(),
      stripeChargeId: json['stripe_charge_id']?.toString(),
      stripeCustomerId: json['stripe_customer_id']?.toString(),
      paidAt: json['paid_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      createdAt: json['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      metadata: (json['metadata'] is Map) ? Map<String, dynamic>.from(json['metadata'] as Map) : {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'restaurant_id': restaurantId,
      'restaurant_name': restaurantName,
      'owner_id': ownerId,
      'amount': amount,
      'currency': currency,
      'payment_method': paymentMethod,
      'payment_reference': paymentReference,
      'status': status,
      'statutory_citation': statutoryCitation,
      'invoice_url': invoiceUrl,
      'receipt_url': receiptUrl,
      'receipt_number': receiptNumber,
      'stripe_charge_id': stripeChargeId,
      'stripe_customer_id': stripeCustomerId,
      'paid_at': paidAt,
      'created_at': createdAt,
      'metadata': metadata,
    };
  }

  PaymentModel copyWith({
    String? id,
    String? restaurantId,
    String? restaurantName,
    String? ownerId,
    double? amount,
    String? currency,
    String? paymentMethod,
    String? paymentReference,
    String? status,
    String? statutoryCitation,
    String? invoiceUrl,
    String? receiptUrl,
    String? receiptNumber,
    String? stripeChargeId,
    String? stripeCustomerId,
    String? paidAt,
    String? createdAt,
    Map<String, dynamic>? metadata,
  }) {
    return PaymentModel(
      id: id ?? this.id,
      restaurantId: restaurantId ?? this.restaurantId,
      restaurantName: restaurantName ?? this.restaurantName,
      ownerId: ownerId ?? this.ownerId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentReference: paymentReference ?? this.paymentReference,
      status: status ?? this.status,
      statutoryCitation: statutoryCitation ?? this.statutoryCitation,
      invoiceUrl: invoiceUrl ?? this.invoiceUrl,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      stripeChargeId: stripeChargeId ?? this.stripeChargeId,
      stripeCustomerId: stripeCustomerId ?? this.stripeCustomerId,
      paidAt: paidAt ?? this.paidAt,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }
}
