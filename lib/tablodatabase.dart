import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

class TabloDatabase{
  final Database db;
  final String serverID;
  static const _dbVer = 1;

  TabloDatabase._internalConstructor(this.db, this.serverID) {
    try {
      final result = db.select('select * from system');
      final dbVer = result.isNotEmpty ? result.first['dbVer'] : null;
      if (result.isEmpty || dbVer != _dbVer) {
        _init();
      }
    } on SqliteException {
      _init();
    }
  }

  static TabloDatabase getDatabase(String serverID, String name, String privateIP) {
    Directory('databases').createSync();
    final databaseLocal = sqlite3.open('databases/$serverID.cache');
    final databaseMemory = sqlite3.openInMemory();
    databaseLocal.backup(databaseMemory);
    databaseLocal.dispose();
    return TabloDatabase._internalConstructor(databaseMemory, serverID);
  }

  _init() {
    final newDB = sqlite3.openInMemory();
    newDB.backup(db);
    newDB.dispose();

    _createSystemTable();
    _createGuideTables();
    _createRecordingTables();
    _createErrorTable();
    _createSettingsTables();
  }

  _createSystemTable() {
    db.execute('''
      CREATE TABLE system (
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
    saveToDisk();
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
      CREATE TABLE show (
        showID        INT PRIMARY KEY,
        rule          INT,
        channelID     INT,
        keep          INT,
        count         INT,
        typeID        INT,
        title         TEXT,
        description   TEXT,
        releaseDate   INT,
        origRunTime   INT,
        rating        INT,
        stars         INT
      );
    ''');
    db.execute('''
      CREATE TABLE rule (
        ruleID        INT NOT NULL PRIMARY KEY,
        rule          TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE keep (
        keepID        INT NOT NULL PRIMARY KEY,
        keep          TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE type (
        typeID        INT NOT NULL PRIMARY KEY,
        type          TEXT NOT NULL,
        suffix        TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE showGenre (
        showID        INT NOT NULL,
        genreID       INT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE genre (
        genreID       INT NOT NULL PRIMARY KEY,
        genre         TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE rating (
        ratingID      INT NOT NULL PRIMARY KEY,
        rating        TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE showCast (
        showID        INT NOT NULL PRIMARY KEY,
        castID        INT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE cast (
        castID        INT NOT NULL,
        cast          TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE showAward (
        showID        INT NOT NULL,
        awardID       INT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE award (
        awardID       INT NOT NULL PRIMARY KEY,
        award         TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE showDirector (
        showID        INT NOT NULL,
        castID        INT NOT NULL
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
        description   TEXT,
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
    saveToDisk();
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
    saveToDisk();
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
    saveToDisk();
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
    saveToDisk();
  }
  
  updateSystemTable(Map<String, dynamic> sysInfo) {
    sysInfo = _sanitizeMap(sysInfo);
    db.execute('''
      INSERT INTO system (
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
    saveToDisk();
  }

  updateChannels(List<Map<String, dynamic>> channels) {
    final channelTypes = _getChannelTypes();
    for (var channel in channels) {
      if (channelTypes[channel['channelType']] == null) {
        channelTypes[channel['channelType']] = _addChannelType(channel['channelType']);
      }
      final channelType = channelTypes[channel['channelType']];
      channel = _sanitizeMap(channel);
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
          $channelType,
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
    saveToDisk();
  }
  
  Map<String, int> _getChannelTypes() {
    final channelTypes = <String, int>{};
    final channelTypeTable = db.select('SELECT * FROM channelType');
    for (final type in channelTypeTable) {
      channelTypes[type['channelType']] = type['channelTypeID'];
    }
    return channelTypes;
  }
  
  int _addChannelType(String channelType) {
    channelType = _sanitizeString(channelType);
    db.execute('''
      INSERT INTO channelType (channelType)
      VALUES ($channelType);
    ''');
    final record = db.select("SELECT channelTypeID FROM channelType WHERE channelType = $channelType;");
    saveToDisk();
    return record.first['channelTypeID'];
  }
  
  String _sanitizeString(String value) {
    value = value.replaceAll("'", "''");
    return value == 'null' ? value : "'$value'";
  }
  
  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    for (final key in map.keys) {
      if (map[key] is String) {
        map[key] = _sanitizeString(map[key]);
      } else if (map[key] is Map<String, dynamic>) {
        map[key] = _sanitizeMap(map[key]);
      } else if (map[key] is List<dynamic>) {
        map[key] = _sanitizeList(map[key]);
      }
    }
    return map;
  }
  
  List<dynamic> _sanitizeList(List<dynamic> list) {
    for (var i = 0; i < list.length; ++i) {
      if (list[i] is String) {
        list[i] = _sanitizeString(list[i]);
      } else if (list[i] is Map<String, dynamic>) {
        list[i] = _sanitizeMap(list[i]);
      } else if (list[i] is List<dynamic>) {
        list[i] = _sanitizeList(list[i]);
      }
    }
    return list;
  }

  saveToDisk() {
    final writedb = sqlite3.open('databases/$serverID.cache');
    db.backup(writedb);
    writedb.dispose();
  }
}