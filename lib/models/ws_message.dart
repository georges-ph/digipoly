import 'dart:convert';

/// Every websocket frame is one JSON-encoded [WsMessage]:
/// `{"type": "...", "payload": {...}}`.
///
/// Clients send *intents* (join, pay, leave); the server validates, applies
/// them to the authoritative state and broadcasts the resulting *events* to
/// everyone — including the sender. Clients only ever mutate local state in
/// response to a server event.
enum MessageType {
  // Client -> server intents.
  joinRequest,
  paymentIntent,
  buyProperty,
  payRent,
  setHouses,
  mortgage,
  transferProperty,
  moneyRequest,
  moneyRequestResponse,
  rollDice,
  drawCard,
  endTurn,
  leaveGame,
  editTransactionNote,
  payJailFine,
  useJailCard,
  transferJailCard,
  takeLoan,
  repayLoan,
  startAuction,
  placeBid,
  closeAuction,
  dismissRoll,
  kickPlayer,

  // Server -> client events.
  joinAccepted,
  joinRejected,
  snapshot,
  paymentApplied,
  paymentRejected,
  propertyChanged,
  transactionNoteUpdated,
  moneyRequested,
  moneyRequestResolved,
  jailCardUsed,
  jailCardTransferred,
  diceRolled,
  cardDrawn,
  turnChanged,
  playerJoined,
  playerLeft,
  presenceChanged,
  gameClosed,
  auctionStarted,
  auctionBid,
  auctionClosed,
  auctionRejected,
  rollDismissed,
  kicked,
  unknown;

  static MessageType fromName(String name) => MessageType.values.firstWhere(
        (type) => type.name == name,
        orElse: () => MessageType.unknown,
      );
}

class WsMessage {
  const WsMessage(this.type, [this.payload = const {}]);

  final MessageType type;
  final Map<String, dynamic> payload;

  String encode() => jsonEncode({'type': type.name, 'payload': payload});

  factory WsMessage.decode(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return WsMessage(
        MessageType.fromName(json['type'] as String? ?? ''),
        json['payload'] as Map<String, dynamic>? ?? const {},
      );
    } catch (_) {
      return const WsMessage(MessageType.unknown);
    }
  }
}
