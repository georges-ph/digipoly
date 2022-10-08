import 'dart:convert';

class Payment {
  final int toPort;
  final num amount;

  Payment({
    required this.toPort,
    required this.amount,
  });

  Map<String, dynamic> toMap() {
    return {
      'toPort': toPort,
      'amount': amount,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      toPort: map['toPort']?.toInt() ?? 0,
      amount: map['amount'] ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory Payment.fromJson(String source) =>
      Payment.fromMap(json.decode(source));

  @override
  String toString() => 'Payment(toPort: $toPort, amount: $amount)';
}
