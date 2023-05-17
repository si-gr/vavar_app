import 'dart:math';

class TESpeedCalculator {
  double lastKinE = 0;
  int lastKinETime = 0;
  double varioValue = 0;

  double setNewTE(double airspeed, double heightChange) {
    double kinE = pow(airspeed, 2) / (2 * 9.81);
    if (lastKinE == 0) {
      lastKinE = kinE;
      lastKinETime = DateTime.now().microsecondsSinceEpoch;
      return kinE;
    }
    varioValue = (kinE - lastKinE) *
        1000000 /
        (DateTime.now().microsecondsSinceEpoch - lastKinETime).toDouble();
    varioValue += heightChange;
    lastKinETime = DateTime.now().microsecondsSinceEpoch;
    lastKinE = kinE;
    return varioValue;
  }

  double getVario() {
    return varioValue;
  }
}
