import 'package:client_server_sockets/client_server_sockets.dart';
import 'package:digipoly/enums/socket_type.dart';
import 'package:digipoly/models/players.dart';

late Server server;
late Client client;
SocketType socketType = SocketType.none;
Players players = Players(players: []);
num startingAmount = 0;
