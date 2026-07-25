import 'package:flutter/material.dart';

import '../services/identity_service.dart';

/// Makes sure the device has a display name before hosting or joining.
/// Returns true once a name is set (or already was).
Future<bool> ensurePlayerName(
  BuildContext context,
  IdentityService identity,
) async {
  if (identity.hasName) return true;
  final name = await promptPlayerName(context, identity);
  return name != null;
}

/// Bottom sheet asking for the player's display name. Returns the saved
/// name, or null if dismissed.
Future<String?> promptPlayerName(
  BuildContext context,
  IdentityService identity,
) {
  final controller = TextEditingController(text: identity.displayName);

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What should players call you?',
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'This name shows up in every game you join.',
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              maxLength: 24,
              decoration: const InputDecoration(
                hintText: 'Your name',
                counterText: '',
              ),
              onSubmitted: (_) => _save(sheetContext, identity, controller),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _save(sheetContext, identity, controller),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _save(
  BuildContext sheetContext,
  IdentityService identity,
  TextEditingController controller,
) async {
  final name = controller.text.trim();
  if (name.isEmpty) return;
  await identity.setDisplayName(name);
  if (sheetContext.mounted) Navigator.of(sheetContext).pop(name);
}
