import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wildbit/storage/database.dart';

void main() {
  test(
    'keeps a signed offline Nostr event in the encrypted database queue',
    () async {
      final database = WildBitDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final createdAt = DateTime.utc(2026, 9, 1, 12);

      await database
          .into(database.pendingNostrPublications)
          .insert(
            PendingNostrPublicationsCompanion.insert(
              eventJson: '{"id":"signed-event"}',
              createdAt: createdAt,
              lastError: const Value('Relay non raggiungibile.'),
            ),
          );

      final pending = await (database.select(
        database.pendingNostrPublications,
      )..orderBy([(row) => OrderingTerm.asc(row.createdAt)])).getSingle();
      expect(pending.eventJson, '{"id":"signed-event"}');
    expect(pending.createdAt.toUtc(), createdAt);
      expect(pending.retryCount, 0);
      expect(pending.lastError, 'Relay non raggiungibile.');
    },
  );
}
