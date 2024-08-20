import 'dart:io';
import 'dart:developer';

import 'package:sqlite3/sqlite3.dart';
import 'package:tablo_app/log.dart';

class TabloDatabase {
  final Database db;
  final String serverID;
  static const _dbVer = 1;

  static const _currentLibrary = 'tablo_database';
  static Log _log = Log();

  static void redirectLog(Log log) {
    _log = log;
  }

  bool get isNew {
    ResultSet result;
    try {
      result = db.select('SELECT serverID FROM systemInfo;');
    } on SqliteException {
      return true;
    }
    return result.isEmpty || result.first['serverID'] != serverID;
  }

  TabloDatabase._internalConstructor(this.db, this.serverID) {
    try {
      final result = db.select('SELECT dbVer FROM systemInfo;');
      final dbVer = result.isNotEmpty ? result.first['dbVer'] : null;
      if (dbVer == null || dbVer != _dbVer) {
        _init();
      }
    } on SqliteException {
      _init();
    }
  }

  static Future<TabloDatabase> getDatabase(String serverID) async {
    Directory('databases').createSync();
    final databaseLocal = sqlite3.open('databases/$serverID.cache');
    final databaseMemory = sqlite3.openInMemory();
    await _backup(databaseLocal, databaseMemory);
    if (_validate(databaseLocal, databaseMemory)) {
      databaseLocal.dispose();
    } else {
      throw SqliteException(1, 'Error copying db to memory');
    }
    return TabloDatabase._internalConstructor(databaseMemory, serverID);
  }

  _init() {
    final newDB = sqlite3.openInMemory();
    _backup(newDB, db);
    newDB.dispose();

    _createSystemInfoTable();
    _createGuideTables();
    _createRecordingTables();
    _createSettingsTables();
    saveToDisk();
  }

  _createSystemInfoTable() {
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('''
      CREATE TABLE systemInfo (
        serverID TEXT NOT NULL PRIMARY KEY,
        serverName TEXT NOT NULL,
        privateIP TEXT NOT NULL,
        dbVer INT NOT NULL,
        lastUpdated INT NOT NULL,
        lastSaved INT NOT NULL,
        totalSize INT,
        freeSize INT
      );
    ''');
  }

  _createGuideTables() {
    db.execute('''
      CREATE TABLE channel (
        channelID     INT NOT NULL PRIMARY KEY,
        callSign      TEXT NOT NULL,
        major         INT NOT NULL,
        minor         INT NOT NULL,
        network       TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE rule (
        ruleID        INTEGER PRIMARY KEY,
        rule          TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE keepRecording (
        keepRecordingID INTEGER PRIMARY KEY,
        keepRecording   TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE showType (
        showTypeID    INTEGER PRIMARY KEY,
        showType      TEXT NOT NULL,
        suffix        TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE genre (
        genreID       INTEGER PRIMARY KEY,
        genre         TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE rating (
        ratingID      INTEGER PRIMARY KEY,
        rating        TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE cast (
        castID        INTEGER PRIMARY KEY,
        cast          TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE awardName (
        awardNameID   INTEGER PRIMARY KEY,
        awardName     TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE awardCategory (
        awardCategoryID INTEGER PRIMARY KEY,
        awardCategory   TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE show (
        showID          INT NOT NULL PRIMARY KEY,
        parentShowID    INT,
        ruleID          INT,
        channelID       INT,
        keepRecordingID INT NOT NULL,
        count           INT,
        showTypeID      INT NOT NULL,
        title           TEXT NOT NULL,
        descript        TEXT,
        releaseDate     INT,
        origRunTime     INT,
        ratingID        INT,
        stars           INT,
        FOREIGN KEY (parentShowID) REFERENCES show(showID),
        FOREIGN KEY (ruleID) REFERENCES rule(ruleID),
        FOREIGN KEY (channelID) REFERENCES channel(channelID),
        FOREIGN KEY (keepRecordingID) REFERENCES keepRecording(keepRecordingID),
        FOREIGN KEY (showTypeID) REFERENCES showType(showTypeID),
        FOREIGN KEY (ratingID) REFERENCES rating(ratingID)
      );
    ''');
    db.execute('''
      CREATE TABLE showAward (
        showID          INT NOT NULL,
        won             INT NOT NULL,
        awardNameID     INT NOT NULL,
        awardCategoryID INT NOT NULL,
        awardYear       INT NOT NULL,
        castID          INT,
        PRIMARY KEY (showID, awardNameID, awardCategoryID, awardYear, castID),
        FOREIGN KEY (showID) REFERENCES show(showID),
        FOREIGN KEY (awardNameID) REFERENCES awardName(awardNameID),
        FOREIGN KEY (awardCategoryID) REFERENCES awardCategory(awardCategoryID),
        FOREIGN KEY (castID) REFERENCES cast(castID)
      );
    ''');
    db.execute('''
      CREATE TABLE showGenre (
        showID        INT NOT NULL,
        genreID       INT NOT NULL,
        PRIMARY KEY (showID, genreID),
        FOREIGN KEY (showID) REFERENCES show(showID),
        FOREIGN KEY (genreID) REFERENCES genre(genreID)
      );
    ''');
    db.execute('''
      CREATE TABLE showCast (
        showID        INT NOT NULL,
        castID        INT NOT NULL,
        PRIMARY KEY (showID, castID),
        FOREIGN KEY (showID) REFERENCES show(showID),
        FOREIGN KEY (castID) REFERENCES cast(castID)
      );
    ''');
    db.execute('''
      CREATE TABLE showDirector (
        showID        INT NOT NULL,
        castID        INT NOT NULL,
        PRIMARY KEY (showID, castID),
        FOREIGN KEY (showID) REFERENCES show(showID),
        FOREIGN KEY (castID) REFERENCES cast(castID)
      );
    ''');
    db.execute('''
      CREATE TABLE scheduled (
        scheduledID   INTEGER PRIMARY KEY,
        scheduled     TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE seasonType (
        seasonTypeID  INTEGER PRIMARY KEY,
        seasonType    TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE team (
        teamID        INT NOT NULL PRIMARY KEY,
        team          TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE season (
        seasonID      INTEGER PRIMARY KEY,
        season        TEXT NOT NULL
      );
    ''');
    db.execute('''
      INSERT INTO  season (seasonID, season) VALUES (1000, '1000');
    ''');
    db.execute('''
      CREATE TABLE episode (
        episodeID       TEXT NOT NULL PRIMARY KEY,
        showID          INT NOT NULL,
        title           TEXT,
        descript        TEXT,
        episode         INT,
        seasonID        INT,
        seasonTypeID    INT,
        originalAirDate INT,
        homeTeamID      INT,
        FOREIGN KEY (showID) REFERENCES show(showID),
        FOREIGN KEY (seasonID) REFERENCES season(seasonID),
        FOREIGN KEY (seasonTypeID) REFERENCES seasonType(seasonTypeID),
        FOREIGN KEY (homeTeamID) REFERENCES team(teamID)
      );
    ''');
    db.execute('''
      CREATE TABLE airing (
        airingID      INT NOT NULL PRIMARY KEY,
        showID        INT NOT NULL,
        airDate       INT NOT NULL,
        duration      INT NOT NULL,
        channelID     INT NOT NULL,
        scheduledID   INT NOT NULL,
        episodeID     TEXT,
        FOREIGN KEY (showID) REFERENCES show(showID),
        FOREIGN KEY (channelID) REFERENCES channel(channelID),
        FOREIGN KEY (scheduledID) REFERENCES scheduled(scheduledID),
        FOREIGN KEY (episodeID) REFERENCES episode(episodeID)
      );
    ''');
    db.execute('''
      CREATE TABLE episodeTeam (
        episodeID     TEXT NOT NULL,
        teamID        INT NOT NULL,
        PRIMARY KEY (episodeID, teamID),
        FOREIGN KEY (episodeID) REFERENCES episode(episodeID),
        FOREIGN KEY (teamID) REFERENCES team(teamID)
      );
    ''');
  }

  _createRecordingTables() {
    db.execute('''
      CREATE TABLE recordingState (
        recordingStateID  INTEGER PRIMARY KEY,
        recordingState    TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE comSkipState (
        comSkipStateID    INTEGER PRIMARY KEY,
        comSkipState      TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE recording (
        recordingID       INT NOT NULL PRIMARY KEY,
        showID            INT NOT NULL,
        airDate           INT NOT NULL,
        airingDuration    INT NOT NULL,
        channelID         INT NOT NULL,
        recordingStateID  INT NOT NULL,
        clean             INT NOT NULL,
        recordingDuration INT NOT NULL,
        recordingSize     INT NOT NULL,
        comSkipStateID    INT NOT NULL,
        episodeID         INT,
        FOREIGN KEY (showID) REFERENCES show(showID),
        FOREIGN KEY (channelID) REFERENCES channel(channelID),
        FOREIGN KEY (recordingStateID) REFERENCES recordingState(recordingStateID),
        FOREIGN KEY (comSkipStateID) REFERENCES comSkipState(comSkipStateID),
        FOREIGN KEY (episodeID) REFERENCES episode(episodeID)
      );
    ''');
    db.execute('''
      CREATE TABLE errorCode (
        errorCodeID INTEGER PRIMARY KEY,
        errorCode   TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE errorDetails (
        errorDetailsID  INTEGER PRIMARY KEY,
        errorDetails    TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE error (
        errorID           INTEGER PRIMARY KEY,
        recordingID       INT NOT NULL,
        recordingShowID   INT NOT NULL,
        showID            INT,
        episodeID         INT,
        channelID         INT NOT NULL,
        airDate           INT NOT NULL,
        airingDuration    INT NOT NULL,
        recordingDuration INT NOT NULL,
        recordingSize     INT NOT NULL,
        recordingStateID  INT NOT NULL,
        clean             INT NOT NULL,
        comSkipStateID    INT NOT NULL,
        comSkipError      TEXT,
        errorCodeID       INT,
        errorDetailsID    INT,
        errorDescription  TEXT,
        FOREIGN KEY (errorCodeID) REFERENCES errorCode(errorCodeID),
        FOREIGN KEY (errorDetailsID) REFERENCES errorDetails(errorDetailsID)
      );
    ''');
  }

  _createSettingsTables() {
    // TODO: Figure out what goes here and what the defaults are.
    db.execute('''
      CREATE TABLE settings (
        settingID         INT NOT NULL PRIMARY KEY
      );
    ''');
    db.execute('''
      CREATE TABLE queue (
        queueID           INT NOT NULL PRIMARY KEY
      );
    ''');
  }

  updateSystemInfoTable(Map<String, dynamic> sysInfo) {
    sysInfo = _sanitizeMap(sysInfo);
    db.execute('''
      INSERT INTO systemInfo (
        serverID,
        serverName,
        privateIP,
        dbVer,
        lastUpdated,
        lastSaved,
        totalSize,
        freeSize
      )
      VALUES (
        ${sysInfo['serverID']},
        ${sysInfo['serverName']},
        ${sysInfo['privateIP']},
        $_dbVer,
        0,
        0,
        ${sysInfo['totalSize']},
        ${sysInfo['freeSize']}
      )
      ON CONFLICT DO UPDATE SET
        serverName = ${sysInfo['serverName']},
        privateIP = ${sysInfo['privateIP']},
        totalSize = ${sysInfo['totalSize']},
        freeSize = ${sysInfo['freeSize']};
    ''');
  }

  updateChannels(List<Map<String, dynamic>> channels) {
    final channelsClean = _sanitizeList(channels);
    for (final channel in channelsClean) {
      db.execute('''
        INSERT INTO channel(
          channelID,
          callSign,
          major,
          minor,
          network
        )
        VALUES (
          ${channel['channelID']},
          ${channel['callSign']},
          ${channel['major']},
          ${channel['minor']},
          ${channel['network']}
        )
        ON CONFLICT DO UPDATE SET
          callSign = ${channel['callSign']},
          major = ${channel['major']},
          minor = ${channel['minor']},
          network = ${channel['network']};
      ''');
    }
  }

  updateGuideShows(List<Map<String, dynamic>> guideShows) {
    var lookup = <String, Map>{};

    lookup['rule'] = _getLookup('rule');
    lookup['keepRecording'] = _getLookup('keepRecording');
    lookup['showType'] = _getLookup('showType');
    lookup['genre'] = _getLookup('genre');
    lookup['rating'] = _getLookup('rating');
    lookup['cast'] = _getLookup('cast');
    lookup['awardName'] = _getLookup('awardName');
    lookup['awardCategory'] = _getLookup('awardCategory');
    lookup['showType'] = _getLookup('showType');

    lookup = _updateLookups(guideShows, lookup);
    guideShows = _addLookupIDs(guideShows, lookup);
    final guideShowsClean = _sanitizeList(guideShows);
    for (final show in guideShowsClean) {
      _updateShow(show);
    }
  }

  void _updateShow(show) {
    db.execute('''
      INSERT INTO show (
        showID,
        parentShowID,
        ruleID,
        channelID,
        keepRecordingID,
        count,
        showTypeID,
        title,
        descript,
        releaseDate,
        origRunTime,
        ratingID,
        stars
      )
      VALUES (
        ${show['showID']},
        ${show['parentShowID']},
        ${show['ruleID']},
        ${show['channelID']},
        ${show['keepRecordingID']},
        ${show['count']},
        ${show['showTypeID']},
        ${show['title']},
        ${show['descript']},
        ${_convertDateTimeToInt(show['releaseDate'])},
        ${show['origRunTime']},
        ${show['ratingID']},
        ${show['stars']}
      )
      ON CONFLICT DO UPDATE SET
        parentShowID = ${show['parentShowID']},
        ruleID = ${show['ruleID']},
        channelID = ${show['channelID']},
        keepRecordingID = ${show['keepRecordingID']},
        count = ${show['count']},
        showTypeID = ${show['showTypeID']},
        title = ${show['title']},
        descript = ${show['descript']},
        releaseDate = ${_convertDateTimeToInt(show['releaseDate'])},
        origRunTime = ${show['origRunTime']},
        ratingID = ${show['ratingID']},
        stars = ${show['stars']};
    ''');
    if (show['cast'] != null &&
        show['cast'].length > 0 &&
        show['parentShowID'] == null) {
      for (final castID in show['castID']) {
        db.execute('''
          INSERT INTO showCast (showID, castID) VALUES (${show['showID']}, $castID) ON CONFLICT DO NOTHING;
        ''');
      }
    }
    if (show['genre'] != null &&
        show['genre'].length > 0 &&
        show['parentShowID'] == null) {
      for (final genreID in show['genreID']) {
        db.execute('''
          INSERT INTO showGenre (showID, genreID) VALUES (${show['showID']}, $genreID) ON CONFLICT DO NOTHING;
        ''');
      }
    }
    if (show['director'] != null &&
        show['director'].length > 0 &&
        show['parentShowID'] == null) {
      for (final castID in show['directorID']) {
        db.execute('''
          INSERT INTO showDirector (showID, castID) VALUES (${show['showID']}, $castID) ON CONFLICT DO NOTHING;
        ''');
      }
    }
    if (show['award'] != null &&
        show['award'].length > 0 &&
        show['parentShowID'] == null) {
      for (final award in show['award']) {
        db.execute('''
          INSERT INTO showAward (
            showID,
            won,
            awardNameID,
            awardCategoryID,
            awardYear,
            castID
          )
          VALUES (
            ${show['showID']},
            ${award['won'] ? 1 : 0},
            ${award['awardNameID']},
            ${award['awardCategoryID']},
            ${award['awardYear']},
            ${award['castID']}
          )
          ON CONFLICT DO NOTHING;
        ''');
      }
    }
  }

  updateGuideAirings(List<Map<String, dynamic>> guideAirings,
      List<Map<String, dynamic>> guideEpisodes) {
    var lookup = <String, Map>{};

    lookup['scheduled'] = _getLookup('scheduled');
    lookup['season'] = _getLookup('season');
    lookup['seasonType'] = _getLookup('seasonType');
    lookup = _updateLookups(guideAirings, lookup);
    lookup = _updateLookups(guideEpisodes, lookup);
    guideAirings = _addLookupIDs(guideAirings, lookup);
    guideEpisodes = _addLookupIDs(guideEpisodes, lookup);
    final guideAiringsClean = _sanitizeList(guideAirings);
    final guideEpisodesClean = _sanitizeList(guideEpisodes);
    for (final episode in guideEpisodesClean) {
      _updateEpisode(episode);
    }
    for (final airing in guideAiringsClean) {
      db.execute('''
        INSERT INTO airing (
          airingID,
          showID,
          airDate,
          duration,
          channelID,
          scheduledID,
          episodeID
        )
        VALUES (
          ${airing['airingID']},
          ${airing['showID']},
          ${_convertDateTimeToInt(airing['airDate'])},
          ${airing['duration']},
          ${airing['channelID']},
          ${airing['scheduledID']},
          ${airing['episodeID']}
        )
        ON CONFLICT DO UPDATE SET
          showID = ${airing['showID']},
          airDate = ${_convertDateTimeToInt(airing['airDate'])},
          duration = ${airing['duration']},
          channelID = ${airing['channelID']},
          scheduledID = ${airing['scheduledID']},
          episodeID = ${airing['episodeID']};
      ''');
    }
  }

  String _sanitizeString(String value) {
    var cleanValue = value.replaceAll("'", "''");
    return cleanValue == 'null' ? cleanValue : "'$cleanValue'";
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    final cleanMap = <String, dynamic>{};
    for (final key in map.keys) {
      if (map[key] is String) {
        cleanMap[key] = _sanitizeString(map[key]);
      } else if (map[key] is Map<String, dynamic>) {
        cleanMap[key] = _sanitizeMap(map[key]);
      } else if (map[key] is List<dynamic>) {
        cleanMap[key] = _sanitizeList(map[key]);
      } else {
        cleanMap[key] = map[key];
      }
    }
    return cleanMap;
  }

  List<dynamic> _sanitizeList(List<dynamic> list) {
    final cleanList = <dynamic>[];
    for (final item in list) {
      if (item is String) {
        cleanList.add(_sanitizeString(item));
      } else if (item is Map<String, dynamic>) {
        cleanList.add(_sanitizeMap(item));
      } else if (item is List<dynamic>) {
        cleanList.add(_sanitizeList(item));
      } else {
        cleanList.add(item);
      }
    }
    return cleanList;
  }

  saveToDisk() {
    final writedb = sqlite3.open('databases/$serverID.cache');
    _backup(db, writedb);
    writedb.dispose();
  }

  Map<String, Map> _updateLookups(dynamic items, Map<String, Map> lookup) {
    final uniqueInput = <String, Set>{};
    for (final table in lookup.keys) {
      uniqueInput[table] = <String>{};
    }
    final keys = <dynamic>[];
    if (items is List) {
      keys.addAll(List<int>.generate(items.length, (int i) => i));
    } else if (items is Map) {
      keys.addAll(items.keys);
    } else {
      throw FormatException(
          "_updateLookups: items must be List or Map. Input type: ${items.runtimeType}");
    }
    for (final key in keys) {
      final item = items[key];
      for (final table in lookup.keys) {
        if (item[table] is List) {
          for (final subItem in item[table]) {
            uniqueInput[table]!.add(subItem);
          }
          if (table == 'cast' && item['director'] != null) {
            for (final subItem in item['director']) {
              uniqueInput[table]!.add(subItem);
            }
          }
        } else if (item[table] != null && item[table] != "null") {
          uniqueInput[table]!.add(item[table]);
        }
      }
      if (item['award'] != null && item['award'].length > 0) {
        for (final subItem in item['award']) {
          for (final table in lookup.keys) {
            if (subItem[table] != null) {
              uniqueInput[table]!.add(subItem[table]);
            }
          }
        }
      }
      if (item['team'] != null && item['team'].length > 0) {
        for (final subItem in item['team']) {
          db.execute('''
            INSERT INTO team (teamID, team)
            VALUES (${subItem['teamID']}, ${_sanitizeString(subItem['team'])})
            ON CONFLICT DO NOTHING;
          ''');
        }
      }
    }
    for (final table in lookup.keys) {
      for (final item in uniqueInput[table]!) {
        if (!lookup[table]!.containsKey(item)) {
          final itemClean = _sanitizeString(item);
          if (table == 'season') {
            try {
              final season = int.parse(item);
              if (season < 1000) {
                db.execute('''
                  INSERT INTO season (seasonID, season) VALUES ($item, $itemClean);
                ''');
              } else {
                db.execute('''
                  INSERT INTO season (season) VALUES ($itemClean);
                ''');
              }
            } on Exception {
              db.execute('''
                INSERT INTO season (season) VALUES ($itemClean);
              ''');
            }
          } else {
            db.execute('''
              INSERT INTO $table ($table)
              VALUES ($itemClean);
            ''');
          }
          final itemID = db.select('''
            SELECT ${table}ID
            FROM $table as lutable
            WHERE lutable.$table = $itemClean;
          ''');
          lookup[table]![item] = itemID.first['${table}ID'];
        }
      }
    }
    return lookup;
  }

  dynamic _addLookupIDs(dynamic items, Map<String, dynamic> lookup) {
    final keys = <dynamic>[];
    if (items is List) {
      keys.addAll(List<int>.generate(items.length, (int i) => i));
    } else if (items is Map) {
      keys.addAll(items.keys);
    } else {
      throw FormatException(
          "_addLookupIDs: items must be List or Map. Input type: ${items.runtimeType}");
    }
    for (final key in keys) {
      for (final table in lookup.keys) {
        final lookupValue = items[key][table];
        if (lookupValue is String) {
          items[key]['${table}ID'] = (lookup[table] as Map)[lookupValue];
        } else if (lookupValue is List) {
          final lookupIDs = <int>[];
          for (final val in lookupValue) {
            lookupIDs.add(lookup[table][val]);
          }
          items[key]['${table}ID'] = lookupIDs;
          if (table == 'cast' && items[key]['director'] != null) {
            lookupIDs.clear();
            for (final val in items[key]['director']) {
              lookupIDs.add(lookup[table][val]);
            }
            items[key]['directorID'] = lookupIDs;
          }
        }
      }
      if (items[key]['award'] != null && items[key]['award'].length > 0) {
        for (var j = 0; j < items[key]['award'].length; ++j) {
          for (final table in lookup.keys) {
            final lookupValue = items[key]['award'][j][table];
            if (lookupValue != null) {
              items[key]['award'][j]['${table}ID'] =
                  (lookup[table] as Map)[lookupValue];
            }
          }
        }
      }
    }
    return items;
  }

  Map<String, int> _getLookup(String table) {
    final lookupTableMap = <String, int>{};
    final lookupTable = db.select('SELECT * FROM $table');
    for (final lookupRow in lookupTable) {
      lookupTableMap[lookupRow[table]] = lookupRow['${table}ID'];
    }
    return lookupTableMap;
  }

  String? _convertDateTimeToInt(dynamic date) {
    var dateTime = DateTime.fromMicrosecondsSinceEpoch(0);
    if (date is int) {
      dateTime = DateTime(date);
    } else if (date is String) {
      if (date.startsWith("'")) {
        date = date.substring(1, date.length - 1);
      }
      dateTime = DateTime.parse(date);
    } else {
      return null;
    }
    return (dateTime.millisecondsSinceEpoch ~/ 1000).toString();
  }

  static String? getIP(String databasePath) {
    String? privateIP;
    try {
      final db = sqlite3.open(databasePath);
      final result = db.select('SELECT privateIP FROM systemInfo;');
      privateIP = result.first['privateIP'];
    } on Exception {
      return null;
    }
    return privateIP;
  }

  static bool _validate(Database databaseLocal, Database databaseMemory) {
    try {
      const sql = 'SELECT serverID FROM systemInfo;';
      ResultSet? localResults;
      try {
        localResults = databaseLocal.select(sql);
      } on SqliteException {
        try {
          databaseMemory.select(sql);
        } on SqliteException {
          return true;
        }
        return false;
      }
      final memoryResults = databaseMemory.select(sql);
      if (localResults.length != memoryResults.length) {
        return false;
      } else if (localResults.isNotEmpty) {
        return localResults.first['serverID'] ==
            memoryResults.first['serverID'];
      } else {
        return true;
      }
    } on SqliteException {
      return false;
    }
  }

  static _backup(Database fromDatabase, Database toDatabase) async {
    final stream = fromDatabase.backup(toDatabase);
    await stream.drain();
  }

  static void _logMessage(String message, {String? level}) {
    if (level == null) {
      _log.logMessage(_currentLibrary, message);
    } else {
      _log.logMessage(_currentLibrary, message, level: level);
    }
  }

  void updateRecordings(
      List<Map<String, dynamic>> recordingShows,
      List<Map<String, dynamic>> recordings,
      List<Map<String, dynamic>> recordingEpisodes,
      List<Map<String, dynamic>> recordingErrors) {
    _logMessage('Beginning updateRecordings.');
    var lookup = <String, Map>{};

    _logMessage('Getting lookup tables.');
    lookup['recordingState'] = _getLookup('recordingState');
    lookup['comSkipState'] = _getLookup('comSkipState');
    lookup['errorCode'] = _getLookup('errorCode');
    lookup['errorDetails'] = _getLookup('errorDetails');
    lookup['season'] = _getLookup('season');
    lookup['seasonType'] = _getLookup('seasonType');
    lookup['keepRecording'] = _getLookup('keepRecording');
    lookup['showType'] = _getLookup('showType');
    lookup['cast'] = _getLookup('cast');
    lookup['awardName'] = _getLookup('awardName');
    lookup['rating'] = _getLookup('rating');
    lookup['awardCategory'] = _getLookup('awardCategory');
    lookup['genre'] = _getLookup('genre');

    _logMessage('Updating lookup tables with new values.');
    lookup = _updateLookups(recordings, lookup);
    lookup = _updateLookups(recordingEpisodes, lookup);
    lookup = _updateLookups(recordingErrors, lookup);
    lookup = _updateLookups(recordingShows, lookup);

    _logMessage('Adding lookup IDs to records.');
    recordings = _addLookupIDs(recordings, lookup);
    recordingEpisodes = _addLookupIDs(recordingEpisodes, lookup);
    recordingErrors = _addLookupIDs(recordingErrors, lookup);
    recordingShows = _addLookupIDs(recordingShows, lookup);

    _logMessage('Sanitizing strings for SQL,');
    final recordingsClean = _sanitizeList(recordings);
    final recordingEpisodesClean = _sanitizeList(recordingEpisodes);
    final recordingErrorsClean = _sanitizeList(recordingErrors);
    final recordingShowsClean = _sanitizeList(recordingShows);

    _logMessage('Beginning updating ${recordingShowsClean.length} shows.');
    for (final show in recordingShowsClean) {
      _updateShow(show);
    }

    _logMessage(
        'Beginning updating ${recordingEpisodesClean.length} episodes.');
    for (final episode in recordingEpisodesClean) {
      _updateEpisode(episode);
    }

    _logMessage('Beginning updating ${recordingsClean.length} recordings.');
    for (final recording in recordingsClean) {
      db.execute('''
        INSERT INTO recording (
          recordingID,
          showID,
          airDate,
          airingDuration,
          channelID,
          recordingStateID,
          clean,
          recordingDuration,
          recordingSize,
          comSkipStateID,
          episodeID
        )
        VALUES (
          ${recording['recordingID']},
          ${recording['showID']},
          ${_convertDateTimeToInt(recording['airDate'])},
          ${recording['airingDuration']},
          ${recording['channelID']},
          ${recording['recordingStateID']},
          ${recording['clean'] ? 1 : 0},
          ${recording['recordingDuration']},
          ${recording['recordingSize']},
          ${recording['comSkipStateID']},
          ${recording['episodeID']}
        )
        ON CONFLICT DO UPDATE SET
          showID = ${recording['showID']},
          airDate = ${_convertDateTimeToInt(recording['airDate'])},
          airingDuration = ${recording['airingDuration']},
          channelID = ${recording['channelID']},
          recordingStateID = ${recording['recordingStateID']},
          clean = ${recording['clean'] ? 1 : 0},
          recordingDuration = ${recording['recordingDuration']},
          recordingSize = ${recording['recordingSize']},
          comSkipStateID = ${recording['comSkipStateID']},
          episodeID = ${recording['episodeID']};
      ''');
    }

    _logMessage('Beginning updating ${recordingErrorsClean.length} errors.');
    for (final error in recordingErrorsClean) {
      db.execute('''
        INSERT INTO error (
          recordingID,
          recordingShowID,
          showID,
          episodeID,
          channelID,
          airDate,
          airingDuration,
          recordingDuration,
          recordingSize,
          recordingStateID,
          clean,
          comSkipStateID,
          comSkipError,
          errorCodeID,
          errorDetailsID,
          errorDescription
        )
        VALUES (
          ${error['recordingID']},
          ${error['recordingShowID']},
          ${error['showID']},
          ${error['episodeID']},
          ${error['channelID']},
          ${_convertDateTimeToInt(error['airDate'])},
          ${error['airingDuration']},
          ${error['recordingDuration']},
          ${error['recordingSize']},
          ${error['recordingStateID']},
          ${error['clean'] ? 1 : 0},
          ${error['comSkipStateID']},
          ${error['comSkipError']},
          ${error['errorCodeID']},
          ${error['errorDetailsID']},
          ${error['errorDescription']}
        )
        ON CONFLICT DO NOTHING;
      ''');
    }
  }

  void _updateEpisode(episode) {
    db.execute('''
      INSERT INTO episode (
        episodeID,
        showID,
        title,
        descript,
        episode,
        seasonID,
        seasonTypeID,
        originalAirDate,
        homeTeamID
      )
      VALUES (
        ${episode['episodeID']},
        ${episode['showID']},
        ${episode['title']},
        ${episode['descript']},
        ${episode['episode']},
        ${episode['seasonID']},
        ${episode['seasonTypeID']},
        ${_convertDateTimeToInt(episode['originalAirDate'])},
        ${episode['homeTeamID']}
      )
      ON CONFLICT DO UPDATE SET
        title = ${episode['title']},
        descript = ${episode['descript']},
        seasonTypeID = ${episode['seasonTypeID']},
        originalAirDate = ${_convertDateTimeToInt(episode['originalAirDate'])},
        homeTeamID = ${episode['homeTeamID']};
    ''');
    if (episode['team'] != null && episode['team'].length > 0) {
      for (final team in episode['team']) {
        db.execute('''
          INSERT INTO episodeTeam (episodeID, teamID) VALUES (${episode['episodeID']}, ${team['teamID']}) ON CONFLICT DO NOTHING;
        ''');
      }
    }
  }
}
