import 'dart:math';
import 'package:vector_math/vector_math.dart';


class GPSSample{
  Vector3 gpsSpeed = Vector3(0, 0, 0);
  int timestamp = 0;
}
class XCSoarWind{
  static const double WIND_K0 = 1.0e-2;
  static const double WIND_K1 = 1.0e-5;
  
  List<double> airspeedWindResult = [0, 0, 1]; // results

  double k = WIND_K0*4;


  int circleCount = 0;
  double currentCircleStart = 0;
  double currentCircle = 0;
  List<GPSSample> circleSamples = [];
  Vector3 circleWind = Vector3(0, 0, 0);
  
  int circleWindQuality = 0;


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

  Future<void> update(double airspeed, Vector3 gpsSpeed) async
  {
    if(!airspeed.isNaN && !gpsSpeed.x.isNaN && !gpsSpeed.y.isNaN){

      // airsp = sf * | gps_v - wind_v |
      double dx = gpsSpeed.x - airspeedWindResult[0];
      double dy = gpsSpeed.y - airspeedWindResult[1];
      double mag = hypot(dx, dy).toDouble();

      List<double> K = [
        -airspeedWindResult[2]*dx/mag*k,
        -airspeedWindResult[2]*dy/mag*k,
        mag*WIND_K1
      ];
      k += 0.01 * (WIND_K0 - k);
      
      // measurement equation
      double Error = airspeed - airspeedWindResult[2]*mag;
      airspeedWindResult[0] += K[0] * Error;
      airspeedWindResult[1] += K[1] * Error;
      airspeedWindResult[2] += K[2] * Error;
      
      // limit values
      if (airspeedWindResult[2] < 0.5) {
        airspeedWindResult[2] = 0.5;
      } else if ( airspeedWindResult[2] > 1.5) {
        airspeedWindResult[2] = 1.5;
      }
    }

  }

  List<double> getWind()
  {
    return airspeedWindResult;
  }

/* Wind calculation based on XCSoar Circle Wind
- Calculate min and max ground speed of last circle
- Difference between min and max is the wind speed * 2
- Does not account for differences in airspeed and only relies on gps data
*/
Future<void> updateCircleWind() async {
  if(circleCount <= 0 || circleSamples.isEmpty) return;

  // reject if average time step greater than 2.0 seconds
  if (circleSamples.last.timestamp - circleSamples.first.timestamp > 2000) return;
  if ((circleSamples.last.timestamp - circleSamples.first.timestamp) / (circleSamples.length - 1) > 2000) return;

  // find average
  double av = 0;
  circleSamples.forEach((element) { av += element.gpsSpeed.length; });
  
  av /= circleSamples.length;

  // find zero time for times above average
  double rthismax = 0;
  double rthismin = 0;
  int jmax = -1;
  int jmin = -1;

  for (int j = 0; j < circleSamples.length; j++) {
    double rthisp = 0;

    for (int i = 1; i < circleSamples.length; i++) {
      int ithis = (i + j) % circleSamples.length;
      int idiff = i;

      if (idiff > circleSamples.length / 2)
        idiff = circleSamples.length - idiff;

      rthisp += circleSamples[ithis].gpsSpeed.length * idiff;
    }

    if ((rthisp < rthismax) || (jmax == -1)) {
      rthismax = rthisp;
      jmax = j;
    }

    if ((rthisp > rthismin) || (jmin == -1)) {
      rthismin = rthisp;
      jmin = j;
    }
  }

  // attempt to fit cycloid
  double mag = (circleSamples[jmax].gpsSpeed.length - circleSamples[jmin].gpsSpeed.length) / 2;
  if (mag >= 30)
    // limit to reasonable values (60 knots), reject otherwise
    return;

  double rthis = 0;

  circleSamples.forEach((sample) {
    double wx = sample.gpsSpeed.x * av + sample.gpsSpeed.y;
    double wy = sample.gpsSpeed.y * av;
    double cmag = hypot(wx, wy) - sample.gpsSpeed.length;
    rthis += cmag * cmag;
  });

  rthis /= circleSamples.length;
  rthis = sqrt(rthis);


  if (mag > 1)
    circleWindQuality = 5 - (rthis / mag * 3).round();
  else
    circleWindQuality = 5 - rthis.round();

  if (circleCount < 3)
    circleWindQuality--;
  if (circleCount < 2)
    circleWindQuality--;

  if (circleWindQuality < 1)
    //measurment quality too low
    return;

  /* 5 is maximum quality, make sure we honour that */
  circleWindQuality = min(circleWindQuality, 5);

  // jmax is the point where most wind samples are below
  circleSamples.elementAt(jmax).gpsSpeed.scale(-1);
  circleSamples.elementAt(jmax).gpsSpeed.normalizeInto(circleWind);
  circleWind.scale(-1 * mag);
}

}