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
import '../models/property_auction.dart';
import '../models/property_ownership.dart';
import '../models/result.dart';
import '../models/ws_message.dart';
import '../services/database_service.dart';
import '../services/discovery_service.dart';
import '../services/game_client.dart';
import '../services/game_server.dart';
import '../services/identity_service.dart';

typedef CardDrawEvent = ({
  String playerId,
  // Identifies this specific draw, not just who drew it — the same player
  // can draw more than once in a turn, so this is what the dismissRoll
  // reveal-ordering handshake actually waits on (see dismissRoll below).
  String drawId,
  String deck,
  BoardCard card,
  // The actual amount charged/paid for a "pay per building" repairs card
  // (computed server-side from the drawer's buildings) — null for every
  // other card, which can be read straight off card.amount instead.
  int? chargedAmount,
});

typedef PropertyTransferEvent = ({
  String propertyId,
  String fromId,
  String toId,
});

typedef BankCollectionEvent = ({String playerId, int amount});

typedef PaymentReceivedEvent = ({String fromId, int amount, bool isRent});

typedef PropertyPurchaseEvent = ({
  String playerId,
  String propertyId,
  int amount,
});

typedef AuctionStartEvent = ({String propertyId, String startedBy});

typedef JailEvent = ({String playerId});

/// Any other money-moving transaction type not already covered by a more
/// specific event above (salary, houses, mortgage, tax, Free Parking) —
/// carries the whole transaction since the right icon/copy depends on its
/// type the same way `TransactionTile` already works it out.
typedef OtherTransactionEvent = ({GameTransaction tx});

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
  }) : _db = database,
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
  final Map<String, PropertyAuction> _auctions = {};
  String? _currentTurnId;
  DiceRoll? _lastRoll;
  bool _turnRolled = false;
  int _freeParkingPot = 0;
  MoneyRequest? _incomingRequest;
  ClientStatus _connection = ClientStatus.disconnected;
  bool _hostEnded = false;
  bool _kicked = false;
  bool _closing = false;
  bool _disposed = false;
  Timer? _reconnectTimer;

  /// Watching a room read-only (e.g. a TV running the dashboard) — never a
  /// seat, never persisted to this device's games list.
  bool _spectating = false;

  Completer<Result<void>>? _pendingJoin;
  Completer<Result<void>>? _pendingRoll;
  final Map<String, Completer<Result<void>>> _pendingPayments = {};
  final Map<String, Completer<Result<void>>> _pendingRequests = {};

  /// Where a fresh join is headed, so the record can be built once the
  /// server accepts us and sends the game.
  ({String host, int port})? _joinTarget;

  /// Set for the duration of a claim join (see [joinRoom]) — the existing
  /// player id this device is taking over, instead of its own identity.
  /// Only needed to bridge the gap before [_record] exists; once it does,
  /// `_record.myPlayerId` already carries the same value forward.
  String? _claimPlayerId;

  final _errors = StreamController<String>.broadcast();
  final _cardDraws = StreamController<CardDrawEvent>.broadcast();
  final _diceRolls = StreamController<DiceRoll>.broadcast();
  final _propertyTransfers =
      StreamController<PropertyTransferEvent>.broadcast();
  final _bankCollections = StreamController<BankCollectionEvent>.broadcast();
  final _bankPayments = StreamController<BankCollectionEvent>.broadcast();
  final _paymentsReceived = StreamController<PaymentReceivedEvent>.broadcast();
  final _propertyPurchases =
      StreamController<PropertyPurchaseEvent>.broadcast();
  final _auctionStarts = StreamController<AuctionStartEvent>.broadcast();
  final _playerJoins = StreamController<Player>.broadcast();
  final _jailEntries = StreamController<JailEvent>.broadcast();
  final _otherTransactions =
      StreamController<OtherTransactionEvent>.broadcast();
  final _rollDismissals = StreamController<String>.broadcast();

  /// Every drawId a `rollDismissed` broadcast has already arrived for.
  /// `rollDismissals` alone isn't enough to wait on: it's a live stream, so
  /// a listener that starts even slightly after the matching event already
  /// fired would miss it entirely and stall on the fallback timeout (this
  /// bit hard the first time — a spam-drawn burst of cards sends several
  /// dismissRoll signals in quick succession, easily ahead of a receiving
  /// device's queue getting around to listening for any one of them). This
  /// set lets a would-be listener check "did this already happen?" first.
  final Set<String> _dismissedDraws = {};
  String? _outgoingRequestId;

  // ------------------------------------------------------------- Getters

  /// Transient error messages for snackbars (rejected payments, etc.).
  Stream<String> get errors => _errors.stream;

  /// Cards drawn at the table — every device shows them.
  Stream<CardDrawEvent> get cardDraws => _cardDraws.stream;

  /// Every dice roll anyone makes — every device sees it, so the board can
  /// pop up automatically wherever players are looking.
  Stream<DiceRoll> get diceRolls => _diceRolls.stream;

  /// Fires with a draw's id the moment *the drawer's own* device is about
  /// to show its copy of that card — lets everyone else's reveal of that
  /// same draw wait for that instead of guessing how long it takes someone
  /// to look at their own dice result first. Keyed by drawId rather than
  /// playerId since the same player can draw more than once in a turn.
  /// Check [wasDismissed] before waiting on this — see its own doc.
  Stream<String> get rollDismissals => _rollDismissals.stream;

  /// Whether a `rollDismissed` signal for [drawId] has already arrived —
  /// check this before waiting on [rollDismissals] for it, since the
  /// stream itself won't replay an event that already fired.
  bool wasDismissed(String drawId) => _dismissedDraws.contains(drawId);

  /// Every property handed from one player to another — the recipient's
  /// device uses this to pop up a "you were given X" notice.
  Stream<PropertyTransferEvent> get propertyTransfers =>
      _propertyTransfers.stream;

  /// Every free-form "Collect from bank" payment — anyone can trigger a
  /// bank payout, so this is what lets the rest of the table actually
  /// notice it happened instead of finding out later in the activity feed.
  Stream<BankCollectionEvent> get bankCollections => _bankCollections.stream;

  /// The reverse: a free-form payment sent *to* the bank (paying it back,
  /// covering something manually). Same reasoning as [bankCollections] —
  /// otherwise it only shows up later in the activity feed.
  Stream<BankCollectionEvent> get bankPayments => _bankPayments.stream;

  /// A direct payment or rent landing in my account (not a settled money
  /// request — that already has its own resolution UI, and not a card or
  /// transfer, which already pop their own dialog for everyone involved).
  Stream<PaymentReceivedEvent> get paymentsReceived => _paymentsReceived.stream;

  /// Someone bought a property (not an auction win, not me) — the rest of
  /// the table only otherwise learns this from the properties list/board
  /// updating quietly, so it's worth flagging like a bank collection or an
  /// incoming payment is.
  Stream<PropertyPurchaseEvent> get propertyPurchases =>
      _propertyPurchases.stream;

  /// A live auction just opened — everyone already sees the running
  /// `AuctionCard` once it exists, but nothing else calls out that it just
  /// started, so anyone not already looking at that spot would miss it.
  Stream<AuctionStartEvent> get auctionStarts => _auctionStarts.stream;

  /// A new player took a seat — a genuinely new join, not a reconnect (the
  /// server tells the two apart itself), so an already-known player coming
  /// back online doesn't re-announce itself as if they just joined.
  Stream<Player> get playerJoins => _playerJoins.stream;

  /// Someone's token just landed them in jail (a Go To Jail square, or a
  /// card that moves them onto one) — surfaced the same way any other
  /// landing effect worth a heads-up is.
  Stream<JailEvent> get jailEntries => _jailEntries.stream;

  /// Salary, houses, mortgage, tax and Free Parking — every money-moving
  /// transaction type that doesn't already have its own richer notice
  /// above, for whoever the transaction actually happened to (never fired
  /// for my own).
  Stream<OtherTransactionEvent> get otherTransactions =>
      _otherTransactions.stream;

  bool get hasActiveSession => _record != null && _client != null;
  GameRecord? get record => _record;
  Game? get game => _record?.game;
  ClientStatus get connection => _connection;
  bool get hostEnded => _hostEnded;

  /// The host removed me from this game — same idea as [hostEnded], just
  /// targeted at me specifically rather than the whole room closing.
  bool get kicked => _kicked;
  bool get isHost => _record?.role == GameRole.host;

  /// Normally this device's own permanent identity — but a claimed seat
  /// (see [joinRoom]'s `claimPlayerId`) plays as someone else's existing
  /// player id for this one game, so this game's record is the source of
  /// truth once it exists.
  String get myPlayerId => _record?.myPlayerId ?? _identity.playerId;

  /// Watching read-only — no seat, no balance, not part of the rotation.
  bool get isSpectating => _spectating;

  /// Whether incoming events should be cached to this device's local DB —
  /// the host already persisted them, and a spectator session isn't a game
  /// this device belongs to, so neither writes anything locally.
  bool get _persistLocally => !isHost && !_spectating;

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
  List<Player> get otherActivePlayers =>
      players.where((p) => p.id != myPlayerId && !p.hasLeft).toList();

  /// Newest first, for activity feeds.
  List<GameTransaction> get transactions => _transactions.reversed.toList();

  Map<String, PropertyOwnership> get ownerships =>
      Map.unmodifiable(_ownerships);

  PropertyOwnership? ownershipOf(String propertyId) => _ownerships[propertyId];

  /// Auctions currently running at the table, keyed by property id.
  Map<String, PropertyAuction> get auctions => Map.unmodifiable(_auctions);

  PropertyAuction? auctionFor(String propertyId) => _auctions[propertyId];

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
  bool get canResolve => _connection == ClientStatus.connected && isMyTurn;

  /// Accumulated Free Parking pot (0 on boards without a curated layout).
  int get freeParkingPot => _freeParkingPot;

  /// Whether I can pay my way out of jail right now — my turn, in jail,
  /// before rolling.
  bool get canPayJailFine =>
      _connection == ClientStatus.connected &&
      isMyTurn &&
      !_turnRolled &&
      me?.inJail == true;

  /// Whether I can use a held Get Out of Jail Free card right now — my
  /// turn, in jail, before rolling, and I actually have one.
  bool get canUseJailCard =>
      _connection == ClientStatus.connected &&
      isMyTurn &&
      !_turnRolled &&
      me?.inJail == true &&
      (me?.jailCards ?? 0) > 0;

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
        freeParkingPot: turnState.freeParkingPot,
      );
    }

    // Load this device's last-known cache first so the screen has real
    // data to show right away — and, if the host can't be reached, keeps
    // showing it instead of going blank. A fresh snapshot (once/if the
    // connection succeeds) replaces it wholesale, same as it always has.
    _record = record;
    _players = await _db.getPlayers(record.game.id);
    _transactions = await _db.getTransactions(record.game.id);
    _ownerships
      ..clear()
      ..addEntries(
        (await _db.getOwnerships(
          record.game.id,
        )).map((o) => MapEntry(o.propertyId, o)),
      );
    final turnState = await _db.getTurnState(record.game.id);
    _currentTurnId = turnState.currentTurnId;
    _lastRoll = turnState.lastRoll;
    _turnRolled = turnState.turnRolled;
    _freeParkingPot = turnState.freeParkingPot;
    notifyListeners();

    final host = record.hostAddress;
    final port = record.hostPort;
    if (host == null || port == null) {
      return err('No known address for this game. Join it from Discover.');
    }
    return _connect(host, port);
  }

  /// Joins a room found via discovery or a manually typed address.
  /// [claimPlayerId] takes over an existing (kicked/left) player's seat —
  /// their balance and properties — instead of joining as a brand-new
  /// player; see the host's "Replace this player" flow.
  Future<Result<void>> joinRoom({
    required String host,
    required int port,
    String? claimPlayerId,
  }) async {
    await closeSession();
    _joinTarget = (host: host, port: port);
    _claimPlayerId = claimPlayerId;
    return _connect(host, port);
  }

  /// Watches a room read-only — no seat, no balance, never part of the
  /// turn rotation, and never saved to this device's games list. Meant for
  /// a spare screen (a TV) running just the dashboard.
  Future<Result<void>> watchRoom({
    required String host,
    required int port,
  }) async {
    await closeSession();
    _joinTarget = (host: host, port: port);
    return _connect(host, port, spectator: true);
  }

  Future<Result<void>> _startHosting({
    required Game game,
    required List<Player> players,
    required List<GameTransaction> transactions,
    List<PropertyOwnership> ownerships = const [],
    String? currentTurnId,
    DiceRoll? lastRoll,
    bool turnRolled = false,
    int freeParkingPot = 0,
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
      freeParkingPot: freeParkingPot,
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

  Future<Result<void>> _connect(
    String host,
    int port, {
    bool spectator = false,
  }) async {
    _hostEnded = false;
    _kicked = false;
    _closing = false;
    _spectating = spectator;

    _messageSub?.cancel();
    _statusSub?.cancel();
    _client?.dispose();

    final client = GameClient();
    _client = client;
    _messageSub = client.messages.listen(_onMessage);
    _statusSub = client.statusChanges.listen(_onStatus);
    notifyListeners();

    // A fresh claim join sends the seat being taken over; once the record
    // exists (this connect is a reconnect), its own myPlayerId already
    // carries whichever identity — own or claimed — this game plays as.
    final connected = await client.connect(
      host: host,
      port: port,
      playerId: _claimPlayerId ?? _record?.myPlayerId ?? _identity.playerId,
      playerName: _identity.displayName,
      spectator: spectator,
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

  /// Host-only: removes another player, freeing their seat for someone
  /// else to claim (see [joinRoom]'s `claimPlayerId`). Their balance and
  /// properties stay exactly as they were — same as if they'd left
  /// themselves. Fire-and-forget, like other host-side moderation would be;
  /// the server enforces that only the host can do this.
  void kickPlayer(String playerId) => _client?.sendKickPlayer(playerId);

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
    _auctions.clear();
    _dismissedDraws.clear();
    _currentTurnId = null;
    _lastRoll = null;
    _turnRolled = false;
    _incomingRequest = null;
    _connection = ClientStatus.disconnected;
    _joinTarget = null;
    _claimPlayerId = null;
    _spectating = false;
    _pendingJoin = null;
    _pendingRoll = null;
    _pendingPayments.clear();
    _pendingRequests.clear();
    _closing = false;
    _hostEnded = false;
    _kicked = false;
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
  Future<Result<void>> collectSalary({bool landedOnGo = false}) => sendPayment(
    fromId: Player.bankId,
    toId: myPlayerId,
    amount: (game?.board.salary ?? 0) * (landedOnGo ? 2 : 1),
    note: landedOnGo ? 'Landed on GO' : 'Passed GO',
  );

  /// Edits a past transaction's note. Only the note changes — amount and
  /// parties are fixed once a transaction is booked.
  Future<Result<void>> editTransactionNote(String transactionId, String note) {
    final offline = _requireConnection();
    if (offline != null) return Future.value(offline);
    return _awaitVerdict(
      _client!.sendEditTransactionNote(transactionId, note),
    );
  }

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

  /// Starts a live, table-held auction for an unowned property. Anyone can
  /// start one and everyone connected sees the bidding live — not gated to
  /// your turn, since auctions arise on other players' turns.
  void startAuction(String propertyId) {
    if (_connection == ClientStatus.connected) {
      _client?.sendStartAuction(propertyId);
    }
  }

  /// Raises the bid on a running auction. No turn order — anyone can raise
  /// anytime, as long as it beats the current bid.
  void placeBid(String propertyId, int amount) {
    if (_connection == ClientStatus.connected) {
      _client?.sendPlaceBid(propertyId, amount);
    }
  }

  /// Closes a running auction — anyone can, not just whoever started it.
  /// Sells to the current top bidder at their bid, or cancels if nobody
  /// bid.
  void closeAuction(String propertyId) {
    if (_connection == ClientStatus.connected) {
      _client?.sendCloseAuction(propertyId);
    }
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
      return Future.value(
        err(
          _turnRolled ? 'You already rolled this turn.' : "It's not your turn.",
        ),
      );
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

  /// Tells the table it's fine to reveal a Chance/Community Chest card I
  /// just drew — sent right as my own copy of that card's dialog is about
  /// to show, whether that draw came from landing on a roll (by then queued
  /// behind my own dice sheet already closing) or a manual quick action
  /// (nothing to queue behind, so effectively immediate). [drawId] ties
  /// this signal to that specific draw — I can draw more than once in a
  /// turn, and a bare playerId can't tell those apart. Fire-and-forget,
  /// like rollDice/drawCard: nothing is waiting on a reply.
  void dismissRoll(String drawId) => _client?.sendDismissRoll(drawId);

  /// Ends my turn; the server advances the rotation. Only allowed after
  /// rolling — a turn is roll, act, end.
  void endTurn() {
    if (canEndTurn) _client?.sendEndTurn();
  }

  /// Pays my way out of jail immediately, before rolling. Rolling doubles
  /// instead (via [rollDice]) escapes for free.
  Future<Result<void>> payJailFine() {
    if (!canPayJailFine) {
      return Future.value(err("You're not stuck in jail right now."));
    }
    final offline = _requireConnection();
    if (offline != null) return Future.value(offline);
    return _awaitVerdict(_client!.sendPayJailFine());
  }

  /// Uses a held Get Out of Jail Free card to leave immediately, before
  /// rolling — no fine, no roll.
  Future<Result<void>> useJailCard() {
    if (!canUseJailCard) {
      return Future.value(err("You don't have a Get Out of Jail Free card."));
    }
    final offline = _requireConnection();
    if (offline != null) return Future.value(offline);
    return _awaitVerdict(_client!.sendUseJailCard());
  }

  // ------------------------------------------------------- Incoming events

  void _onMessage(WsMessage message) {
    switch (message.type) {
      case MessageType.joinAccepted:
      case MessageType.snapshot:
        _applySnapshot(message.payload);
      case MessageType.joinRejected:
        final reason = message.payload['reason'] as String? ?? 'Join rejected.';
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
          if (record != null && _persistLocally) {
            _db.upsertOwnerships(record.game.id, [ownership]);
          }
          final txJson =
              message.payload['transaction'] as Map<String, dynamic>?;
          if (txJson != null) {
            final tx = GameTransaction.fromJson(txJson);
            if (!_transactions.any((t) => t.id == tx.id)) {
              _transactions.add(tx);
              if (record != null && _persistLocally) {
                _db.insertTransactions(record.game.id, [tx]);
              }
            }
            _propertyTransfers.add((
              propertyId: tx.propertyId ?? ownership.propertyId,
              fromId: tx.fromId,
              toId: tx.toId,
            ));
          }
          notifyListeners();
        }
      case MessageType.transactionNoteUpdated:
        final txId = message.payload['txId'] as String?;
        _pendingPayments.remove(txId)?.complete(ok(null));
        final json = message.payload['transaction'] as Map<String, dynamic>?;
        if (json != null) {
          final updated = GameTransaction.fromJson(json);
          final index = _transactions.indexWhere((t) => t.id == updated.id);
          if (index != -1) {
            _transactions[index] = updated;
            final record = _record;
            if (record != null && _persistLocally) {
              _db.insertTransactions(record.game.id, [updated]);
            }
            notifyListeners();
          }
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
      case MessageType.jailCardUsed:
        // Moves no money, so this resolves the pending intent itself
        // (carries the intent's txId) instead of via paymentApplied.
        _pendingPayments
            .remove(message.payload['txId'] as String?)
            ?.complete(ok(null));
        final json = message.payload['player'] as Map<String, dynamic>?;
        if (json != null) _upsertPlayer(Player.fromJson(json));
      case MessageType.cardDrawn:
        final cardJson = message.payload['card'] as Map<String, dynamic>?;
        final drawerId = message.payload['playerId'] as String?;
        // A "go to X" card moves the drawer's token — the broadcast carries
        // the resulting player list so every device's board stays in sync,
        // same as a dice roll.
        final playersJson = message.payload['players'] as List<dynamic>?;
        if (playersJson != null) {
          final updated = playersJson
              .map((e) => Player.fromJson(e as Map<String, dynamic>))
              .toList();
          _emitNewJailEntries(_players, updated);
          _players = updated;
          final record = _record;
          if (record != null && _persistLocally) {
            _db.upsertPlayers(record.game.id, _players);
          }
        }
        if (cardJson != null && drawerId != null) {
          _cardDraws.add((
            playerId: drawerId,
            drawId: message.payload['drawId'] as String? ?? '',
            deck: message.payload['deck'] as String? ?? 'chance',
            card: BoardCard.fromJson(cardJson),
            chargedAmount: message.payload['chargedAmount'] as int?,
          ));
        }
        notifyListeners();
      case MessageType.diceRolled:
        final json = message.payload['roll'] as Map<String, dynamic>?;
        if (json != null) {
          _lastRoll = DiceRoll.fromJson(json);
          _diceRolls.add(_lastRoll!);
          _turnRolled = message.payload['turnRolled'] as bool? ?? true;
          _freeParkingPot =
              message.payload['freeParkingPot'] as int? ?? _freeParkingPot;
          final playersJson = message.payload['players'] as List<dynamic>?;
          if (playersJson != null) {
            final updated = playersJson
                .map((e) => Player.fromJson(e as Map<String, dynamic>))
                .toList();
            _emitNewJailEntries(_players, updated);
            _players = updated;
          }
          final record = _record;
          if (record != null && _persistLocally) {
            _db.upsertPlayers(record.game.id, _players);
            _db.setTurnState(
              record.game.id,
              currentTurnId: _currentTurnId,
              lastRoll: _lastRoll,
              turnRolled: _turnRolled,
              freeParkingPot: _freeParkingPot,
            );
          }
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
        if (record != null && _persistLocally) {
          _db.setTurnState(
            record.game.id,
            currentTurnId: _currentTurnId,
            lastRoll: _lastRoll,
            turnRolled: false,
            freeParkingPot: _freeParkingPot,
          );
        }
        notifyListeners();
      case MessageType.playerJoined:
        final json = message.payload['player'] as Map<String, dynamic>?;
        if (json != null) {
          final player = Player.fromJson(json);
          _upsertPlayer(player);
          if (player.id != myPlayerId) _playerJoins.add(player);
        }
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
      case MessageType.kicked:
        _kicked = true;
        notifyListeners();
      case MessageType.auctionStarted:
        final json = message.payload['auction'] as Map<String, dynamic>?;
        if (json != null) {
          final auction = PropertyAuction.fromJson(json);
          _auctions[auction.propertyId] = auction;
          _auctionStarts.add((
            propertyId: auction.propertyId,
            startedBy: auction.startedBy,
          ));
          notifyListeners();
        }
      case MessageType.auctionBid:
        final json = message.payload['auction'] as Map<String, dynamic>?;
        if (json != null) {
          final auction = PropertyAuction.fromJson(json);
          _auctions[auction.propertyId] = auction;
          notifyListeners();
        }
      case MessageType.auctionClosed:
        final propertyId = message.payload['propertyId'] as String?;
        if (propertyId != null) _auctions.remove(propertyId);
        final reason = message.payload['reason'] as String?;
        if (message.payload['cancelled'] == true && reason != null) {
          _errors.add(reason);
        }
        notifyListeners();
      case MessageType.auctionRejected:
        final reason =
            message.payload['reason'] as String? ?? 'That bid was rejected.';
        _errors.add(reason);
      case MessageType.rollDismissed:
        final drawId = message.payload['drawId'] as String?;
        if (drawId != null && drawId.isNotEmpty) {
          // Recorded before the stream event fires, so a listener that
          // checks wasDismissed() first — even one that hasn't started
          // listening yet — can still find out this already happened.
          _dismissedDraws.add(drawId);
          _rollDismissals.add(drawId);
        }
      default:
        break;
    }
  }

  Future<void> _applySnapshot(Map<String, dynamic> payload) async {
    final json = payload['snapshot'] as Map<String, dynamic>?;
    if (json == null) return;
    final snapshot = GameSnapshot.fromJson(json);

    final target = _joinTarget;
    if (_record == null && target != null) {
      // Fresh join: this is the first time the device sees this game.
      _record = GameRecord(
        game: snapshot.game,
        role: GameRole.client,
        myPlayerId: _claimPlayerId ?? _identity.playerId,
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
    _claimPlayerId = null;

    _players = snapshot.players;
    _transactions = snapshot.transactions;
    _ownerships
      ..clear()
      ..addEntries(
        snapshot.ownerships.map((o) => MapEntry(o.propertyId, o)),
      );
    _auctions
      ..clear()
      ..addEntries(
        snapshot.auctions.map((a) => MapEntry(a.propertyId, a)),
      );
    _currentTurnId = snapshot.currentTurnId;
    _lastRoll = snapshot.lastRoll;
    _turnRolled = snapshot.turnRolled;
    _freeParkingPot = snapshot.freeParkingPot;

    if (isHost) {
      // The server already persisted players and transactions.
      await _db.upsertGameRecord(_record!);
    } else if (!_spectating) {
      await _db.saveSnapshot(_record!, snapshot);
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
    _freeParkingPot = payload['freeParkingPot'] as int? ?? _freeParkingPot;
    if (!_transactions.any((t) => t.id == tx.id)) {
      _transactions.add(tx);
      // A free-form bank payout (not salary/card/Free Parking, which have
      // their own transaction types) — the one case where any player can
      // hand themselves an arbitrary amount, so it's worth flagging to
      // everyone else rather than only showing up in the activity feed.
      if (tx.type == TransactionType.payment && tx.fromId == Player.bankId) {
        _bankCollections.add((playerId: tx.toId, amount: tx.amount));
      } else if (tx.type == TransactionType.payment &&
          tx.toId == Player.bankId) {
        _bankPayments.add((playerId: tx.fromId, amount: tx.amount));
      } else if (tx.toId == myPlayerId &&
          tx.fromId != Player.bankId &&
          (tx.type == TransactionType.payment ||
              tx.type == TransactionType.rent)) {
        // A direct payment or rent landing in my account — the two cases
        // where money shows up without me having done anything myself, so
        // there's nothing else already telling me it happened (unlike a
        // card draw or a transfer, which already pop their own dialog for
        // everyone involved).
        _paymentsReceived.add((
          fromId: tx.fromId,
          amount: tx.amount,
          isRent: tx.type == TransactionType.rent,
        ));
      } else if (tx.type == TransactionType.purchase &&
          tx.fromId != myPlayerId &&
          tx.propertyId != null) {
        // Someone else bought a property (a plain buy or an auction win) —
        // nothing else tells the rest of the table this happened.
        _propertyPurchases.add((
          playerId: tx.fromId,
          propertyId: tx.propertyId!,
          amount: tx.amount,
        ));
      } else if (tx.type == TransactionType.salary ||
          tx.type == TransactionType.tax) {
        // Auto-resolved by landing on a square mid-roll (or a "go to X"
        // card) — unlike a manual action, the player it happened to gets
        // no confirming dialog of their own, so they need this banner too,
        // not just everyone else at the table.
        _otherTransactions.add((tx: tx));
      } else if (const {
        TransactionType.house,
        TransactionType.mortgage,
        TransactionType.freeParking,
      }.contains(tx.type)) {
        // Whichever side isn't the bank is who this actually happened to —
        // skip when that's me, since I already got direct feedback from
        // whatever I just did (each of these is a manual, confirmed action).
        final primary = tx.fromId != Player.bankId ? tx.fromId : tx.toId;
        if (primary != myPlayerId) _otherTransactions.add((tx: tx));
      }
    }

    _record = record.copyWith(lastPlayedAt: DateTime.now());
    if (!_spectating) _db.upsertGameRecord(_record!);
    if (_persistLocally) {
      _db.upsertPlayers(record.game.id, _players);
      _db.insertTransactions(record.game.id, [tx]);
      _db.setTurnState(
        record.game.id,
        currentTurnId: _currentTurnId,
        lastRoll: _lastRoll,
        turnRolled: _turnRolled,
        freeParkingPot: _freeParkingPot,
      );
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
    if (record != null && _persistLocally) {
      _db.upsertPlayers(record.game.id, [player]);
    }
    notifyListeners();
  }

  /// Flags whoever's [Player.inJail] flipped from false to true between an
  /// old and updated player list — a dice roll or a "go to X" card are the
  /// only ways to actually land on the Go To Jail square, and neither gets
  /// a dedicated message type of its own for it, so it's detected here off
  /// the full player list both already carry.
  void _emitNewJailEntries(List<Player> before, List<Player> after) {
    final wasInJail = {for (final p in before) p.id: p.inJail};
    for (final p in after) {
      if (p.inJail && wasInJail[p.id] != true) {
        _jailEntries.add((playerId: p.id));
      }
    }
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
    if (_closing || _hostEnded || _kicked) return;
    final record = _record;
    if (record == null) return;
    final host = record.hostAddress;
    final port = record.hostPort;
    if (host == null || port == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (_closing || _hostEnded || _kicked || _record == null) return;
      if (_connection != ClientStatus.disconnected) return;
      _connect(host, port, spectator: _spectating);
    });
  }

  // closeSession() (and in-flight polls/completers) run async work after
  // dispose() fires it without awaiting — guard the single notifyListeners
  // choke point rather than every call site that could land after teardown.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    closeSession();
    _errors.close();
    _cardDraws.close();
    _diceRolls.close();
    _propertyTransfers.close();
    _bankCollections.close();
    _bankPayments.close();
    _paymentsReceived.close();
    _propertyPurchases.close();
    _auctionStarts.close();
    _playerJoins.close();
    _jailEntries.close();
    _otherTransactions.close();
    _rollDismissals.close();
    super.dispose();
  }
}
