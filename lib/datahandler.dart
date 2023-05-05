import 'dart:typed_data';
import 'dart:math';
import 'dart:ui';
import 'package:ble_larus_android/xcsoar_windekf.dart';
import 'package:vector_math/vector_math.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;

class VarioData {
  double airspeed = double.nan;

  Vector3 airspeedVector = Vector3(0, 0, 0);
  double roll = double.nan;

  Vector3 ardupilotWind = Vector3(0, 0, 0);
  Vector3 acceleration = Vector3(0, 0, 0);
  double height_gps = double.nan;
  double pitch = double.nan;

  int latitude = 0;
  int longitude = 0;
  double batteryVoltage = double.nan;
  int gpsTime = 0;
  double presTemp = double.nan;
  int gpsStatus = -5;
  double turnRadius = double.nan;
  Vector2 ekfGroundSpeed = Vector2(0, 0);
  double ground_speed = double.nan;
  double ground_course = double.nan;
  double yaw = double.nan;
  double yawRate = double.nan; // yaw per second
  int lastYawUpdate = 0; // time in ms of last yaw update
  double yawRateTurn = 0.5; // yaw rate to count as a turn
  int turnStartTime = 0; // time in ms of start of turn
  int yawRateOverLimitCounter = 0; // counter for how many ms

  double prev_raw_total_energy = double.nan;
  double prev_simple_total_energy = double.nan;
  double raw_climb_rate = double.nan;
  double simple_climb_rate = double.nan;
  double reading = double.nan;

  Vector3 gpsSpeed = Vector3(0, 0, 0);

  Vector3 velned = Vector3(0, 0, 0);

  int lastUpdate = 0;
  int updateTime = 0;

  XCSoarWind xcsoarEkf = XCSoarWind();
  XCSoarWind xcsoarEkfVelned = XCSoarWind();

  Vector3 larusWind = Vector3(0, 0, 0);

  final int appStartTime = DateTime.now().millisecondsSinceEpoch;
  String logFilePath = "";
  String tmpWriteBuffer = "";
  var dataStreamController = StreamController<String>();

  Future<void> writeStreamedData(Stream<String> dataStream) async {
    IOSink logFileSink = File(logFilePath).openWrite(mode: FileMode.append);
    await for (final dataString in dataStream.distinct()) {
      logFileSink
          .write('${DateTime.now().millisecondsSinceEpoch},$dataString\n');
    }
  }

// usually instantly returns
  Future<void> writeData(String data) async {
    if (logFilePath == "") {
      logFilePath = "-1";
      logFilePath = path.join((await getExternalStorageDirectory())!.path,
          'log${appStartTime.toString()}.csv');
      //print(logFilePath);
      File logFile = File(logFilePath);
      logFile.createSync(recursive: true);
      writeStreamedData(dataStreamController.stream);
    }
    if (logFilePath.length > 3) {
      dataStreamController.add(data);
    }
    //File logFile = File(logFilePath);
    //await logFile.writeAsString('${DateTime.now().millisecondsSinceEpoch},$data\n', mode: FileMode.append);
  }

  void calculateYawUpdate(newYaw) {
    larusWind = gpsSpeed - airspeedVector;
    yawRate = (yaw - newYaw) /
        ((DateTime.now().millisecondsSinceEpoch - lastYawUpdate) / 1000.0);
    if (yawRate.abs() < yawRateTurn) {
      yawRateOverLimitCounter = 0;
      turnStartTime = DateTime.now().millisecondsSinceEpoch;
      xcsoarEkf.resetCircleSamples();
    } else if (yawRateOverLimitCounter == 0) {
      yawRateOverLimitCounter =
          DateTime.now().millisecondsSinceEpoch - turnStartTime;
    }
    yaw = newYaw;
    lastYawUpdate = DateTime.now().millisecondsSinceEpoch;
  }

  void calculateGPSSpeedUpdate() {
    if (yawRate.abs() > yawRateTurn) {
      xcsoarEkf.addCircleSample(
          gpsSpeed, DateTime.now().millisecondsSinceEpoch);
    }
    xcsoarEkf.update(airspeed, gpsSpeed);
    xcsoarEkfVelned.update(airspeed, velned);
  }

  void parse_ble_data(List<int> data) {
    updateTime = DateTime.now().millisecondsSinceEpoch - lastUpdate;
    lastUpdate = DateTime.now().millisecondsSinceEpoch;
    int blePacketNum = data[data.length - 1];
    final bytes = Uint8List.fromList(data);
    final byteData = ByteData.sublistView(bytes);
    String logString = "";
    for (int datItem in data) {
      logString += "$datItem,";
    }
    switch (blePacketNum) {
      case 0:
        airspeed = byteData.getFloat32(0, Endian.little);
        airspeedVector = Vector3(
            byteData.getFloat32(4, Endian.little),
            byteData.getFloat32(8, Endian.little),
            byteData.getFloat32(12, Endian.little));
        roll = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        writeData(
            '0,${airspeed.toStringAsFixed(4)},${airspeedVector.toString()},${roll.toStringAsFixed(4)}~$logString');
        break;
      case 1:
        ardupilotWind = Vector3(
            byteData.getFloat32(0, Endian.little),
            byteData.getFloat32(4, Endian.little),
            byteData.getFloat32(8, Endian.little));
        height_gps = byteData.getInt32(12, Endian.little) / 100.0;
        pitch = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        writeData(
            '1,${ardupilotWind.toString()},${height_gps.toStringAsFixed(4)},${pitch.toStringAsFixed(4)}~$logString');
        break;
      case 2:
        ground_course = byteData.getFloat32(0, Endian.little);
        latitude = byteData.getInt32(4, Endian.little);
        longitude = byteData.getInt32(8, Endian.little);
        ground_speed = byteData.getFloat32(12, Endian.little);
        double newYaw = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        calculateYawUpdate(newYaw);
        writeData(
            '2,${latitude.toString()},${longitude.toString()},${ground_speed.toStringAsFixed(4)},${ground_course.toStringAsFixed(4)},${yaw.toStringAsFixed(4)},${larusWind.toString()},${newYaw.toStringAsFixed(4)}~$logString');
        break;
      case 3:
        turnRadius = byteData.getFloat32(0, Endian.little);
        ekfGroundSpeed = Vector2(byteData.getInt16(4, Endian.little) / 500.0,
            byteData.getInt16(6, Endian.little) / 500.0);
        raw_climb_rate = byteData.getFloat32(8, Endian.little);
        simple_climb_rate = byteData.getFloat32(12, Endian.little);
        reading = byteData.getInt16(16, Endian.little) / 100.0;
        writeData(
            '3,${turnRadius.toStringAsFixed(4)},${ekfGroundSpeed.toString()},${raw_climb_rate.toStringAsFixed(4)},${simple_climb_rate.toStringAsFixed(4)},${reading.toString()}~$logString');
        break;
      case 4:
        gpsSpeed = Vector3(
            byteData.getInt16(0, Endian.little) / 500.0,
            byteData.getInt16(2, Endian.little) / 500.0,
            byteData.getInt16(4, Endian.little) / 500.0);
        velned = Vector3(
            byteData.getInt16(6, Endian.little) / 500.0,
            byteData.getInt16(8, Endian.little) / 500.0,
            byteData.getInt16(10, Endian.little) / 500.0);
        calculateGPSSpeedUpdate();
        writeData(
            '4,${gpsSpeed.toString()},${velned.toString()},${gpsSpeed.angleTo(Vector3(0, 0, 0))}~$logString');
        break;
      case 5:
        acceleration = Vector3(
            byteData.getInt16(0, Endian.little) / 1000.0,
            byteData.getInt16(2, Endian.little) / 1000.0,
            byteData.getInt16(4, Endian.little) / 1000.0);

        batteryVoltage = byteData.getInt16(6, Endian.little) / 100.0;
        gpsTime = byteData.getUint32(8, Endian.little);
        presTemp = byteData.getFloat32(12, Endian.little);
        gpsStatus = byteData.getInt16(16, Endian.little);
        writeData(
            '5,${acceleration.toString()},${batteryVoltage.toString()},${gpsTime.toString()},${presTemp.toStringAsFixed(4)},${gpsStatus.toString()}~$logString');
        break;
      default:
        break;
    }
  }
}
