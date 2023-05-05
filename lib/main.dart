import 'dart:collection';
import 'dart:ffi';
import 'dart:math';

import 'package:ble_larus_android/xcsoar_windekf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:ble_larus_android/datahandler.dart';
import 'package:ble_larus_android/datarestream.dart';
import 'package:ble_larus_android/settingsDialog.dart';
import 'package:ble_larus_android/vario.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'package:sound_generator/sound_generator.dart';
import 'package:sound_generator/waveTypes.dart';
import 'package:vector_math/vector_math.dart' hide Colors, Matrix4;
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

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
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
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
  var _displayText = ["", "", "", ""];
  VarioData varioData = VarioData();
  int buttonPressed = 0;
  Map<String, double> settingsValues = {};
  bool isPlaying = false;
  bool colorSwitchVario = false;
  Color varioColor = Colors.white;
  final List<Color> warningColors = [
    const Color.fromARGB(255, 255, 145, 137),
    const Color.fromARGB(255, 255, 217, 50)
  ];
  int warningColorIndex = 0;
  final List<String> warningStrings = ["Flachkurbler", "Latenz"];
  String currentWarningString = "";
  double rollAngle = 0;
  double targetMinRoll = 40;
  Color currentVarioColor = Colors.green;

  double currentVario = 0;
  double oldVario = 0;
  double averageVario = 0;
  double wind1Rotation = 0;
  double wind2Rotation = 0;
  Vector3 averageWind = Vector3(0, 0, 0);
  Vector3 longAverageWind = Vector3(0, 0, 0);
  // Some state management stuff
  bool _foundDeviceWaitingToConnect = false;
  bool _scanStarted = false;
  bool _connected = false;
  Future<int> _mLineCounter = Future.value(0);
// Bluetooth related variables
  late DiscoveredDevice _ubiqueDevice;

  late DataRestream dataRestream;
  final flutterReactiveBle = FlutterReactiveBle();

  late StreamSubscription<DiscoveredDevice> _scanStream;
  late QualifiedCharacteristic _rxCharacteristic;
// These are the UUIDs of your device
  final Uuid serviceUuid = Uuid.parse("0000abf0-0000-1000-8000-00805f9b34fb");
  final Uuid characteristicUuid =
      Uuid.parse("0000abf2-0000-1000-8000-00805f9b34fb");

  /// Activate settings in settingsValues such that they take effect
  void activateSettings() {
    varioData.logRawData = settingsValues["logRawData"]! == 1;
    varioData.logRawData = settingsValues["logProcessedData"]! == 1;
    varioData.setVarioAverageTime((settingsValues["varioAverageTimeS"]! * 1000).round());
    varioData.setWindEstimatorAverageTime((settingsValues["windAverageTimeS"]! * 1000).round());
  }
/// Reset settings to default values
  void resetSettings() {
    settingsValues = {
      "scalingFactor": 300,
      "zeroFrequency": 250,
      "frequencyChange": 50,
      "varioOnOffChangeFactor":15,
      "varioSoundGeneratorSampleRate": 20000,
      "circleDetectionMinTime": 5000,
      "varioVolume": 0.5,
      "targetMinRoll": 40,
      "varioAverageTimeS": 30,
      "windAverageTimeS":5,
      "logRawData": 1,
      "logProcessedData": 1,
    };
  }
/// Restore settings from shared preferences store
  void restoreSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (String key in settingsValues.keys) {
      if (prefs.containsKey(key)) {
        settingsValues[key] = prefs.getDouble(key)!;
      }
    }
  }
/// Save settings map to shared preferences store
  void saveSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (String key in settingsValues.keys) {
      if (settingsValues[key]! == -42) {
        resetSettings();
        saveSettings();
        return;
      }
      prefs.setDouble(key, settingsValues[key]!);
    }
  }

  @override
  void initState() {
    super.initState();
    resetSettings();
    restoreSettings();
    activateSettings();
    SoundGenerator.init(settingsValues["varioSoundGeneratorSampleRate"]!.toInt());

    SoundGenerator.onIsPlayingChanged.listen((value) {
      setState(() {
        isPlaying = value;
      });
    });

    SoundGenerator.setAutoUpdateOneCycleSample(true);
    //Force update for one time
    SoundGenerator.refreshOneCycleData();

    SoundGenerator.setWaveType(waveTypes.SINUSOIDAL);

    regulateVariometer();
  }

  void _startScan() async {
// Platform permissions handling stuff
    bool permGranted = false;
    setState(() {
      _scanStarted = true;
    });
    PermissionStatus permission;
    if (Platform.isAndroid) {
      permission = await Permission.location.request();
      if (permission == PermissionStatus.granted) {
        permission = await Permission.bluetoothScan.request();

        permission = await Permission.bluetoothConnect.request();
      } else {
        print("Location permission denied");
      }
      print(permission);
      if (permission == PermissionStatus.granted) permGranted = true;
    } else if (Platform.isIOS) {
      permGranted = true;
    }
// Main scanning logic happens here ⤵️
    if (permGranted) {
      _scanStream = flutterReactiveBle.scanForDevices(
          withServices: [], scanMode: ScanMode.lowLatency).listen((device) {
        // Change this string to what you defined in Zephyr
        if (device.name == 'ESP_SPP_SERVER') {
          print(device.serviceUuids);
          print(device.serviceData);
          setState(() {
            _ubiqueDevice = device;
            _foundDeviceWaitingToConnect = true;
          });
          Future.delayed(const Duration(seconds: 1), () => _connectToDevice());
        }
      });
    }
  }

  Future<void> regulateVariometer() async {
    bool varioOn = false;
    double cycleTimeOn = 800;
    double cycleTimeOff = 800;
    int lastTime = DateTime.now().millisecondsSinceEpoch;
    while (true) {
      await Future.delayed(
        const Duration(milliseconds: 10),
      );

      cycleTimeOn = min(
          max(
              800 -
                  (log((currentVario.abs() * settingsValues["varioOnOffChangeFactor"]!) + 1)) *
                      200 *
                      (currentVario > 0 ? 1 : -1),
              50),
          1000);
      cycleTimeOff = cycleTimeOn;
      // start cycle
      if (varioOn == false &&
          DateTime.now().millisecondsSinceEpoch - lastTime > cycleTimeOff) {
        lastTime = DateTime.now().millisecondsSinceEpoch;
        varioOn = true;
        SoundGenerator.setVolume(settingsValues["varioVolume"]!);
        if (colorSwitchVario) {
          setState(() {
            varioColor = Colors.white;
            warningColorIndex = 0;
          });
        }
      }
      if (varioOn == true &&
          DateTime.now().millisecondsSinceEpoch - lastTime > cycleTimeOn &&
          currentVario > 0) {
        lastTime = DateTime.now().millisecondsSinceEpoch;
        varioOn = false;
        SoundGenerator.setVolume(0);
        if (colorSwitchVario) {
          setState(() {
            varioColor = Colors.black;
            warningColorIndex = 1;
          });
        }
      }
      SoundGenerator.setFrequency(settingsValues["zeroFrequency"]! + currentVario * settingsValues["frequencyChange"]!);
    }
  }

  void _updateValues() {
    //currentVario = varioData.airspeed;
    rollAngle = varioData.roll / (2 * pi) * 360;
    currentWarningString = "";
    if (rollAngle.abs() < targetMinRoll) {
      if (varioData.yawRateOverLimitCounter > settingsValues["circleDetectionMinTime"]!) {
        currentWarningString =
            "${warningStrings[0]} ${(rollAngle).toStringAsFixed(0)}°";
      }
    }
    longAverageWind = longAverageWind * 0.9 + averageWind * 0.1;

    setState(() {
      currentWarningString += varioData.updateTime.toString();

      if (buttonPressed == 0) { // GPS Button
        _displayText = [
          "lat ${varioData.latitude.toString()}",
          "lon ${varioData.longitude.toString()}",
          "alt ${varioData.height_gps.toString()}",
          "raw climb"
        ];
        currentVario = varioData.rawClimbVario.getCurrentValue();
        averageVario = varioData.rawClimbVario.getAverageValue();

      } else if (buttonPressed == 1) {  // Airspeed Button
        _displayText = [
          "as simpleclimb ${((varioData.airspeed) * 3.6).toString().substring(0, 4)}",
          "airsx ${varioData.airspeedVector.x.toString()}",
          "airsy ${varioData.airspeedVector.y.toString()}",
          "airsz ${varioData.airspeedVector.z.toString()}"
        ];
        currentVario = varioData.simpleClimbVario.getCurrentValue();
        averageVario = varioData.simpleClimbVario.getAverageValue();
      } else if (buttonPressed == 2) {
        _displayText = [
          "awx ${varioData.ardupilotWind.x.toString()}",
          "awy ${varioData.ardupilotWind.y.toString()}",
          "awz ${varioData.ardupilotWind.z.toString()}",
          "gps vario"
        ];
        currentVario = varioData.gpsVario.getCurrentValue();
        averageVario = varioData.gpsVario.getAverageValue();
      } else if (buttonPressed == 3) {  // Cloud Button
        _displayText = [
          "turn radius ${varioData.turnRadius.toString()}",
          "climb ${varioData.raw_climb_rate.toString()}",
          "rd ${varioData.reading.toString()}",
          "mywindcomp"
        ];
        currentVario = varioData.windCompVario.getCurrentValue();
        averageVario = varioData.windCompVario.getAverageValue();
        wind1Rotation = varioData.windEstimator.lastWindEstimate.angleTo(Vector2(0, 0));
        wind2Rotation = varioData.ardupilotWind.angleTo(Vector3(0, 0, 0));
      } else if (buttonPressed == 4) {
        _displayText = [
          "gx ${(varioData.gpsSpeed.x).toString()}",
          "gy ${(varioData.gpsSpeed.y).toString()}",
          "gz ${(varioData.gpsSpeed.z).toString()}",
          "gps speed"
        ];
        wind1Rotation = varioData.ardupilotWind.angleTo(Vector3(0, 0, 0));
        wind2Rotation = varioData.ekfGroundSpeed.angleTo(Vector2(0, 0));
      } else if (buttonPressed == 5) {  // source icon
        _displayText = [
          "xwx ${(varioData.xcsoarEkf.getWind()[0] * -1).toString()}",
          "xwy ${(varioData.xcsoarEkf.getWind()[1] * -1).toString()}",
          "xwz ${(varioData.xcsoarEkf.getWind()[2]).toString()}",
          "xcsoar wind"
        ];
        wind2Rotation = longAverageWind.angleTo(Vector3(0, 0, 0));
      } else if (buttonPressed == 6) {
        _displayText = [
          "lwx ${(varioData.larusWind.x).toString()}",
          "lwy ${(varioData.larusWind.y).toString()}",
          "larus wind",
          ""
        ];
        wind1Rotation = varioData.windEstimator.lastWindEstimate.angleTo(Vector2(0, 0));
        wind2Rotation = varioData.ardupilotWind.angleTo(Vector3(0, 0, 0));
      } else if (buttonPressed == 7) {
        _displayText = [
          "vx ${(varioData.velned.x).toString()}",
          "vy ${(varioData.velned.y).toString()}",
          "vz ${(varioData.velned.z).toString()}",
          "velned speed"
        ];
      }
    });
  }

  Future<void> _regularUpdates() async {
    _updateValues();
    while (
        DateTime.now().millisecondsSinceEpoch - varioData.lastUpdate < 5000) {
      await Future.delayed(const Duration(milliseconds: 1));
      _updateValues();
    }
  }

  Future<void> _dialogBuilder(BuildContext context) async {
    var filesList = (await getExternalStorageDirectory())!.listSync();
    filesList.sort((a, b) => a.path.compareTo(b.path));
    var number = await showDialog<int>(
        context: context,
        builder: (BuildContext context) {
          return SimpleDialog(
            title: const Text('Select file'),
            children: <Widget>[
              for (var i = 0; i < filesList.length; i++)
                SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(context, i);
                  },
                  child: Text(filesList[i].path),
                ),
            ],
          );
        });
    if (await number != null) {
      print(filesList[number!]);
      dataRestream = DataRestream(varioData, filesList[number]);
      dataRestream.restreamFile(); //.then((value) => print("finished"));
      _regularUpdates();
    } else {
      if (filesList.length > 0) {
        print(filesList[0]);
      }
    }
  }

  void _connectToDevice() {
    // We're done scanning, we can cancel it
    _scanStream.cancel();
    // Let's listen to our connection so we can make updates on a state change
    Stream<ConnectionStateUpdate> _currentConnectionStream = flutterReactiveBle
        .connectToAdvertisingDevice(
            id: _ubiqueDevice.id,
            prescanDuration: const Duration(seconds: 1),
            withServices: [serviceUuid]);
    _currentConnectionStream.listen((event) {
      switch (event.connectionState) {
        // We're connected and good to go!
        case DeviceConnectionState.connected:
          {
            print("connected");
            _rxCharacteristic = QualifiedCharacteristic(
                serviceId: serviceUuid,
                characteristicId: characteristicUuid,
                deviceId: event.deviceId);
            setState(() {
              _foundDeviceWaitingToConnect = false;
              _connected = true;
            });

            final characteristic = QualifiedCharacteristic(
                serviceId: serviceUuid,
                characteristicId: characteristicUuid,
                deviceId: event.deviceId);
            flutterReactiveBle.subscribeToCharacteristic(characteristic).listen(
                (data) {
              //print(DateTime.now().millisecondsSinceEpoch);
              varioData.parse_ble_data(data);

              _updateValues();
            }, onError: (dynamic error) {
              print("error: $error");
              setState(() {
                _foundDeviceWaitingToConnect = false;
                _connected = false;
                _startScan();
              });
            }, onDone: () {
              print("done");
              _foundDeviceWaitingToConnect = false;
              _connected = false;
              _startScan();
            }, cancelOnError: true);
            break;
          }
        // Can add various state state updates on disconnect
        case DeviceConnectionState.disconnected:
          {
            if (_connected) {
              print("disconnected");
              setState(() {
                _connected = false;
                _displayText = ["", "", "", ""];
              });
              _startScan();
            }
            break;
          }
        default:
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_scanStarted) {
      _startScan();
    }
    String message = "Not connected";
    if (_scanStarted) {
      message = "Scanning...";
    }
    if (_foundDeviceWaitingToConnect) {
      message = "Found device, connecting...";
    }
    if (_connected) {
      message = "Connected!";
    }
    if (_displayText[0] != "") {
      message = _displayText[0];
    }

    final old_vario_widgets = ListQueue<Widget>();
    int opacity_int = 255;
    int vario_counter = 0;
    /*for (var vario_value in oldVarioQueue){
      if (vario_counter < numCurrentVarioValues){
        opacity_int = (255 * pow(opacity_correction_value, vario_counter)).round();
        old_vario_widgets.addFirst(Transform(transform: Matrix4.rotationZ(vario_value / 10 * 0.5 * pi + 1.5*pi), origin: Offset(100, 100), child: Icon(Icons.arrow_upward, color: Color.fromARGB(opacity_int, 0, 255, 0), size: 200.0, semanticLabel: 'Vario',)));
        
      } else if (vario_counter < num_old_vario_values){
        opacity_int = (255 * pow(opacity_correction_value, vario_counter - numCurrentVarioValues)).round();
        old_vario_widgets.addFirst(Transform(transform: Matrix4.rotationZ(vario_value / 10 * 0.5 * pi + 1.5*pi), origin: Offset(110, 110), child: Icon(Icons.arrow_upward, color: Color.fromARGB(opacity_int, 0, 0, 255), size: 220.0, semanticLabel: 'Vario',)));
      }
      vario_counter++;
    }
    */
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              //Stack(children: old_vario_widgets.toList(growable: false),),
              Stack(children: [
                Image(
                  image: AssetImage("assets/vario_background.png"),
                  width: settingsValues["scalingFactor"]!,
                  height: settingsValues["scalingFactor"]!,
                ),
                //Transform(transform: Matrix4.rotationZ((currentVario.isFinite ? currentVario : 0.0) / 10.0 * 0.5 * pi), alignment: FractionalOffset.center, child: Image(image: AssetImage("assets/vario_current.png"), width: scaling_factor, height: scaling_factor,)),
                //Transform(transform: Matrix4.rotationZ((oldVario.isFinite ? currentVario : 0.0) / 10 * 0.5 * pi), alignment: FractionalOffset.center, child: Image(image: AssetImage("assets/vario_average1.png"), width: scaling_factor, height: scaling_factor,)),
                Transform(
                    transform: Matrix4.rotationZ(
                        (((currentVario.isFinite ? currentVario : 0.0) * 20) /
                                360) *
                            (2 * pi)),
                    alignment: FractionalOffset.center,
                    child: Image(
                      image: const AssetImage("assets/vario_current.png"),
                      width: settingsValues["scalingFactor"]!,
                      height: settingsValues["scalingFactor"]!,
                      color: currentVarioColor,
                    )),
                Transform(
                    transform: Matrix4.rotationZ(
                        (((averageVario.isFinite ? averageVario : 0.0) * 20) /
                                360) *
                            (2 * pi)),
                    alignment: FractionalOffset.center,
                    child: Image(
                      image: const AssetImage("assets/vario_average1.png"),
                      width: settingsValues["scalingFactor"]!,
                      height: settingsValues["scalingFactor"]!,
                      color: currentVarioColor,
                    )),
                Transform(
                    transform: Matrix4.rotationZ(wind1Rotation),
                    alignment: FractionalOffset.center,
                    child: SizedBox(
                        width: settingsValues["scalingFactor"]!,
                        height: settingsValues["scalingFactor"]!,
                        child: Icon(
                          Icons.keyboard_backspace_rounded,
                          color: Color.fromARGB(255, 162, 223, 255),
                          size: settingsValues["scalingFactor"]! * 0.6,
                        ))),
                Transform(
                    transform: Matrix4.rotationZ(
                        wind2Rotation),
                    alignment: FractionalOffset.center,
                    child: SizedBox(
                        width: settingsValues["scalingFactor"]!,
                        height: settingsValues["scalingFactor"]!,
                        child: Icon(
                          Icons.keyboard_backspace_rounded,
                          color: Color.fromARGB(255, 141, 141, 141),
                          size: settingsValues["scalingFactor"]! * 0.6,
                        ))),
              ]),
              Text(
                '$message',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${_displayText[1]}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${_displayText[2]}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${_displayText[3]}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  IconButton(
                      onPressed: () {
                        setState(() {
                          buttonPressed = 0;
                          currentVarioColor = Colors.green;
                        });
                      },
                      icon: const Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 40.0,
                      )),
                  IconButton(
                      onPressed: () {
                        setState(() {
                          buttonPressed = 1;
                          currentVarioColor = Colors.red;
                        });
                      },
                      icon: const Icon(
                        Icons.speed,
                        color: Colors.red,
                        size: 40.0,
                      )),
                  IconButton(
                      onPressed: () {
                        setState(() {
                          buttonPressed = 3;
                          currentVarioColor = Colors.blue;
                          SoundGenerator.play();
                        });
                      },
                      icon: const Icon(
                        Icons.cloud_upload,
                        color: Colors.blue,
                        size: 40.0,
                      )),
                  IconButton(
                      onPressed: () {
                        setState(() {
                          buttonPressed = 4;
                          currentVarioColor = Colors.brown;
                        });
                      },
                      icon: const Icon(
                        Icons.subway_rounded,
                        color: Colors.brown,
                        size: 40.0,
                      )),
                  IconButton(
                      onPressed: () {
                        setState(() {
                          buttonPressed = 7;
                          currentVarioColor = Colors.deepPurple;
                        });
                      },
                      icon: const Icon(
                        Icons.computer,
                        color: Colors.deepPurple,
                        size: 40.0,
                      )),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                      onPressed: () {
                        setState(() {
                          buttonPressed = 5;
                        });
                      },
                      icon: const Icon(
                        Icons.source,
                        color: Color.fromARGB(255, 158, 224, 255),
                        size: 40.0,
                      )),
                  IconButton(
                      onPressed: () {
                        setState(() {
                          buttonPressed = 2;

                          SoundGenerator.stop();
                        });
                      },
                      icon: const Icon(
                        Icons.airplanemode_active_outlined,
                        color: Colors.yellow,
                        size: 40.0,
                      )),
                  IconButton(
                      onPressed: () {
                        setState(() {
                          buttonPressed = 6;
                        });
                        print(settingsValues);
                      },
                      icon: const Icon(
                        Icons.connecting_airports_rounded,
                        color: Colors.yellow,
                        size: 40.0,
                      )),
                  IconButton(
                      onPressed: () => _dialogBuilder(context),
                      icon: const Icon(
                        Icons.fast_rewind,
                        color: Colors.grey,
                        size: 40.0,
                      )),
                  IconButton(
                      onPressed: () => showDialog(
                                  context: context,
                                  builder: (context) => SettingsDialog(
                                      settingsValues: settingsValues))
                              .then((value) {
                            if (value != null) {
                              settingsValues = value;
                              saveSettings();
    activateSettings();
                            }
                          }),
                      icon: const Icon(
                        Icons.settings,
                        color: Colors.grey,
                        size: 40.0,
                      )),
                ],
              ),
              Container(
                color: warningColors[warningColorIndex],
                child: Text(
                  currentWarningString,
                  style: TextStyle(
                      fontSize: 30,
                      color: warningColors[(warningColorIndex + 1) % 2]),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
