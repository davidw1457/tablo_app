import 'dart:io';

// import 'package:flutter/material.dart';
// import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'package:tablo_app/tablo.dart';
import 'package:tablo_app/log.dart';

const currentLibrary = 'main';

final testServerID = getTestServerID();
final log = Log();

void main() async {
  // runApp(const MyApp());
  Tablo.redirectLog(log);
  // TODO: Delete the next several lines once the database format is finalized and no longer needs to be recreated from scratch each time
  logMessage(
      '$currentLibrary: Backing up or deleting database from previous execution.');
  final database = File('databases\\$testServerID.cache');
  if (database.existsSync()) {
    logMessage('$testServerID.cache exists.');
    final oldDatabase = File('databases\\$testServerID.cache.old');
    if (!oldDatabase.existsSync()) {
      logMessage('Renaming $testServerID.cache');
      database.renameSync('databases\\$testServerID.cache.old');
    } else if (database.lengthSync() >= oldDatabase.lengthSync() ~/ (10 / 9)) {
      logMessage(
          'Deleting $testServerID.cache.old and renaming $testServerID.cache');
      oldDatabase.deleteSync();
      database.renameSync('databases\\$testServerID.cache.old');
    } else {
      logMessage(
          '$testServerID.cache is < 90% the size of $testServerID.cache.old. Deleting $testServerID.cache');
      database.deleteSync();
    }
  }
  final timer = Stopwatch();
  logMessage('Creating Tablo objects');
  timer.start();
  final tablos = await Tablo.getTablos();
  timer.stop();
  logMessage('Completed creating Tablo objects');
  logMessage('Total elapsed time: ${timer.elapsed}');
  logMessage('Tablos located: ${tablos.length}');
  final tablo = tablos[0];

  logMessage('Running delete failed recordings');
  final failedRecordings = tablo.getRecordings(failed: true);
  final pathList = <String>[];
  for (final failedRecording in failedRecordings) {
    logMessage(failedRecording.toString());
    pathList.add(failedRecording['path']);
  }
  await tablo.deleteRecordingList(pathList);

  logMessage('Running delete bad recordings');
  final badRecordings = tablo.getRecordings(bad: true);
  pathList.clear();
  for (final badRecording in badRecordings) {
    logMessage(badRecording.toString());
    pathList.add(badRecording['path']);
  }
  await tablo.deleteRecordingList(pathList);

  logMessage('Listing Conflicts');
  final conflicts = tablo.getConflictedAirings();
  for (final conflict in conflicts) {
    logMessage('Conflicts:');
    for (final show in conflict) {
      logMessage(show.toString());
    }
  }

  logMessage('Getting all recordings');
  final recordings = tablo.getRecordings();
  logMessage('Attempting to export all recordings with a valid season');
  for (final recording in recordings) {
    try {
      final season = int.parse(recording['season']);
      if (season > 0) {
        logMessage(
            'Exporting ${recording['recordingID']}: ${recording['showTitle']}: ${recording['season']}:${recording['episode']} ${recording['episodeTitle']}');
        await tablo.exportRecording(recording['recordingID'], delete: true);
      }
    } catch (e) {
      logMessage('Unable to process ${recording['recordingID']}: $e');
    }
  }

  logMessage('Execution complete.');
}

String getTestServerID() {
  final databaseDirectory = Directory('databases');
  if (!databaseDirectory.existsSync()) {
    return "none";
  } else {
    final databaseFiles = databaseDirectory.listSync();
    for (final file in databaseFiles) {
      final path = file.path;
      if (path.substring(path.length - 5) == 'cache') {
        return path.substring(10).split('.')[0];
      }
    }
  }
  return "none";
}

void logMessage(String message, {String? level}) {
  if (level == null) {
    log.logMessage(message, currentLibrary);
  } else {
    log.logMessage(message, currentLibrary, level: level);
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
