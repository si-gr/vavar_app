class Kalman1D {
  double errorMeasure = 2;
  double errorEstimate = 2;
  double _q = 0.001;
  double _lastEstimate = 0;
  double _currentEstimate = 0;

  Kalman1D(lastEstimate, q)
      : _lastEstimate = lastEstimate,
        _q = q;

  void setGain(double q) {
    _q = q;
  }

  void setLastEstimate(double lastEstimate) {
    _lastEstimate = lastEstimate;
  }

  void setNewValue(value) {
    setNewValueAcc(value, 0);
  }

  void setNewValueAcc(value, acceleration) {
    double kalmanGain = errorEstimate / (errorEstimate + errorMeasure);
    double currentEstimate =
        _lastEstimate + kalmanGain * (acceleration + value - _lastEstimate);
    errorEstimate = (1.0 - kalmanGain) * errorEstimate +
        (_lastEstimate - currentEstimate).abs() * _q;
    _lastEstimate = currentEstimate;
    _currentEstimate = currentEstimate;
  }

  double getLastValue() {
    return _currentEstimate;
  }
}
