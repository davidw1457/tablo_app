import 'dart:convert';
import 'dart:io';
import 'dart:math';
// import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

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

  /// Redirect the logging for all Tablos to the provided log
  static void redirectLog(Log log) {
    _log = log;
    log.logMessage(_currentLibrary, 'Redirected log.');
    TabloDatabase.redirectLog(log);
  }

  static void _logMessage(String message, {String? level}) {
    if (level == null) {
      _log.logMessage(message, _currentLibrary);
    } else {
      _log.logMessage(message, _currentLibrary, level: level);
    }
  }

  /// Get a List of all available Tablos
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
        _logMessage('Updating recordings for $tablo');
        await tablo.updateRecordings();
        _logMessage('Saving cache to disk for $tablo');
        await tablo.saveCacheToDisk();
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
        'channelID': channel['object_id'] * -1,
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
      guideShows.add(_createShowMap(show));
    }
    cache.updateGuideShows(guideShows);
  }

  Map<String, dynamic> _createShowMap(Map<String, dynamic> show,
      {bool recording = false}) {
    final showProperties = show['series'] ?? show['movie'] ?? show['sport'];
    final awards = <Map<String, dynamic>>[];
    Map<String, dynamic> showMap;
    if (show['guide_path'] != null) {
      showMap = {
        'showID': -show['object_id'],
        'parentShowID': _getIDfromPath(show['guide_path']),
        'keepRecording': show['keep']['rule'],
        'showType': _getShowType(show['path']),
        'title': '',
      };
    } else {
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
      var channelID = _getIDfromPath(show['schedule']?['channel_path']);
      if (recording && channelID != null) channelID *= -1;
      showMap = {
        'showID': show['object_id'] * (recording ? -1 : 1),
        'parentShowID': _getIDfromPath(show['guide_path']),
        'rule': show['schedule']?['rule'],
        'channelID': channelID,
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
      };
    }
    return showMap;
  }

  Future<void> updateGuideAirings({bool scheduledOnly = false}) async {
    _logMessage('Beginning updateGuideAirings(scheduledOnly: $scheduledOnly)');
    List<dynamic> guideAiringsList;
    final episodesAdded = <String>{};
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
      final showID = _getIDfromPath(airing['series_path'] ??
          airing['sport_path'] ??
          airing['movie_path']);
      final episodeID = _getEpisodeID(airing, showID!);
      guideAirings.add({
        'airingID': airing['object_id'],
        'showID': showID,
        'airDate': airing['airing_details']['datetime'],
        'duration': airing['airing_details']['duration'],
        'channelID': airing['airing_details']['channel']['object_id'],
        'scheduled': airing['schedule']['state'],
        'episodeID': episodeID,
      });
      if (showType != 'movies' && episodesAdded.add(episodeID!)) {
        guideEpisodes.add(_createEpisodeMap(
            airing['episode'] ?? airing['event'], showType, showID, episodeID));
      }
    }
    cache.updateGuideAirings(guideAirings, guideEpisodes);
  }

  @override
  String toString() {
    return serverID;
  }

  Map<String, dynamic> _createEpisodeMap(Map<String, dynamic> episode,
      String showType, int showID, String episodeID) {
    final episodeMap = <String, dynamic>{};
    if (showType == 'sports' && episode['teams'].length > 0) {
      final teams = <Map<String, dynamic>>[];
      for (final team in episode['teams']) {
        teams.add({
          'team': team['name'],
          'teamID': team['team_id'],
        });
      }
      episodeMap['team'] = teams;
    }
    episodeMap['episodeID'] = episodeID;
    episodeMap['showID'] = showID;
    episodeMap['title'] = episode['title'];
    episodeMap['descript'] = episode['description'];
    episodeMap['episode'] = episode['number'];
    episodeMap['season'] =
        episode['season_number']?.toString() ?? episode['season']?.toString();
    episodeMap['seasonType'] = episode['season_type'];
    episodeMap['originalAirDate'] = episode['orig_air_date'];
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

  Future<dynamic> _post(String path, {String? data}) async {
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
      final iterResponseBody = await _post('batch', data: datum);
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

  int? _getIDfromPath(String? path) {
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

  String? _getEpisodeID(Map<String, dynamic> record, int showID) {
    String? episodeID;
    final recordType = _getShowType(record['path']);
    if (recordType == 'series' || recordType == 'sports') {
      final seasonNumber = record['episode']?['season_number'] ??
          record['event']?['season'] ??
          '0';
      int episodeNumber = record['episode']?['number'] ?? 0;
      if (episodeNumber == 0) {
        final airDate = DateTime.parse(record['airing_details']['datetime']);
        episodeNumber = airDate.millisecondsSinceEpoch ~/ 524288;
      }
      episodeID = '$showID.$seasonNumber.$episodeNumber';
    }
    return episodeID;
  }

  Future<void> updateRecordings() async {
    _logMessage('Updating Recordings.');
    final recordingShowPaths = await _get('recordings/shows');
    final recordingAiringPaths = await _get('recordings/airings');
    final recordingShowData = await _batch(recordingShowPaths);
    final recordingAiringData = await _batch(recordingAiringPaths);

    final recordingShowsXref = <int, int>{};
    final recordingShows = <Map<String, dynamic>>[];
    final episodesAdded = <String>{};
    final recordingEpisodes = <Map<String, dynamic>>[];
    final recordingErrors = <Map<String, dynamic>>[];
    final recordings = <Map<String, dynamic>>[];

    _logMessage('Creating recordingShowData List');
    for (final show in recordingShowData) {
      final showID = _getIDfromPath(show['guide_path']);
      if (showID != null) {
        recordingShowsXref[show['object_id'] * -1] = showID;
      }
      recordingShows.add(_createShowMap(show, recording: true));
    }
    _logMessage('Creating episode Lists');
    for (final recording in recordingAiringData) {
      var recordingShowID = _getIDfromPath(recording['series_path'] ??
              recording['sport_path'] ??
              recording['movie_path'])! *
          -1;
      final showID = recordingShowsXref[recordingShowID];
      final episodeID = _getEpisodeID(recording, showID ?? recordingShowID);
      final showType = _getShowType(recording['path']);

      recordings.add({
        'recordingID': recording['object_id'],
        'showID': recordingShowID,
        'airDate': recording['airing_details']['datetime'],
        'airingDuration': recording['airing_details']['duration'],
        'channelID': recording['airing_details']['channel']['object_id'] * -1,
        'recordingState': recording['video_details']['state'],
        'clean': recording['video_details']['clean'],
        'recordingDuration': recording['video_details']['duration'],
        'recordingSize': recording['video_details']['size'],
        'comSkipState': recording['video_details']['comskip']['state'],
        'episodeID': episodeID,
      });
      if (showType != 'movies' && episodesAdded.add(episodeID!)) {
        recordingEpisodes.add(_createEpisodeMap(
            recording['episode'] ?? recording['event'],
            showType,
            showID ?? recordingShowID,
            episodeID));
      }
      if (recording['video_details']['state'] == 'failed' ||
          recording['video_details']['clean'] == false ||
          recording['video_details']['comskip']['state'] != 'none' ||
          recording['video_details']['warnings'].length > 0) {
        recordingErrors.add({
          'recordingID': recording['object_id'],
          'recordingShowID': recordingShowID,
          'showID': showID,
          'episodeID': episodeID,
          'channelID': recording['airing_details']['channel']['object_id'] * -1,
          'airDate': recording['airing_details']['datetime'],
          'airingDuration': recording['airing_details']['duration'],
          'recordingDuration': recording['video_details']['state'],
          'recordingSize': recording['video_details']['size'],
          'recordingState': recording['video_details']['state'],
          'clean': recording['video_details']['clean'],
          'comSkipState': recording['video_details']['comskip']['state'],
          'comSkipError': recording['video_details']['comskip']['error'],
          'errorCode': recording['video_details']['error']?['code'],
          'errorDetails': recording['video_details']['error']?['details'],
          'errorDescription': recording['video_details']['error']
              ?['description'],
        });
      }
    }
    _logMessage('Saving recordings to database.');
    cache.updateRecordings(
        recordingShows, recordings, recordingEpisodes, recordingErrors);
  }

  Future<void> _delete(String path) async {
    final url = Uri.http('$privateIP:$_tabloServerPort', path);
    _logMessage('http.delete($url);');
    await http.delete(url);
  }

  List<List<Map<String, dynamic>>> getConflictedAirings() {
    final conflicts = <List<Map<String, dynamic>>>[];

    final cacheConflicts = cache.getScheduled(excludeScheduled: true);
    final cacheScheduled = cache.getScheduled(excludeConflicts: true);

    for (final conflict in cacheConflicts) {
      final conflictList = <Map<String, dynamic>>[];
      conflictList.add({
        'showTitle': conflict['showTitle'],
        'startDateTime': conflict['startDateTime'],
        'season': conflict['season'],
        'episode': conflict['episode'],
        'episodeTitle': conflict['episodeTitle'],
        'description': conflict['description'],
        'endDateTime': conflict['endDateTime'],
        'path': conflict['path'],
        'airingID': conflict['airingID'],
      });
      for (final scheduled in cacheScheduled) {
        if (_areOverlappingAirings(conflict, scheduled)) {
          conflictList.add({
            'showTitle': scheduled['showTitle'],
            'startDateTime': scheduled['startDateTime'],
            'season': scheduled['season'],
            'episode': scheduled['episode'],
            'episodeTitle': scheduled['episodeTitle'],
            'description': scheduled['description'],
            'endDateTime': scheduled['endDateTime'],
            'path': scheduled['path'],
            'airingID': scheduled['airingID'],
          });
        }
      }
      conflicts.add(conflictList);
    }
    return conflicts;
  }

  static bool _areOverlappingAirings(
      Map<String, dynamic> primary, Map<String, dynamic> secondary) {
    // Breaking out the many positive conditions to keep it readable
    // This method could be re-written as follows, but is difficult to read:
    // return
    //   secondary['startDateTime'].isAtSameMomentAs(primary['startDateTime']) || secondary['endDateTime'].isAtSameMomentAs(primary['endDateTime']) ||
    //   (secondary['startDateTime'].isAfter(primary['startDateTime']) && secondary['startDateTime'].isBefore(primary['endDateTime'])) ||
    //   (secondary['endDateTime'].isAfter(primary['startDateTime']) && secondary['endDateTime'].isBefore(primary['endDateTime'])) ||
    //   (secondary['startDateTime'].isBefore(primary['startDateTime']) && secondary['endDateTime'].isAfter(primary['endDateTime']));
    var overlapping = false;
    if (secondary['startDateTime'].isAtSameMomentAs(primary['startDateTime']) ||
        secondary['endDateTime'].isAtSameMomentAs(primary['endDateTime'])) {
      // Two shoes start or end at the same time
      overlapping = true;
    } else if (secondary['startDateTime'].isAfter(primary['startDateTime']) &&
        secondary['startDateTime'].isBefore(primary['endDateTime'])) {
      // Secondary show starts during the primary show.
      overlapping = true;
    } else if (secondary['endDateTime'].isAfter(primary['startDateTime']) &&
        secondary['endDateTime'].isBefore(primary['endDateTime'])) {
      // Secondary show ends during the primary show
      overlapping = true;
    } else if (secondary['startDateTime'].isBefore(primary['startDateTime']) &&
        secondary['endDateTime'].isAfter(primary['endDateTime'])) {
      // Primary show is entirely during the Secondary show. The inverse is captured in the previous two cases.
      overlapping = true;
    }
    return overlapping;
  }

  List<Map<String, dynamic>> getRecordings(
      {bool bad = false, bool failed = false}) {
    _logMessage('Fetching recordings from database');
    final badRecordingsQueryResults =
        cache.getRecordings(bad: bad, failed: failed);
    final badRecordings = <Map<String, dynamic>>[];
    _logMessage('Parsing recordings');
    for (final badRecording in badRecordingsQueryResults) {
      badRecordings.add({
        'recordingID': badRecording['recordingID'],
        'path': badRecording['path'],
        'showTitle': badRecording['showTitle'],
        'startDateTime': badRecording['startDateTime'],
        'season': badRecording['season'],
        'episode': badRecording['episode'],
        'episodeTitle': badRecording['episodeTitle'],
        'description': badRecording['description'],
        'clean': badRecording['clean'],
        'percentage': badRecording['percentage'],
      });
    }
    return badRecordings;
  }

  Future<void> deleteRecordingList(List<String> paths) async {
    for (final path in paths) {
      await _delete(path);
    }
  }

  Future<void> exportRecording(int recordingID, {bool delete = false}) async {
    const exportSuccessThreshold = 0.997;
    final episodeDetails = cache.getRecordingDetails(recordingID);
    final exportPath = _getExportFullPath(episodeDetails);

    if (File(exportPath).existsSync()) {
      // For now, we'll skip if the file exists already
      // TODO: Optionally suffix
      _logMessage('$exportPath already exists. Skipping.');
      return;
    } else if (!Directory(path.dirname(exportPath)).existsSync()) {
      Directory(path.dirname(exportPath)).createSync(recursive: true);
    }

    final watchApiResponse = await _post('${episodeDetails['path']}/watch');

    _logMessage('Exporting $exportPath');
    final process = await Process.start(path.join('ffmpeg', 'ffmpeg.exe'), [
      '-i',
      '${watchApiResponse['playlist_url']}',
      '-c',
      'copy',
      exportPath
    ]);
    // stderr.addStream(process.stderr);
    // TODO: Do something with this stream to update progress on item somehow
    process.stdout.transform(utf8.decoder).forEach((line) {
      if (line.startsWith('size=')) {
        final speed = line.split('=').last;
        if (speed.startsWith('0')) {
          _logMessage(
              'Speed dropped to $speed. Skipping export for $recordingID');
          process.kill();
          if (File(exportPath).existsSync()) {
            File(exportPath).deleteSync();
          }
          return;
        }
      }
    });
    await process.stderr.drain();
    // await for (final value in process.stdout) {
    //   final str = utf8.decode(value);
    //   if (str.startsWith('size=')) {
    //     final speed = str.split('=').last;
    //     if (speed.startsWith('0')) {
    //       _logMessage('Speed dropped to $speed. Skipping export for $recordingID');
    //       process.kill();
    //       if (File(exportPath).existsSync()) {
    //         File(exportPath).deleteSync();
    //       }
    //       return;
    //     }
    //   }
    // }

    _logMessage('Verifying export $exportPath.');
    final durationRaw =
        await Process.runSync(path.join('ffmpeg', 'ffprobe.exe'), [
      '-v',
      'error',
      '-hide_banner',
      '-of',
      'default=noprint_wrappers=0',
      '-print_format',
      'json',
      '-show_entries',
      'stream=duration',
      exportPath
    ]).stdout;
    final duration = json.decode(durationRaw.toString());

    double exportDuration = 0.0;
    final recordingDuration = episodeDetails['recordingDuration'].toDouble();
    final firstDuration = double.parse(duration['streams'][0]['duration']);
    final secondDuration = double.parse(duration['streams'][1]['duration']);

    if (firstDuration >= secondDuration * exportSuccessThreshold &&
        firstDuration * exportSuccessThreshold <= secondDuration) {
      exportDuration = min(firstDuration, secondDuration);
    } else if (File(exportPath).existsSync()) {
      _logMessage('Stream duration variance outside of error threshold.');
      _logMessage('1: $firstDuration 2: $secondDuration');
      File(exportPath).deleteSync();
      return;
    }

    if (delete &&
        exportDuration >= recordingDuration * exportSuccessThreshold) {
      await _delete(episodeDetails['path']);
    } else if (File(exportPath).existsSync() &&
        exportDuration < recordingDuration * exportSuccessThreshold) {
      _logMessage('Export does not match recorded length.');
      _logMessage('Export: $exportDuration Recorded: $recordingDuration');
      File(exportPath).deleteSync();
    }
  }

  String _getExportFullPath(Map<String, dynamic> episodeDetails) {
    // TODO: Create a logic to customize file naming
    final sanitizedEpisodeDetails = _sanitizeMap(episodeDetails);
    var fullPath = r'\\bigdaddy\TabloBackups\';
    switch (sanitizedEpisodeDetails['showType']) {
      case 'series':
        fullPath = path.join(
            fullPath,
            'TV',
            sanitizedEpisodeDetails['showTitle'],
            'Season ${sanitizedEpisodeDetails['season']}',
            '${sanitizedEpisodeDetails['showTitle']} - s${sanitizedEpisodeDetails['season']}e${sanitizedEpisodeDetails['episode']} - ${sanitizedEpisodeDetails['episodeTitle']}.mp4');
      case 'movies':
        fullPath = path.join(
            fullPath, 'Movies', '${sanitizedEpisodeDetails['showTitle']}.mp4');
      case 'sports':
        fullPath = path.join(
            fullPath,
            'Sports',
            sanitizedEpisodeDetails['showTitle'],
            'Season ${sanitizedEpisodeDetails['season']}',
            '.mp4');
    }
    return fullPath;
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    final sanitizedMap = <String, dynamic>{};
    for (final key in map.keys) {
      if (map[key] is String) {
        sanitizedMap[key] = _sanitizeString(map[key]);
      } else if (map[key] is int) {
        sanitizedMap[key] = map[key];
      } else {
        throw FormatException(
            'Unable to sanitize map[$key]: ${map[key].runtimeType}');
      }
    }
    return sanitizedMap;
  }

  String _sanitizeString(String str) {
    var sanitizedString = str.replaceAll(RegExp(r'''[\\/:*?"<>|']'''), '_');
    if (sanitizedString.length == 1) {
      try {
        int.parse(sanitizedString);
        return '0$sanitizedString';
      } on FormatException {
        return sanitizedString;
      }
    } else if (sanitizedString.length > 50) {
      return sanitizedString.substring(0, 50);
    }
    return sanitizedString;
  }
}
