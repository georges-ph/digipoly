import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/board.dart';
import '../models/dice_roll.dart';
import '../models/game.dart';
import '../models/game_transaction.dart';
import '../models/money_request.dart';
import '../models/player.dart';
import '../models/property.dart';
import '../models/property_ownership.dart';
import '../models/result.dart';
import '../models/ws_message.dart';
import '../services/database_service.dart';
import '../services/discovery_service.dart';
import '../services/game_client.dart';
import '../services/game_server.dart';
import '../services/identity_service.dart';

typedef CardDrawEvent = ({String playerId, String deck, BoardCard card});

/// The active game session on this device.
///
/// Whether hosting or joining, the device always participates through a
/// [GameClient]; hosting just means a [GameServer] is also running locally
/// and the client points at 127.0.0.1. All state mutations happen in
/// response to server events — never locally first.
class GameProvider extends ChangeNotifier {
  GameProvider({
    required DatabaseService database,
    required IdentityService identity,
    required DiscoveryService discovery,
  })  : _db = database,
        _identity = identity,
        _discovery = discovery;

  final DatabaseService _db;
  final IdentityService _identity;
  final DiscoveryService _discovery;

  GameServer? _server;
  GameClient? _client;
  StreamSubscription<WsMessage>? _messageSub;
  StreamSubscription<ClientStatus>? _statusSub;

  GameRecord? _record;
  List<Player> _players = [];
  List<GameTransaction> _transactions = [];
  final Map<String, PropertyOwnership> _ownerships = {};
  String? _currentTurnId;
  DiceRoll? _lastRoll;
  bool _turnRolled = false;
  MoneyRequest? _incomingRequest;
  ClientStatus _connection = ClientStatus.disconnected;
  bool _hostEnded = false;
  bool _closing = false;
  Timer? _reconnectTimer;

  Completer<Result<void>>? _pendingJoin;
  Completer<Result<void>>? _pendingRoll;
  final Map<String, Completer<Result<void>>> _pendingPayments = {};
  final Map<String, Completer<Result<void>>> _pendingRequests = {};

  /// Where a fresh join is headed, so the record can be built once the
  /// server accepts us and sends the game.
  ({String host, int port})? _joinTarget;

  final _errors = StreamController<String>.broadcast();
  final _cardDraws = StreamController<CardDrawEvent>.broadcast();
  String? _outgoingRequestId;

  // ------------------------------------------------------------- Getters

  /// Transient error messages for snackbars (rejected payments, etc.).
  Stream<String> get errors => _errors.stream;

  /// Cards drawn at the table — every device shows them.
  Stream<CardDrawEvent> get cardDraws => _cardDraws.stream;

  bool get hasActiveSession => _record != null && _client != null;
  GameRecord? get record => _record;
  Game? get game => _record?.game;
  ClientStatus get connection => _connection;
  bool get hostEnded => _hostEnded;
  bool get isHost => _record?.role == GameRole.host;
  String get myPlayerId => _identity.playerId;

  Player? get me {
    for (final player in _players) {
      if (player.id == myPlayerId) return player;
    }
    return null;
  }

  int get myBalance => me?.balance ?? 0;

  /// Me first, then online players, then the rest; left players last.
  List<Player> get players {
    final sorted = List.of(_players);
    int rank(Player p) {
      if (p.id == myPlayerId) return 0;
      if (p.hasLeft) return 3;
      return p.isOnline ? 1 : 2;
    }

    sorted.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.name.compareTo(b.name);
    });
    return sorted;
  }

  /// Valid payment recipients: everyone still in the game except me.
  List<Player> get otherActivePlayers => players
      .where((p) => p.id != myPlayerId && !p.hasLeft)
      .toList();

  /// Newest first, for activity feeds.
  List<GameTransaction> get transactions => _transactions.reversed.toList();

  Map<String, PropertyOwnership> get ownerships =>
      Map.unmodifiable(_ownerships);

  PropertyOwnership? ownershipOf(String propertyId) =>
      _ownerships[propertyId];

  Property? propertyById(String propertyId) {
    final board = game?.board;
    if (board == null) return null;
    for (final property in board.properties) {
      if (property.id == propertyId) return property;
    }
    return null;
  }

  String propertyNameOf(String propertyId) =>
      propertyById(propertyId)?.name ?? 'a property';

  /// Properties owned by [playerId], in board order.
  List<Property> propertiesOwnedBy(String playerId) {
    final board = game?.board;
    if (board == null) return const [];
    return board.properties
        .where((p) => _ownerships[p.id]?.ownerId == playerId)
        .toList();
  }

  String? get currentTurnId => _currentTurnId;
  bool get isMyTurn => _currentTurnId == myPlayerId;
  Player? get currentTurnPlayer =>
      _currentTurnId == null ? null : playerById(_currentTurnId!);

  /// The most recent dice roll anyone made.
  DiceRoll? get lastRoll => _lastRoll;

  /// Whether the current player already rolled this turn. A turn is
  /// roll → act → end; End turn stays locked until the dice are thrown.
  bool get turnRolled => _turnRolled;
  bool get canRoll =>
      isMyTurn && !_turnRolled && _connection == ClientStatus.connected;
  bool get canEndTurn =>
      isMyTurn && _turnRolled && _connection == ClientStatus.connected;

  /// Housekeeping — building/selling houses — happens on your own turn,
  /// *before* you roll. Money moves use [canResolve]; requesting money and
  /// answering someone's request are allowed anytime.
  bool get canAct =>
      _connection == ClientStatus.connected && isMyTurn && !_turnRolled;

  /// Anything that resolves your position or moves money — buying the
  /// square you're on, paying its rent, sends, collects, drawing a card,
  /// GO salary — is allowed the whole turn: before the roll (last turn's
  /// landing, taxes) or after it (this roll's).
  bool get canResolve =>
      _connection == ClientStatus.connected && isMyTurn;

  /// A money request another player sent me, waiting for my answer.
  MoneyRequest? get incomingRequest => _incomingRequest;

  Player? playerById(String id) {
    for (final player in _players) {
      if (player.id == id) return player;
    }
    return null;
  }

  String accountName(String id) =>
      id == Player.bankId ? Player.bankName : (playerById(id)?.name ?? '?');

  /// The LAN endpoint other players can type manually. Host only.
  Future<String?> roomEndpoint() async {
    final port = _server?.port;
    if (port == null) return null;
    final ip = await _lanAddress();
    return ip == null ? null : '$ip:$port';
  }

  /// This device's LAN IPv4. network_info_plus works on mobile; on desktop
  /// it often returns null, so fall back to scanning the interfaces.
  Future<String?> _lanAddress() async {
    if (kIsWeb) return null;
    try {
      final fromPlugin = await NetworkInfo().getWifiIP();
      if (fromPlugin != null && fromPlugin.isNotEmpty) return fromPlugin;
    } catch (_) {}
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      String? candidate;
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;
          candidate ??= address.address;
          // Prefer classic private ranges over anything exotic (VPNs etc.).
          if (address.address.startsWith('192.168.') ||
              address.address.startsWith('10.')) {
            return address.address;
          }
        }
      }
      return candidate;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------- Session control

  Future<Result<void>> hostGame({
    required Board board,
    required String gameName,
  }) {
    final game = Game(
      id: const Uuid().v4(),
      name: gameName.trim(),
      board: board,
      hostId: _identity.playerId,
      createdAt: DateTime.now(),
    );
    return _startHosting(game: game, players: [], transactions: []);
  }

  /// Reopens a game from the home screen: hosts restart their room, clients
  /// reconnect to where the host was last seen.
  Future<Result<void>> resumeGame(GameRecord record) async {
    if (_record?.game.id == record.game.id && hasActiveSession) {
      return ok(null);
    }
    await closeSession();

    if (record.role == GameRole.host) {
      final players = await _db.getPlayers(record.game.id);
      final transactions = await _db.getTransactions(record.game.id);
      final ownerships = await _db.getOwnerships(record.game.id);
      final turnState = await _db.getTurnState(record.game.id);
      return _startHosting(
        game: record.game,
        players: players,
        transactions: transactions,
        ownerships: ownerships,
        currentTurnId: turnState.currentTurnId,
        lastRoll: turnState.lastRoll,
        turnRolled: turnState.turnRolled,
      );
    }

    final host = record.hostAddress;
    final port = record.hostPort;
    if (host == null || port == null) {
      return err('No known address for this game. Join it from Discover.');
    }
    _record = record;
    return _connect(host, port);
  }

  /// Joins a room found via discovery or a manually typed address.
  Future<Result<void>> joinRoom({
    required String host,
    required int port,
  }) async {
    await closeSession();
    _joinTarget = (host: host, port: port);
    return _connect(host, port);
  }

  Future<Result<void>> _startHosting({
    required Game game,
    required List<Player> players,
    required List<GameTransaction> transactions,
    List<PropertyOwnership> ownerships = const [],
    String? currentTurnId,
    DiceRoll? lastRoll,
    bool turnRolled = false,
  }) async {
    if (kIsWeb) {
      return err(
        'Hosting is not available in the browser — host from the Windows '
        'or Android app, then join from here.',
      );
    }
    final server = GameServer(database: _db);
    final started = await server.start(
      game: game,
      players: players,
      transactions: transactions,
      ownerships: ownerships,
      currentTurnId: currentTurnId,
      lastRoll: lastRoll,
      turnRolled: turnRolled,
    );
    if (!started.isOk) return err(started.error!);
    _server = server;
    final port = started.requireValue;

    _record = GameRecord(
      game: game,
      role: GameRole.host,
      myPlayerId: _identity.playerId,
      lastPlayedAt: DateTime.now(),
      hostAddress: '127.0.0.1',
      hostPort: port,
    );
    await _db.upsertGameRecord(_record!);
    try {
      await _discovery.advertise(game: game, port: port);
    } catch (_) {
      // Discovery is a convenience; the room still works via manual join.
    }

    return _connect('127.0.0.1', port);
  }

  Future<Result<void>> _connect(String host, int port) async {
    _hostEnded = false;
    _closing = false;

    _messageSub?.cancel();
    _statusSub?.cancel();
    _client?.dispose();

    final client = GameClient();
    _client = client;
    _messageSub = client.messages.listen(_onMessage);
    _statusSub = client.statusChanges.listen(_onStatus);
    notifyListeners();

    final connected = await client.connect(
      host: host,
      port: port,
      playerId: _identity.playerId,
      playerName: _identity.displayName,
    );
    if (!connected.isOk) {
      _scheduleReconnectIfResumable();
      return connected;
    }

    final pending = Completer<Result<void>>();
    _pendingJoin = pending;
    return pending.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => err('The host did not respond.'),
    );
  }

  /// Explicitly quits the game: tells the server, then removes it from this
  /// device entirely. As host this also closes the room for everyone.
  Future<void> leaveGame() async {
    final gameId = _record?.game.id;
    _client?.sendLeave();
    // Give the frame a moment to flush before tearing the socket down.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await closeSession();
    if (gameId != null) await _db.deleteGame(gameId);
  }

  /// Tears the session down but keeps the game on this device so it can be
  /// resumed later.
  Future<void> closeSession() async {
    _closing = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _messageSub?.cancel();
    _messageSub = null;
    _statusSub?.cancel();
    _statusSub = null;
    _client?.dispose();
    _client = null;
    await _server?.stop();
    _server = null;
    await _discovery.stopAdvertising();
    _record = null;
    _players = [];
    _transactions = [];
    _ownerships.clear();
    _currentTurnId = null;
    _lastRoll = null;
    _turnRolled = false;
    _incomingRequest = null;
    _connection = ClientStatus.disconnected;
    _joinTarget = null;
    _pendingJoin = null;
    _pendingRoll = null;
    _pendingPayments.clear();
    _pendingRequests.clear();
    _closing = false;
    notifyListeners();
  }

  // -------------------------------------------------------------- Payments

  Future<Result<void>> sendPayment({
    required String toId,
    required int amount,
    String? fromId,
    String note = '',
  }) {
    final client = _client;
    if (client == null || _connection != ClientStatus.connected) {
      return Future.value(err('Not connected to the game.'));
    }
    final txId = client.sendPayment(
      fromId: fromId ?? myPlayerId,
      toId: toId,
      amount: amount,
      note: note,
    );
    return _awaitVerdict(txId);
  }

  /// Passing GO: the bank pays me the board's salary — doubled when the
  /// token lands exactly on GO (common house rule).
  Future<Result<void>> collectSalary({bool landedOnGo = false}) =>
      sendPayment(
        fromId: Player.bankId,
        toId: myPlayerId,
        amount: (game?.board.salary ?? 0) * (landedOnGo ? 2 : 1),
        note: landedOnGo ? 'Landed on GO' : 'Passed GO',
      );

  /// Draws from the board's Chance ('chance') or Community Chest ('chest')
  /// deck. The server picks the card, shows it to everyone and applies its
  /// money effect.
  void drawCard(String deck) {
    if (canResolve) _client?.sendDrawCard(deck);
  }

  /// Registers a pending transaction and waits for the server's verdict.
  Future<Result<void>> _awaitVerdict(String txId) {
    final completer = Completer<Result<void>>();
    _pendingPayments[txId] = completer;
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _pendingPayments.remove(txId);
        return err('No response from the host.');
      },
    );
  }

  Result<void>? _requireConnection() {
    if (_client == null || _connection != ClientStatus.connected) {
      return err('Not connected to the game.');
    }
    return null;
  }

  /// Buys an unowned property. [price] settles a table-held auction at
  /// the winning bid instead of the list price.
  Future<Result<void>> buyProperty(String propertyId, {int? price}) {
    final offline = _requireConnection();
    if (offline != null) return Future.value(offline);
    return _awaitVerdict(_client!.sendBuyProperty(propertyId, price: price));
  }

  /// Pays whatever rent the server computes for [propertyId].
  /// [diceTotal] is required for utilities. [payerId] charges another
  /// player instead of me — owner-side POS, authorized by their card tap
  /// on my device (the server only accepts it from the property's owner).
  Future<Result<void>> payRent(
    String propertyId, {
    int? diceTotal,
    String? payerId,
  }) {
    final offline = _requireConnection();
    if (offline != null) return Future.value(offline);
    return _awaitVerdict(
      _client!.sendPayRent(propertyId, diceTotal: diceTotal, payerId: payerId),
    );
  }

  Future<Result<void>> setHouses(String propertyId, int houses) {
    final offline = _requireConnection();
    if (offline != null) return Future.value(offline);
    return _awaitVerdict(_client!.sendSetHouses(propertyId, houses));
  }

  /// Mortgages (or unmortgages) one of my properties with the bank.
  Future<Result<void>> setMortgaged(String propertyId, bool mortgaged) {
    final offline = _requireConnection();
    if (offline != null) return Future.value(offline);
    return _awaitVerdict(
      _client!.sendMortgage(propertyId, mortgage: mortgaged),
    );
  }

  /// Hands one of my properties to [toId] — the property side of a trade;
  /// the deal's cash (if any) is sent separately as a normal payment.
  Future<Result<void>> transferProperty(String propertyId, String toId) {
    final offline = _requireConnection();
    if (offline != null) return Future.value(offline);
    return _awaitVerdict(
      _client!.sendTransferProperty(propertyId, toId),
    );
  }

  /// Asks [targetId] for money. Resolves when they pay or decline on their
  /// device — that can take a while, they're probably arguing about it.
  Future<Result<void>> requestMoney({
    required String targetId,
    required int amount,
    String note = '',
  }) {
    final offline = _requireConnection();
    if (offline != null) return Future.value(offline);
    final requestId = _client!.sendMoneyRequest(
      targetId: targetId,
      amount: amount,
      note: note,
    );
    _outgoingRequestId = requestId;
    final completer = Completer<Result<void>>();
    _pendingRequests[requestId] = completer;
    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        _pendingRequests.remove(requestId);
        if (_outgoingRequestId == requestId) _outgoingRequestId = null;
        return err('No answer — ask them in person.');
      },
    );
  }

  /// Withdraws my outstanding money request (leaving the request screen);
  /// the other player's approval prompt disappears.
  void cancelOutgoingRequest() {
    final requestId = _outgoingRequestId;
    if (requestId == null) return;
    _outgoingRequestId = null;
    final pending = _pendingRequests.remove(requestId);
    if (pending != null && !pending.isCompleted) {
      pending.complete(err('cancelled'));
    }
    _client?.sendDeclineRequest(requestId);
  }

  /// Answers the request currently shown on this device. Accepting pays it
  /// as a normal validated payment carrying the request id.
  Future<Result<void>> respondToIncomingRequest({required bool accept}) async {
    final request = _incomingRequest;
    if (request == null) return ok(null);

    if (!accept) {
      _client?.sendDeclineRequest(request.id);
      _incomingRequest = null;
      notifyListeners();
      return ok(null);
    }

    final offline = _requireConnection();
    if (offline != null) return offline;
    final txId = _client!.sendPayment(
      fromId: myPlayerId,
      toId: request.requesterId,
      amount: request.amount,
      note: request.note,
      requestId: request.id,
    );
    final result = await _awaitVerdict(txId);
    if (result.isOk) {
      _incomingRequest = null;
      notifyListeners();
    }
    return result;
  }

  /// Rolls the dice for my turn. The server generates the result and
  /// broadcasts it to every device; resolves when it arrives.
  Future<Result<void>> rollDice() {
    if (!canRoll) {
      return Future.value(err(
        _turnRolled ? 'You already rolled this turn.' : "It's not your turn.",
      ));
    }
    _client!.sendRollDice();
    final completer = Completer<Result<void>>();
    _pendingRoll = completer;
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _pendingRoll = null;
        return err('No response from the host.');
      },
    );
  }

  /// Ends my turn; the server advances the rotation. Only allowed after
  /// rolling — a turn is roll, act, end.
  void endTurn() {
    if (canEndTurn) _client?.sendEndTurn();
  }

  // ------------------------------------------------------- Incoming events

  void _onMessage(WsMessage message) {
    switch (message.type) {
      case MessageType.joinAccepted:
      case MessageType.snapshot:
        _applySnapshot(message.payload);
      case MessageType.joinRejected:
        final reason =
            message.payload['reason'] as String? ?? 'Join rejected.';
        _completeJoin(err(reason));
      case MessageType.paymentApplied:
        _applyPayment(message.payload);
      case MessageType.paymentRejected:
        final txId = message.payload['txId'] as String?;
        final reason =
            message.payload['reason'] as String? ?? 'Payment rejected.';
        _pendingPayments.remove(txId)?.complete(err(reason));
        _errors.add(reason);
      case MessageType.propertyChanged:
        // Transfers move no money, so their intent resolves here (the
        // event carries the intent id) instead of via paymentApplied.
        _pendingPayments
            .remove(message.payload['txId'] as String?)
            ?.complete(ok(null));
        final json = message.payload['ownership'] as Map<String, dynamic>?;
        if (json != null) {
          final ownership = PropertyOwnership.fromJson(json);
          _ownerships[ownership.propertyId] = ownership;
          final record = _record;
          if (record != null && !isHost) {
            _db.upsertOwnerships(record.game.id, [ownership]);
          }
          notifyListeners();
        }
      case MessageType.moneyRequested:
        final json = message.payload['request'] as Map<String, dynamic>?;
        if (json != null) {
          _incomingRequest = MoneyRequest.fromJson(json);
          notifyListeners();
        }
      case MessageType.moneyRequestResolved:
        final requestId = message.payload['requestId'] as String?;
        final accepted = message.payload['accepted'] == true;
        final reason = message.payload['reason'] as String?;
        // Requester side: settle the waiting future.
        if (_outgoingRequestId == requestId) _outgoingRequestId = null;
        final pendingRequest = _pendingRequests.remove(requestId);
        if (pendingRequest != null && !pendingRequest.isCompleted) {
          pendingRequest.complete(
            accepted ? ok(null) : err(reason ?? 'The request was declined.'),
          );
        }
        // Target side: the request is settled either way — drop the banner.
        if (_incomingRequest?.id == requestId) {
          _incomingRequest = null;
          notifyListeners();
        }
      case MessageType.cardDrawn:
        final cardJson = message.payload['card'] as Map<String, dynamic>?;
        final drawerId = message.payload['playerId'] as String?;
        if (cardJson != null && drawerId != null) {
          _cardDraws.add((
            playerId: drawerId,
            deck: message.payload['deck'] as String? ?? 'chance',
            card: BoardCard.fromJson(cardJson),
          ));
        }
      case MessageType.diceRolled:
        final json = message.payload['roll'] as Map<String, dynamic>?;
        if (json != null) {
          _lastRoll = DiceRoll.fromJson(json);
          _turnRolled = message.payload['turnRolled'] as bool? ?? true;
          final pending = _pendingRoll;
          _pendingRoll = null;
          if (pending != null && !pending.isCompleted) {
            pending.complete(ok(null));
          }
          notifyListeners();
        }
      case MessageType.turnChanged:
        _currentTurnId = message.payload['playerId'] as String?;
        _turnRolled = false;
        final record = _record;
        if (record != null && !isHost) {
          _db.setTurnState(
            record.game.id,
            currentTurnId: _currentTurnId,
            lastRoll: _lastRoll,
            turnRolled: false,
          );
        }
        notifyListeners();
      case MessageType.playerJoined:
      case MessageType.presenceChanged:
        final json = message.payload['player'] as Map<String, dynamic>?;
        if (json != null) _upsertPlayer(Player.fromJson(json));
      case MessageType.playerLeft:
        final playerId = message.payload['playerId'] as String?;
        final player = playerId == null ? null : playerById(playerId);
        if (player != null) {
          _upsertPlayer(player.copyWith(hasLeft: true, isOnline: false));
        }
      case MessageType.gameClosed:
        _hostEnded = true;
        notifyListeners();
      default:
        break;
    }
  }

  void _applySnapshot(Map<String, dynamic> payload) {
    final json = payload['snapshot'] as Map<String, dynamic>?;
    if (json == null) return;
    final snapshot = GameSnapshot.fromJson(json);

    final target = _joinTarget;
    if (_record == null && target != null) {
      // Fresh join: this is the first time the device sees this game.
      _record = GameRecord(
        game: snapshot.game,
        role: GameRole.client,
        myPlayerId: _identity.playerId,
        lastPlayedAt: DateTime.now(),
        hostAddress: target.host,
        hostPort: target.port,
      );
    } else if (_record != null) {
      _record = _record!.copyWith(
        game: snapshot.game,
        lastPlayedAt: DateTime.now(),
      );
    } else {
      return;
    }
    _joinTarget = null;

    _players = snapshot.players;
    _transactions = snapshot.transactions;
    _ownerships
      ..clear()
      ..addEntries(
        snapshot.ownerships.map((o) => MapEntry(o.propertyId, o)),
      );
    _currentTurnId = snapshot.currentTurnId;
    _lastRoll = snapshot.lastRoll;
    _turnRolled = snapshot.turnRolled;

    if (isHost) {
      // The server already persisted players and transactions.
      _db.upsertGameRecord(_record!);
    } else {
      _db.saveSnapshot(_record!, snapshot);
    }

    _completeJoin(ok(null));
    notifyListeners();
  }

  void _applyPayment(Map<String, dynamic> payload) {
    final record = _record;
    if (record == null) return;

    final txJson = payload['transaction'] as Map<String, dynamic>?;
    if (txJson == null) return;
    final tx = GameTransaction.fromJson(txJson);

    final playersJson = payload['players'] as List<dynamic>?;
    if (playersJson != null) {
      _players = playersJson
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (!_transactions.any((t) => t.id == tx.id)) {
      _transactions.add(tx);
    }

    _record = record.copyWith(lastPlayedAt: DateTime.now());
    _db.upsertGameRecord(_record!);
    if (!isHost) {
      _db.upsertPlayers(record.game.id, _players);
      _db.insertTransactions(record.game.id, [tx]);
    }

    _pendingPayments.remove(tx.id)?.complete(ok(null));
    notifyListeners();
  }

  void _upsertPlayer(Player player) {
    final index = _players.indexWhere((p) => p.id == player.id);
    if (index >= 0) {
      _players[index] = player;
    } else {
      _players.add(player);
    }
    final record = _record;
    if (record != null && !isHost) {
      _db.upsertPlayers(record.game.id, [player]);
    }
    notifyListeners();
  }

  void _onStatus(ClientStatus status) {
    _connection = status;
    notifyListeners();
    if (status == ClientStatus.disconnected) {
      _completeJoin(err('Connection lost.'));
      _scheduleReconnectIfResumable();
    }
  }

  void _completeJoin(Result<void> result) {
    final pending = _pendingJoin;
    _pendingJoin = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  void _scheduleReconnectIfResumable() {
    if (_closing || _hostEnded) return;
    final record = _record;
    if (record == null) return;
    final host = record.hostAddress;
    final port = record.hostPort;
    if (host == null || port == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (_closing || _hostEnded || _record == null) return;
      if (_connection != ClientStatus.disconnected) return;
      _connect(host, port);
    });
  }

  @override
  void dispose() {
    closeSession();
    _errors.close();
    _cardDraws.close();
    super.dispose();
  }
}
