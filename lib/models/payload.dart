import 'dart:convert';

import 'package:digipoly/enums/payload_type.dart';

class Payload {
  // enum
  final Payloadtype type;
  final dynamic data;

  Payload({
    required this.type,
    required this.data,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.index,
      'data': data,
    };
  }

  factory Payload.fromMap(Map<String, dynamic> map) {
    return Payload(
      type: Payloadtype.values[map['type'] ?? 0],
      data: map['data'],
    );
  }

  String toJson() => json.encode(toMap());

  factory Payload.fromJson(String source) =>
      Payload.fromMap(json.decode(source));

  @override
  String toString() => 'Payload(type: $type, data: $data)';
}
