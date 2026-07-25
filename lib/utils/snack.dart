import 'package:flutter/material.dart';

/// Shows [message] right away: any snackbar still on screen is removed
/// instead of queueing behind it, so feedback never lags the action.
void showSnack(BuildContext context, String message) =>
    showSnackWith(ScaffoldMessenger.of(context), message);

/// Same as [showSnack] for a messenger captured before an await.
void showSnackWith(ScaffoldMessengerState messenger, String message) {
  messenger
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
      duration: const Duration(seconds: 2),
    ));
}
