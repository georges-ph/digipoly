import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/dice_roll.dart';
import '../models/game.dart';
import '../models/game_transaction.dart';
import '../models/money_request.dart';
import '../models/player.dart';
import '../models/property.dart';
import '../models/property_auction.dart';
import '../models/property_ownership.dart';
import '../models/result.dart';
import '../models/ws_message.dart';
import 'database_service.dart';
import 'game_engine.dart';

/// The authoritative side of a game session, run on the hosting device.
///
/// Owns the game state, validates every intent through [GameEngine],
/// persists the outcome and broadcasts the resulting event to every
/// connected client. The host device itself joins through a regular
/// [GameClient] pointed at 127.0.0.1, so there is a single code path for
/// everyone.
///
/// If the repo's web build is bundled (assets/web/web_app.zip, created by
/// tool/bundle_web_app.ps1), the same port also serves the app over plain
/// HTTP — scanning the room QR opens the game in any browser on the wifi.
class GameServer {
  GameServer({required DatabaseService database}) : _db = database;

  static const int defaultPort = 47912;

  final DatabaseService _db;

  Game? _game;
  final Map<String, Player> _players = {};
  final List<GameTransaction> _transactions = [];
  final Map<String, PropertyOwnership> _ownerships = {};
  final Map<String, MoneyRequest> _pendingRequests = {};
  final Map<String, PropertyAuction> _auctions = {};
  String? _currentTurnId;
  DiceRoll? _lastRoll;
  bool _turnRolled = false;
  int _freeParkingPot = 0;
  final _random = Random();

  final Map<String, WebSocketChannel> _connections = {};

  HttpServer? _http;

  /// The bundled web app, keyed by normalized path. Null when not bundled.
  Map<String, List<int>>? _webApp;

  bool get isRunning => _http != null;
  int? get port => _http?.port;

  /// Starts serving [game]. Tries [defaultPort] first so manual joins are
  /// predictable, falls back to an ephemeral port if it is taken.
  Future<Result<int>> start({
    required Game game,
    required List<Player> players,
    required List<GameTransaction> transactions,
    List<PropertyOwnership> ownerships = const [],
    String? currentTurnId,
    DiceRoll? lastRoll,
    bool turnRolled = false,
    int freeParkingPot = 0,
  }) async {
    if (isRunning) await stop();

    _game = game;
    _players
      ..clear()
      ..addEntries(
        players.map((p) => MapEntry(p.id, p.copyWith(isOnline: false))),
      );
    _transactions
      ..clear()
      ..addAll(transactions);
    _ownerships
      ..clear()
      ..addEntries(ownerships.map((o) => MapEntry(o.propertyId, o)));
    _pendingRequests.clear();
    _auctions.clear();
    // Roll state is restored from the DB so restarting the host app
    // mid-turn doesn't hand the current player a fresh roll.
    _currentTurnId = currentTurnId;
    _lastRoll = lastRoll;
    _turnRolled = turnRolled;
    _freeParkingPot = freeParkingPot;

    await _loadWebApp();

    // pingInterval matters: without keepalives a phone that dies or drops
    // off the wifi never sends a close frame, and its player would show
    // online forever.
    final handler = Cascade()
        .add(webSocketHandler(
          _onConnection,
          pingInterval: const Duration(seconds: 5),
        ))
        .add(_serveWebApp)
        .handler;
    try {
      _http = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        defaultPort,
      );
    } on SocketException {
      try {
        _http = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
      } catch (e) {
        return err('Could not start the room: $e');
      }
    } catch (e) {
      return err('Could not start the room: $e');
    }
    return ok(_http!.port);
  }

  Future<void> stop() async {
    // Snapshotted: closing a sink runs its onDone handler, which removes
    // the channel from these same collections — mutating them mid-iteration
    // would throw ConcurrentModificationError.
    for (final channel in _connections.values.toList()) {
      channel.sink.add(const WsMessage(MessageType.gameClosed).encode());
      channel.sink.close();
    }
    _connections.clear();
    await _http?.close(force: true);
    _http = null;
    _game = null;
  }

  // -------------------------------------------------------------- Web app

  Future<void> _loadWebApp() async {
    if (_webApp != null) return;
    try {
      final data = await rootBundle.load('assets/web/web_app.zip');
      final archive = ZipDecoder().decodeBytes(data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ));
      final files = <String, List<int>>{};
      for (final file in archive.files) {
        if (!file.isFile) continue;
        files[file.name.replaceAll('\\', '/')] = file.content as List<int>;
      }
      _webApp = files;
    } catch (_) {
      _webApp = null; // Not bundled; the server is websocket-only.
    }
  }

  Response _serveWebApp(Request request) {
    final files = _webApp;
    if (files == null) {
      return Response.ok(
        'digipoly room server. Join from the app on the same network.',
      );
    }
    var path = request.url.path;
    if (path.isEmpty || path.endsWith('/')) path = 'index.html';
    final content = files[path];
    if (content == null) return Response.notFound('Not found');
    return Response.ok(content, headers: {
      'Content-Type': _contentTypeFor(path),
      'Cache-Control': 'no-cache',
    });
  }

  static String _contentTypeFor(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'html' => 'text/html; charset=utf-8',
      'js' || 'mjs' => 'application/javascript',
      'css' => 'text/css',
      'json' => 'application/json',
      'wasm' => 'application/wasm',
      'png' => 'image/png',
      'ico' => 'image/x-icon',
      'svg' => 'image/svg+xml',
      'otf' => 'font/otf',
      'ttf' => 'font/ttf',
      _ => 'application/octet-stream',
    };
  }

  // ----------------------------------------------------------- Connections

  void _onConnection(WebSocketChannel channel, String? protocol) {
    String? boundPlayerId;

    channel.stream.listen(
      (raw) {
        if (raw is! String) return;
        final message = WsMessage.decode(raw);
        if (message.type == MessageType.joinRequest) {
          boundPlayerId = _handleJoin(channel, message.payload);
          return;
        }
        final playerId = boundPlayerId;
        if (playerId == null) return;
        switch (message.type) {
          case MessageType.paymentIntent:
            _handlePayment(playerId, channel, message.payload);
          case MessageType.buyProperty:
            _handleBuy(playerId, channel, message.payload);
          case MessageType.payRent:
            _handlePayRent(playerId, channel, message.payload);
          case MessageType.setHouses:
            _handleSetHouses(playerId, channel, message.payload);
          case MessageType.mortgage:
            _handleMortgage(playerId, channel, message.payload);
          case MessageType.transferProperty:
            _handleTransferProperty(playerId, channel, message.payload);
          case MessageType.moneyRequest:
            _handleMoneyRequest(playerId, channel, message.payload);
          case MessageType.moneyRequestResponse:
            _handleMoneyRequestResponse(playerId, message.payload);
          case MessageType.rollDice:
            _handleRollDice(playerId);
          case MessageType.drawCard:
            _handleDrawCard(playerId, message.payload);
          case MessageType.editTransactionNote:
            _handleEditTransactionNote(playerId, channel, message.payload);
          case MessageType.payJailFine:
            _handlePayJailFine(playerId, channel, message.payload);
          case MessageType.startAuction:
            _handleStartAuction(playerId, message.payload);
          case MessageType.placeBid:
            _handlePlaceBid(playerId, message.payload);
          case MessageType.closeAuction:
            _handleCloseAuction(playerId, message.payload);
          case MessageType.endTurn:
            _handleEndTurn(playerId, channel);
          case MessageType.leaveGame:
            _handleLeave(playerId);
          default:
            break;
        }
      },
      onDone: () {
        final playerId = boundPlayerId;
        if (playerId != null) _handleDisconnect(playerId, channel);
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  String? _handleJoin(WebSocketChannel channel, Map<String, dynamic> payload) {
    final game = _game;
    final playerId = payload['playerId'] as String?;
    final name = (payload['name'] as String? ?? '').trim();

    if (game == null || playerId == null || playerId.isEmpty) {
      _send(channel, const WsMessage(MessageType.joinRejected, {
        'reason': 'Invalid join request.',
      }));
      return null;
    }

    final existing = _players[playerId];
    final isNew = existing == null;
    final player = isNew
        ? Player(
            id: playerId,
            name: name.isEmpty ? 'Player' : name,
            balance: game.board.startingBalance,
            seat: _nextSeat(),
            isHost: playerId == game.hostId,
            isOnline: true,
            position: game.board.goIndex >= 0 ? game.board.goIndex : 0,
          )
        : existing.copyWith(
            name: name.isEmpty ? existing.name : name,
            isOnline: true,
            hasLeft: false,
          );
    _players[playerId] = player;

    // The first player to ever join opens the turn rotation.
    if (_currentTurnId == null) {
      _currentTurnId = playerId;
      _db.setTurnState(game.id, currentTurnId: playerId);
    }

    // A reconnect replaces any stale connection for the same identity.
    final stale = _connections[playerId];
    if (stale != null && stale != channel) stale.sink.close();
    _connections[playerId] = channel;

    _db.upsertPlayers(game.id, [player]);

    _send(channel, WsMessage(MessageType.joinAccepted, {
      'snapshot': _snapshot().toJson(),
    }));
    _broadcast(
      WsMessage(
        isNew ? MessageType.playerJoined : MessageType.presenceChanged,
        {'player': player.toJson()},
      ),
      except: playerId,
    );
    return playerId;
  }

  int _nextSeat() => _players.values.isEmpty
      ? 0
      : _players.values.map((p) => p.seat).reduce((a, b) => a > b ? a : b) + 1;

  // --------------------------------------------------------------- Intents

  /// Shared tail of every money intent: run the engine, persist, broadcast.
  /// Returns true when the transaction was applied.
  bool _applyTransaction(
    GameTransaction tx,
    void Function(String reason) reject,
  ) {
    final result = GameEngine.applyPayment(_players.values.toList(), tx);
    if (!result.isOk) {
      reject(result.error!);
      return false;
    }

    for (final player in result.requireValue) {
      _players[player.id] = player;
    }
    _transactions.add(tx);

    final game = _game!;
    _db.upsertPlayers(game.id, result.requireValue);
    _db.insertTransactions(game.id, [tx]);

    _broadcast(WsMessage(MessageType.paymentApplied, {
      'transaction': tx.toJson(),
      'players': _players.values.map((p) => p.toJson()).toList(),
      'freeParkingPot': _freeParkingPot,
    }));
    return true;
  }

  /// Validates the common preconditions of every intent and returns a
  /// rejection callback bound to [channel], or null if [txId] was already
  /// processed (a retried intent is acknowledged silently).
  void Function(String reason)? _prepareIntent(
    String senderId,
    WebSocketChannel channel,
    String? txId,
  ) {
    if (txId == null) return null;
    if (_transactions.any((tx) => tx.id == txId)) return null;

    void reject(String reason) => _send(
          channel,
          WsMessage(MessageType.paymentRejected, {
            'txId': txId,
            'reason': reason,
          }),
        );

    final sender = _players[senderId];
    if (_game == null || sender == null || sender.hasLeft) {
      reject('You are not part of this game.');
      return null;
    }
    return reject;
  }

  void _handlePayment(
    String senderId,
    WebSocketChannel channel,
    Map<String, dynamic> payload,
  ) {
    final txId = payload['id'] as String?;
    final reject = _prepareIntent(senderId, channel, txId);
    if (reject == null) return;

    final fromId = payload['fromId'] as String? ?? senderId;
    if (!GameEngine.canInitiate(senderId: senderId, fromId: fromId)) {
      reject("You can only move your own money or the bank's.");
      return;
    }

    final requestId = payload['requestId'] as String?;
    final tx = GameTransaction(
      id: txId!,
      gameId: _game!.id,
      fromId: fromId,
      toId: payload['toId'] as String? ?? Player.bankId,
      amount: payload['amount'] as int? ?? 0,
      type: requestId != null
          ? TransactionType.request
          : TransactionType.payment,
      timestamp: DateTime.now(),
      note: payload['note'] as String? ?? '',
    );

    final request = requestId == null ? null : _pendingRequests[requestId];
    final settlesRequest = request != null &&
        request.targetId == senderId &&
        request.requesterId == tx.toId;

    if (!_applyTransaction(tx, reject)) {
      // The payer accepted but cannot cover it — settle the request as
      // declined so the requester is not left waiting.
      if (settlesRequest) {
        _resolveRequest(
          request,
          accepted: false,
          reason: '${_players[senderId]?.name ?? 'They'} accepted but '
              'does not have enough money.',
        );
      }
      return;
    }

    if (settlesRequest) _resolveRequest(request, accepted: true);
  }

  /// Settles a pending request and tells both sides, so the requester's
  /// waiting screen and the target's banner both resolve.
  void _resolveRequest(
    MoneyRequest request, {
    required bool accepted,
    String? reason,
  }) {
    _pendingRequests.remove(request.id);
    final message = WsMessage(MessageType.moneyRequestResolved, {
      'requestId': request.id,
      'accepted': accepted,
      'reason': ?reason,
    });
    _sendTo(request.requesterId, message);
    _sendTo(request.targetId, message);
  }

  /// Edits a past transaction's note — the amount and parties never change.
  /// Either party to the transaction may add or correct it, any time.
  void _handleEditTransactionNote(
    String senderId,
    WebSocketChannel channel,
    Map<String, dynamic> payload,
  ) {
    final txId = payload['id'] as String?;
    final reject = _prepareIntent(senderId, channel, txId);
    if (reject == null) return;

    final transactionId = payload['transactionId'] as String?;
    final index = _transactions.indexWhere((t) => t.id == transactionId);
    if (index == -1) {
      reject('That transaction no longer exists.');
      return;
    }
    final target = _transactions[index];
    if (target.fromId != senderId && target.toId != senderId) {
      reject('You can only edit notes on your own transactions.');
      return;
    }

    final updated = target.copyWith(note: payload['note'] as String? ?? '');
    _transactions[index] = updated;
    _db.insertTransactions(_game!.id, [updated]);

    _broadcast(WsMessage(MessageType.transactionNoteUpdated, {
      'txId': txId,
      'transaction': updated.toJson(),
    }));
  }

  void _handleBuy(
    String senderId,
    WebSocketChannel channel,
    Map<String, dynamic> payload,
  ) {
    final txId = payload['id'] as String?;
    final reject = _prepareIntent(senderId, channel, txId);
    if (reject == null) return;

    final propertyId = payload['propertyId'] as String? ?? '';
    // An explicit price means a table-held auction was won at that bid.
    final price = payload['price'] as int?;
    final validated = GameEngine.validatePurchase(
      board: _game!.board,
      ownerships: _ownerships,
      propertyId: propertyId,
      buyer: _players[senderId]!,
      price: price,
    );
    if (!validated.isOk) {
      reject(validated.error!);
      return;
    }
    final property = validated.requireValue;

    final tx = GameTransaction(
      id: txId!,
      gameId: _game!.id,
      fromId: senderId,
      toId: Player.bankId,
      amount: price ?? property.price,
      type: TransactionType.purchase,
      propertyId: propertyId,
      timestamp: DateTime.now(),
      note: price == null ? '' : 'Auction',
    );
    if (!_applyTransaction(tx, reject)) return;

    final ownership = PropertyOwnership(
      propertyId: propertyId,
      ownerId: senderId,
    );
    _ownerships[propertyId] = ownership;
    _db.upsertOwnerships(_game!.id, [ownership]);
    _broadcast(WsMessage(MessageType.propertyChanged, {
      'ownership': ownership.toJson(),
    }));
  }

  // ------------------------------------------------------------- Auctions

  Property? _findProperty(String propertyId) {
    for (final property in _game!.board.properties) {
      if (property.id == propertyId) return property;
    }
    return null;
  }

  void _rejectAuction(String senderId, String propertyId, String reason) =>
      _sendTo(senderId, WsMessage(MessageType.auctionRejected, {
        'propertyId': propertyId,
        'reason': reason,
      }));

  /// Starts a live auction for an unowned property — not turn-gated, since
  /// auctions arise on other players' turns (someone else declined to buy).
  /// Anyone can start one and everyone watching sees it live.
  void _handleStartAuction(String senderId, Map<String, dynamic> payload) {
    final sender = _players[senderId];
    if (sender == null || sender.hasLeft) return;

    final propertyId = payload['propertyId'] as String? ?? '';
    final property = _findProperty(propertyId);
    if (property == null || !property.kind.isOwnable) {
      _rejectAuction(senderId, propertyId, "This square can't be auctioned.");
      return;
    }
    if (_ownerships.containsKey(propertyId)) {
      _rejectAuction(senderId, propertyId, '${property.name} is already owned.');
      return;
    }
    if (_auctions.containsKey(propertyId)) {
      _rejectAuction(
        senderId,
        propertyId,
        'An auction for ${property.name} is already running.',
      );
      return;
    }

    final auction = PropertyAuction(propertyId: propertyId, startedBy: senderId);
    _auctions[propertyId] = auction;
    _broadcast(WsMessage(MessageType.auctionStarted, {
      'auction': auction.toJson(),
    }));
  }

  /// Raises the bid on a running auction. No turn order — anyone can raise
  /// anytime, as long as it beats the current bid and they can afford it.
  void _handlePlaceBid(String senderId, Map<String, dynamic> payload) {
    final sender = _players[senderId];
    if (sender == null || sender.hasLeft) return;

    final propertyId = payload['propertyId'] as String? ?? '';
    final auction = _auctions[propertyId];
    if (auction == null) {
      _rejectAuction(senderId, propertyId, 'That auction is no longer running.');
      return;
    }
    final amount = payload['amount'] as int? ?? 0;
    if (amount <= auction.currentBid) {
      _rejectAuction(
        senderId,
        propertyId,
        'Bid higher than the current bid.',
      );
      return;
    }
    if (sender.balance < amount) {
      _rejectAuction(senderId, propertyId, "You don't have that much.");
      return;
    }

    final updated =
        auction.copyWith(currentBid: amount, currentBidderId: senderId);
    _auctions[propertyId] = updated;
    _broadcast(WsMessage(MessageType.auctionBid, {
      'auction': updated.toJson(),
    }));
  }

  /// Closes a running auction — anyone can, not just the one who started
  /// it. Sells to the current top bidder at their bid, or cancels if
  /// nobody bid (or the bid can no longer be honored).
  void _handleCloseAuction(String senderId, Map<String, dynamic> payload) {
    final sender = _players[senderId];
    if (sender == null || sender.hasLeft) return;

    final propertyId = payload['propertyId'] as String? ?? '';
    final auction = _auctions.remove(propertyId);
    if (auction == null) return;

    final bidderId = auction.currentBidderId;
    final bidder = bidderId == null ? null : _players[bidderId];
    if (bidderId == null || bidder == null || bidder.hasLeft) {
      _broadcast(WsMessage(MessageType.auctionClosed, {
        'propertyId': propertyId,
        'cancelled': true,
      }));
      return;
    }

    final validated = GameEngine.validatePurchase(
      board: _game!.board,
      ownerships: _ownerships,
      propertyId: propertyId,
      buyer: bidder,
      price: auction.currentBid,
    );
    if (!validated.isOk) {
      _broadcast(WsMessage(MessageType.auctionClosed, {
        'propertyId': propertyId,
        'cancelled': true,
        'reason': validated.error,
      }));
      return;
    }

    final tx = GameTransaction(
      id: const Uuid().v4(),
      gameId: _game!.id,
      fromId: bidderId,
      toId: Player.bankId,
      amount: auction.currentBid,
      type: TransactionType.purchase,
      propertyId: propertyId,
      timestamp: DateTime.now(),
      note: 'Auction',
    );
    if (!_applyTransaction(tx, (_) {})) {
      _broadcast(WsMessage(MessageType.auctionClosed, {
        'propertyId': propertyId,
        'cancelled': true,
      }));
      return;
    }

    final ownership = PropertyOwnership(propertyId: propertyId, ownerId: bidderId);
    _ownerships[propertyId] = ownership;
    _db.upsertOwnerships(_game!.id, [ownership]);
    _broadcast(WsMessage(MessageType.propertyChanged, {
      'ownership': ownership.toJson(),
    }));
    _broadcast(WsMessage(MessageType.auctionClosed, {
      'propertyId': propertyId,
      'winnerId': bidderId,
      'amount': auction.currentBid,
    }));
  }

  void _handlePayRent(
    String senderId,
    WebSocketChannel channel,
    Map<String, dynamic> payload,
  ) {
    final txId = payload['id'] as String?;
    final reject = _prepareIntent(senderId, channel, txId);
    if (reject == null) return;

    final propertyId = payload['propertyId'] as String? ?? '';
    final ownership = _ownerships[propertyId];
    if (ownership == null) {
      reject('Nobody owns this property.');
      return;
    }

    // Owner-side POS: `payerId` charges someone else's account — allowed
    // only for the property's owner, whose device read the payer's card
    // (the physical tap is the authorization, like trusting the banker).
    final payerId = payload['payerId'] as String? ?? senderId;
    if (payerId != senderId && ownership.ownerId != senderId) {
      reject('Only the owner can charge rent to a tapped card.');
      return;
    }
    final payer = _players[payerId];
    if (payer == null || payer.hasLeft) {
      reject('That player is not in this game.');
      return;
    }
    if (ownership.ownerId == payerId) {
      reject(payerId == senderId
          ? 'You own this property — no rent due.'
          : 'They own this property — no rent due.');
      return;
    }

    // Utilities need the dice; the payer's own in-app roll is used
    // automatically when they didn't send one.
    var diceTotal = payload['diceTotal'] as int?;
    if (diceTotal == null && _lastRoll?.playerId == payerId) {
      diceTotal = _lastRoll!.total;
    }

    final rent = GameEngine.computeRent(
      board: _game!.board,
      ownerships: _ownerships,
      propertyId: propertyId,
      diceTotal: diceTotal,
    );
    if (!rent.isOk) {
      reject(rent.error!);
      return;
    }

    _applyTransaction(
      GameTransaction(
        id: txId!,
        gameId: _game!.id,
        fromId: payerId,
        toId: ownership.ownerId,
        amount: rent.requireValue,
        type: TransactionType.rent,
        propertyId: propertyId,
        timestamp: DateTime.now(),
      ),
      reject,
    );
  }

  void _handleSetHouses(
    String senderId,
    WebSocketChannel channel,
    Map<String, dynamic> payload,
  ) {
    final txId = payload['id'] as String?;
    final reject = _prepareIntent(senderId, channel, txId);
    if (reject == null) return;

    final propertyId = payload['propertyId'] as String? ?? '';
    final targetHouses = payload['houses'] as int? ?? 0;
    final validated = GameEngine.validateHouses(
      board: _game!.board,
      ownerships: _ownerships,
      propertyId: propertyId,
      senderId: senderId,
      targetHouses: targetHouses,
    );
    if (!validated.isOk) {
      reject(validated.error!);
      return;
    }

    final cost = validated.requireValue;
    final applied = _applyTransaction(
      GameTransaction(
        id: txId!,
        gameId: _game!.id,
        fromId: cost > 0 ? senderId : Player.bankId,
        toId: cost > 0 ? Player.bankId : senderId,
        amount: cost.abs(),
        type: TransactionType.house,
        propertyId: propertyId,
        timestamp: DateTime.now(),
      ),
      reject,
    );
    if (!applied) return;

    final ownership =
        _ownerships[propertyId]!.copyWith(houses: targetHouses);
    _ownerships[propertyId] = ownership;
    _db.upsertOwnerships(_game!.id, [ownership]);
    _broadcast(WsMessage(MessageType.propertyChanged, {
      'ownership': ownership.toJson(),
    }));
  }

  void _handleMortgage(
    String senderId,
    WebSocketChannel channel,
    Map<String, dynamic> payload,
  ) {
    final txId = payload['id'] as String?;
    final reject = _prepareIntent(senderId, channel, txId);
    if (reject == null) return;

    final propertyId = payload['propertyId'] as String? ?? '';
    final mortgage = payload['mortgage'] as bool? ?? true;
    final validated = GameEngine.validateMortgage(
      board: _game!.board,
      ownerships: _ownerships,
      propertyId: propertyId,
      senderId: senderId,
      mortgage: mortgage,
    );
    if (!validated.isOk) {
      reject(validated.error!);
      return;
    }

    // Negative = the bank pays the owner (mortgaging), positive = the
    // owner buys the mortgage back (value + interest).
    final cost = validated.requireValue;
    final applied = _applyTransaction(
      GameTransaction(
        id: txId!,
        gameId: _game!.id,
        fromId: cost > 0 ? senderId : Player.bankId,
        toId: cost > 0 ? Player.bankId : senderId,
        amount: cost.abs(),
        type: TransactionType.mortgage,
        propertyId: propertyId,
        timestamp: DateTime.now(),
      ),
      reject,
    );
    if (!applied) return;

    final ownership =
        _ownerships[propertyId]!.copyWith(mortgaged: mortgage);
    _ownerships[propertyId] = ownership;
    _db.upsertOwnerships(_game!.id, [ownership]);
    _broadcast(WsMessage(MessageType.propertyChanged, {
      'ownership': ownership.toJson(),
    }));
  }

  /// Hands a property to another player — the property side of a trade;
  /// no money moves (the deal's cash is a normal payment). The broadcast
  /// carries the intent id so the sender's pending future resolves.
  void _handleTransferProperty(
    String senderId,
    WebSocketChannel channel,
    Map<String, dynamic> payload,
  ) {
    final txId = payload['id'] as String?;
    final reject = _prepareIntent(senderId, channel, txId);
    if (reject == null) return;

    final propertyId = payload['propertyId'] as String? ?? '';
    final toId = payload['toId'] as String? ?? '';
    final validated = GameEngine.validateTransfer(
      board: _game!.board,
      ownerships: _ownerships,
      propertyId: propertyId,
      senderId: senderId,
      target: _players[toId],
    );
    if (!validated.isOk) {
      reject(validated.error!);
      return;
    }

    final ownership = _ownerships[propertyId]!.copyWith(ownerId: toId);
    _ownerships[propertyId] = ownership;
    _db.upsertOwnerships(_game!.id, [ownership]);
    _broadcast(WsMessage(MessageType.propertyChanged, {
      'ownership': ownership.toJson(),
      'txId': txId,
    }));
  }

  void _handleMoneyRequest(
    String senderId,
    WebSocketChannel channel,
    Map<String, dynamic> payload,
  ) {
    final requestId = payload['requestId'] as String?;
    final targetId = payload['targetId'] as String? ?? '';
    final amount = payload['amount'] as int? ?? 0;
    if (requestId == null || _pendingRequests.containsKey(requestId)) return;

    void resolve(bool accepted, [String? reason]) => _send(
          channel,
          WsMessage(MessageType.moneyRequestResolved, {
            'requestId': requestId,
            'accepted': accepted,
            'reason': ?reason,
          }),
        );

    final target = _players[targetId];
    if (target == null || target.hasLeft) {
      resolve(false, 'That player is not in the game.');
      return;
    }
    if (!target.isOnline || !_connections.containsKey(targetId)) {
      resolve(false, '${target.name} is offline right now.');
      return;
    }
    if (amount <= 0) {
      resolve(false, 'Amount must be greater than zero.');
      return;
    }
    if (target.balance < amount) {
      resolve(false, '${target.name} does not have that much.');
      return;
    }

    final request = MoneyRequest(
      id: requestId,
      gameId: _game!.id,
      requesterId: senderId,
      targetId: targetId,
      amount: amount,
      note: payload['note'] as String? ?? '',
      createdAt: DateTime.now(),
    );
    _pendingRequests[requestId] = request;
    _sendTo(
      targetId,
      WsMessage(MessageType.moneyRequested, {'request': request.toJson()}),
    );
  }

  void _handleMoneyRequestResponse(
    String senderId,
    Map<String, dynamic> payload,
  ) {
    final requestId = payload['requestId'] as String?;
    final request = requestId == null ? null : _pendingRequests[requestId];
    // The target declines it — or the requester withdraws their own.
    if (request == null ||
        (request.targetId != senderId && request.requesterId != senderId)) {
      return;
    }

    // Accepting happens through a paymentIntent carrying the requestId;
    // this message only carries declines.
    if (payload['accept'] == true) return;

    _resolveRequest(request, accepted: false);
  }

  /// Dice are rolled on the server — by the player whose turn it is, and
  /// everyone sees the same result. A double leaves the turn un-rolled:
  /// the player rolls again, and (since ending requires a roll) must do so
  /// before ending the turn.
  ///
  /// On a board with a curated layout (`board.goIndex != -1`) the roll also
  /// moves the player's token and resolves whatever they land on — tax,
  /// Free Parking, Go To Jail, Chance/Community Chest all trigger
  /// automatically; buying/paying rent/mortgaging stay manual, as always.
  /// A board with no layout behaves exactly as before this feature existed.
  void _handleRollDice(String senderId) {
    if (senderId != _currentTurnId || _turnRolled) return;
    final game = _game!;
    final board = game.board;
    final roll = DiceRoll(
      playerId: senderId,
      die1: _random.nextInt(6) + 1,
      die2: _random.nextInt(6) + 1,
    );
    _lastRoll = roll;

    final player = _players[senderId];
    if (player == null || board.goIndex < 0) {
      // No curated layout: no position tracking, no jail — just the roll.
      _turnRolled = !roll.isDouble;
    } else if (player.inJail) {
      // Jail never grants the doubles-roll-again bonus.
      _resolveJailTurn(player, roll);
      _turnRolled = true;
    } else {
      _movePlayer(player, roll.total);
      // Landing on Go To Jail cancels a doubles bonus roll.
      _turnRolled = !roll.isDouble || _players[senderId]!.inJail;
    }

    _db.setTurnState(
      game.id,
      currentTurnId: _currentTurnId,
      lastRoll: _lastRoll,
      turnRolled: _turnRolled,
      freeParkingPot: _freeParkingPot,
    );
    _broadcast(WsMessage(MessageType.diceRolled, {
      'roll': roll.toJson(),
      'turnRolled': _turnRolled,
      'players': _players.values.map((p) => p.toJson()).toList(),
      'freeParkingPot': _freeParkingPot,
    }));
  }

  /// Advances [player]'s token by [total] squares, auto-pays salary if GO
  /// was passed or landed on exactly, then resolves the landing square.
  void _movePlayer(Player player, int total) {
    final game = _game!;
    final board = game.board;
    final advance = GameEngine.advancePosition(
      squareCount: board.properties.length,
      currentPosition: player.position,
      total: total,
      goIndex: board.goIndex,
    );
    var current = player.copyWith(position: advance.position);
    _players[current.id] = current;

    if (advance.crossedGo && board.salary > 0) {
      final tx = GameTransaction(
        id: const Uuid().v4(),
        gameId: game.id,
        fromId: Player.bankId,
        toId: current.id,
        amount: board.salary * (advance.landedOnGo ? 2 : 1),
        type: TransactionType.salary,
        timestamp: DateTime.now(),
        note: advance.landedOnGo ? 'Landed on GO' : 'Passed GO',
      );
      _applyTransaction(tx, (_) {}); // bank-funded; cannot fail
      current = _players[current.id]!;
    }

    _db.upsertPlayers(game.id, [current]);
    _resolveLanding(current, board.properties[advance.position]);
  }

  /// Auto-effects for the square a token just landed on. Ownable squares
  /// (street/railroad/utility) and plain GO/Jail have no auto-effect —
  /// buying, paying rent, and mortgaging all stay manual and confirmed.
  void _resolveLanding(Player player, Property square) {
    final game = _game!;
    switch (square.kind) {
      case PropertyKind.tax:
        final amount = square.price;
        if (amount <= 0) return;
        final tx = GameTransaction(
          id: const Uuid().v4(),
          gameId: game.id,
          fromId: player.id,
          toId: Player.bankId,
          amount: amount,
          type: TransactionType.tax,
          timestamp: DateTime.now(),
          note: square.name,
        );
        final applied = _applyTransaction(
          tx,
          (reason) => _sendTo(player.id, WsMessage(MessageType.paymentRejected, {
            'txId': tx.id,
            'reason': reason,
          })),
        );
        if (applied) _freeParkingPot += amount;
      case PropertyKind.freeParking:
        if (_freeParkingPot <= 0) return;
        final tx = GameTransaction(
          id: const Uuid().v4(),
          gameId: game.id,
          fromId: Player.bankId,
          toId: player.id,
          amount: _freeParkingPot,
          type: TransactionType.freeParking,
          timestamp: DateTime.now(),
        );
        if (_applyTransaction(tx, (_) {})) _freeParkingPot = 0;
      case PropertyKind.goToJail:
        final jailIndex = game.board.jailIndex;
        if (jailIndex < 0) return;
        final jailed = player.copyWith(
          position: jailIndex,
          inJail: true,
          jailTurns: 0,
        );
        _players[jailed.id] = jailed;
        _db.upsertPlayers(game.id, [jailed]);
      case PropertyKind.chance:
        _drawCardFor(player.id, 'chance');
      case PropertyKind.communityChest:
        _drawCardFor(player.id, 'chest');
      case PropertyKind.street:
      case PropertyKind.railroad:
      case PropertyKind.utility:
      case PropertyKind.go:
      case PropertyKind.jail:
        break;
    }
  }

  /// Resolves one roll attempted from jail: doubles escape free and move;
  /// the 3rd failed attempt forces paying the fine and moves anyway.
  void _resolveJailTurn(Player player, DiceRoll roll) {
    final game = _game!;
    final outcome = GameEngine.resolveJailRoll(
      jailTurns: player.jailTurns,
      isDouble: roll.isDouble,
    );
    switch (outcome) {
      case JailRollOutcome.stillStuck:
        final stuck = player.copyWith(jailTurns: player.jailTurns + 1);
        _players[stuck.id] = stuck;
        _db.upsertPlayers(game.id, [stuck]);
      case JailRollOutcome.escaped:
        final freed = player.copyWith(inJail: false, jailTurns: 0);
        _players[freed.id] = freed;
        _movePlayer(freed, roll.total);
      case JailRollOutcome.mustPayNow:
        final freed = player.copyWith(inJail: false, jailTurns: 0);
        _players[freed.id] = freed;
        final tx = GameTransaction(
          id: const Uuid().v4(),
          gameId: game.id,
          fromId: freed.id,
          toId: Player.bankId,
          amount: game.board.jailFine,
          type: TransactionType.tax,
          timestamp: DateTime.now(),
          note: 'Jail fine',
        );
        final applied = _applyTransaction(
          tx,
          (reason) => _sendTo(freed.id, WsMessage(MessageType.paymentRejected, {
            'txId': tx.id,
            'reason': reason,
          })),
        );
        if (applied) _freeParkingPot += game.board.jailFine;
        _movePlayer(_players[freed.id]!, roll.total);
    }
  }

  void _handlePayJailFine(
    String senderId,
    WebSocketChannel channel,
    Map<String, dynamic> payload,
  ) {
    final txId = payload['id'] as String?;
    final reject = _prepareIntent(senderId, channel, txId);
    if (reject == null) return;

    final player = _players[senderId]!;
    if (senderId != _currentTurnId || !player.inJail || _turnRolled) {
      reject("You're not stuck in jail right now.");
      return;
    }

    final game = _game!;
    // Clear the jail state first so the transaction's single broadcast
    // already carries the freed player, rather than a second broadcast.
    _players[senderId] = player.copyWith(inJail: false, jailTurns: 0);

    final tx = GameTransaction(
      id: txId!,
      gameId: game.id,
      fromId: senderId,
      toId: Player.bankId,
      amount: game.board.jailFine,
      type: TransactionType.tax,
      timestamp: DateTime.now(),
      note: 'Jail fine',
    );
    if (!_applyTransaction(tx, reject)) {
      _players[senderId] = player; // roll back — the fine wasn't paid
      return;
    }
    _freeParkingPot += game.board.jailFine;
    _db.setTurnState(
      game.id,
      currentTurnId: _currentTurnId,
      lastRoll: _lastRoll,
      turnRolled: _turnRolled,
      freeParkingPot: _freeParkingPot,
    );
  }

  /// Draws a random card from the board's deck, shows it to the whole
  /// table and applies its effect — either a bank transaction or, for a
  /// "go to X" card, moving the drawer's token and resolving whatever's
  /// there (same as landing on it normally). Called both for a manual
  /// Chance/Chest quick action and for auto-landing on one.
  void _drawCardFor(String playerId, String deck) {
    final game = _game!;
    final board = game.board;
    final cards =
        deck == 'chest' ? board.communityChestCards : board.chanceCards;
    if (cards.isEmpty) return;
    final card = cards[_random.nextInt(cards.length)];

    // Move first so the broadcast below already carries the new position.
    // Only meaningful on a board with a curated layout — elsewhere there is
    // no position to move, so the card is shown with no further effect.
    final moveTarget = card.moveToPropertyId;
    if (moveTarget != null && board.goIndex >= 0) {
      final targetIndex =
          board.properties.indexWhere((p) => p.id == moveTarget);
      final mover = _players[playerId];
      if (targetIndex >= 0 && mover != null && !mover.inJail) {
        final total =
            (targetIndex - mover.position) % board.properties.length;
        _movePlayer(mover, total);
      }
    }

    _broadcast(WsMessage(MessageType.cardDrawn, {
      'playerId': playerId,
      'deck': deck,
      'card': card.toJson(),
      'players': _players.values.map((p) => p.toJson()).toList(),
    }));

    if (card.amount == 0) return;
    final tx = GameTransaction(
      id: const Uuid().v4(),
      gameId: game.id,
      fromId: card.amount > 0 ? Player.bankId : playerId,
      toId: card.amount > 0 ? playerId : Player.bankId,
      amount: card.amount.abs(),
      type: TransactionType.card,
      timestamp: DateTime.now(),
      note: card.text,
    );
    _applyTransaction(
      tx,
      (reason) => _sendTo(
        playerId,
        WsMessage(MessageType.paymentRejected, {
          'txId': tx.id,
          'reason': reason,
        }),
      ),
    );
  }

  /// Draws a card for the current player's manual Chance/Chest quick
  /// action (boards without a layout only have this manual path).
  void _handleDrawCard(String senderId, Map<String, dynamic> payload) {
    if (_game == null || senderId != _currentTurnId) return;
    _drawCardFor(senderId, payload['deck'] as String? ?? 'chance');
  }

  void _handleEndTurn(String senderId, WebSocketChannel channel) {
    // A turn is: roll, act, end. No ending a turn without having rolled.
    if (senderId != _currentTurnId || !_turnRolled) return;
    _advanceTurn();
  }

  void _advanceTurn() {
    final game = _game;
    if (game == null) return;
    _currentTurnId =
        GameEngine.nextTurn(_players.values.toList(), _currentTurnId);
    _turnRolled = false;
    _db.setTurnState(
      game.id,
      currentTurnId: _currentTurnId,
      lastRoll: _lastRoll,
      turnRolled: false,
      freeParkingPot: _freeParkingPot,
    );
    _broadcast(WsMessage(MessageType.turnChanged, {
      'playerId': _currentTurnId,
    }));
  }

  void _handleLeave(String playerId) {
    final game = _game;
    final player = _players[playerId];
    if (game == null || player == null) return;

    final left = player.copyWith(hasLeft: true, isOnline: false);
    _players[playerId] = left;
    _db.upsertPlayers(game.id, [left]);

    _connections.remove(playerId)?.sink.close();
    _broadcast(WsMessage(MessageType.playerLeft, {'playerId': playerId}));

    if (_currentTurnId == playerId) _advanceTurn();
  }

  void _handleDisconnect(String playerId, WebSocketChannel channel) {
    // Ignore if the identity has already reconnected on a newer channel.
    if (_connections[playerId] != channel) return;
    _connections.remove(playerId);

    final game = _game;
    final player = _players[playerId];
    if (game == null || player == null || player.hasLeft) return;

    final offline = player.copyWith(isOnline: false);
    _players[playerId] = offline;
    _db.upsertPlayers(game.id, [offline]);

    _broadcast(WsMessage(MessageType.presenceChanged, {
      'player': offline.toJson(),
    }));
  }

  GameSnapshot _snapshot() => GameSnapshot(
        game: _game!,
        players: _players.values.toList(),
        transactions: List.of(_transactions),
        ownerships: _ownerships.values.toList(),
        currentTurnId: _currentTurnId,
        lastRoll: _lastRoll,
        turnRolled: _turnRolled,
        freeParkingPot: _freeParkingPot,
        auctions: _auctions.values.toList(),
      );

  void _send(WebSocketChannel channel, WsMessage message) =>
      channel.sink.add(message.encode());

  void _sendTo(String playerId, WsMessage message) {
    final channel = _connections[playerId];
    if (channel != null) _send(channel, message);
  }

  void _broadcast(WsMessage message, {String? except}) {
    final encoded = message.encode();
    for (final entry in _connections.entries) {
      if (entry.key == except) continue;
      entry.value.sink.add(encoded);
    }
  }
}
