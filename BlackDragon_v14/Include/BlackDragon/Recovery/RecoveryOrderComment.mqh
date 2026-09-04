// T17.21 presentation metadata from filled order comments, never a trade gate.
// digits-tested: unitless identifiers; price digits do not affect this codec.
#ifndef BD_RECOVERY_ORDER_COMMENT_MQH
#define BD_RECOVERY_ORDER_COMMENT_MQH
#include "RecoveryTypes.mqh"
#include <BlackDragon/OrderCommentCodec.mqh>

struct SRecoveryCommentOpening
{
   int round;
   int generation;
   int bundle;
   int child;
};

bool Recovery_CommentHasLiveGeneration(const int cycle, const int generation,
                                        const int bundle)
{
   long wanted = cycle == 1 ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         PositionGetInteger(POSITION_MAGIC)!=(long)RecoveryMagic_ ||
         PositionGetInteger(POSITION_TYPE)!=wanted) continue;
      if(OC_RhMatchesBundle(PositionGetString(POSITION_COMMENT),cycle,generation,bundle))
         return true;
   }
   return false;
}

bool Recovery_CommentOwnedOpening(const ulong deal, const long wanted)
{
   if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol ||
      HistoryDealGetInteger(deal,DEAL_MAGIC)!=(long)RecoveryMagic_ ||
      HistoryDealGetInteger(deal,DEAL_TYPE)!=wanted) return false;
   long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
   return entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT;
}

bool Recovery_CommentLatestOpening(const int cycle, SRecoveryCommentOpening &last)
{
   last.round=-1; last.generation=-1; last.bundle=-1; last.child=-1;
   if(!HistorySelect(0,TimeCurrent())) return false;
   long wanted = cycle == 1 ? DEAL_TYPE_SELL : DEAL_TYPE_BUY;
   for(int i=HistoryDealsTotal()-1; i>=0; i--)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(!Recovery_CommentOwnedOpening(deal,wanted)) continue;
      string c=HistoryDealGetString(deal,DEAL_COMMENT);
      if(!OC_RhMatchesCycle(c,cycle)) continue;
      last.round=OC_RhRound(c);
      last.generation=OC_RhGeneration(c);
      last.bundle=OC_RhBundle(c);
      last.child=OC_PipeField(c,"N");
      return true;
   }
   return false;
}

string Recovery_BuildReadableComment(const int cycle, const int generation,
                                     const int bundle, const int stage,
                                     const int child, const bool afterProtectiveReset)
{
   bool liveGeneration=Recovery_CommentHasLiveGeneration(cycle,generation,bundle);
   SRecoveryCommentOpening last;
   bool known=Recovery_CommentLatestOpening(cycle,last);
   int round=OC_NextRhRound(afterProtectiveReset,liveGeneration,known,
                            last.round,last.generation,generation);
   int nextChild=child;
   if(liveGeneration && known && last.generation==generation &&
      last.bundle==bundle && last.round==round &&
      last.child>=nextChild && last.child<2147483647)
      nextChild=last.child+1;
   // Missing/migrated history displays RHSL?; it never invents a past ordinal
   // and never blocks or changes an already-authorized Recovery order.
   return OC_BuildRh(cycle,generation,bundle,stage,nextChild,round);
}
#endif
