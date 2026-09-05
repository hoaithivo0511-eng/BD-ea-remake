//+------------------------------------------------------------------+
//| Filters/AdxFilter.mqh — BlackDragon v14.0.0                      |
//| Purpose   : SAMPLE P5 extension (default OFF). Blocks a new      |
//|             series when ADX < MinAdx (require enough trend       |
//|             strength before starting a basket).                  |
//| Proof     : adding a feature = 1 new file + 1 registration line. |
//| Depends on: Types.mqh                                            |
//+------------------------------------------------------------------+
#ifndef BD_ADXFILTER_MQH
#define BD_ADXFILTER_MQH
#include "../Types.mqh"

class CAdxFilter : public IEntryFilter
{
private:
   int m_handle;
public:
   CAdxFilter() : m_handle(INVALID_HANDLE) {}
   ~CAdxFilter() { if(m_handle != INVALID_HANDLE) IndicatorRelease(m_handle); }
   bool Init()
   {
      m_handle = iADX(_Symbol, PERIOD_CURRENT, AdxPeriod);
      return m_handle != INVALID_HANDLE;
   }
   bool Allow(const EAContext &ctx, const int dir)
   {
      double adx[1];
      // T17.23 F07: enabling ADX means new risk requires valid indicator
      // evidence. Temporary history/indicator unavailability waits instead of
      // silently bypassing the user's filter.
      if(m_handle==INVALID_HANDLE || CopyBuffer(m_handle, 0, 1, 1, adx) != 1)
         return false;
      return adx[0] >= MinAdx;
   }
};
#endif // BD_ADXFILTER_MQH
