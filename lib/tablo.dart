import 'package:tablo_app/tablodatabase.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class Tablo{
  final String serverID;
  final String privateIP;
  final TabloDatabase db;
  final Function saveToDisk;

  static const _webServer = 'api.tablotv.com';
  static const _webFolder = 'assocserver/getipinfo/';
  static const _port = '8885';
  static const _maxBatchSize = 50;
  
  Tablo._internalConstructor(this.serverID, this.privateIP, this.db, this.saveToDisk);

  static Future<List<Tablo>> getTablos() async {
    final tabloIDs = await _getCaches();
    if (tabloIDs.isEmpty) {
      final url = Uri.https(_webServer, _webFolder);
      final response = await http.get(url);
      final responseBody = json.decode(response.body);
      for (final tablo in responseBody['cpes']) {
        tabloIDs.add({
          'serverID': tablo['serverid'],
          'privateIP': tablo['private_ip'],
        });
      }
    }
    
    final tablos = <Tablo>[];
    for (final serverIDs in tabloIDs) {
      final tabloDB = await TabloDatabase.getDatabase(serverIDs['serverID']!);
      tablos.add(Tablo._internalConstructor(
          serverIDs['serverID']!,
          serverIDs['privateIP']!,
          tabloDB,
          tabloDB.saveToDisk
        )
      );
      
      if (tabloDB.isNew) {
        await tablos.last.updateSystemInfoTable();
        await tablos.last.updateChannels();
        await tablos.last.updateGuideShows();
        tablos.last.saveToDisk();
      }
    }
    return tablos;
  }

  static Future<bool> pingServer(String ipAddress, String serverID) async {
    final url = Uri.http('$ipAddress:$_port', 'server/info');
    var pingResponse = false;
    try {
      final response = await http.get(url);
      final body = utf8.decode(response.body.codeUnits);
      final responseBody = json.decode(body) as Map<String, dynamic>;
      pingResponse = responseBody['server_id'] == serverID;
    } on Exception {
      return false;
    }
    return pingResponse;
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

  Future<void> updateSystemInfoTable() async {
    final fullInfo = <String, dynamic>{};
    final systemInfo = await _get('server/info');
    fullInfo.addAll({
      'serverID': systemInfo['server_id'],
      'serverName': systemInfo['name'],
      'privateIP': systemInfo['local_address'],
    });
    final space = await _getSpace();
    fullInfo.addAll(space);
    db.updateSystemInfoTable(fullInfo);
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

  Future<void> updateGuideShows() async {
    final guideShowsList = await _get('guide/shows');
    final guideShowsDesc = await _batch(guideShowsList);
    final guideShows = <Map<String, dynamic>>[];
    for (final show in guideShowsDesc.values) {
      guideShows.add({
        'showID': show['object_id'],
        'rule': show['schedule']?['rule'],
        'channelID': _getID(show['schedule']?['channel_path']),
        'keepRecording': show['keep']['rule'],
        'count': show['keep']['count'],
        'showType' : _getShowType(show['path'])
      });
      guideShows.last.addAll(_getShowProperties(show));
    }
    db.updateGuideShows(guideShows);
  }

  Future<dynamic> _get(String path) async {
    final url = Uri.http('$privateIP:$_port', path);
    final response = await http.get(url);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw HttpException('Unable to connect to $path: ${response.statusCode} ${response.body}');
    }
    final body = utf8.decode(response.body.codeUnits);
    return json.decode(body);
  }

  Future<dynamic> _post(String path, String data) async {
    final url = Uri.http('$privateIP:$_port', path);
    final response = await http.post(url, body: data);
    final body = utf8.decode(response.body.codeUnits);
    return json.decode(body);
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
  
  String? _getID(String? path) {
    return path == null ? path : path.split('/').last;
  }

  String _getShowType(String path) {
    return path.split("/")[2];
  }
  
  Map<String, dynamic> _getShowProperties(Map<String, dynamic>record) {
    final show = record['series'] ?? record['movie'] ?? record['sport'];
    final awards = <Map<String, dynamic>>[];
    if (show['awards'] != null && show['awards'].length > 0) {
      for (final award in show['awards']) {
        awards.add({
          "won": award['won'],
          "awardName": award['name'],
          "awardCategory": award['category'],
          "year": award['year'],
          "nominee": award['nominee'],
        });
      }
    }
    show['awards'] = awards;
    final properties = {
      'title': show['title'],
      'descript': show['description'] ?? show['plot'],
      'releaseDate': show['orig_air_date'] ?? show['release_year'],
      'origRunTime': show['episode_runtime'] ?? show['original_runtime'],
      'rating': show['series_rating'] ?? show['film_rating'],
      'stars': show['quality_rating'],
      'genre': show['genres'],
      'cast': show['cast'],
      'award': show['awards'],
      'director': show['directors'],
    };
    return properties;
  }
  
  static Future<List<Map<String, String>>> _getCaches () async {
    final tabloIDs = <Map<String, String>>[];
    final databaseDirectory = Directory('databases');
    final databases = databaseDirectory.list();
    await for (final database in databases) {
      if (database.path.substring(database.path.length - 5) == 'cache') {
        final serverID = database.path.substring(10, database.path.length - 6);
        final privateIP = TabloDatabase.getIP(database.path);
        if (privateIP != null && await pingServer(privateIP, serverID)) {
          tabloIDs.add({
            'serverID': serverID,
            'privateIP': privateIP,
          });
        }
      }
    }
    return tabloIDs;
  }

  
  // saveToDisk() {
  //   db.saveToDisk();
  // }
}