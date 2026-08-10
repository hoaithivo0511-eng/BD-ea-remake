//+------------------------------------------------------------------+
//| Logger.mqh — BlackDragon v14.0.0                                 |
//| Purpose   : Leveled, throttled logging. Replaces Alert+Sleep     |
//|             chains (bug #7). No Sleep() anywhere.                |
//| Invariants: Never blocks. Max 1 repeated message per key/minute. |
//| Depends on: (nothing)                                            |
//+------------------------------------------------------------------+
#ifndef BD_LOGGER_MQH
#define BD_LOGGER_MQH

#define BD_LOG_THROTTLE_SEC 60

string   g_logKeys[];
datetime g_logLast[];

void Log_Info(const string module, const string msg)
{
   Print("[BD:", module, "] ", msg);
}

// Throttled: repeated identical keys print at most once per minute (bug #7)
void Log_Warn(const string module, const string key, const string msg)
{
   int n = ArraySize(g_logKeys);
   for(int i = 0; i < n; i++)
      if(g_logKeys[i] == key)
      {
         if(TimeCurrent() - g_logLast[i] < BD_LOG_THROTTLE_SEC) return;
         g_logLast[i] = TimeCurrent();
         Print("[BD:", module, "] WARN ", msg);
         return;
      }
   ArrayResize(g_logKeys, n + 1);
   ArrayResize(g_logLast, n + 1);
   g_logKeys[n] = key;
   g_logLast[n] = TimeCurrent();
   Print("[BD:", module, "] WARN ", msg);
}

void Log_Error(const string module, const string msg)
{
   Print("[BD:", module, "] ERROR ", msg, " (LastError=", GetLastError(), ")");
}
#endif // BD_LOGGER_MQH
