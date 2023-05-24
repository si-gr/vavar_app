import 'dart:collection';
import 'dart:ffi';
import 'dart:math';

import 'package:ble_larus_android/apWindStore.dart';
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
import 'package:vector_math/vector_math_64.dart' hide Colors, Matrix4;
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
      debugShowCheckedModeBanner: false,
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
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
              color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        ),
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
  int windButtonPressed = 0;
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

  double horizonPitch = 0;
  double currentVario = 0;
  double oldVario = 0;
  double averageVario = 0;
  double wind1Rotation = 0;
  double wind2Rotation = 0;
  double windRatio = 1;
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
    varioData.setVarioAverageTime(
        (settingsValues["varioAverageTimeS"]! * 1000).round());
    varioData.setWindEstimatorAverageTime(
        (settingsValues["windAverageTimeS"]! * 1000).round());
    varioData.windEstimator
        .setFilterCovariance(settingsValues["windFilterCovariance"]!);
    varioData.windEstimator.setMsBetweenWindEstimates(
        settingsValues["msBetweenWindEstimates"]!.toInt());
    varioData.rawClimbVario.setKalmanQ(settingsValues["rawVarKalQ"]!);
    varioData.rawClimbVario.setKalmanAverageQ(settingsValues["rawVarAvgKalQ"]!);
    varioData.rawClimbSpeedVario.setKalmanQ(settingsValues["rawVarKalQ"]!);
    varioData.rawClimbSpeedVario
        .setKalmanAverageQ(settingsValues["rawVarAvgKalQ"]!);
    varioData.gpsVario.setKalmanQ(settingsValues["rawVarKalQ"]!);
    varioData.gpsVario.setKalmanAverageQ(settingsValues["rawVarAvgKalQ"]!);
    varioData.airspeedOffset = settingsValues["airspeedOffset"]!;
    varioData.kalmanAccFactor = settingsValues["kalmanAccFactor"]!;
    varioData.varioSpeedFactor = settingsValues["varioSpeedFactor"]!;
    varioData.windStore = APWindStore(rollingWindowSize: settingsValues["windRollingWindowSize"]!.toInt());
    print("activating settings");
  }

  /// Reset settings to default values
  void resetSettings() {
    settingsValues = {
      "airspeedOffset": -4,
      "potECompensationFactor": 1,
      "kalmanAccFactor": 1,
      "scalingFactor": 300,
      "zeroFrequency": 250,
      "frequencyChange": 50,
      "varioOnOffChangeFactor": 15,
      "varioOnTimeZ": 600,
      "varioOffTimeZ": 600,
      "varioSoundGeneratorSampleRate": 20000,
      "circleDetectionMinTime": 5000,
      "varioVolume": 0.99,
      "targetMinRoll": 40,
      "varioAverageTimeS": 30,
      "windAverageTimeS": 5,
      "logRawData": 1,
      "logProcessedData": 1,
      "windFilterCovariance": 0.2,
      "msBetweenWindEstimates": 20,
      "rawVarKalQ": 0.003,
      "rawVarAvgKalQ": 0.002,
      "artHorizonRollFactor": -1,
      "artHorizonPitchFactor": 1,
      "varioSpeedFactor": 1,
      "windRollingWindowSize": 40,
      "windChangeIndicatorMult": 2,
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
      if (settingsValues[key] == -42) {
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
    SoundGenerator.init(
        settingsValues["varioSoundGeneratorSampleRate"]!.toInt());

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
    double cycleTimeOn = settingsValues["varioOnTimeZ"]!;
    double cycleTimeOff = settingsValues["varioOffTimeZ"]!;
    int lastTime = DateTime.now().millisecondsSinceEpoch;
    double audioVarioValue = min(currentVario.abs(), 5);  // vario is max 5 m/s for audio
    while (true) {
      await Future.delayed(
        const Duration(milliseconds: 10),
      );
      audioVarioValue = min(currentVario.abs(), 5);
      audioVarioValue = max(audioVarioValue, -4); // vario is min 0.1 m/s for audio
      cycleTimeOn = min(
          max(
              settingsValues["varioOnTimeZ"]! -
                  (log((audioVarioValue.abs() *
                              settingsValues["varioOnOffChangeFactor"]!) +
                          1)) *
                      200 *
                      (audioVarioValue > 0 ? 1 : -1),
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
          audioVarioValue > 0) {
        lastTime = DateTime.now().millisecondsSinceEpoch;
        varioOn = false;
        SoundGenerator.setVolume(0);
      }
      SoundGenerator.setFrequency(settingsValues["zeroFrequency"]! +
          audioVarioValue * settingsValues["frequencyChange"]!);
    }
  }

  void _updateValues() {
    //currentVario = varioData.airspeed;
    rollAngle = varioData.roll / (2 * pi) * 360;
    horizonPitch = varioData.pitch / (2 * pi) * 360;
    currentWarningString = "";
    if (rollAngle.abs() < targetMinRoll) {
      if (varioData.yawRateOverLimitCounter >
          settingsValues["circleDetectionMinTime"]!) {
        currentWarningString =
            "${warningStrings[0]} ${(rollAngle).toStringAsFixed(0)}°";
      }
    }

    setState(() {
      currentWarningString += varioData.updateTime.toString();

      if (buttonPressed == 0) {
        // GPS Button
        _displayText = [
          "lat ${varioData.latitude.toString()}",
          "lon ${varioData.longitude.toString()}",
          "alt ${varioData.height_gps.toString()}",
          "raw climb"
        ];
        currentVario = varioData.rawClimbVario.getFilteredVario();
        averageVario = varioData.rawClimbVario.getAverageValue();
      } else if (buttonPressed == 1) {
        // Airspeed Button
        _displayText = [
          "as ap ${((varioData.airspeed) * 3.6).toString().substring(0, 4)} tas ${((varioData.tasstate) * 3.6).toString().substring(0, 4)}",
          "asx ${varioData.airspeedVector.x.toStringAsFixed(1)} lwx ${varioData.larusWind.x.toStringAsFixed(1)}",
          "asy ${varioData.airspeedVector.y.toStringAsFixed(1)} lwy ${varioData.larusWind.y.toStringAsFixed(1)}",
          "az ${varioData.airspeedVector.z.toStringAsFixed(1)} lwz ${varioData.larusWind.z.toStringAsFixed(1)}"
        ];
        currentVario = varioData.reading;
        averageVario = settingsValues["potECompensationFactor"]! * varioData.SPEdot + varioData.SKEdot;
      } else if (buttonPressed == 2) {
        _displayText = [
          "awx ${varioData.ardupilotWind.x.toStringAsFixed(1)}",
          "awy ${varioData.ardupilotWind.y.toStringAsFixed(1)}",
          "awz ${varioData.ardupilotWind.z.toStringAsFixed(1)}",
          "gps vario"
        ];
        currentVario = varioData.gpsVario.getFilteredVario();
        averageVario = varioData.gpsVario.getFilteredAverageVario();
      } else if (buttonPressed == 3) {
        // Cloud Button
        _displayText = [
          "turn radius ${varioData.turnRadius.toStringAsFixed(1)} vx ${(varioData.velned.x).toStringAsFixed(1)}",
          "climb ${varioData.raw_climb_rate.toStringAsFixed(1)} vy ${(varioData.velned.y).toStringAsFixed(1)}",
          "rd ${varioData.reading.toString()} vz ${(varioData.velned.z).toStringAsFixed(1)}",
          "fastVario and rawavg"
        ];
        currentVario = varioData.fastVario;
        averageVario = varioData.rawClimbSpeedVario.getAverageValue();
      } else if (buttonPressed == 4) {
        _displayText = [
          "gx ${(varioData.gpsSpeed.x).toStringAsFixed(1)} xwx ${(varioData.xcsoarEkf.getWind()[0] * -1).toStringAsFixed(1)}",
          "gy ${(varioData.gpsSpeed.y).toStringAsFixed(1)} xwy ${(varioData.xcsoarEkf.getWind()[1] * -1).toStringAsFixed(1)}",
          "gz ${(varioData.gpsSpeed.z).toStringAsFixed(1)} xwz ${(varioData.xcsoarEkf.getWind()[2]).toStringAsFixed(1)}",
          "raw climb speed"
        ];
        currentVario = varioData.rawClimbSpeedVario.getFilteredVario();
        averageVario = varioData.rawClimbSpeedVario.getAverageValue();
      }

      if (windButtonPressed == 0) {
        wind2Rotation = -1 *
            (Vector2(varioData.xcsoarEkf.getWind()[0],
                        varioData.xcsoarEkf.getWind()[1])
                    .angleToSigned(varioData.gpsSpeed.xy) +
                pi);
        wind1Rotation = -1 *
            (varioData.ardupilotWind.xy.angleToSigned(varioData.gpsSpeed.xy) +
                pi);

        //print(
        //    "xcsoar wind: ${Vector2(varioData.xcsoarEkf.getWind()[0], varioData.xcsoarEkf.getWind()[1]).angleTo(Vector2(1, 0))}");
      } else if (windButtonPressed == 1) {
        wind1Rotation = -1 * (varioData.windStore.windAverage.xy.angleToSigned(varioData.gpsSpeed.xy) + pi);
        wind2Rotation = -1 * (varioData.windStore.currentWindChange.xy.angleToSigned(varioData.gpsSpeed.xy) + pi);
        windRatio = settingsValues["windChangeIndicatorMult"]! * varioData.windStore.currentWindChange.length / varioData.windStore.windAverage.length;
      } else if (windButtonPressed == 2) {
        wind2Rotation =
            varioData.ardupilotWind.xy.angleToSigned(varioData.gpsSpeed.xy);
        wind2Rotation = varioData.ekfGroundSpeed.angleTo(Vector2(1, 0));
      }
    });
  }

  Future<void> _regularUpdates() async {
    _updateValues();
    int notUpdatingCounter = 0;
    while (notUpdatingCounter < 5) {
      await Future.delayed(const Duration(milliseconds: 1));
      _updateValues();
      if (DateTime.now().microsecondsSinceEpoch - varioData.lastUpdate <
          5000000) {
        notUpdatingCounter = 0;
      } else {
        notUpdatingCounter++;
      }
    }
    print("no longer updating");
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
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Stack(children: [
                  Image(
                    image: const AssetImage("assets/vario_background.png"),
                    width: settingsValues["scalingFactor"]!,
                    height: settingsValues["scalingFactor"]!,
                    alignment: Alignment.centerRight,
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
                      transform: Matrix4.rotationZ(wind1Rotation + pi / 2),
                      alignment: FractionalOffset.center,
                      child: SizedBox(
                          width: settingsValues["scalingFactor"]!,
                          height: settingsValues["scalingFactor"]!,
                          child: Icon(
                            Icons.keyboard_backspace_rounded,
                            color: Color.fromARGB(255, 172, 226, 255),
                            size: settingsValues["scalingFactor"]! * 0.6,
                          ))),
                  Transform(
                      transform: Matrix4.rotationZ(wind2Rotation + pi / 2),
                      alignment: FractionalOffset.center,
                      child: SizedBox(
                          width: settingsValues["scalingFactor"]!,
                          height: settingsValues["scalingFactor"]!,
                          child: Icon(
                            Icons.keyboard_backspace_rounded,
                            color: Color.fromARGB(255, 255, 156, 156),
                            size: settingsValues["scalingFactor"]! * 0.6 * min(windRatio, 1.1),
                          ))),
                  Container(
                    child: Text(
                      '${varioData.batteryVoltage} V',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.left,
                    ),
                  ),
                  Container(
                    width: settingsValues["scalingFactor"]!,
                    height: settingsValues["scalingFactor"]!,
                    alignment: const Alignment(0.9, 0),
                    child: Text(
                      'AS ${((varioData.airspeed) * 3.6).toStringAsFixed(1)} km/h',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Container(
                    width: settingsValues["scalingFactor"]!,
                    height: settingsValues["scalingFactor"]!,
                    alignment: const Alignment(0.7, -0.3),
                    child: Text(
                      'W ${((varioData.windStore.windAverage.length) * 3.6).toStringAsFixed(1)} km/h',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.right,
                    ),
                  ),

                  Container(
                    width: settingsValues["scalingFactor"]!,
                    height: settingsValues["scalingFactor"]!,
                    alignment: const Alignment(0.7, 0.3),
                    child: Text(
                      '${(currentVario).toStringAsFixed(1)} m/s',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ]),
              ),
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
                          buttonPressed = 2;
                          currentVarioColor = Colors.blue;
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
                          buttonPressed = 3;
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
                          buttonPressed = 4;
                          currentVarioColor = Colors.deepPurple;
                        });
                      },
                      icon: const Icon(
                        Icons.computer,
                        color: Colors.deepPurple,
                        size: 40.0,
                      )),
                  IconButton(
                      onPressed: () {
                        setState(() {
                          SoundGenerator.play();
                        });
                      },
                      icon: const Icon(
                        Icons.volume_up,
                        color: Colors.green,
                        size: 40.0,
                      )),
                  IconButton(
                      onPressed: () {
                        setState(() {
                          SoundGenerator.stop();
                        });
                      },
                      icon: const Icon(
                        Icons.volume_off,
                        color: Colors.red,
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
                          windButtonPressed = 0;
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
                          windButtonPressed = 1;
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
                          windButtonPressed = 2;
                        });
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
              Stack(
                children: [
                  Transform(
                    transform: Matrix4.rotationZ(
                        settingsValues["artHorizonRollFactor"]! *
                            rollAngle *
                            pi /
                            180),
                    alignment: Alignment.center,
                    child: ClipOval(
                      child: Container(
                        width: settingsValues["scalingFactor"]!,
                        height: settingsValues["scalingFactor"]!,
                        child: Transform(
                          transform: Matrix4.diagonal3Values(8, 8, 8) +
                              Matrix4.translation(Vector3(
                                  -245,
                                  -1050 +
                                      ((settingsValues[
                                                  "artHorizonPitchFactor"]! *
                                              horizonPitch *
                                              pi /
                                              180) *
                                          618),
                                  2)),
                          child: Image(
                            image: const AssetImage("assets/arthorizon.png"),
                            alignment: Alignment(-1, 0),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ClipOval(
                    child: Image(
                      image: const AssetImage("assets/horizon_static.png"),
                      width: settingsValues["scalingFactor"]!,
                      height: settingsValues["scalingFactor"]!,
                    ),
                  )
                ],
              ),

              /*
              Container(
                color: warningColors[warningColorIndex],
                child: Text(
                  currentWarningString,
                  style: TextStyle(
                      fontSize: 30,
                      color: warningColors[(warningColorIndex + 1) % 2]),
                ),
              )*/
            ],
          ),
        ),
      ),
    );
  }
}
