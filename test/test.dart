import 'package:test/test.dart';
import 'package:tablo_app/main.dart';
import 'package:http/http.dart' as http;

void main() async {
  final response = await http.get(Uri.https(webServer, webFolder));

  test('Can instatiate Tablo object list', () async {
    expect(Tablo.listTablos(response), isA<List<Tablo>>());
  });

  test('Tablos have IP addresses', () async {
    final tablos = Tablo.listTablos(response);
    for (final tablo in tablos) {
      expect(tablo.privateIP, isNotNull);
    }
  });

  test('Tablos have server IDs', () async {
    final tablos = Tablo.listTablos(response);
    for (final tablo in tablos) {
      expect(tablo.serverid, isNotNull);
    }
  });

  test('findTablos() returns Tablo list', () async {
    var tablos = await findTablos();
    expect(tablos, isA<List<Tablo>>());
  });
}