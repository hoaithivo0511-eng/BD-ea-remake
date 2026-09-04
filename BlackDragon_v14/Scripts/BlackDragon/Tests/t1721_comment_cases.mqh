// Independent literal expectations shared by C++ and native MQL5.
// digits-tested: unitless identifiers; no price conversion.
#ifndef BD_T1721_COMMENT_CASES_MQH
#define BD_T1721_COMMENT_CASES_MQH
void T1721CodecCases()
{
   T1721Check("RH SELL initial",OC_BuildRh(1,1,1,2,1,0)=="RH-S|G1|P2|N1");
   T1721Check("RH BUY initial",OC_BuildRh(2,3,3,0,2,0)=="RH-B|G3|N2");
   T1721Check("first protective reentry",OC_BuildRh(1,1,1,1,1,1)=="RHSL1-S|G1|P1|N1");
   T1721Check("second protective reentry",OC_BuildRh(2,1,1,1,1,2)=="RHSL2-B|G1|P1|N1");
   T1721Check("distinct legacy bundle",OC_BuildRh(1,2,7,0,1,0)=="RH-S|G2|B7|N1");
   T1721Check("migration unknown visible",OC_BuildRh(1,1,1,0,1,-1)=="RHSL?-S|G1|N1");
   T1721Check("Pyramid BUY",OC_BuildPyramid(0,3)=="PYR-B#3");
   T1721Check("Pyramid SELL",OC_BuildPyramid(1,17)=="PYR-S#17");
   T1721Check("old RH generation",OC_RhGeneration("BDR|C=1|G=3|B=3|P=2|N=1")==3);
   T1721Check("old RH cycle",OC_RhCycle("BDR|C=2|G=1|B=4|N=1")==2);
   T1721Check("old exact pending bundle",OC_RhMatchesBundle("BDR|C=1|G=2|B=7|N=1",1,2,7));
   T1721Check("old similar bundle refused",!OC_RhMatchesBundle("BDR|C=1|G=2|B=70|N=1",1,2,7));
   T1721Check("old similar side refused",!OC_RhMatchesCycle("BDR|C=10|G=2|B=7|N=1",1));
   T1721Check("new pending bundle",OC_RhMatchesBundle("RHSL2-S|G2|B7|N1",1,2,7));
   T1721Check("new wrong side refused",!OC_RhMatchesCycle("RHSL2-S|G2|B7|N1",2));
   T1721Check("new wrong generation refused",!OC_RhMatchesBundle("RHSL2-S|G2|B7|N1",1,3,7));
   T1721Check("new wrong bundle refused",!OC_RhMatchesBundle("RHSL2-S|G2|B7|N1",1,2,8));
   T1721Check("ARCS implicit bundle",OC_RhBundle("RH-B|G6|P3|N2")==6);
   T1721Check("new round explicit",OC_RhRound("RHSL12-B|G1|P1|N1")==12);
   T1721Check("initial round zero",OC_RhRound("RH-B|G1|N1")==0);
   T1721Check("legacy ordinal not invented",OC_RhRound("BDR|C=1|G=1|B=1|N=1")==-1);
   T1721Check("unknown round identity valid",OC_RhMatchesBundle("RHSL?-S|G1|N1",1,1,1));
   T1721Check("malformed label refused",!OC_RhMatchesCycle("RHSL0-S|G1|N1",1));
   T1721Check("malformed generation refused",!OC_RhMatchesCycle("RH-S|G1oops|N1",1));
   T1721Check("negative generation refused",!OC_RhMatchesCycle("RH-S|G-1|N1",1));
   T1721Check("overflow generation refused",!OC_RhMatchesCycle("RH-S|G2147483648|N1",1));
   T1721Check("nonpositive generation refused",!OC_RhMatchesCycle("RH-S|G0|N1",1));
   T1721Check("invalid direction refused",!OC_RhMatchesCycle("RH-X|G1|N1",1));
   T1721Check("Pyramid not RH",!OC_RhMatchesCycle("PYR-S#1",1));
   T1721Check("Core not RH",!OC_RhMatchesCycle("EA Black Dragon|2",1));
   T1721Check("new Pyramid identity",OC_IsPyramid("PYR-B#3")&&OC_PyramidDirection("PYR-B#3")==0&&OC_PyramidLevel("PYR-B#3")==3);
   T1721Check("old Pyramid identity",OC_IsPyramid("BDP|D=1|L=7|R=6")&&OC_PyramidDirection("BDP|D=1|L=7|R=6")==1&&OC_PyramidLevel("BDP|D=1|L=7|R=6")==7);
   T1721Check("Pyramid zero refused",!OC_IsPyramid("PYR-B#0"));
   T1721Check("Pyramid wrong direction refused",!OC_IsPyramid("PYR-X#2"));
   T1721Check("Pyramid bad serial refused",!OC_IsPyramid("PYR-B#2x"));
   T1721Check("Core not Pyramid",!OC_IsPyramid("EA Black Dragon|2"));
   T1721Check("first campaign resets ordinal",OC_NextRhRound(false,false,true,9,1,1)==0);
   T1721Check("reset same G1 increments",OC_NextRhRound(true,false,true,0,1,1)==1);
   T1721Check("reset lower generation increments",OC_NextRhRound(true,false,true,1,6,1)==2);
   T1721Check("next stage retains round",OC_NextRhRound(true,true,true,2,1,1)==2);
   T1721Check("next generation retains round",OC_NextRhRound(true,false,true,2,1,2)==2);
   T1721Check("restart live retains round",OC_NextRhRound(true,true,true,3,1,1)==3);
   T1721Check("old history round unknown",OC_NextRhRound(true,false,true,-1,1,1)==-1);
   T1721Check("missing history round unknown",OC_NextRhRound(true,false,false,0,1,1)==-1);
   T1721Check("ordinal overflow unknown",OC_NextRhRound(true,false,true,2147483647,1,1)==-1);
   string large=OC_BuildRh(1,2147483647,2147483646,32,2147483647,2147483647);
   T1721Check("extreme identity fits broker limit",StringLen(large)<=31&&OC_RhMatchesBundle(large,1,2147483647,2147483646));
   for(int side=1;side<=2;side++)
      for(int round=0;round<=2;round++)
         for(int generation=1;generation<=32;generation+=31)
         {
            string c=OC_BuildRh(side,generation,generation,3,99,round);
            T1721Check("bounded roundtrip",StringLen(c)<=31&&OC_RhMatchesBundle(c,side,generation,generation)&&OC_RhRound(c)==round&&OC_PipeField(c,"P")==3&&OC_PipeField(c,"N")==99);
         }
}
#endif
