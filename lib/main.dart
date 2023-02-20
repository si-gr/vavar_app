import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:ble_larus_android/ble_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'dart:typed_data';





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
  // Some state management stuff
  bool _foundDeviceWaitingToConnect = false;
  bool _scanStarted = false;
  bool _connected = false;
// Bluetooth related variables
  late DiscoveredDevice _ubiqueDevice;
  final flutterReactiveBle = FlutterReactiveBle();

  late StreamSubscription<DiscoveredDevice> _scanStream;
  late QualifiedCharacteristic _rxCharacteristic;
// These are the UUIDs of your device
  final Uuid serviceUuid = Uuid.parse("0000abf0-0000-1000-8000-00805f9b34fb");
  final Uuid characteristicUuid = Uuid.parse("0000abf2-0000-1000-8000-00805f9b34fb");
  
  void _startScan() async {
// Platform permissions handling stuff
    bool permGranted = false;
    setState(() {
      _scanStarted = true;
    });
    PermissionStatus permission;
    if (Platform.isAndroid) {
      permission = await Permission.location.request();
      if (permission == PermissionStatus.granted){
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
      _scanStream = flutterReactiveBle
          .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency).listen((device) {
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
            
            
            final characteristic = QualifiedCharacteristic(serviceId: serviceUuid, characteristicId: characteristicUuid, deviceId: event.deviceId);
            flutterReactiveBle.subscribeToCharacteristic(characteristic).listen((data) {
              String values_string = "";
              final bytes = Uint8List.fromList(data);
              final byteData = ByteData.sublistView(bytes);
              //print(byteData.lengthInBytes.toString() + " bytes");
              for (int i = 0; i < byteData.lengthInBytes - 4; i += 4) {
                //print(i.toString() + " bytes s" + (byteData.lengthInBytes + 4).toString());
                double value = byteData.getFloat32(i, Endian.little);
                
                values_string += value.toString() + " ";

              }
              int display_number = data[data.length - 1];
              
              //print('$values_string num $display_number');
              if(display_number >= 0 && display_number < 4){
                setState(() {
                  _displayText[display_number] = values_string;

                });
              }
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
            if(_connected){
              print("disconnected");
              setState(() {
                _connected = false;    
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
    if(!_scanStarted) {
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[          
            Text(
              '$message',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              '${_displayText[1]}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              '${_displayText[2]}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              '${_displayText[3]}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Icon(
              Icons.arrow_upward,
              color: Colors.blue,
              size: 24.0,
              semanticLabel: 'Wind direction',
            ),

          ],
          
        ),
        
      ),
    );
  }
}
