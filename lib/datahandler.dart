import 'dart:typed_data';
import 'dart:math';
import 'package:ble_larus_android/xcsoar_windekf.dart';




class VarioData {
  double airspeed = double.nan;
  double airspeed_vector_x = double.nan;
  double airspeed_vector_y = double.nan;
  double airspeed_vector_z = double.nan;
  double roll = double.nan;
  
  double wind_vector_x = double.nan;
  double wind_vector_y = double.nan;
  double wind_vector_z = double.nan;
  double height_gps = double.nan;
  double pitch = double.nan;

  int latitude = 0;
  int longitude = 0;
  double ground_speed = double.nan;
  double ground_course = double.nan;
  double yaw = double.nan;

  double prev_raw_total_energy = double.nan;
  double prev_simple_total_energy = double.nan;
  double raw_climb_rate = double.nan;
  double simple_climb_rate = double.nan;
  double reading = double.nan;

  double gps_vector_x = double.nan;
  double gps_vector_y = double.nan;
  double gps_vector_z = double.nan;
  double velned_vector_x = double.nan;
  double velned_vector_y = double.nan;
  double velned_vector_z = double.nan;

  
  XCSoarWind xcsoarEkf = XCSoarWind();
  XCSoarWind xcsoarEkfVelned = XCSoarWind();

  double larusWindX = double.nan;
  double larusWindY = double.nan;
      
  void parse_ble_data(List<int> data) {
    
    int blePacketNum = data[data.length - 1];
    final bytes = Uint8List.fromList(data);
    final byteData = ByteData.sublistView(bytes);
    switch (blePacketNum){
      case 0:
        airspeed = byteData.getFloat32(0, Endian.little);
        airspeed_vector_x = byteData.getFloat32(4, Endian.little);
        airspeed_vector_y = byteData.getFloat32(8, Endian.little);
        airspeed_vector_z = byteData.getFloat32(12, Endian.little);
        roll = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        break;
      case 1:
        wind_vector_x = byteData.getFloat32(0, Endian.little);
        wind_vector_y = byteData.getFloat32(4, Endian.little);
        wind_vector_z = byteData.getFloat32(8, Endian.little);
        height_gps = byteData.getFloat32(12, Endian.little);
        pitch = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        break;
      case 2:
        latitude = byteData.getInt32(0, Endian.little);
        longitude = byteData.getInt32(4, Endian.little);
        ground_speed = byteData.getFloat32(8, Endian.little);
        ground_course = byteData.getFloat32(12, Endian.little);
        yaw = byteData.getInt16(16, Endian.little) / 0x8000 * pi;
        larusWindX = gps_vector_x - (cos(yaw) * airspeed);
        larusWindY = gps_vector_x - (sin(yaw) * airspeed);
        break;
      case 3:
        prev_raw_total_energy = byteData.getFloat32(0, Endian.little);
        prev_simple_total_energy = byteData.getFloat32(4, Endian.little);
        raw_climb_rate = byteData.getFloat32(8, Endian.little);
        simple_climb_rate = byteData.getFloat32(12, Endian.little);
        reading = byteData.getInt16(16, Endian.little) / 100.0;
        break;
      case 4:
        gps_vector_x = byteData.getInt16(0, Endian.little) / 500.0;
        gps_vector_y = byteData.getInt16(2, Endian.little) / 500.0;
        gps_vector_z = byteData.getInt16(4, Endian.little) / 500.0;
        velned_vector_x = byteData.getInt16(6, Endian.little) / 500.0;
        velned_vector_y = byteData.getInt16(8, Endian.little) / 500.0;
        velned_vector_z = byteData.getInt16(10, Endian.little) / 500.0;
        xcsoarEkf.update(airspeed, [gps_vector_x, gps_vector_y, gps_vector_z]);
        xcsoarEkfVelned.update(airspeed, [velned_vector_x, velned_vector_y, velned_vector_z]);
        break;
      default:
        break;
    }
  }
}