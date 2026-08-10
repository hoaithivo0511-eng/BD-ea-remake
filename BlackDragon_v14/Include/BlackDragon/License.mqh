//+------------------------------------------------------------------+
//| License.mqh — BlackDragon v14.0.0                                |
//| Purpose   : Account-binding check, semantics preserved from v13  |
//|             LIC(): NumAcc==0 and sNumeAcc=="" -> unrestricted.   |
//| Invariants: Same defaults as the source provided (unrestricted). |
//| Depends on: Logger.mqh                                           |
//| KHONG DUOC DOI: binding semantics.                               |
//+------------------------------------------------------------------+
#ifndef BD_LICENSE_MQH
#define BD_LICENSE_MQH
#include "Logger.mqh"

long   License_NumAcc   = 0;   // v13: NumAcc  = 0  (no binding)
string License_sNumeAcc = "";  // v13: sNumeAcc = "" (no binding)

bool License_Check()
{
   if(License_NumAcc == 0 && StringLen(License_sNumeAcc) == 0) return true;
   long acc = AccountInfoInteger(ACCOUNT_LOGIN);
   if(License_NumAcc != 0 && acc == License_NumAcc) return true;
   if(StringLen(License_sNumeAcc) > 0)
   {
      // v13 format: digits separated by arbitrary spaces, e.g. "1 23 4 5"
      string s = License_sNumeAcc;
      StringReplace(s, " ", "");
      if((long)StringToInteger(s) == acc) return true;
   }
   Log_Warn("LIC", "lic", "Account " + (string)AccountInfoInteger(ACCOUNT_LOGIN) + " is not licensed for this EA");
   return false;
}
#endif // BD_LICENSE_MQH
