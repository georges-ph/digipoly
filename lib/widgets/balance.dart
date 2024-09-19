// ignore_for_file: public_member_api_docs, sort_constructors_first, prefer_const_constructors, prefer_const_literals_to_create_immutables, avoid_print, unused_field, use_super_parameters, unused_import
import 'package:client_server_sockets/client_server_sockets.dart';
import 'package:flutter/material.dart';

import '../enums/socket_type.dart';
import '../models/player.dart';

class Balance extends StatelessWidget {
  const Balance({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text("Balance"),
    );
  }
}
