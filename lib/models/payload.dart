// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import '../enums/payload_type.dart';

class Payload {
  final int? port;
  // enum
  final PayloadType type;
  final dynamic data;
  
  Payload({
     this.port,
    required this.type,
    required this.data,
  });



  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'port': port,
      'type': type.index,
      'data': data,
    };
  }

  factory Payload.fromMap(Map<String, dynamic> map) {
    return Payload(
      port: map['port'] != null ? map['port'] as int : null,
      type: PayloadType.values[map['type'] as int],
      data: map['data'] as dynamic,
    );
  }

  String toJson() => json.encode(toMap());

  factory Payload.fromJson(String source) => Payload.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'Payload(port: $port, type: $type, data: $data)';
}
