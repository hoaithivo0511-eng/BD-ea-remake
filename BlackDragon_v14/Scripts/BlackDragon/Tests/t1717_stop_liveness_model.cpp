#include <iostream>
#include <string>

enum Owner { NONE=0, SIDE=1, ACCOUNT=2 };

Owner owner(bool accountWide,bool sideCycle)
{
    if(accountWide) return ACCOUNT;
    if(sideCycle) return SIDE;
    return NONE;
}

bool expectedSlBypass(bool arcs,Owner coordinator,bool exactProof)
{
    return arcs && coordinator!=ACCOUNT && exactProof;
}

bool verifiedFlatReset(bool guardComplete,int positions,
                       bool execPending,bool recoveryBlocking)
{
    return guardComplete && positions==0 && !execPending && !recoveryBlocking;
}

bool relatch(bool guardComplete,bool resetOk)
{
    return guardComplete && !resetOk;
}

int main()
{
    int pass=0,fail=0;
    auto t=[&](bool ok,const std::string &name){
        if(ok) ++pass; else { ++fail; std::cout<<"FAIL: "<<name<<'\n'; }
    };
    t(owner(false,false)==NONE,"no owner");
    t(owner(false,true)==SIDE,"side owner");
    t(owner(true,false)==ACCOUNT,"account owner");
    t(owner(true,true)==ACCOUNT,"account preempts side");
    t(expectedSlBypass(true,NONE,true),"ordinary exact SL bypass");
    t(expectedSlBypass(true,SIDE,true),"side-cycle exact SL bypass");
    t(!expectedSlBypass(true,ACCOUNT,true),"account cycle no bypass");
    t(!expectedSlBypass(true,SIDE,false),"no proof no bypass");
    t(!expectedSlBypass(false,SIDE,true),"non ARCS no bypass");
    t(verifiedFlatReset(true,0,false,false),"verified flat reset");
    t(!verifiedFlatReset(false,0,false,false),"no guard epoch");
    t(!verifiedFlatReset(true,2,false,false),"positions remain");
    t(!verifiedFlatReset(true,0,true,false),"journal pending");
    t(!verifiedFlatReset(true,0,false,true),"Recovery blocking");
    t(relatch(true,false),"failure relatches");
    t(!relatch(true,true),"success stays complete");
    t(!relatch(false,false),"no invented epoch");
    std::cout<<"T17.17 stop/liveness model: "<<pass
             <<" passed, "<<fail<<" failed\n";
    if(fail==0) std::cout<<"ALL GREEN\n";
    return fail==0?0:1;
}

