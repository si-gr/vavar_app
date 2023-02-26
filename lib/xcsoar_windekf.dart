import 'dart:math';

class XCSoarWind{
  static const double WIND_K0 = 1.0e-2;
  static const double WIND_K1 = 1.0e-5;
  List<double> X = [0, 0, 0]; // results
  double k = 0;

  num hypot(num x, num y) {
    var first = x.abs();
    var second = y.abs();

    if (y > x) {
      first = y.abs();
      second = x.abs();
    }

    if (first == 0.0) {
      return second;
    }

    final t = second / first;
    return first * sqrt(1 + t * t);
  }

  Future<void> update(double airspeed, List<double> gps_vel) async
  {
    if(!airspeed.isNaN && gps_vel.length == 2 && !gps_vel[0].isNaN && !gps_vel[1].isNaN){

      // airsp = sf * | gps_v - wind_v |
      double dx = gps_vel[0]-X[0];
      double dy = gps_vel[1]-X[1];
      double mag = hypot(dx, dy).toDouble();

      List<double> K = [
        -X[2]*dx/mag*k,
        -X[2]*dy/mag*k,
        mag*WIND_K1
      ];
      k += 0.01 * (WIND_K0 - k);
      
      // measurement equation
      double Error = airspeed - X[2]*mag;
      X[0] += K[0] * Error;
      X[1] += K[1] * Error;
      X[2] += K[2] * Error;
      
      // limit values
      if (X[2] < 0.5) {
        X[2] = 0.5;
      } else if ( X[2] > 1.5) {
        X[2] = 1.5;
      }
    }

  }

  XCSoarWind()
  {
    k = WIND_K0*4;

    X[0] = X[1] = 0;	// initial wind speed (m/s)
    X[2] = 1;             // initial scale factor
  }

  List<double> getWind()
  {
    return X;
  }
}