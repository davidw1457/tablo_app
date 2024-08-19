import 'dart:convert';
import 'dart:io';
import 'dart:developer';
import 'package:http/http.dart' as http;

import 'package:tablo_app/log.dart';
import 'package:tablo_app/tablo_database.dart';

class Tablo {
  /// Unique id for Tablo server.
  final String serverID;

  /// IP address of Tablo server.
  final String privateIP;

  /// Database cache of Tablo server data.
  final TabloDatabase cache;

  /// Save database cache to permanent storage.
  final Function saveCacheToDisk;

  static const _tabloApiServer = 'api.tablotv.com';
  static const _tabloApiPath = 'assocserver/getipinfo/';
  static const _tabloServerPort = '8885';
  static const _maximumBatchItemCount = 50;
  static const _currentLibrary = 'tablo';

  static Log _log = Log();

  static void redirectLog(Log log) {
    _log = log;
    log.logMessage(_currentLibrary, 'Redirected log.');
    TabloDatabase.redirectLog(log);
  }

  static void _logMessage(String message, {String? level}) {
    if (level == null) {
      _log.logMessage(_currentLibrary, message);
    } else {
      _log.logMessage(_currentLibrary, message, level: level);
    }
  }

  static Future<List<Tablo>> getTablos() async {
    _logMessage('Beginning getTablos.');
    final tabloIDs = await _getCaches();
    if (tabloIDs.isEmpty) {
      _logMessage('Retrieving tablo information from $_tabloApiServer.');
      final url = Uri.https(_tabloApiServer, _tabloApiPath);
      final response = await http.get(url).timeout(const Duration(seconds: 30));
      final responseBody = json.decode(response.body);
      for (final tablo in responseBody['cpes']) {
        tabloIDs.add({
          'serverID': tablo['serverid'],
          'privateIP': tablo['private_ip'],
        });
      }
    }

    _logMessage('Creating Tablo list.');
    final tablos = <Tablo>[];
    for (final serverIDs in tabloIDs) {
      _logMessage('Opening database for ${serverIDs['serverID']}');
      final tabloDB = await TabloDatabase.getDatabase(serverIDs['serverID']!);
      _logMessage('Adding Tablo ${serverIDs['serverID']}.');
      tablos.add(Tablo._internalConstructor(
          serverIDs['serverID']!, serverIDs['privateIP']!, tabloDB));

      if (tabloDB.isNew) {
        final tablo = tablos.last;
        _logMessage('Updating system tables for $tablo');
        await tablo.updateSystemInfoTable();
        _logMessage('Updating channels for $tablo');
        await tablo.updateChannels();
        _logMessage('Updating guide shows for $tablo');
        await tablo.updateGuideShows();
        _logMessage('Updating scheduled airings for $tablo');
        await tablo.updateGuideAirings(scheduledOnly: true);
        _logMessage('Saving cache to disk for $tablo');
        tablo.saveCacheToDisk();
      }
    }
    return tablos;
  }

  static Future<bool> isServerAvailable(
      String ipAddress, String serverID) async {
    _logMessage('Testing $serverID availability.');
    final url = Uri.http('$ipAddress:$_tabloServerPort', 'server/info');
    var pingResponse = false;
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 30));
      final body = utf8.decode(response.body.codeUnits);
      final responseBody = json.decode(body) as Map<String, dynamic>;
      pingResponse = responseBody['server_id'] == serverID;
    } on Exception catch (e) {
      _logMessage('Error testing server availablility: $e', level: 'warning');
      return false;
    }
    _logMessage('$serverID ${pingResponse ? '' : 'in'}accessible');
    return pingResponse;
  }

  Tablo._internalConstructor(this.serverID, this.privateIP, this.cache)
      : saveCacheToDisk = cache.saveToDisk;

  Future<List<Map<String, dynamic>>> getAllRecordings() async {
    final recordings = await _get('recordings/airings') as List<dynamic>;
    final responseBody = await _batch(recordings);
    return responseBody;
  }

  Future<List<Map<String, dynamic>>> getScheduled() async {
    final scheduled =
        await _get('guide/airings?state=scheduled') as List<dynamic>;
    final conflicted =
        await _get('guide/airings?state=conflicted') as List<dynamic>;
    scheduled.addAll(conflicted);
    final responseBody = await _batch(scheduled);
    return responseBody;
  }

  Future<List<Map<String, dynamic>>> getFullGuide() async {
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
    cache.updateSystemInfoTable(fullInfo);
  }

  Future<void> updateChannels() async {
    final channels = <Map<String, dynamic>>[];
    final guideChannelsPaths = await _get('guide/channels');
    final guideChannels = await _batch(guideChannelsPaths);
    for (final channel in guideChannels) {
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
    for (final channel in recordingChannels) {
      channels.add({
        'channelID': channel['object_id'],
        'channelType': 'recordings',
        'callSign': channel['channel']['call_sign'],
        'major': channel['channel']['major'],
        'minor': channel['channel']['minor'],
        'network': channel['channel']['network'],
      });
    }
    cache.updateChannels(channels);
  }

  Future<void> updateGuideShows() async {
    final guideShowsList = await _get('guide/shows');
    final guideShowsDesc = await _batch(guideShowsList);
    final guideShows = <Map<String, dynamic>>[];
    for (final show in guideShowsDesc) {
      final showProperties = show['series'] ?? show['movie'] ?? show['sport'];
      final awards = <Map<String, dynamic>>[];
      if (showProperties['awards'] != null &&
          showProperties['awards'].length > 0) {
        for (final award in showProperties['awards']) {
          awards.add({
            "won": award['won'],
            "awardName": award['name'],
            "awardCategory": award['category'],
            "awardYear": award['year'],
            "cast": award['nominee'],
          });
        }
      }
      guideShows.add({
        'showID': show['object_id'],
        'rule': show['schedule']?['rule'],
        'channelID': _getID(show['schedule']?['channel_path']),
        'channelType': 'guide',
        'keepRecording': show['keep']['rule'],
        'count': show['keep']['count'],
        'showType': _getShowType(show['path']),
        'title': showProperties['title'],
        'descript': showProperties['description'] ?? showProperties['plot'],
        'releaseDate':
            showProperties['orig_air_date'] ?? showProperties['release_year'],
        'origRunTime': showProperties['episode_runtime'] ??
            showProperties['original_runtime'],
        'rating':
            showProperties['series_rating'] ?? showProperties['film_rating'],
        'stars': showProperties['quality_rating'],
        'genre': showProperties['genres'],
        'cast': showProperties['cast'],
        'award': awards,
        'director': showProperties['directors'],
      });
    }
    cache.updateGuideShows(guideShows);
  }

  Future<void> updateGuideAirings({bool scheduledOnly = false}) async {
    _logMessage('Beginning updateGuideAirings(scheduledOnly: $scheduledOnly)');
    List<dynamic> guideAiringsList;
    if (scheduledOnly) {
      guideAiringsList = await _get('guide/airings?state=scheduled');
      guideAiringsList.addAll(await _get('guide/airings?state=conflicted'));
    } else {
      guideAiringsList = await _get('guide/airings');
    }
    final guideAiringsDesc = await _batch(guideAiringsList);
    final guideAirings = <Map<String, dynamic>>[];
    final guideEpisodes = <Map<String, dynamic>>[];
    for (final airing in guideAiringsDesc) {
      final showType = _getShowType(airing['path']);
      final episodeID = _getEpisodeID(airing);
      final showID = _getID(airing['series_path'] ??
          airing['sport_path'] ??
          airing['movie_path']);
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
        guideEpisodes.add(_createEpisodeMap(
            airing['episode'] ?? airing['event'], showType, showID!, episodeID!));
      }
    }
    cache.updateGuideAirings(guideAirings, guideEpisodes);
  }

  @override
  String toString() {
    return serverID;
  }

  Map<String, dynamic> _createEpisodeMap(
      Map<String, dynamic> episode, String showType, int showID, String episodeID) {
    final episodeMap = <String, dynamic>{};
    if (showType == 'sports' && episode['teams'].length > 0) {
      final teams = <Map<String, dynamic>>[];
      for (final team in episode['teams']) {
        teams.add({
          'team': team['name'],
          'teamID': team['team_id'],
        });
      }
      episodeMap['teams'] = teams;
    }
    episodeMap['episodeID'] = episodeID;
    episodeMap['showID'] = showID;
    episodeMap['title'] = episode['title'];
    episodeMap['descript'] = episode['description'];
    episodeMap['episode'] = episode['number'];
    episodeMap['season'] =
        episode['season_number']?.toString() ?? episode['season']?.toString();
    episodeMap['seasonType'] = episode['season_type'];
    episodeMap['airDate'] = episode['orig_air_date'];
    episodeMap['homeTeamID'] = episode['home_team_id'];
    return episodeMap;
  }

  Future<dynamic> _get(String path) async {
    final url = Uri.http('$privateIP:$_tabloServerPort', path);
    final response = await http.get(url).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw HttpException(
          'Unable to connect to $path: ${response.statusCode} ${response.body}');
    }
    final body = utf8.decode(response.body.codeUnits);
    return json.decode(body);
  }

  Future<dynamic> _post(String path, String data) async {
    final url = Uri.http('$privateIP:$_tabloServerPort', path);
    http.Response response;
    try {
      response =
          await http.post(url, body: data).timeout(const Duration(seconds: 30));
    } on Exception {
      response =
          await http.post(url, body: data).timeout(const Duration(seconds: 30));
    }
    final body = utf8.decode(response.body.codeUnits);
    return json.decode(body);
  }

  Future<List<Map<String, dynamic>>> _batch(List<dynamic> list) async {
    _logMessage('Executing batch request: $list');
    final data = _listStringMerge(list, _maximumBatchItemCount);
    final responseBody = <String, dynamic>{};
    for (final datum in data) {
      final iterResponseBody = await _post('batch', datum);
      responseBody.addAll(iterResponseBody);
    }
    _logMessage('Batch POST complete.');
    return List.from(responseBody.values);
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

  int? _getID(String? path) {
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
    return path.split("/")[2];
  }

  static Future<List<Map<String, String>>> _getCaches() async {
    final tabloIDs = <Map<String, String>>[];
    final databaseDirectory = Directory('databases');
    final databases = databaseDirectory.list();
    await for (final database in databases) {
      if (database.path.substring(database.path.length - 5) == 'cache') {
        final serverID = database.path.substring(10, database.path.length - 6);
        final privateIP = TabloDatabase.getIP(database.path);
        if (privateIP != null && await isServerAvailable(privateIP, serverID)) {
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
    String? episodeID;
    final recordType = _getShowType(record['path']);
    if (recordType == 'series' || recordType == 'sports') {
      final showID = _getID(record['series_path'] ?? record['sport_path']);
      final seasonNumber = record['episode']?['season_number'] ??
          record['event']?['season'] ??
          '0';
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
