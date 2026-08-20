//+------------------------------------------------------------------+
//| Logger.mqh — BlackDragon v14.0.0 / T16.5                         |
//| Purpose   : Leveled, throttled logging. Replaces Alert+Sleep     |
//|             chains (bug #7). No Sleep() anywhere.                |
//| Invariants: Never blocks. Repeated WARN diagnostics are throttled|
//|             while trade/fill/state-transition INFO remains exact.|
//+------------------------------------------------------------------+
#ifndef BD_LOGGER_MQH
#define BD_LOGGER_MQH

// T16.5: the old 60-second repeated-warning cadence generated very large
// Strategy Tester journals during long Recovery waits. Keep the FIRST event
// immediate, then reduce the default heartbeat to once per five minutes.
#define BD_LOG_THROTTLE_SEC 300

string   g_logKeys[];
datetime g_logLast[];

bool Log_ThrottleAllow(const string key, const int intervalSec)
{
   datetime now = TimeCurrent();
   int n = ArraySize(g_logKeys);
   for(int i = 0; i < n; i++)
   {
      if(g_logKeys[i] != key) continue;
      // interval=0 => first occurrence only for the lifetime of this EA run.
      if(intervalSec <= 0) return false;
      if(now - g_logLast[i] < intervalSec) return false;
      g_logLast[i] = now;
      return true;
   }
   ArrayResize(g_logKeys, n + 1);
   ArrayResize(g_logLast, n + 1);
   g_logKeys[n] = key;
   g_logLast[n] = now;
   return true;
}

void Log_Info(const string module, const string msg)
{
   Print("[BD:", module, "] ", msg);
}

// Keyed INFO is reserved for lifecycle/order evidence and remains immediate.
// Waiting/heartbeat INFO must use Log_InfoEvery() instead.
void Log_Info(const string module, const string key, const string msg)
{
   Print("[BD:", module, "] ", msg, " [", key, "]");
}

void Log_InfoEvery(const string module, const string key,
                   const string msg, const int intervalSec)
{
   if(!Log_ThrottleAllow("I|" + module + "|" + key, intervalSec)) return;
   Print("[BD:", module, "] ", msg, " [", key, "]");
}

// Default WARN: first event immediate, repeated key at most once per 5 min.
void Log_Warn(const string module, const string key, const string msg)
{
   if(!Log_ThrottleAllow("W|" + module + "|" + key, BD_LOG_THROTTLE_SEC)) return;
   Print("[BD:", module, "] WARN ", msg);
}

// Custom heartbeat for long-running, expected waits. interval=0 logs only the
// first event; errors and concrete trade mutations must NOT use this helper.
void Log_WarnEvery(const string module, const string key,
                   const string msg, const int intervalSec)
{
   if(!Log_ThrottleAllow("W|" + module + "|" + key, intervalSec)) return;
   Print("[BD:", module, "] WARN ", msg);
}

void Log_Error(const string module, const string msg)
{
   Print("[BD:", module, "] ERROR ", msg, " (LastError=", GetLastError(), ")");
}
#endif // BD_LOGGER_MQH
