import 'dart:math';

class TECalculator{
  double lastTE = 0;
  int lastTETime = 0;
  double varioValue = 0;
  
  double setNewTE(double airspeed, double altitude){
    double currentTE = pow(airspeed,2) / (2 * 9.81) + altitude;
    if (lastTE == 0){
      lastTE = currentTE;
      lastTETime = DateTime.now().microsecondsSinceEpoch;
      return currentTE;
    }
    varioValue = (currentTE - lastTE) * 1000000 / (DateTime.now().microsecondsSinceEpoch - lastTETime).toDouble();
    //print("as $airspeed alt $altitude te $currentTE var $varioValue micro ${(DateTime.now().microsecondsSinceEpoch - lastTETime)}");
    lastTETime = DateTime.now().microsecondsSinceEpoch;
    lastTE = currentTE;
    return currentTE;
  }

  double getVario(){
    return varioValue;
  }
}