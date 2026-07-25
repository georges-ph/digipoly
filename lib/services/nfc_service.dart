import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import '../models/result.dart';

/// What a Digipoly NFC card holds.
sealed class NfcCardData {
  const NfcCardData();
}

/// A physical property card: tap it in-game to buy or pay rent.
class NfcPropertyCard extends NfcCardData {
  const NfcPropertyCard({required this.boardId, required this.propertyId});
  final String boardId;
  final String propertyId;
}

/// A player's payment card: tap it to pick them as a payment recipient.
class NfcPlayerCard extends NfcCardData {
  const NfcPlayerCard({required this.playerId});
  final String playerId;
}

/// Physical game cards: an NFC tag holds a tiny NDEF text payload
/// (`digipoly:prop:<boardId>:<propertyId>` or `digipoly:player:<playerId>`)
/// and the app looks the rest up locally.
///
/// One shared instance coordinates the single NFC radio: a long-lived
/// *watch* session runs while a game screen is open (any Digipoly card
/// tapped routes into the app — and while a reader session is active,
/// Android's own "new tag" UI stays out of the way), and one-shot
/// read/write operations temporarily take the radio over, then hand it
/// back to the watch.
class NfcService {
  NfcService._();

  static final NfcService instance = NfcService._();

  /// Error sentinel for a user-cancelled read/write; flows treat it as
  /// silence, not an error worth a snackbar.
  static const cancelled = 'cancelled';

  void Function(NfcCardData card)? _onWatchCard;
  void Function(NfcCardData card)? _watchOverride;
  bool _sessionOpen = false;
  bool _oneShotActive = false;
  void Function()? _cancelPending;
  DateTime _lastWatchHit = DateTime.fromMillisecondsSinceEpoch(0);

  static String propertyPayload({
    required String boardId,
    required String propertyId,
  }) =>
      'digipoly:prop:$boardId:$propertyId';

  static String playerPayload({required String playerId}) =>
      'digipoly:player:$playerId';

  static NfcCardData? parsePayload(String text) {
    final parts = text.trim().split(':');
    if (parts.length < 3 || parts[0] != 'digipoly') return null;
    if (parts[1] == 'prop' && parts.length == 4) {
      return NfcPropertyCard(boardId: parts[2], propertyId: parts[3]);
    }
    if (parts[1] == 'player') {
      return NfcPlayerCard(playerId: parts[2]);
    }
    // Legacy property cards written before payloads were typed.
    if (parts.length == 3) {
      return NfcPropertyCard(boardId: parts[1], propertyId: parts[2]);
    }
    return null;
  }

  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      return await NfcManager.instance.checkAvailability() ==
          NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------------------------------------------- Watch

  /// Starts (or re-targets) the long-lived watch: every Digipoly card
  /// tapped while it runs is delivered to [onCard].
  Future<void> startWatch(void Function(NfcCardData card) onCard) async {
    _onWatchCard = onCard;
    if (!_oneShotActive) await _openWatchSession();
  }

  Future<void> stopWatch() async {
    _onWatchCard = null;
    if (!_oneShotActive) await _stopSession();
  }

  /// Temporarily routes watch taps to [onCard] — for sheets that offer
  /// their own tap-to-pay behavior on top of the running watch (e.g. the
  /// property sheet's "tap a card to buy / pay rent"). The underlying
  /// session is untouched; pair with [clearWatchOverride].
  void setWatchOverride(void Function(NfcCardData card) onCard) =>
      _watchOverride = onCard;

  void clearWatchOverride() => _watchOverride = null;

  Future<void> _openWatchSession() async {
    if (_onWatchCard == null || !await isAvailable()) return;
    await _stopSession();
    _sessionOpen = true;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: const {NfcPollingOption.iso14443},
        onDiscovered: (tag) async {
          final handler = _watchOverride ?? _onWatchCard;
          if (handler == null || _oneShotActive) return;
          // The same card re-reads while held against the phone; debounce.
          if (DateTime.now().difference(_lastWatchHit) <
              const Duration(seconds: 2)) {
            return;
          }
          try {
            final message = await _readMessage(tag);
            final text = message == null ? null : _decodeText(message);
            final card = text == null ? null : parsePayload(text);
            if (card != null) {
              _lastWatchHit = DateTime.now();
              handler(card);
            }
          } catch (_) {}
        },
      );
    } catch (_) {
      _sessionOpen = false;
    }
  }

  // -------------------------------------------------------------- One-shot

  /// Waits for a tag and reads its first NDEF text record.
  Future<Result<String>> readText() => _withTag<String>((tag) async {
        final message = await _readMessage(tag);
        if (message == null) return err('This card is empty.');
        final text = _decodeText(message);
        return text == null
            ? err('No readable text on this card.')
            : ok(text);
      });

  /// Waits for a tag and writes [text] as an NDEF text record.
  Future<Result<void>> writeText(String text) => _withTag<void>((tag) async {
        final message = NdefMessage(records: [_textRecord(text)]);
        if (defaultTargetPlatform == TargetPlatform.android) {
          final ndef = NdefAndroid.from(tag);
          if (ndef == null) return err('This card does not support NDEF.');
          if (!ndef.isWritable) return err('This card is read-only.');
          await ndef.writeNdefMessage(message);
        } else {
          final ndef = NdefIos.from(tag);
          if (ndef == null) return err('This card does not support NDEF.');
          await ndef.writeNdef(message);
        }
        return ok(null);
      });

  /// Aborts the pending one-shot read/write, resolving it with [cancelled].
  void cancel() => _cancelPending?.call();

  Future<Result<T>> _withTag<T>(
    Future<Result<T>> Function(NfcTag tag) body,
  ) async {
    if (!await isAvailable()) {
      return err('NFC is not available on this device.');
    }
    _oneShotActive = true;
    await _stopSession();

    final completer = Completer<Result<T>>();
    _cancelPending = () {
      if (!completer.isCompleted) completer.complete(err(cancelled));
    };
    _sessionOpen = true;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: const {NfcPollingOption.iso14443},
        alertMessageIos: 'Hold the card near the phone',
        onDiscovered: (tag) async {
          if (completer.isCompleted) return;
          try {
            final result = await body(tag);
            if (!completer.isCompleted) completer.complete(result);
          } catch (e) {
            if (!completer.isCompleted) {
              completer.complete(err(_shortError(e)));
            }
          }
        },
      );
    } catch (e) {
      _sessionOpen = false;
      _oneShotActive = false;
      _cancelPending = null;
      return err('Could not start NFC: ${_shortError(e)}');
    }

    final result = await completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => err('No card detected.'),
    );
    _cancelPending = null;
    _oneShotActive = false;

    if (_onWatchCard != null) {
      // Hand the radio straight back to the watch.
      await _openWatchSession();
    } else {
      // Keep the session alive briefly: if it closes while the card is
      // still against the phone, Android's own NFC dispatch grabs the tag
      // and pops the system scan UI over the app.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 3)).then((_) async {
          if (!_oneShotActive && _onWatchCard == null) await _stopSession();
        }),
      );
    }
    return result;
  }

  Future<void> _stopSession() async {
    if (!_sessionOpen) return;
    _sessionOpen = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  /// Platform exceptions can be paragraphs long — keep snackbars readable.
  static String _shortError(Object e) {
    final text = e.toString().replaceAll(RegExp(r'\s+'), ' ');
    return text.length <= 90 ? text : '${text.substring(0, 90)}…';
  }

  Future<NdefMessage?> _readMessage(NfcTag tag) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final ndef = NdefAndroid.from(tag);
      if (ndef == null) return null;
      return await ndef.getNdefMessage() ?? ndef.cachedNdefMessage;
    }
    final ndef = NdefIos.from(tag);
    if (ndef == null) return null;
    return ndef.readNdef();
  }

  /// A well-known "T" (text) record: status byte with the language length,
  /// then the language code, then UTF-8 text.
  static NdefRecord _textRecord(String text) {
    const language = 'en';
    final payload = Uint8List.fromList([
      language.length,
      ...ascii.encode(language),
      ...utf8.encode(text),
    ]);
    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList(ascii.encode('T')),
      identifier: Uint8List(0),
      payload: payload,
    );
  }

  static String? _decodeText(NdefMessage message) {
    for (final record in message.records) {
      if (record.typeNameFormat != TypeNameFormat.wellKnown) continue;
      if (record.type.length != 1 || record.type.first != 0x54) continue;
      final payload = record.payload;
      if (payload.isEmpty) continue;
      final languageLength = payload.first & 0x3F;
      if (payload.length <= 1 + languageLength) continue;
      return utf8.decode(payload.sublist(1 + languageLength));
    }
    return null;
  }
}
