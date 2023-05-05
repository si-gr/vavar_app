import 'dart:math';

class TECalculator{
  double lastTE = 0;
  int lastTETime = 0;
  double varioValue = 0;
  
  double setNewTE(double airspeed, double altitude){
    double currentTE = pow(airspeed,2) / (2 * 9.81) + altitude;
    if (lastTE == 0){
      lastTE = currentTE;
      lastTETime = DateTime.now().millisecondsSinceEpoch;
      return currentTE;
    }
    varioValue = (currentTE - lastTE) / (DateTime.now().millisecondsSinceEpoch - lastTETime) / 1000;
    lastTETime = DateTime.now().millisecondsSinceEpoch;
    return currentTE;
  }

  double getVario(){
    return varioValue;
  }
}