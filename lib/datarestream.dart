import 'dart:typed_data';
import 'dart:math';
import 'dart:ui';
import 'package:ble_larus_android/datahandler.dart';
import 'package:ble_larus_android/xcsoar_windekf.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;

class DataRestream {
  VarioData varioData;
  FileSystemEntity logFilePath;
  int realStartTime = 0;
  int timeOffset = 0;

  //DataRestream(this.varioData, this.logFilePath); // constructor

  DataRestream(this.varioData, this.logFilePath) {
    // create new thread for data restream
    realStartTime = DateTime.now().microsecondsSinceEpoch;
  } // constructor

  Future<int> restreamFile() async {
    // read file
    var file = File(logFilePath.path);
    var lines = file.readAsLinesSync();
    print(lines[0]);
    print("Length: ${lines.length}");
    int logStartTime = getLineTime(lines[0]);

    timeOffset = realStartTime - logStartTime;
    int lineCounter = 1;
    while (lineCounter < lines.length) {     
      while (getLineTime(lines[lineCounter]) >
          DateTime.now().microsecondsSinceEpoch - timeOffset) {
        await Future.delayed(Duration(milliseconds: 1));
      }
      updateVarioData(lines[lineCounter]);
      lineCounter++;
      //print("new line $lineCounter");
    }
    print("Log file done\n");
    return lineCounter;
  }

  int getLineTime(String line) {
    if (line.indexOf(',') > 0) {
      try {
        return int.parse(line.substring(0, line.indexOf(',')));
      } on FormatException {
        print("Error parsing line time");
        return 0;
      }
    }
    return 0;
  }

  String stripNonNumeric(String line) {
    return line.replaceAll(RegExp(r'[^0-9\.\-]'), '');
  }

  void updateVarioData(String line) {
    var splittedLine = line.split("~")[1].split(',');
    if (splittedLine.length < 3) {
      return;
    }
    List<int> data = [];
    for (String datItem in splittedLine) {
      try {
        if (datItem.length > 0){
          data.add(int.parse(datItem));
        }
      } on FormatException catch (e){
        print("Error parsing line $e");
      }
    }
    varioData.parse_ble_data(data);
    /*
    try {
      switch (splittedLine[1]) {
        case '0':
          // '0,${airspeed.toStringAsFixed(4)},${airspeedVector.toString()},${roll.toStringAsFixed(4)}');
          varioData.airspeed = double.parse(stripNonNumeric(splittedLine[2]));
          varioData.airspeedVector = Vector3(
              double.parse(stripNonNumeric(splittedLine[3])),
              double.parse(stripNonNumeric(splittedLine[4])),
              double.parse(stripNonNumeric(splittedLine[5])));
          varioData.roll = double.parse(stripNonNumeric(splittedLine[6]));
          varioData.fastVario = double.parse(stripNonNumeric(splittedLine[7]));
          break;
        case '1':
          // '1,${ardupilotWind.toString()},${height_gps.toStringAsFixed(4)},${pitch.toStringAsFixed(4)}');
          varioData.ardupilotWind = Vector3(
              double.parse(stripNonNumeric(splittedLine[2])),
              double.parse(stripNonNumeric(splittedLine[3])),
              double.parse(stripNonNumeric(splittedLine[4])));
          varioData.height_gps = double.parse(stripNonNumeric(splittedLine[5]));
          varioData.pitch = double.parse(stripNonNumeric(splittedLine[6]));
          varioData.fastVario = double.parse(stripNonNumeric(splittedLine[7]));
          /*
          varioData.kalmanVarioTECalculator
              .setNewTE(varioData.airspeed, varioData.height_gps);
          varioData.rawClimbVario
              .setNewValue(varioData.kalmanVarioTECalculator.getVario());
              */
          break;
        case '2':
          // '2,${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)},${ground_speed.toStringAsFixed(4)},${ground_course.toStringAsFixed(4)},${yaw.toStringAsFixed(4)},${larusWind.toString()},${yawRate.toStringAsFixed(4)}');
          varioData.latitude = int.parse(stripNonNumeric(splittedLine[2]));
          varioData.longitude = int.parse(stripNonNumeric(splittedLine[3]));
          varioData.ground_speed =
              double.parse(stripNonNumeric(splittedLine[4]));
          varioData.ground_course =
              double.parse(stripNonNumeric(splittedLine[5]));
          varioData.yaw = double.parse(stripNonNumeric(splittedLine[6]));
          varioData.fastVario = double.parse(stripNonNumeric(splittedLine[7]));
          break;
        case '3':
          // '3,${turnRadius.toStringAsFixed(4)},${ekfGroundSpeed.toString()},${raw_climb_rate.toStringAsFixed(4)},${reading.toStringAsFixed(4)},${thermability.toString()}~${logRawData ? logString : ""}');
          varioData.turnRadius = double.parse(stripNonNumeric(splittedLine[2]));
          varioData.ekfGroundSpeed = Vector2(
              double.parse(stripNonNumeric(splittedLine[3])),
              double.parse(stripNonNumeric(splittedLine[4])));
          varioData.raw_climb_rate =
              double.parse(stripNonNumeric(splittedLine[5]));
          varioData.reading = double.parse(stripNonNumeric(splittedLine[6]));
          varioData.thermability =
              double.parse(stripNonNumeric(splittedLine[7]));
          varioData.fastVario = double.parse(stripNonNumeric(splittedLine[8]));
          break;
        case '4':
          // '4,${gpsSpeed.toString()},${velned.toString()},${tasstate.toString()},${height_baro.toString()}~${logRawData ? logString : ""}');
          varioData.gpsSpeed = Vector3(
              double.parse(stripNonNumeric(splittedLine[2])),
              double.parse(stripNonNumeric(splittedLine[3])),
              double.parse(stripNonNumeric(splittedLine[4])));
          varioData.velned = Vector3(
              double.parse(stripNonNumeric(splittedLine[5])),
              double.parse(stripNonNumeric(splittedLine[6])),
              double.parse(stripNonNumeric(splittedLine[7])));
          varioData.tasstate = double.parse(stripNonNumeric(splittedLine[8]));
          varioData.height_baro =
              double.parse(stripNonNumeric(splittedLine[9]));
          varioData.fastVario = double.parse(stripNonNumeric(splittedLine[10]));
          //varioData.calculateGPSSpeedUpdate();
          //print("setting ${varioData.gpsSpeed.z * -1.0}");
          //varioData.gpsVario.setNewValue(varioData.gpsSpeed.z * -1.0);
          /*if (!varioData.gpsSpeed.z.isNaN &&
              !varioData.airspeed.isNaN &&
              varioData.airspeed > 0.0) {
            varioData.teSpeedCalculator
                .setNewTE(varioData.airspeed, varioData.gpsSpeed.z * -1.0);
            varioData.rawClimbSpeedVario
                .setNewValue(varioData.teSpeedCalculator.getVario());
          }*/
          //print("gps speed z is ${varioData.gpsSpeed.z}");
          break;
        case '5':
          // '5,${acceleration.toString()},${batteryVoltage.toString()},${gpsTime.toString()},${SPEdot.toString()},${SKEdot.toString()},${gpsStatus.toString()}~${logRawData ? logString : ""}');
          varioData.acceleration = Vector3(
              double.parse(stripNonNumeric(splittedLine[2])),
              double.parse(stripNonNumeric(splittedLine[3])),
              double.parse(stripNonNumeric(splittedLine[4])));
          varioData.batteryVoltage =
              double.parse(stripNonNumeric(splittedLine[5]));
          varioData.gpsTime = int.parse(stripNonNumeric(splittedLine[6]));
          varioData.SPEdot = double.parse(stripNonNumeric(splittedLine[7]));
          varioData.SKEdot = double.parse(stripNonNumeric(splittedLine[8]));
          varioData.gpsStatus = int.parse(stripNonNumeric(splittedLine[9]));
          varioData.fastVario = double.parse(stripNonNumeric(splittedLine[10]));

          break;
        default:
          break;
      }
    } on RangeError catch (e) {
      print(e);
    } on FormatException catch (e) {
      print(e);
    }
    
    varioData.updateTime =
        DateTime.now().microsecondsSinceEpoch - varioData.lastUpdate;
    varioData.lastUpdate = DateTime.now().microsecondsSinceEpoch;
    varioData.processUpdate(int.parse(splittedLine[1]));
    */
  }
}
