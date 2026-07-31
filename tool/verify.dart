import '../lib/engine/hitori_engine.dart';
import '../lib/engine/generator.dart';
void main(){
  var n=0,worst=0,fails=0;
  final sw=Stopwatch()..start();
  for(final d in Difficulty.all){
    for(var seed=1;seed<=60;seed++){
      final t=Stopwatch()..start();
      Puzzle p;
      try{ p=Generator(seed*104729).generate(d); }catch(e){ fails++; continue; }
      t.stop(); if(t.elapsedMilliseconds>worst)worst=t.elapsedMilliseconds;
      n++;
      final blank=List<int>.filled(p.cellCount,kUnknown);
      final s=Solver(p.numbers,p.size);
      if(s.countSolutions(blank,limit:2)!=1) throw StateError('NOT UNIQUE');
      final l=s.solveByLogic(blank);
      if(l==null||l.contains(kUnknown)) throw StateError('NEEDS GUESSING');
      for(var i=0;i<p.cellCount;i++){ if(l[i]!=p.solution[i]) throw StateError('LOGIC != SOLUTION'); }
      if(checkComplete(p.numbers,p.solution,p.size)!=Violation.none) throw StateError('INVALID');
    }
  }
  sw.stop();
  print('n=$n genFails=$fails unique=OK noGuess=OK matchesSolution=OK worst=${worst}ms total=${sw.elapsedMilliseconds}ms');
}
