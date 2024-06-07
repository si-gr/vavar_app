import 'package:ble_larus_android/kalman1d.dart';

class Vario {
  Map<int, double> _varioValues = {};
  int _averageTimeUs = 30000;
  Kalman1D kalman1d = Kalman1D(0.01, 0.0004);
  Kalman1D kalman1dAverage = Kalman1D(0.01, 0.00005);

  Vario(averageTimeMs) : _averageTimeUs = averageTimeMs * 1000;

  void setKalmanQ(double q) {
    kalman1d.setGain(q);
  }

  void setKalmanAverageQ(double q) {
    kalman1dAverage.setGain(q);
  }

  void setNewValue(double varioValue) {
    setNewValueAcc(varioValue, 0);
  }

  void setNewValueAcc(double varioValue, double accelerationZ) {
    if(varioValue.isNaN) return;
    if(varioValue.isInfinite) return;
    if(accelerationZ.isNaN) return;
    if(accelerationZ.isInfinite) return;
    if (_varioValues.isEmpty) {
      kalman1d.setLastEstimate(varioValue);
      kalman1dAverage.setLastEstimate(varioValue);
    } else {
      kalman1d.setNewValueAcc(varioValue, accelerationZ + 9.81);
      kalman1dAverage.setNewValueAcc(varioValue, accelerationZ + 9.81);
    }
    _varioValues.removeWhere((key, value) =>
        key < DateTime.now().microsecondsSinceEpoch - _averageTimeUs);
    _varioValues.addAll(
        {DateTime.now().microsecondsSinceEpoch: kalman1d.getLastValue()});
  }

  double getCurrentValue() {
    if (_varioValues.length > 0) {
      return _varioValues[_varioValues.keys.last]!;
    } else {
      return 0;
    }
  }

  double getFilteredVario() {
    return kalman1d.getLastValue();
  }

  double getFilteredAverageVario() {
    return kalman1dAverage.getLastValue();
  }

  void setAveragingTime(int timeMs) {
    _averageTimeUs = timeMs * 1000;
  }

  double getAverageValue() {
    _varioValues.removeWhere((key, value) =>
        key < DateTime.now().microsecondsSinceEpoch - _averageTimeUs);
    if (_varioValues.length > 0) {
      double sum = 0;
      _varioValues.forEach((key, value) {
        sum += value;
      });
      return sum / _varioValues.length;
    } else {
      return 0;
    }
  }
}
