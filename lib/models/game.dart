import 'board.dart';
import 'dice_roll.dart';
import 'game_transaction.dart';
import 'player.dart';
import 'property_ownership.dart';

/// The shared, wire-format part of a game: what every device agrees on.
/// The board definition travels inside it, so joining players never need to
/// own the board beforehand.
class Game {
  const Game({
    required this.id,
    required this.name,
    required this.board,
    required this.hostId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final Board board;
  final String hostId;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'board': board.toJson(),
        'hostId': hostId,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Game.fromJson(Map<String, dynamic> json) => Game(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Game',
        board: Board.fromJson(json['board'] as Map<String, dynamic>),
        hostId: json['hostId'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['createdAt'] as int? ?? 0,
        ),
      );
}

enum GameRole {
  host,
  client;

  static GameRole fromName(String name) =>
      name == 'host' ? GameRole.host : GameRole.client;
}

/// Device-local metadata about a game this device belongs to. Never sent
/// over the wire — it records *my* relationship to the game so the home
/// screen can list it and the app can resume it later.
class GameRecord {
  const GameRecord({
    required this.game,
    required this.role,
    required this.myPlayerId,
    required this.lastPlayedAt,
    this.hostAddress,
    this.hostPort,
  });

  final Game game;
  final GameRole role;
  final String myPlayerId;
  final DateTime lastPlayedAt;

  /// Where the host was last seen. Only meaningful for [GameRole.client].
  final String? hostAddress;
  final int? hostPort;

  GameRecord copyWith({
    Game? game,
    DateTime? lastPlayedAt,
    String? hostAddress,
    int? hostPort,
  }) =>
      GameRecord(
        game: game ?? this.game,
        role: role,
        myPlayerId: myPlayerId,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        hostAddress: hostAddress ?? this.hostAddress,
        hostPort: hostPort ?? this.hostPort,
      );
}

/// Full authoritative state of a game, sent by the server whenever a client
/// (re)connects. Clients replace their local copy wholesale.
class GameSnapshot {
  const GameSnapshot({
    required this.game,
    required this.players,
    required this.transactions,
    this.ownerships = const [],
    this.currentTurnId,
    this.lastRoll,
    this.turnRolled = false,
  });

  final Game game;
  final List<Player> players;
  final List<GameTransaction> transactions;
  final List<PropertyOwnership> ownerships;
  final String? currentTurnId;

  /// The most recent dice roll, so late joiners see the table state.
  final DiceRoll? lastRoll;

  /// Whether the current player has already rolled this turn.
  final bool turnRolled;

  Map<String, dynamic> toJson() => {
        'game': game.toJson(),
        'players': players.map((p) => p.toJson()).toList(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'ownerships': ownerships.map((o) => o.toJson()).toList(),
        if (currentTurnId != null) 'currentTurnId': currentTurnId,
        if (lastRoll != null) 'lastRoll': lastRoll!.toJson(),
        'turnRolled': turnRolled,
      };

  factory GameSnapshot.fromJson(Map<String, dynamic> json) => GameSnapshot(
        game: Game.fromJson(json['game'] as Map<String, dynamic>),
        players: (json['players'] as List<dynamic>? ?? const [])
            .map((e) => Player.fromJson(e as Map<String, dynamic>))
            .toList(),
        transactions: (json['transactions'] as List<dynamic>? ?? const [])
            .map((e) => GameTransaction.fromJson(e as Map<String, dynamic>))
            .toList(),
        ownerships: (json['ownerships'] as List<dynamic>? ?? const [])
            .map((e) => PropertyOwnership.fromJson(e as Map<String, dynamic>))
            .toList(),
        currentTurnId: json['currentTurnId'] as String?,
        lastRoll: json['lastRoll'] == null
            ? null
            : DiceRoll.fromJson(json['lastRoll'] as Map<String, dynamic>),
        turnRolled: json['turnRolled'] as bool? ?? false,
      );
}
