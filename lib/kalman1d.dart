class Kalman1D {
  double errorMeasure = 0.5;
  double errorEstimate = 0.5;
  double _q = 0.001;
  double _lastEstimate;
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
    double kalmanGain = errorEstimate / (errorEstimate + errorMeasure);
    double currentEstimate =
        _lastEstimate + kalmanGain * (value - _lastEstimate);
    errorEstimate = (1.0 - kalmanGain) * errorEstimate +
        (_lastEstimate - currentEstimate).abs() * _q;
    _lastEstimate = currentEstimate;
    _currentEstimate = currentEstimate;
  }

  double getLastValue(){
    return _currentEstimate;
  }
}
