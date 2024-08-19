import 'package:test/test.dart';
import 'package:tablo_app/tablo.dart';

void main() async {
  final tablos = await Tablo.getTablos();

  test('Can instatiate Tablo object list', () async {
    expect(tablos, isA<List<Tablo>>());
  });

  test('Tablos have IP addresses', () async {
    for (final tablo in tablos) {
      expect(tablo.privateIP, isNotNull);
    }
  });

  test('Tablos have server IDs', () async {
    for (final tablo in tablos) {
      expect(tablo.serverID, isNotNull);
    }
  });

  test('pingServer() returns true if server is accessible', () async {
    for (final tablo in tablos) {
      final accessible =
          await Tablo.isServerAvailable(tablo.privateIP, tablo.serverID);
      expect(accessible, isTrue);
    }
  });

  final tablo = tablos[0];

  test('getAllRecordings() returns a Map of items', () async {
    final recordings = await tablo.getAllRecordings();
    expect(recordings, isA<Map<String, dynamic>>());
  }, timeout: const Timeout.factor(4));

  test('getScheduled() returns a Map of items', () async {
    final scheduled = await tablo.getScheduled();
    expect(scheduled, isA<Map<String, dynamic>>());
  }, timeout: const Timeout.factor(4));

  test('getFullGuide() returns a Map of items', () async {
    final fullGuide = await tablo.getScheduled();
    expect(fullGuide, isA<Map<String, dynamic>>());
  }, timeout: const Timeout.factor(14));
}
