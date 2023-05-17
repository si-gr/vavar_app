import 'dart:math';
import 'package:vector_math/vector_math_64.dart';

class GPSSample {
  Vector3 gpsSpeed = Vector3(0, 0, 0);
  int timestamp = 0;
}

class XCSoarWind {
  //static const double WIND_K0 = 1.0e-2;
  //static const double WIND_K1 = 1.0e-5;

  double WIND_K0 = 1.0e-1;
  double WIND_K1 = 1.0e-3;

  List<double> airspeedWindResult = [0, 0, 1]; // results

  double k = 0;

  int circleCount = 0;
  Vector3 currentCircleStart = Vector3(0, 0, 0);
  double currentCircle = 0;
  List<GPSSample> circleSamples = [];
  Vector3 circleWind = Vector3(0, 0, 0);
  int circleWindQuality = 0;
  final int maximumSampleAgeUs = 2000000;

  XCSoarWind(WIND_K0, WIND_K1) {
    k = WIND_K0 * 4;
  }

  Future<void> update(double airspeed, Vector3 gpsSpeed) async {
    if (!airspeed.isNaN && !gpsSpeed.x.isNaN && !gpsSpeed.y.isNaN) {
      //print("updating xcsoar wind $airspeed $gpsSpeed");
      // airsp = sf * | gps_v - wind_v |
      double dx = gpsSpeed.x - airspeedWindResult[0];
      double dy = gpsSpeed.y - airspeedWindResult[1];
      double mag = sqrt(pow(dx, 2) + pow(dy, 2));

      List<double> K = [
        -airspeedWindResult[2] * dx / mag * k,
        -airspeedWindResult[2] * dy / mag * k,
        mag * WIND_K1
      ];
      k += 0.01 * (WIND_K0 - k);

      // measurement equation
      double Error = airspeed - airspeedWindResult[2] * mag;
      airspeedWindResult[0] += K[0] * Error;
      airspeedWindResult[1] += K[1] * Error;
      airspeedWindResult[2] += K[2] * Error;

      // limit values
      if (airspeedWindResult[2] < 0.5) {
        airspeedWindResult[2] = 0.5;
      } else if (airspeedWindResult[2] > 1.5) {
        airspeedWindResult[2] = 1.5;
      }
    }
  }

  List<double> getWind() {
    return airspeedWindResult;
  }

/* Wind calculation based on XCSoar Circle Wind
- Calculate min and max ground speed of last circle
- Difference between min and max is the wind speed * 2
- Does not account for differences in airspeed and only relies on gps data
*/
  Future<void> updateCircleWind() async {
    if (circleCount <= 0 || circleSamples.isEmpty) return;

    // reject if average time step greater than 2.0 seconds
    if (circleSamples.last.timestamp - circleSamples.first.timestamp >
        maximumSampleAgeUs) return;
    if ((circleSamples.last.timestamp - circleSamples.first.timestamp) /
            (circleSamples.length - 1) >
        maximumSampleAgeUs) return;

    // find average
    double av = 0;
    circleSamples.forEach((element) {
      av += element.gpsSpeed.length;
    });

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
    double mag = (circleSamples[jmax].gpsSpeed.length -
            circleSamples[jmin].gpsSpeed.length) /
        2;
    if (mag >= 30)
      // limit to reasonable values (60 knots), reject otherwise
      return;

    double rthis = 0;

    circleSamples.forEach((sample) {
      double wx = sample.gpsSpeed.x * av + sample.gpsSpeed.y;
      double wy = sample.gpsSpeed.y * av;
      double cmag = sqrt(pow(wx, 2) + pow(wy, 2)) - sample.gpsSpeed.length;
      rthis += cmag * cmag;
    });

    rthis /= circleSamples.length;
    rthis = sqrt(rthis);

    if (mag > 1) {
      circleWindQuality = 5 - (rthis / mag * 3).round();
    } else {
      circleWindQuality = 5 - rthis.round();
    }
    if (circleCount < 3) {
      circleWindQuality--;
    }
    if (circleCount < 2) {
      circleWindQuality--;
    }
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

  void resetCircleSamples() {
    circleCount = 0;
    currentCircleStart = Vector3(0, 0, 0);
    currentCircle = 0;
    circleSamples.clear();
  }

  void addCircleSample(Vector3 gpsSpeed, int timestamp) {
    GPSSample value = GPSSample();
    value.gpsSpeed = gpsSpeed;
    value.timestamp = timestamp;
    if (circleSamples.isNotEmpty &&
        timestamp - circleSamples.last.timestamp > maximumSampleAgeUs) {
      // check if last timestamp is more than 2 seconds ago - probably new circle now
      circleCount = 0;
      currentCircleStart =
          gpsSpeed; //.angleToSigned(Vector3(0, 0, 0), Vector3(0, 0, 1));
      currentCircle = 0;
      circleSamples.clear();
    }
    // if absolute difference between circleStart and last two angles was decreasing and now increasing again, we are at the end of the circle
    if (circleSamples.isNotEmpty && circleSamples.length > 4) {
      if (circleSamples[circleSamples.length - 3]
                  .gpsSpeed
                  .angleTo(currentCircleStart) >
              circleSamples[circleSamples.length - 2]
                  .gpsSpeed
                  .angleTo(currentCircleStart) &&
          circleSamples[circleSamples.length - 2]
                  .gpsSpeed
                  .angleTo(currentCircleStart) >
              circleSamples[circleSamples.length - 1]
                  .gpsSpeed
                  .angleTo(currentCircleStart)) {
        if (circleSamples[circleSamples.length - 1]
                .gpsSpeed
                .angleTo(currentCircleStart) <
            value.gpsSpeed.angleTo(currentCircleStart)) {
          circleCount++;
        }
      }
    }
    gpsSpeed.angleToSigned(Vector3(0, 0, 0), Vector3(0, 0, 1));
    circleSamples.add(value);
  }
}
