import 'dart:typed_data';
import 'dart:math';
import 'package:ble_larus_android/xcsoar_windekf.dart';
import 'package:vector_math/vector_math.dart';

class VarioData {
  double airspeed = double.nan;
  
  Vector3 airspeedVector = Vector3(0, 0, 0);
  double roll = double.nan;
  
  Vector3 ardupilotWind = Vector3(0, 0, 0);
  double height_gps = double.nan;
  double pitch = double.nan;

  int latitude = 0;
  int longitude = 0;
  double ground_speed = double.nan;
  double ground_course = double.nan;
  double yaw = double.nan;
  double yawRate = double.nan;  // yaw per second
  int lastYawUpdate = 0;  // time in ms of last yaw update
  double yawRateTurn = 0.5; // yaw rate to count as a turn
  int yawRateOverLimitCounter = 0;  // counter for how many ms

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
      
  void parse_ble_data(List<int> data) {
    updateTime = DateTime.now().millisecondsSinceEpoch - lastUpdate;
    lastUpdate = DateTime.now().millisecondsSinceEpoch;
    int blePacketNum = data[data.length - 1];
    final bytes = Uint8List.fromList(data);
    final byteData = ByteData.sublistView(bytes);
    switch (blePacketNum){
      case 0:
        airspeed = byteData.getFloat32(0, Endian.little);
        airspeedVector = Vector3(byteData.getFloat32(4, Endian.little), byteData.getFloat32(8, Endian.little), byteData.getFloat32(12, Endian.little));
        roll = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        break;
      case 1:
        ardupilotWind = Vector3(byteData.getFloat32(0, Endian.little), byteData.getFloat32(4, Endian.little), byteData.getFloat32(8, Endian.little));
        height_gps = byteData.getFloat32(12, Endian.little);
        pitch = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        break;
      case 2:
        latitude = byteData.getInt32(0, Endian.little);
        longitude = byteData.getInt32(4, Endian.little);
        ground_speed = byteData.getFloat32(8, Endian.little);
        ground_course = byteData.getFloat32(12, Endian.little);
        double newYaw = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        larusWind = gpsSpeed - airspeedVector;
        yawRate = (yaw - newYaw) / ((DateTime.now().millisecondsSinceEpoch - lastYawUpdate) * 1000.0);
        if (yawRate.abs() < yawRateTurn) {
          yawRateOverLimitCounter = 0;
        } else if (yawRateOverLimitCounter  == 0) {
          yawRateOverLimitCounter = lastYawUpdate;
        }
        yaw = newYaw;
        lastYawUpdate = DateTime.now().millisecondsSinceEpoch;
        break;
      case 3:
        prev_raw_total_energy = byteData.getFloat32(0, Endian.little);
        prev_simple_total_energy = byteData.getFloat32(4, Endian.little);
        raw_climb_rate = byteData.getFloat32(8, Endian.little);
        simple_climb_rate = byteData.getFloat32(12, Endian.little);
        reading = byteData.getInt16(16, Endian.little) / 100.0;
        break;
      case 4:
        gpsSpeed = Vector3(byteData.getInt16(0, Endian.little) / 500.0, byteData.getInt16(2, Endian.little) / 500.0, byteData.getInt16(4, Endian.little) / 500.0);
        velned = Vector3(byteData.getInt16(6, Endian.little) / 500.0, byteData.getInt16(8, Endian.little) / 500.0, byteData.getInt16(10, Endian.little) / 500.0);
        xcsoarEkf.update(airspeed, gpsSpeed);
        xcsoarEkfVelned.update(airspeed, velned);
        break;
      default:
        break;
    }
  }
}