#include <iostream>
#include <string>

enum D {
  NO_EFFECT=0,
  WAIT,
  MUTATED,
  PENDING,
  RECONCILE
};

D classify(bool legacyConsumed,bool semanticChanged,bool pending,bool reconcile) {
  if(reconcile) return RECONCILE;
  if(pending) return PENDING;
  if(semanticChanged) return MUTATED;
  if(!legacyConsumed) return NO_EFFECT;
  return WAIT;
}
bool consumes(D d) {
  return d==MUTATED || d==PENDING || d==RECONCILE;
}

int main() {
  int pass=0, fail=0;
  auto check=[&](const std::string& n,bool ok){
    if(ok){++pass; return;}
    ++fail; std::cerr<<"FAIL: "<<n<<"\n";
  };

  check("no-effect yields", !consumes(NO_EFFECT));
  check("wait yields", !consumes(WAIT));
  check("mutation consumes", consumes(MUTATED));
  check("pending consumes", consumes(PENDING));
  check("reconcile consumes", consumes(RECONCILE));
  check("consumed no change -> wait", classify(true,false,false,false)==WAIT);
  check("changed -> mutation", classify(true,true,false,false)==MUTATED);
  check("pending precedence", classify(true,true,true,false)==PENDING);
  check("reconcile precedence", classify(true,true,true,true)==RECONCILE);
  check("changed overrides legacy false", classify(false,true,false,false)==MUTATED);
  check("legacy false no change -> no-effect", classify(false,false,false,false)==NO_EFFECT);

  std::cout<<"T17.7 C1 scheduler model: "<<pass<<" passed, "<<fail<<" failed\n";
  if(fail==0) std::cout<<"ALL GREEN\n";
  return fail==0 ? 0 : 1;
}
