import 'package:tablo_app/tablodatabase.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class Tablo{
  final String serverID;
  final String privateIP;
  final TabloDatabase db;

  static const _webServer = 'api.tablotv.com';
  static const _webFolder = 'assocserver/getipinfo/';
  static const _port = '8885';
  static const _maxBatchSize = 50;
  
  Tablo._internalConstructor(this.serverID, this.privateIP, this.db);

  static Future<List<Tablo>> getTablos() async {
    // add functionality to look in databases folder first    
    final url = Uri.https(_webServer, _webFolder);
    final response = await http.get(url);
    final responseBody = json.decode(response.body);
    final tablos = <Tablo>[];
    for (final tablo in responseBody['cpes']) {
      tablos.add(Tablo._internalConstructor(
        tablo['serverid'],
        tablo['private_ip'],
        TabloDatabase.getDatabase(tablo['serverid'], tablo['name'], tablo['private_ip'])
      ));
      
      await tablos.last.updateSystemTable();
      await tablos.last.updateChannels();
    }
    return tablos;
  }

  Future<bool> pingServer() async {
    final responseBody = await _get('server/info') as Map<String, dynamic>;
    return responseBody['server_id'] == serverID;
  }

  Future<Map<String, dynamic>> getAllRecordings() async {
    final recordings = await _get('recordings/airings') as List<dynamic>;
    final responseBody = await _batch(recordings);
    return responseBody;
  }

  Future<Map<String, dynamic>> getScheduled() async {
    final scheduled = await _get('guide/airings?state=scheduled') as List<dynamic>;
    final conflicted = await _get('guide/airings?state=conflicted') as List<dynamic>;
    scheduled.addAll(conflicted);
    final responseBody = await _batch(scheduled);
    return responseBody;
  }

  Future<Map<String, dynamic>> getFullGuide() async {
    final fullGuide = await _get('guide/airings') as List<dynamic>;
    final responseBody = await _batch(fullGuide);
    return responseBody;
  }

  Future<void> updateSystemTable() async {
    final fullInfo = <String, dynamic>{};
    final systemInfo = await _get('server/info');
    fullInfo.addAll({
      'serverID': systemInfo['server_id'],
      'serverName': systemInfo['name'],
      'privateIP': systemInfo['local_address'],
    });
    final space = await _getSpace();
    fullInfo.addAll(space);
    db.updateSystemTable(fullInfo);
  }

  Future<void> updateChannels() async {
    final channels = <Map<String, dynamic>>[];
    final guideChannelsPaths = await _get('guide/channels');
    final guideChannels = await _batch(guideChannelsPaths);
    for (final channel in guideChannels.values) {
      channels.add({
        'channelID': channel['object_id'],
        'channelType': 'guide',
        'callSign': channel['channel']['call_sign'],
        'major': channel['channel']['major'],
        'minor': channel['channel']['minor'],
        'network': channel['channel']['network'],
      });
    }
    final recordingChannelsPaths = await _get('recordings/channels');
    final recordingChannels = await _batch(recordingChannelsPaths);
    for (final channel in recordingChannels.values) {
      channels.add({
        'channelID': channel['object_id'],
        'channelType': 'recordings',
        'callSign': channel['channel']['call_sign'],
        'major': channel['channel']['major'],
        'minor': channel['channel']['minor'],
        'network': channel['channel']['network'],
      });
    }
    db.updateChannels(channels);
  }

  Future<dynamic> _get(String path) async {
    final url = Uri.http('$privateIP:$_port', path);
    final response = await http.get(url);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw HttpException('Unable to connect to $path: ${response.statusCode} ${response.body}');
    }
    return json.decode(response.body);
  }

  Future<dynamic> _post(String path, String data) async {
    final url = Uri.http('$privateIP:$_port', path);
    final response = await http.post(url, body: data);
    return json.decode(response.body);
  }

  Future<Map<String, dynamic>> _batch(List<dynamic> list) async {
    final data = _listStringMerge(list, _maxBatchSize);
    final responseBody = <String, dynamic>{};
    for (final datum in data) {
      final iterResponseBody = await _post('batch', datum);
      responseBody.addAll(iterResponseBody);
    }
    return responseBody;
  }

  List<String> _listStringMerge(List<dynamic> list, int batchSize) {
    final output = <String>[];
    final buffer = StringBuffer('["${list[0]}"');
    for (int i = 1; i < list.length; ++i) {
      if (i % batchSize == 0) {
        buffer.write(']');
        output.add(buffer.toString());
        buffer.clear();
        buffer.write('["${list[i]}"');
      } else {
        buffer.write(',"${list[i]}"');
      }
    }
    buffer.write(']');
    output.add(buffer.toString());
    return output;
  }
  
  Future<Map<String, int>> _getSpace() async {
    var totalSize = 0;
    var freeSize = 0;
    final response = await _get('server/harddrives');
    for (final drive in response) {
      totalSize += drive['size'] as int;
      freeSize += drive['free'] as int;
    }
    return {
      'totalSize': totalSize,
      'freeSize': freeSize,
    };
  }
}