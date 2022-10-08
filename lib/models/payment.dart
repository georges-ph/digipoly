import 'dart:convert';

class Payment {
  final int fromPort;
  final int toPort;
  final num amount;

  Payment({
    required this.fromPort,
    required this.toPort,
    required this.amount,
  });

  Map<String, dynamic> toMap() {
    return {
      'fromPort': fromPort,
      'toPort': toPort,
      'amount': amount,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      fromPort: map['fromPort']?.toInt() ?? 0,
      toPort: map['toPort']?.toInt() ?? 0,
      amount: map['amount'] ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory Payment.fromJson(String source) =>
      Payment.fromMap(json.decode(source));

  @override
  String toString() =>
      'Payment(fromPort: $fromPort, toPort: $toPort, amount: $amount)';
}
