#include <algorithm>
#include <cmath>
#include <iostream>
#include <string>
using string=std::string;
double MathAbs(double x){return std::abs(x);}
double MathCeil(double x){return std::ceil(x);}
double MathFloor(double x){return std::floor(x);}
double MathMax(double a,double b){return std::max(a,b);}
double MathMin(double a,double b){return std::min(a,b);}
#include "../../../Include/BlackDragon/Pyramid/PyramidProtectionPolicy.mqh"
int passed=0,failed=0;
void T1722_Check(const string &name,bool ok){if(ok)++passed;else{++failed;std::cerr<<"FAIL "<<name<<'\n';}}
#include "t1722_protection_cases.mqh"
int main(){T1722_RunCases();std::cout<<"T17.22 PY protection: "<<passed<<" passed, "<<failed<<" failed\n";if(!failed)std::cout<<"ALL GREEN\n";return failed?1:0;}
