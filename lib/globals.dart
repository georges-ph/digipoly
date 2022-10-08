import 'package:digipoly/enums/socket_type.dart';
import 'package:digipoly/models/players.dart';
import 'package:digipoly/services/client.dart';
import 'package:digipoly/services/server.dart';

late Server server;
late Client client;
SocketType socketType = SocketType.none;
Players players = Players(players: []);
num startingAmount = 0;