// import 'package:flutter/material.dart';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';
import 'dart:convert';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';


// https://api.tablotv.com/assocserver/getipinfo/
const webServer = 'api.tablotv.com';
const webFolder = 'assocserver/getipinfo/';
const port = '8885';
const maxBatchSize = 50;

void main() async {
  // runApp(const MyApp());
  final tablos = await Tablo.getTablos();
  print('commented out');
  // final tablo = tablos[0];
  // final stopwatch = Stopwatch();
  // stopwatch.start();
  // final fullGuide = await tablo.getFullGuide();
  // stopwatch.stop();
  // print(fullGuide);
  // print('type: ${fullGuide.runtimeType}');
  // print('seconds: ${stopwatch.elapsedMilliseconds / 1000}');
}

class Tablo{
  final String serverID;
  final String privateIP;
  final TabloDatabase db;
  
  Tablo._internalConstructor(this.serverID, this.privateIP, this.db);

  static Future<List<Tablo>> getTablos() async {
    final url = Uri.https(webServer, webFolder);
    final response = await http.get(url);
    final responseBody = json.decode(response.body);
    final tablos = <Tablo>[];
    for (final tablo in responseBody['cpes']) {
      tablos.add(Tablo._internalConstructor(
        tablo['serverid'],
        tablo['private_ip'],
        TabloDatabase.getDatabase(tablo['serverid'], tablo['name'], tablo['private_ip'])
      ));
      final space = await tablos.last._getSpace();
      tablos.last.db.updateSystemTable(tablo, space);
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

  Future<dynamic> _get(String path) async {
    final url = Uri.http('$privateIP:$port', path);
    final response = await http.get(url);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw HttpException('Unable to connect to $path: ${response.statusCode} ${response.body}');
    }
    return json.decode(response.body);
  }

  Future<dynamic> _post(String path, String data) async {
    final url = Uri.http('$privateIP:$port', path);
    final response = await http.post(url, body: data);
    return json.decode(response.body);
  }

  Future<dynamic> _batch(List<dynamic> list) async {
    final data = _listStringMerge(list, maxBatchSize);
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
    var size = 0;
    var free = 0;
    final response = await _get('server/harddrives');
    for (final drive in response) {
      size += drive['size'] as int;
      free += drive['free'] as int;
    }
    return {
      'size': size,
      'free': free,
    };
  }
}

class TabloDatabase{
  final Database db;
  static const dbVer = 1;

  TabloDatabase._internalConstructor(this.db, String serverID) {
    try {
      final result = db.select('select * from system');
      final dbVer = result.first['dbVer'];
      if (dbVer == null || dbVer != TabloDatabase.dbVer) {
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
          ${TabloDatabase.dbVer},
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


/*

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

*/