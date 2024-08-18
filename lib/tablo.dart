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
  
  Tablo._internalConstructor(this.serverID, this.privateIP, this.db, this.saveToDisk) {
    print('${DateTime.now()}: Tablo._internalConstructor($serverID, $privateIP, $db, $saveToDisk)');
  }

  static Future<List<Tablo>> getTablos() async {
    print('${DateTime.now()}: static Future<List<Tablo>> getTablos() async');
    final tabloIDs = await _getCaches();
    if (tabloIDs.isEmpty) {
      final url = Uri.https(_webServer, _webFolder);
      final response = await http.get(url).timeout(const Duration(seconds: 30));
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
        await tablos.last.updateGuideAirings();
        tablos.last.saveToDisk();
      }
    }
    return tablos;
  }

  static Future<bool> pingServer(String ipAddress, String serverID) async {
    print('${DateTime.now()}: static Future<bool> pingServer($ipAddress, $serverID) async');
    final url = Uri.http('$ipAddress:$_port', 'server/info');
    var pingResponse = false;
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 30));
      final body = utf8.decode(response.body.codeUnits);
      final responseBody = json.decode(body) as Map<String, dynamic>;
      pingResponse = responseBody['server_id'] == serverID;
    } on Exception {
      return false;
    }
    return pingResponse;
  }

  Future<Map<String, dynamic>> getAllRecordings() async {
    print('${DateTime.now()}: Future<Map<String, dynamic>> getAllRecordings() async');
    final recordings = await _get('recordings/airings') as List<dynamic>;
    final responseBody = await _batch(recordings);
    return responseBody;
  }

  Future<Map<String, dynamic>> getScheduled() async {
    print('${DateTime.now()}: Future<Map<String, dynamic>> getScheduled() async');
    final scheduled = await _get('guide/airings?state=scheduled') as List<dynamic>;
    final conflicted = await _get('guide/airings?state=conflicted') as List<dynamic>;
    scheduled.addAll(conflicted);
    final responseBody = await _batch(scheduled);
    return responseBody;
  }

  Future<Map<String, dynamic>> getFullGuide() async {
    print('${DateTime.now()}: Future<Map<String, dynamic>> getFullGuide() async');
    final fullGuide = await _get('guide/airings') as List<dynamic>;
    final responseBody = await _batch(fullGuide);
    return responseBody;
  }

  Future<void> updateSystemInfoTable() async {
    print('${DateTime.now()}: Future<void> updateSystemInfoTable() async');
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
    print('${DateTime.now()}: Future<void> updateChannels() async');
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
    print('${DateTime.now()}: Future<void> updateGuideShows() async');
    final guideShowsList = await _get('guide/shows');
    final guideShowsDesc = await _batch(guideShowsList);
    final guideShows = <Map<String, dynamic>>[];
    for (final show in guideShowsDesc.values) {
      guideShows.add({
        'showID': show['object_id'],
        'rule': show['schedule']?['rule'],
        'channelID': _getID(show['schedule']?['channel_path']),
        'channelType': 'guide',
        'keepRecording': show['keep']['rule'],
        'count': show['keep']['count'],
        'showType' : _getShowType(show['path'])
      });
      guideShows.last.addAll(_getShowProperties(show));
    }
    db.updateGuideShows(guideShows);
  }

  Future<void> updateGuideAirings() async {
    print('${DateTime.now()}: Future<void> updateGuideAirings() async');
    final guideAiringsList = await _get('guide/airings');
    final guideAiringsDesc = await _batch(guideAiringsList);
    final guideAirings = <Map<String, dynamic>>[];
    final guideEpisodes = <String, Map<String, dynamic>>{};
    for (final airing in guideAiringsDesc.values) {
      final showType = _getShowType(airing['path']);
      final episodeID = _getEpisodeID(airing);
      final showID = _getID(airing['series_path'] ?? airing['sport_path'] ?? airing['movie_path']);
      guideAirings.add({
        'airingID': airing['object_id'],
        'showID': showID,
        'airDate': airing['airing_details']['datetime'],
        'duration': airing['airing_details']['duration'],
        'channelID': airing['airing_details']['channel']['object_id'],
        'channelType': 'guide',
        'scheduled': airing['schedule']['state'],
        'episodeID': episodeID,
      });
      if (showType != 'movies') {
        guideEpisodes[episodeID!] = {
          'showID': showID,
          'title': airing['episode']?['title'] ?? airing['event']?['title'],
          'descript': airing['episode']?['description'] ?? airing['event']?['description'],
          'episode': airing['episode']?['number'],
          'season': airing['episode']?['season_number'].toString() ?? airing['event']?['season'].toString(),
          'seasonType': airing['event']?['season_type'],
          'airDate': airing['episode']?['orig_air_date'],
          'venue': airing['event']?['venue'],
          'homeTeamID': airing['event']?['home_team_id'],
        };
        if (showType == 'sports' && airing['event']['teams'].length > 0) {
          final teams = <Map<String, dynamic>>[];
          for (final team in airing['event']['teams']) {
            teams.add({
              'team': team['name'],
              'teamID': team['team_id'],
            });
          }
          guideEpisodes[episodeID]!['team'] = teams;
        }
      }
    }
    db.updateGuideAirings(guideAirings, guideEpisodes);
  }

  Future<dynamic> _get(String path) async {
    print('${DateTime.now()}: Future<dynamic> _get($path) async');
    final url = Uri.http('$privateIP:$_port', path);
    final response = await http.get(url).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw HttpException('Unable to connect to $path: ${response.statusCode} ${response.body}');
    }
    final body = utf8.decode(response.body.codeUnits);
    return json.decode(body);
  }

  Future<dynamic> _post(String path, String data) async {
    print('${DateTime.now()}: Future<dynamic> _post($path, $data) async');
    final url = Uri.http('$privateIP:$_port', path);
    http.Response response;
    try {
      response = await http.post(url, body: data).timeout(const Duration(seconds: 30));
    } on Exception {
      response = await http.post(url, body: data).timeout(const Duration(seconds: 30));
    }
    final body = utf8.decode(response.body.codeUnits);
    print('${DateTime.now()}: return: ${json.decode(body)};');
    return json.decode(body);
  }

  Future<Map<String, dynamic>> _batch(List<dynamic> list) async {
    print('${DateTime.now()}: Future<Map<String, dynamic>> _batch($list) async');
    final data = _listStringMerge(list, _maxBatchSize);
    final responseBody = <String, dynamic>{};
    for (final datum in data) {
      final iterResponseBody = await _post('batch', datum);
      responseBody.addAll(iterResponseBody);
    }
    print('${DateTime.now()}: _batch: return $responseBody;');
    return responseBody;
  }

  List<String> _listStringMerge(List<dynamic> list, int batchSize) {
    print('${DateTime.now()}: List<String> _listStringMerge($list, $batchSize)');
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
    print('${DateTime.now()}: Future<Map<String, int>> _getSpace() async');
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
  
  int? _getID(String? path) {
    print('${DateTime.now()}: String? _getID($path)');
    int? intID;
    try {
      final strID = path == null ? path : path.split('/').last;
      if (strID != null) {
        intID = int.parse(strID);
      } else {
        return null;
      }
    } on Exception {
      return null;
    }
    return intID;
  }

  String _getShowType(String path) {
    print('${DateTime.now()}: String _getShowType($path)');
    return path.split("/")[2];
  }
  
  Map<String, dynamic> _getShowProperties(Map<String, dynamic>record) {
    print('${DateTime.now()}: Map<String, dynamic> _getShowProperties($record)');
    final show = record['series'] ?? record['movie'] ?? record['sport'];
    final awards = <Map<String, dynamic>>[];
    if (show['awards'] != null && show['awards'].length > 0) {
      for (final award in show['awards']) {
        awards.add({
          "won": award['won'],
          "awardName": award['name'],
          "awardCategory": award['category'],
          "awardYear": award['year'],
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
    print('${DateTime.now()}: static Future<List<Map<String, String>>> _getCaches ()');
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
  
  String? _getEpisodeID(Map<String, dynamic> record) {
    print('${DateTime.now()}: String? _getEpisodeID($record)');
    String? episodeID;
    final recordType = _getShowType(record['path']);
    if (recordType == 'series' || recordType == 'sports') {
      final showID = _getID(record['series_path'] ?? record['sport_path']);
      final seasonNumber = record['episode']?['season_number'] ?? record['event']?['season'] ?? '0';
      int episodeNumber = record['episode']?['number'] ?? 0;
      if (episodeNumber == 0) {
        final airDate = DateTime.parse(record['airing_details']['datetime']);
        episodeNumber = airDate.millisecondsSinceEpoch ~/ 524288;
      }
      episodeID = '$showID.$episodeNumber.$seasonNumber';
    }
    return episodeID;
  }
}