import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

class TabloDatabase{
  final Database db;
  static const _dbVer = 1;

  TabloDatabase._internalConstructor(this.db, String serverID) {
    try {
      final result = db.select('select * from system');
      final dbVer = result.first['dbVer'];
      if (dbVer == null || dbVer != _dbVer) {
        _init(serverID);
      }
    } on SqliteException {
      _init(serverID);
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

  _init(String serverID) {
    final newDB = sqlite3.openInMemory();
    newDB.backup(db);
    newDB.dispose();

    _createSystemTable();
    _createGuideTables();
    _createRecordingTables();
    _createErrorTable();
    _createSettingsTables();
    final writedb = sqlite3.open('databases/$serverID.cache');
    db.backup(writedb);
    writedb.dispose();
  }

  _createSystemTable() {
    db.execute('''
      CREATE TABLE system (
        serverID TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        privateIP TEXT NOT NULL,
        dbVer INT NOT NULL,
        lastUpdated INT NOT NULL,
        lastSaved INT NOT NULL,
        size INT,
        free INT
      );
    ''');
  }

  _createGuideTables() {
    db.execute('''
      CREATE TABLE channel (
        channelID     INT NOT NULL PRIMARY KEY,
        callSign      TEXT,
        major         INT NOT NULL,
        minor         INT NOT NULL,
        network       TEXT
      );
    ''');
    db.execute('''
      CREATE TABLE show (
        showID        INT NOT NULL PRIMARY KEY,
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
  
  updateSystemTable(Map<String, dynamic> sysInfo, Map<String, int> space) {
    final result = db.select('select * from system');
    if (result.isEmpty) {
      db.execute('''
        INSERT INTO system (
          serverID,
          name,
          privateIP,
          dbVer,
          lastUpdated,
          lastSaved,
          size,
          free
        )
        VALUES (
          '${sysInfo['serverid']}',
          '${sysInfo['name']}',
          '${sysInfo['private_ip']}',
          $_dbVer,
          0,
          0,
          ${space['size']},
          ${space['free']}
        );
      ''');
    } else {
      db.execute('''
        UPDATE system
        SET
          size = ${space['size']},
          free = ${space['free']};
      ''');
    }
  }
}