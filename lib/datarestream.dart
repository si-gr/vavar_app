import 'dart:typed_data';
import 'dart:math';
import 'dart:ui';
import 'package:ble_larus_android/datahandler.dart';
import 'package:ble_larus_android/xcsoar_windekf.dart';
import 'package:vector_math/vector_math.dart';
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
    realStartTime = DateTime.now().millisecondsSinceEpoch;
    restreamFile();

  } // constructor

  Future<void> restreamFile() async {
    // read file
    var file = File(logFilePath.path);
    var lines = file.readAsLinesSync();
    print(lines[0]);
    int logStartTime = int.parse(lines[0].substring(0, lines[0].indexOf(',') - 1));
    timeOffset = realStartTime - logStartTime;
    int lineCounter = 1;
    while (lineCounter < lines.length) {
      while (getLineTime(lines[lineCounter]) < DateTime.now().millisecondsSinceEpoch - timeOffset) {
        await Future.delayed(Duration(milliseconds: 1));
      }
      updateVarioData(lines[lineCounter]);
      lineCounter++;
    }
    print("Log file done\n");
  }

  int getLineTime(String line) {
    return int.parse(line.substring(0, line.indexOf(',') - 1));
  }

  void updateVarioData(String line) {
    var splittedLine = line.split(',');
    if (splittedLine.length < 3) {
      return;
    }
    switch (splittedLine[1]){
      case '0':
        varioData.airspeed = double.parse(splittedLine[2]);
        break;
      case '1':
        varioData.airspeedVector = Vector3(double.parse(splittedLine[2]), double.parse(splittedLine[3]), double.parse(splittedLine[4]));
        break;
      case '2':
        varioData.roll = double.parse(splittedLine[2]);
        break;
      case '3':
        varioData.ardupilotWind = Vector3(double.parse(splittedLine[2]), double.parse(splittedLine[3]), double.parse(splittedLine[4]));
        break;
      case '4':
        varioData.height_gps = double.parse(splittedLine[2]);
        break;
      default:
        break;
    }

    varioData.airspeed = 0.0;
  }



}