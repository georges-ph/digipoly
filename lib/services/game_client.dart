import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/result.dart';
import '../models/ws_message.dart';

enum ClientStatus { disconnected, connecting, connected }

/// The device's connection to a game server. Only transport lives here:
/// connect, send intents, surface incoming messages as a stream. What the
/// messages *mean* is the provider's business.
class GameClient {
  WebSocketChannel? _channel;
  ClientStatus _status = ClientStatus.disconnected;

  final _messages = StreamController<WsMessage>.broadcast();
  final _statusChanges = StreamController<ClientStatus>.broadcast();

  Stream<WsMessage> get messages => _messages.stream;
  Stream<ClientStatus> get statusChanges => _statusChanges.stream;
  ClientStatus get status => _status;

  Future<Result<void>> connect({
    required String host,
    required int port,
    required String playerId,
    required String playerName,
    bool spectator = false,
  }) async {
    await disconnect();
    _setStatus(ClientStatus.connecting);

    try {
      final channel = WebSocketChannel.connect(
        Uri(scheme: 'ws', host: host, port: port),
      );
      await channel.ready.timeout(const Duration(seconds: 8));

      _channel = channel;
      channel.stream.listen(
        (raw) {
          if (raw is String && !_messages.isClosed) {
            _messages.add(WsMessage.decode(raw));
          }
        },
        onDone: () => _handleClosed(channel),
        onError: (_) => _handleClosed(channel),
        cancelOnError: false,
      );

      send(WsMessage(MessageType.joinRequest, {
        'playerId': playerId,
        'name': playerName,
        if (spectator) 'spectator': true,
      }));
      _setStatus(ClientStatus.connected);
      return ok(null);
    } on TimeoutException {
      _setStatus(ClientStatus.disconnected);
      return err('Connection timed out. Is the host on the same network?');
    } catch (_) {
      _setStatus(ClientStatus.disconnected);
      return err('Could not reach the host.');
    }
  }

  void send(WsMessage message) => _channel?.sink.add(message.encode());

  /// Sends a payment intent and returns its transaction id, so the caller
  /// can match the server's paymentApplied / paymentRejected answer.
  /// [requestId] links the payment to a money request it settles.
  String sendPayment({
    required String fromId,
    required String toId,
    required int amount,
    String note = '',
    String? requestId,
  }) {
    final txId = const Uuid().v4();
    send(WsMessage(MessageType.paymentIntent, {
      'id': txId,
      'fromId': fromId,
      'toId': toId,
      'amount': amount,
      'note': note,
      'requestId': ?requestId,
    }));
    return txId;
  }

  String sendBuyProperty(String propertyId, {int? price}) {
    final txId = const Uuid().v4();
    send(WsMessage(MessageType.buyProperty, {
      'id': txId,
      'propertyId': propertyId,
      'price': ?price,
    }));
    return txId;
  }

  String sendPayRent(String propertyId, {int? diceTotal, String? payerId}) {
    final txId = const Uuid().v4();
    send(WsMessage(MessageType.payRent, {
      'id': txId,
      'propertyId': propertyId,
      'diceTotal': ?diceTotal,
      'payerId': ?payerId,
    }));
    return txId;
  }

  String sendMortgage(String propertyId, {required bool mortgage}) {
    final txId = const Uuid().v4();
    send(WsMessage(MessageType.mortgage, {
      'id': txId,
      'propertyId': propertyId,
      'mortgage': mortgage,
    }));
    return txId;
  }

  String sendTransferProperty(String propertyId, String toId) {
    final txId = const Uuid().v4();
    send(WsMessage(MessageType.transferProperty, {
      'id': txId,
      'propertyId': propertyId,
      'toId': toId,
    }));
    return txId;
  }

  String sendSetHouses(String propertyId, int houses) {
    final txId = const Uuid().v4();
    send(WsMessage(MessageType.setHouses, {
      'id': txId,
      'propertyId': propertyId,
      'houses': houses,
    }));
    return txId;
  }

  String sendMoneyRequest({
    required String targetId,
    required int amount,
    String note = '',
  }) {
    final requestId = const Uuid().v4();
    send(WsMessage(MessageType.moneyRequest, {
      'requestId': requestId,
      'targetId': targetId,
      'amount': amount,
      'note': note,
    }));
    return requestId;
  }

  void sendDeclineRequest(String requestId) =>
      send(WsMessage(MessageType.moneyRequestResponse, {
        'requestId': requestId,
        'accept': false,
      }));

  void sendRollDice() => send(const WsMessage(MessageType.rollDice));

  /// [deck] is 'chance' or 'chest'.
  void sendDrawCard(String deck) =>
      send(WsMessage(MessageType.drawCard, {'deck': deck}));

  /// Edits an existing transaction's note (the amount and parties never
  /// change). [transactionId] is the ledger entry being edited.
  String sendEditTransactionNote(String transactionId, String note) {
    final txId = const Uuid().v4();
    send(WsMessage(MessageType.editTransactionNote, {
      'id': txId,
      'transactionId': transactionId,
      'note': note,
    }));
    return txId;
  }

  /// Pays the jail fine to leave immediately, before rolling.
  String sendPayJailFine() {
    final txId = const Uuid().v4();
    send(WsMessage(MessageType.payJailFine, {'id': txId}));
    return txId;
  }

  /// Uses a held Get Out of Jail Free card to leave immediately, before
  /// rolling — no fine, no roll.
  String sendUseJailCard() {
    final txId = const Uuid().v4();
    send(WsMessage(MessageType.useJailCard, {'id': txId}));
    return txId;
  }

  /// Starts a live auction for an unowned property. Not turn-gated —
  /// auctions arise on other players' turns, same as the old bid-after-the-
  /// fact flow.
  void sendStartAuction(String propertyId) =>
      send(WsMessage(MessageType.startAuction, {'propertyId': propertyId}));

  void sendPlaceBid(String propertyId, int amount) =>
      send(WsMessage(MessageType.placeBid, {
        'propertyId': propertyId,
        'amount': amount,
      }));

  /// Anyone can close a running auction — sells to the top bidder, or
  /// cancels if nobody bid.
  void sendCloseAuction(String propertyId) =>
      send(WsMessage(MessageType.closeAuction, {'propertyId': propertyId}));

  void sendEndTurn() => send(const WsMessage(MessageType.endTurn));

  void sendLeave() => send(const WsMessage(MessageType.leaveGame));

  /// Host-only: removes another player from the game — same effect as
  /// that player leaving themselves (balance/properties stay exactly as
  /// they were), just triggered by the host instead.
  void sendKickPlayer(String playerId) =>
      send(WsMessage(MessageType.kickPlayer, {'playerId': playerId}));

  /// Tells the table it's fine to reveal a Chance/Community Chest card this
  /// device just drew — sent right as its own copy of that card's dialog is
  /// about to show.
  void sendDismissRoll() => send(const WsMessage(MessageType.dismissRoll));

  void _handleClosed(WebSocketChannel channel) {
    if (_channel != channel) return;
    _channel = null;
    _setStatus(ClientStatus.disconnected);
  }

  Future<void> disconnect() async {
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
    if (channel != null) _setStatus(ClientStatus.disconnected);
  }

  void _setStatus(ClientStatus status) {
    if (_status == status || _statusChanges.isClosed) return;
    _status = status;
    _statusChanges.add(status);
  }

  void dispose() {
    disconnect();
    _messages.close();
    _statusChanges.close();
  }
}
