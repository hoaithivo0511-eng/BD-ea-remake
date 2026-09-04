// T17.20: optional one Recovery opening order per chart bar and direction.
#ifndef BD_RECOVERY_OPEN_BAR_POLICY_MQH
#define BD_RECOVERY_OPEN_BAR_POLICY_MQH

bool Recovery_OpenBarAllowsPure(const bool enabled,
                                const bool barReady,
                                const bool historyReady,
                                const bool openedThisBar)
{
   if(!enabled) return true;
   return barReady && historyReady && !openedThisBar;
}

bool Recovery_OpenBarEntryMatchesPure(const bool symbolMatches,
                                      const bool ownerMatches,
                                      const bool directionMatches,
                                      const bool openingEntry,
                                      const long openTimeMsc,
                                      const long barTimeMsc)
{
   return symbolMatches && ownerMatches && directionMatches && openingEntry &&
          barTimeMsc > 0 && openTimeMsc >= barTimeMsc;
}

#endif
