//+------------------------------------------------------------------+
//| Logger.mqh — BlackDragon T17.7 C6 Vietnamese journal            |
//| Leveled/throttled logging; no blocking or trade side effects.    |
//+------------------------------------------------------------------+
#ifndef BD_LOGGER_MQH
#define BD_LOGGER_MQH

#include "JournalT177.mqh"

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
   Print("[BD:", module, "] THÔNG TIN | ", Journal_T177NormalizePayloadPure(msg));
}

void Log_Info(const string module, const string key, const string msg)
{
   Print("[BD:", module, "] THÔNG TIN | ", Journal_T177NormalizePayloadPure(msg), " [", key, "]");
}

void Log_InfoEvery(const string module, const string key,
                   const string msg, const int intervalSec)
{
   if(!Log_ThrottleAllow("I|" + module + "|" + key, intervalSec)) return;
   Print("[BD:", module, "] THÔNG TIN | ", Journal_T177NormalizePayloadPure(msg), " [", key, "]");
}

void Log_Warn(const string module, const string key, const string msg)
{
   if(!Log_ThrottleAllow("W|" + module + "|" + key, BD_LOG_THROTTLE_SEC)) return;
   string human=Journal_T177NormalizePayloadPure(msg);
   if(Journal_T177StartsWithPure(human,"CHỜ "))
      Print("[BD:", module, "] ", human);
   else
      Print("[BD:", module, "] CẢNH BÁO | ", human);
}

void Log_WarnEvery(const string module, const string key,
                   const string msg, const int intervalSec)
{
   if(!Log_ThrottleAllow("W|" + module + "|" + key, intervalSec)) return;
   string human=Journal_T177NormalizePayloadPure(msg);
   if(Journal_T177StartsWithPure(human,"CHỜ "))
      Print("[BD:", module, "] ", human);
   else
      Print("[BD:", module, "] CẢNH BÁO | ", human);
}

void Log_Error(const string module, const string msg)
{
   Print("[BD:", module, "] LỖI | ", Journal_T177NormalizePayloadPure(msg),
         " | LastError=", GetLastError());
}
#endif // BD_LOGGER_MQH
