import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

class TabloDatabase{
  final Database db;
  final String serverID;
  static const _dbVer = 1;
  
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
    _createErrorTable();
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
      CREATE TABLE channelType (
        channelTypeID INTEGER PRIMARY KEY,
        channelType   TEXT UNIQUE NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE channel (
        channelID     INT NOT NULL,
        channelTypeID INT NOT NULL,
        callSign      TEXT NOT NULL,
        major         INT NOT NULL,
        minor         INT NOT NULL,
        network       TEXT,
        PRIMARY KEY (channelID, channelTypeID),
        FOREIGN KEY (channelTypeID) REFERENCES channelType(channelTypeID)
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
        ruleID          INT,
        channelID       INT,
        channelTypeID   INT,
        keepRecordingID INT NOT NULL,
        count           INT,
        showTypeID      INT NOT NULL,
        title           TEXT NOT NULL,
        descript        TEXT,
        releaseDate     INT NOT NULL,
        origRunTime     INT,
        ratingID        INT,
        stars           INT,
        FOREIGN KEY (ruleID) REFERENCES rule(ruleID),
        FOREIGN KEY (channelID, channelTypeID) REFERENCES channel(channelID, channelTypeID),
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
        year            INT NOT NULL,
        castID          INT,
        PRIMARY KEY (showID, awardNameID, awardCategoryID, year, castID),
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
      CREATE TABLE airing (
        airingID      INT NOT NULL PRIMARY KEY,
        showID        INT,
        datetime      INT,
        duration      INT,
        channelID     INT,
        scheduledID   INT,
        episodeID     INT
      );
    ''');
    db.execute('''
      CREATE TABLE scheduled (
        scheduledID   INT NOT NULL PRIMARY KEY,
        scheduled     TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE episode (
        episodeID     INT NOT NULL PRIMARY KEY,
        title         TEXT,
        descript      TEXT,
        episode       INT,
        season        INT,
        seasonTypeID  INT,
        airDate       INT,
        venueID       INT,
        homeTeamID    INT
      );
    ''');
    db.execute('''
      CREATE TABLE season (
        seasonID      INT NOT NULL PRIMARY KEY,
        season        TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE seasonType (
        seasonTypeID  INT NOT NULL PRIMARY KEY,
        seasonType    TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE venue (
        venueID       INT NOT NULL PRIMARY KEY,
        venue         TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE team (
        teamID        INT NOT NULL PRIMARY KEY,
        name          TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE episodeTeam (
        episodeID     INT NOT NULL,
        teamID        INT NOT NULL
      );
    ''');
  }

  _createRecordingTables() {
    db.execute('''
      CREATE TABLE recordingShow (
        recordingShowID   INT NOT NULL PRIMARY KEY,
        showID            INT
      );
    ''');
    db.execute('''
      CREATE TABLE recording (
        recordingID       INT NOT NULL PRIMARY KEY,
        recordingShowID   INT,
        datetime          INT,
        airingDuration    INT,
        channelID         INT,
        stateID           INT,
        clean             INT,
        recordingDuration INT,
        comSkipStateID    INT,
        episodeID         INT
      );
    ''');
    db.execute('''
      CREATE TABLE state (
        stateID           INT NOT NULL PRIMARY KEY,
        state             TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE comSkipState (
        comSkipStateID    INT NOT NULL PRIMARY KEY,
        comSkipState      TEXT
      );
    ''');
  }

  _createErrorTable() {
    db.execute('''
      CREATE TABLE error (
        errorID           INT NOT NULL PRIMARY KEY,
        recordingID       INT,
        recordingShowID   INT,
        showID            INT,
        episodeID         INT,
        channelID         INT,
        datetime          INT,
        duration          INT,
        comSkipStateID    INT,
        comSkipError      TEXT,
        errorCode         TEXT,
        errorDetails      TEXT,
        errorDesc         TEXT
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
      ) ON CONFLICT DO UPDATE SET
        serverName = ${sysInfo['serverName']},
        privateIP = ${sysInfo['privateIP']},
        totalSize = ${sysInfo['totalSize']},
        freeSize = ${sysInfo['freeSize']};
    ''');
  }

  updateChannels(List<Map<String, dynamic>> channels) {
    Map<String, Map> lookup = {'channelType': _getLookup('channelType')};
    lookup = _updateLookups(channels, lookup);
    channels = _addLookupIDs(channels, lookup);
    final channelsClean = _sanitizeList(channels);
    for (final channel in channelsClean) {
      db.execute('''
        INSERT INTO channel(
          channelID,
          channelTypeID,
          callSign,
          major,
          minor,
          network
        )
        VALUES (
          ${channel['channelID']},
          ${channel['channelTypeID']},
          ${channel['callSign']},
          ${channel['major']},
          ${channel['minor']},
          ${channel['network']}
        ) ON CONFLICT DO UPDATE SET
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
    lookup['channelType'] = _getLookup('channelType');

    lookup = _updateLookups(guideShows, lookup);
    guideShows = _addLookupIDs(guideShows, lookup, channelType: 'guide');
    final guideShowsClean = _sanitizeList(guideShows);
    for (final show in guideShowsClean) {
      db.execute('''
        INSERT INTO show (
          showID,
          ruleID,
          channelID,
          channelTypeID,
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
          ${show['ruleID']},
          ${show['channelID']},
          ${show['channelTypeID']},
          ${show['keepRecordingID']},
          ${show['count']},
          ${show['showTypeID']},
          ${show['title']},
          ${show['descript']},
          ${_convertDateTimeToInt(show['releaseDate'], show['showType'], 'show')},
          ${show['origRunTime']},
          ${show['ratingID']},
          ${show['stars']}
        ) ON CONFLICT DO UPDATE SET
          ruleID = ${show['ruleID']},
          channelID = ${show['channelID']},
          keepRecordingID = ${show['keepRecordingID']},
          count = ${show['count']},
          showTypeID = ${show['showTypeID']},
          title = ${show['title']},
          descript = ${show['descript']},
          releaseDate = ${_convertDateTimeToInt(show['releaseDate'], show['showType'], 'show')},
          origRunTime = ${show['origRunTime']},
          ratingID = ${show['ratingID']},
          stars = ${show['stars']};
      ''');
      if (show['cast'] != null && show['cast'].length > 0) {
        for (final castID in show['castID']) {
          db.execute('''
            INSERT INTO showCast (showID, castID) VALUES (${show['showID']}, $castID) ON CONFLICT DO NOTHING;
          ''');
        }
      }
      if (show['genre'] != null && show['genre'].length > 0) {
        for (final genreID in show['genreID']) {
          db.execute('''
            INSERT INTO showGenre (showID, genreID) VALUES (${show['showID']}, $genreID) ON CONFLICT DO NOTHING;
          ''');
        }
      }
      if (show['director'] != null && show['director'].length > 0) {
        for (final castID in show['directorID']) {
          db.execute('''
            INSERT INTO showDirector (showID, castID) VALUES (${show['showID']}, $castID) ON CONFLICT DO NOTHING;
          ''');
        }
      }
      if (show['award'] != null && show['award'].length > 0) {
        for (final award in show['award']) {
          db.execute('''
            INSERT INTO showAward (
              showID,
              won,
              awardNameID,
              awardCategoryID,
              year,
              castID
            )
            VALUES (
              ${show['showID']},
              ${award['won'] ? 1 : 0},
              ${award['awardNameID']},
              ${award['awardCategoryID']},
              ${award['year']},
              ${award['castID']}
            ) ON CONFLICT DO NOTHING;
          ''');
        }
      }
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
  
  Map<String, Map> _updateLookups(List<Map<String, dynamic>> items, Map<String, Map> lookup) {
    final uniqueInput = <String, Set>{};
    for (final table in lookup.keys) {
      uniqueInput[table] = <String>{};
    }
    for (final item in items) {
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
        } else if (item[table] != null) {
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
    }
    for (final table in lookup.keys) {
      for (final item in uniqueInput[table]!) {
        if (!lookup[table]!.containsValue(item)) {
          final itemClean = _sanitizeString(item);
          db.execute('''
            INSERT INTO $table ($table)
            VALUES ($itemClean);
          ''');
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
  
  List<Map<String, dynamic>> _addLookupIDs(List<Map<String, dynamic>> items, Map<String, dynamic> lookup, {String? channelType}) {
    for (var i = 0; i < items.length; ++i) {
      if (items[i]['channelID'] != null && channelType != null) {
        items[i]['channelType'] = channelType;
      }
      for (final table in lookup.keys) {
        final lookupValue = items[i][table];
        if (lookupValue is String) {
          items[i]['${table}ID'] = (lookup[table] as Map)[lookupValue];
        } else if (lookupValue is List) {
          final lookupIDs = <int>[];
          for (final val in lookupValue) {
            lookupIDs.add(lookup[table][val]);
          }
          items[i]['${table}ID'] = lookupIDs;
          if (table == 'cast' && items[i]['director'] != null) {
            lookupIDs.clear();
            for (final val in items[i]['director']) {
              lookupIDs.add(lookup[table][val]);
            }
            items[i]['directorID'] = lookupIDs;
          }
        }
      }
      if (items[i]['award'] != null && items[i]['award'].length > 0) {
        for (var j = 0; j < items[i]['award'].length; ++j) {
          for (final table in lookup.keys) {
            final lookupValue = items[i]['award'][j][table];
            if (lookupValue != null) {
              items[i]['award'][j]['${table}ID'] = (lookup[table] as Map)[lookupValue];
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
  
  String _convertDateTimeToInt(dynamic date, String recordType, String table) {
    var dateTime = DateTime.fromMicrosecondsSinceEpoch(0);
    if (date is int) {
      dateTime = DateTime(date);
    } else {
      if (recordType == 'show') {
        dateTime = DateTime.parse(date);
      }
      // Add additional conditions for recordings & airings as needed
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
        return localResults.first['serverID'] == memoryResults.first['serverID'];
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
    
}