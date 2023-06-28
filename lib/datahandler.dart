import 'dart:typed_data';
import 'dart:math';
import 'dart:ui';
import 'package:ble_larus_android/apWindStore.dart';
import 'package:ble_larus_android/teSpeedCalculator.dart';
import 'package:ble_larus_android/tecalculator.dart';
import 'package:ble_larus_android/xcsoar_windekf.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ble_larus_android/vario.dart';
import 'WindEstimator.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;

class VarioData {
  double airspeed = double.nan;

  Vector3 airspeedVector = Vector3(0, 0, 0);
  double roll = 0;

  Vector3 ardupilotWind = Vector3(0, 0, 0);
  Vector3 acceleration = Vector3(0, 0, 0);
  double height_gps = 0;
  double pitch = 0;

  int latitude = 0;
  int longitude = 0;
  double batteryVoltage = 0;
  int gpsTime = 0;
  int gpsStatus = -5;
  double turnRadius = 0;
  Vector2 ekfGroundSpeed = Vector2(0, 0);
  double ground_speed = 0;
  double ground_course = 0;

  double yaw = 0;
  double windCorrection = 0;
  int yawUpdateTime = 0;
  double oldYaw = 0;
  int smoothedClimbRate = 0;

  double yawRate = 0; // yaw per second
  int lastYawUpdate = 0; // time in uws of last yaw update
  double yawRateTurn = 0.5; // yaw rate to count as a turn
  int turnStartTime = 0; // time in ms of start of turn
  int yawRateOverLimitCounter = 0; // counter for how many ms

  double raw_climb_rate = 0;
  double thermability = 0;
  double reading = 0;
  double airspeedOffset = -4;
  double height_baro = 0;
  double tasstate = 0;
  double SPEdot = 0;
  double SKEdot = 0;
  APWindStore windStore = APWindStore(rollingWindowSize: 10);

  double kalmanAccFactor = 1;
  double varioSpeedFactor = 1;

  Vario rawClimbVario = Vario(30000);
  Vario simpleClimbVario = Vario(30000);
  Vario gpsVario = Vario(30000);
  Vario windCompVario = Vario(30000);
  WindEstimator windEstimator = WindEstimator(5000, 0.2);
  TECalculator teCalculator = TECalculator();
  TECalculator kalmanVarioTECalculator = TECalculator();
  TESpeedCalculator teSpeedCalculator = TESpeedCalculator();
  Vario rawClimbSpeedVario = Vario(30000);
  double fastVario = 0;

  Vector3 gpsSpeed = Vector3(0, 0, 0);

  Vector3 velned = Vector3(0, 0, 0);

  int lastUpdate = 0;
  int updateTime = 0;

  XCSoarWind xcsoarEkf = XCSoarWind(1.0e-1, 1.0e-3);
  XCSoarWind xcsoarEkfVelned = XCSoarWind(1.0e-1, 1.0e-3);

  Vector3 larusWind = Vector3(0, 0, 0);

  final int appStartTime = DateTime.now().microsecondsSinceEpoch;
  String logFilePath = "";
  String tmpWriteBuffer = "";
  var dataStreamController = StreamController<String>();
  bool logRawData = true;
  bool logProcessedData = true;
  int allDataReceived =
      0; // add 2^packet_num to this variable for each received packet

  void setVarioAverageTime(int timeMs) {
    rawClimbVario.setAveragingTime(timeMs);
    rawClimbSpeedVario.setAveragingTime(timeMs);
    simpleClimbVario.setAveragingTime(timeMs);
    gpsVario.setAveragingTime(timeMs);
    windCompVario.setAveragingTime(timeMs);
  }

  void setWindEstimatorAverageTime(int timeMs) {
    windEstimator.setAveragingTime(timeMs);
  }

  Future<void> writeStreamedData(Stream<String> dataStream) async {
    IOSink logFileSink = File(logFilePath).openWrite(mode: FileMode.append);
    await for (final dataString in dataStream.distinct()) {
      logFileSink
          .write('${DateTime.now().microsecondsSinceEpoch},$dataString\n');
    }
  }

// usually instantly returns
  Future<void> writeData(String data) async {
    if (logProcessedData) {
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
    }
  }

  void calculateYawUpdate() {
    larusWind = gpsSpeed - airspeedVector;
    yawRate = ((oldYaw - yaw) /
                ((DateTime.now().microsecondsSinceEpoch - lastYawUpdate) /
                    1000000.0)) *
            0.1 +
        yawRate * 0.9; // average filter
    if (yawRate.abs() < yawRateTurn) {
      yawRateOverLimitCounter = 0;
      turnStartTime = DateTime.now().microsecondsSinceEpoch;
      xcsoarEkf.resetCircleSamples();
    } else if (yawRateOverLimitCounter == 0) {
      yawRateOverLimitCounter =
          DateTime.now().microsecondsSinceEpoch - turnStartTime;
    }
    oldYaw = yaw;
    lastYawUpdate = DateTime.now().microsecondsSinceEpoch;
  }

  void calculateGPSSpeedUpdate() {
    if (yawRate.abs() > yawRateTurn) {
      xcsoarEkf.addCircleSample(
          gpsSpeed, DateTime.now().microsecondsSinceEpoch);
    }
    xcsoarEkf.update(airspeed, gpsSpeed);
    xcsoarEkfVelned.update(airspeed, velned);
  }

  void processUpdate(int blePacketNum) {
    if ((allDataReceived ~/ pow(2, blePacketNum).toInt()) % 2 == 0) {
      allDataReceived += pow(2, blePacketNum).toInt();
    } else if (allDataReceived == 63) {
      if (blePacketNum == 1) {
        kalmanVarioTECalculator.setNewTE(
            varioSpeedFactor * airspeed, height_gps);
        //print("kalman var ${kalmanVarioTECalculator.getVario()} h ${height_gps} a ${airspeed}");
        rawClimbVario.setNewValue(kalmanVarioTECalculator.getVario());
      }
      if (blePacketNum == 30) {
        /*if (blePacketNum == 2) {
      calculateYawUpdate();
    }*/
        //windEstimator.estimateWind(yaw, airspeed, ekfGroundSpeed);
        //teCalculator.setNewTE(
        //    airspeed - windEstimator.getKalmanWind().x, height_gps);

        //windCompVario.setNewValue(teCalculator.getVario());

        simpleClimbVario.setNewValue(reading);
        calculateGPSSpeedUpdate();
        gpsVario.setNewValue(gpsSpeed.z * -1.0);
        teSpeedCalculator.setNewTE(
            varioSpeedFactor * airspeed, gpsSpeed.z * -1);
        rawClimbSpeedVario.setNewValueAcc(
            teSpeedCalculator.getVario(),
            kalmanAccFactor *
                (acceleration.z * cos(roll) + acceleration.x * sin(roll)));
      } else if (blePacketNum == 1) {
        // new wind
        windStore.update(ardupilotWind);
      }
    }
  }

  void parse_ble_data(List<int> data) {
    updateTime = DateTime.now().microsecondsSinceEpoch - lastUpdate;
    lastUpdate = DateTime.now().microsecondsSinceEpoch;
    int blePacketNum = data[data.length - 1];
    final bytes = Uint8List.fromList(data);
    final byteData = ByteData.sublistView(bytes);
    String logString = "";
    for (int datItem in data) {
      logString += "$datItem,";
    }
    fastVario = byteData.getInt8(18).toDouble() / 25.0;
    switch (blePacketNum) {
      case 0:
        airspeed = byteData.getFloat32(0, Endian.little) + airspeedOffset;
        airspeedVector = Vector3(
            byteData.getFloat32(4, Endian.little),
            byteData.getFloat32(8, Endian.little),
            byteData.getFloat32(12, Endian.little));
        roll = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        writeData(
            '0,${airspeed.toStringAsFixed(4)},${airspeedVector.toString()},${roll.toStringAsFixed(4)},${fastVario.toString()}~${logRawData ? logString : ""}');
        break;
      case 1:
        ardupilotWind = Vector3(
            byteData.getFloat32(0, Endian.little),
            byteData.getFloat32(4, Endian.little),
            byteData.getFloat32(8, Endian.little));
        height_gps = byteData.getInt32(12, Endian.little) / 100.0;
        pitch = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        writeData(
            '1,${ardupilotWind.toString()},${height_gps.toStringAsFixed(4)},${pitch.toStringAsFixed(4)},${fastVario.toString()}~${logRawData ? logString : ""}');
        break;
      case 2:
        ground_course = byteData.getFloat32(0, Endian.little);
        latitude = byteData.getInt32(4, Endian.little);
        longitude = byteData.getInt32(8, Endian.little);
        ground_speed = byteData.getFloat32(12, Endian.little);
        yaw = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        yawUpdateTime = DateTime.now().microsecondsSinceEpoch;
        writeData(
            '2,${latitude.toString()},${longitude.toString()},${ground_speed.toStringAsFixed(4)},${ground_course.toStringAsFixed(4)},${yaw.toStringAsFixed(4)},${fastVario.toString()}~${logRawData ? logString : ""}');

        break;
      case 3:
        turnRadius = byteData.getFloat32(0, Endian.little);
        ekfGroundSpeed = Vector2(byteData.getInt16(4, Endian.little) / 500.0,
            byteData.getInt16(6, Endian.little) / 500.0);
        raw_climb_rate =
            byteData.getFloat32(8, Endian.little); // wind compensated by larus
        reading = (byteData.getInt16(12, Endian.little)).toDouble() / 1000.0;
        thermability = byteData.getFloat32(14, Endian.little);
        writeData(
            '3,${turnRadius.toStringAsFixed(4)},${ekfGroundSpeed.toString()},${raw_climb_rate.toStringAsFixed(4)},${reading.toStringAsFixed(4)},${thermability.toString()},${fastVario.toString()}~${logRawData ? logString : ""}');
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
        tasstate = byteData.getInt16(12, Endian.little).toDouble() / 100.0;
        height_baro = byteData.getFloat32(14, Endian.little);
        writeData(
            '4,${gpsSpeed.toString()},${velned.toString()},${tasstate.toString()},${height_baro.toString()},${fastVario.toString()}~${logRawData ? logString : ""}');
        break;
      case 5:
        acceleration = Vector3(
            byteData.getInt16(0, Endian.little) / 50.0,
            byteData.getInt16(2, Endian.little) / 50.0,
            byteData.getInt16(4, Endian.little) / 50.0);

        batteryVoltage = byteData.getInt16(6, Endian.little) / 100.0;
        gpsTime = byteData.getUint32(8, Endian.little);
        SPEdot =
            (byteData.getInt16(12, Endian.little).toDouble() / 50.0) / 9.81;
        SKEdot =
            (byteData.getInt16(14, Endian.little).toDouble() / 50.0) / 9.81;
        gpsStatus = byteData.getInt16(16, Endian.little);
        writeData(
            '5,${acceleration.toString()},${batteryVoltage.toString()},${gpsTime.toString()},${SPEdot.toString()},${SKEdot.toString()},${gpsStatus.toString()},${fastVario.toString()}~${logRawData ? logString : ""}');
        break;
      case 10:
        /*
      _fast_larus_variables.wind_vector_x = (int16_t)(wind.x * 500.0);
    _fast_larus_variables.wind_vector_y = (int16_t)(wind.y * 500.0);
    _fast_larus_variables.windCorrection = (int16_t)(windCorrection * 500.0);
    _fast_larus_variables.airspeed = (int16_t)(aspd * 500.0);
    _fast_larus_variables.spedot = (int16_t)(_tecs->getSPEdot() * 50);
    _fast_larus_variables.skedot = (int16_t)(_tecs->getSKEdot() * 50);
    _fast_larus_variables.roll = (int16_t)((_ahrs.roll / M_PI) * (float)(0x8000));
    _fast_larus_variables.pitch = (int16_t)((_ahrs.pitch / M_PI) * (float)(0x8000));
      */
        ardupilotWind = Vector3(
            byteData.getInt16(0, Endian.little).toDouble() / 500.0,
            byteData.getInt16(2, Endian.little).toDouble() / 500.0,
            0);
        windCorrection = byteData.getInt16(4, Endian.little).toDouble() / 500.0;
        airspeed = byteData.getInt16(6, Endian.little).toDouble() / 500.0;
        SPEdot = byteData.getInt16(8, Endian.little).toDouble() / 50.0;
        SKEdot = byteData.getInt16(10, Endian.little).toDouble() / 50.0;
        roll = byteData.getInt16(12, Endian.little) / 0x8000 * pi;
        pitch = byteData.getInt16(14, Endian.little) / 0x8000 * pi;
        writeData(
            '10,${ardupilotWind.toString()},${windCorrection.toString()},${airspeed.toString()},${SPEdot.toString()},${SKEdot.toString()},${roll.toString()},${pitch.toString()}~${logRawData ? logString : ""}');

        break;
      case 20:
        /*
      _slow_larus_variables.battery_voltage = roundf(AP::battery().voltage() * 100.0f);   // 2B
    _slow_larus_variables.height_gps = _loc.alt;   // 4B
    _slow_larus_variables.turn_radius = thermallingRadius;
      */

        batteryVoltage = byteData.getInt16(0, Endian.little) / 100.0;
        height_gps = byteData.getInt32(2, Endian.little) / 100.0;
        turnRadius = byteData.getFloat32(6, Endian.little);
        writeData(
            '20,${batteryVoltage.toString()},${height_gps.toString()},${turnRadius.toString()}~${logRawData ? logString : ""}');

        break;

      default:
        break;
    }
    processUpdate(blePacketNum);
  }
}
