#ifndef BD_POSITION_BOOK_MQH
#define BD_POSITION_BOOK_MQH
#include "Recovery/RecoveryMath.mqh"
#include "OrderCommentCodec.mqh"
// T17.24 observation-only materialized view. It is enabled for the read-only
// Recovery OnTick chain and disabled BEFORE Strategy/executor mutations.
// No mutation boundary is permitted to reuse this observation snapshot.
class CObservationPositionBook
{
private:
   bool m_enabled;
   string m_symbol;
   long m_coreMagic;
   long m_hedgeMagic;
   double m_step;
   long m_coreUnits[2];
   long m_hedgeUnits[2];
   int m_triggerCount[2];
   ulong m_scans;
   ulong m_visits;
   ulong m_hits;
public:
   CObservationPositionBook() : m_enabled(false),m_symbol(""),m_coreMagic(0),
      m_hedgeMagic(0),m_step(0),m_scans(0),m_visits(0),m_hits(0) {}
   void End() { m_enabled=false; }
   bool Begin(const string symbol,const long coreMagic,const long hedgeMagic,const double step)
   {
      m_enabled=false; m_symbol=symbol; m_coreMagic=coreMagic; m_hedgeMagic=hedgeMagic; m_step=step;
      if(step<=0 || coreMagic<=0) return false;
      for(int d=0;d<2;d++) { m_coreUnits[d]=0; m_hedgeUnits[d]=0; m_triggerCount[d]=0; }
      int count=PositionsTotal(); m_scans++;
      for(int i=count-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i); m_visits++;
         if(ticket==0) return false; // leave disabled, callers use live path
         if(PositionGetString(POSITION_SYMBOL)!=symbol) continue;
         long owner=PositionGetInteger(POSITION_MAGIC);
         if(owner!=coreMagic && owner!=hedgeMagic) continue;
         long type=PositionGetInteger(POSITION_TYPE);
         if(type!=POSITION_TYPE_BUY && type!=POSITION_TYPE_SELL) return false;
         double lots=PositionGetDouble(POSITION_VOLUME);
         if(!MathIsValidNumber(lots) || lots<=0) return false;
         long units=Recovery_VolumeToUnitsFloor(lots,step);
         int d=type==POSITION_TYPE_BUY ? 0 : 1;
         if(owner==coreMagic)
         {
            m_coreUnits[d]+=units;
            if(units>0 && PositionGetDouble(POSITION_PRICE_OPEN)>0 &&
               !OC_IsPyramid(PositionGetString(POSITION_COMMENT))) m_triggerCount[d]++;
         }
         else m_hedgeUnits[1-d]+=units; // hedge actual SELL protects Core BUY
      }
      if(PositionsTotal()!=count) return false;
      m_enabled=true; return true;
   }
   bool Matches(const string symbol,const long coreMagic,const long hedgeMagic,const double step) const
   { return m_enabled && symbol==m_symbol && coreMagic==m_coreMagic &&
            hedgeMagic==m_hedgeMagic && MathAbs(step-m_step)<1e-12; }
   long CoreUnits(const int dir) { m_hits++; return m_coreUnits[dir]; }
   long HedgeUnits(const int dir) { m_hits++; return m_hedgeUnits[dir]; }
   int CoreCount(const int dir) { m_hits++; return m_triggerCount[dir]; }
   ulong Scans() const { return m_scans; }
   ulong Visits() const { return m_visits; }
   ulong Hits() const { return m_hits; }
};
CObservationPositionBook g_bdObservationBook;
#endif
