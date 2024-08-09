import 'package:test/test.dart';
import 'package:tablo_app/main.dart';
import 'package:http/http.dart' as http;

void main() async {
  final response = await http.get(Uri.https(webServer, webFolder));

  test('Can instatiate Tablo object list', () async {
    expect(Tablo.listTablos(response), isA<List<Tablo>>());
  });

  test('findTablos() returns Tablo list', () async {
    final tablos = await findTablos();
    expect(tablos, isA<List<Tablo>>());
  });

  final tablos = Tablo.listTablos(response);

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
      final accessible = await tablo.pingServer();
      expect(accessible, isTrue);
    }
  });

  test('getAllRecordings() returns a map of items', () async {
    final tablo = tablos[0];
    final recordings = await tablo.getAllRecordings();
    expect(recordings, isA<Map<String, dynamic>>());
  }, timeout: const Timeout.factor(4));
}