//+------------------------------------------------------------------+
//| RecoveryT1719ReentryPersistence.mqh — separate atomic schema v1 |
//| ARCS v4 bytes remain unchanged.                                  |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T1719_REENTRY_PERSISTENCE_MQH
#define BD_RECOVERY_T1719_REENTRY_PERSISTENCE_MQH

#include "RecoveryArcsPersistence.mqh"
#include "RecoveryT1719ReentryPolicy.mqh"

#define BD_T1719_REENTRY_PERSIST_MAGIC   0x39524552
#define BD_T1719_REENTRY_PERSIST_VERSION 1

enum eRecoveryReentryPersistStatusT1719
{
   RECOVERY_REENTRY_PERSIST_OK = 0,
   RECOVERY_REENTRY_PERSIST_NOT_FOUND,
   RECOVERY_REENTRY_PERSIST_CORRUPT,
   RECOVERY_REENTRY_PERSIST_MISMATCH,
   RECOVERY_REENTRY_PERSIST_IO_ERROR
};

struct SRecoveryReentryHeaderT1719
{
   uint magic;
   uint version;
   uint payloadSize;
   uint checksum;
};

struct SRecoveryReentryIdentityT1719
{
   long     accountLogin;
   uint     symbolHash;
   long     coreMagic;
   long     recoveryMagic;
   uint     semanticHash;
   double   volumeStep;
   double   tickSize;
   datetime savedAt;
   long     saveSequence;
};

uint Recovery_T1719SemanticFingerprint()
{
   string canonical = "base=" + (string)Recovery_T16SemanticFingerprint() +
                      "|t1719ReentryRev=1|maxCycles=" +
                      (string)MaxRecoveryReentryCycles_;
   if(MaxRecoveryReentryCycles_ > 0)
      canonical += "|resetBuffer=" +
                   DoubleToString(RecoveryReentryBufferPips_, 12);
   return Recovery_Fnv1aTextPure(canonical);
}

class CRecoveryT1719ReentryPersistence
{
private:
   string m_file;
   string m_temp;

   uint PayloadSize() const
   {
      return (uint)(sizeof(SRecoveryReentryIdentityT1719) +
                    2 * sizeof(SRecoveryReentryStateT1719));
   }

   bool ReadPayloadRaw(const int handle, uchar &raw[], string &why) const
   {
      uint size = PayloadSize();
      ArrayResize(raw, (int)size);
      if(!FileSeek(handle, (long)sizeof(SRecoveryReentryHeaderT1719), SEEK_SET))
      {
         why = "không seek được payload T17.19 re-entry";
         return false;
      }
      uint read = FileReadArray(handle, raw, 0, (int)size);
      if(read != size)
      {
         why = "payload T17.19 re-entry thiếu byte";
         return false;
      }
      return true;
   }

   bool HeaderValid(const SRecoveryReentryHeaderT1719 &header) const
   {
      return header.magic == BD_T1719_REENTRY_PERSIST_MAGIC &&
             header.version == BD_T1719_REENTRY_PERSIST_VERSION &&
             header.payloadSize == PayloadSize();
   }

   eRecoveryReentryPersistStatusT1719 DecodeFile(
      const int handle,
      SRecoveryReentryIdentityT1719 &identity,
      SRecoveryReentryStateT1719 &buy,
      SRecoveryReentryStateT1719 &sell,
      string &why) const
   {
      ulong expected = (ulong)sizeof(SRecoveryReentryHeaderT1719) +
                       (ulong)PayloadSize();
      if(FileSize(handle) != expected)
      {
         why = "kích thước T17.19 re-entry state không đúng schema v1";
         return RECOVERY_REENTRY_PERSIST_CORRUPT;
      }
      SRecoveryReentryHeaderT1719 header;
      if(FileReadStruct(handle, header) != sizeof(SRecoveryReentryHeaderT1719) ||
         !HeaderValid(header))
      {
         why = "header T17.19 re-entry state không hợp lệ";
         return RECOVERY_REENTRY_PERSIST_CORRUPT;
      }
      uchar raw[];
      if(!ReadPayloadRaw(handle, raw, why))
         return RECOVERY_REENTRY_PERSIST_CORRUPT;
      if(Recovery_ArcsFnv1aBytes(raw) != header.checksum)
      {
         why = "checksum T17.19 re-entry state không khớp";
         return RECOVERY_REENTRY_PERSIST_CORRUPT;
      }
      if(!FileSeek(handle, (long)sizeof(SRecoveryReentryHeaderT1719), SEEK_SET) ||
         FileReadStruct(handle, identity) != sizeof(SRecoveryReentryIdentityT1719) ||
         FileReadStruct(handle, buy) != sizeof(SRecoveryReentryStateT1719) ||
         FileReadStruct(handle, sell) != sizeof(SRecoveryReentryStateT1719))
      {
         why = "decode T17.19 re-entry state thất bại";
         return RECOVERY_REENTRY_PERSIST_CORRUPT;
      }
      return RECOVERY_REENTRY_PERSIST_OK;
   }

   eRecoveryReentryPersistStatusT1719 ValidateIdentity(
      const SRecoveryReentryIdentityT1719 &identity,
      const SRecoveryReentryStateT1719 &buy,
      const SRecoveryReentryStateT1719 &sell,
      string &why) const
   {
      if(identity.accountLogin != AccountInfoInteger(ACCOUNT_LOGIN) ||
         identity.symbolHash != Recovery_ArcsSymbolHash(_Symbol) ||
         identity.coreMagic != (long)Magic ||
         identity.recoveryMagic != (long)RecoveryMagic_ ||
         identity.semanticHash != Recovery_T1719SemanticFingerprint())
      {
         why = "identity/config T17.19 re-entry không khớp";
         return RECOVERY_REENTRY_PERSIST_MISMATCH;
      }
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(MathAbs(identity.volumeStep - step) > 1e-12 ||
         MathAbs(identity.tickSize - tick) > 1e-12 ||
         !Recovery_T1719PhaseValidPure((int)buy.phase) ||
         !Recovery_T1719PhaseValidPure((int)sell.phase))
      {
         why = "broker metadata/phase T17.19 re-entry không khớp";
         return RECOVERY_REENTRY_PERSIST_MISMATCH;
      }
      return RECOVERY_REENTRY_PERSIST_OK;
   }

public:
   void Init(const string symbol,
             const long accountLogin,
             const long coreMagic,
             const long recoveryMagic)
   {
      string token = Recovery_SafeFileToken(symbol);
      m_file = "BlackDragon_Recovery_ReentryV1_" + token + "_" +
               (string)accountLogin + "_" + (string)coreMagic + "_" +
               (string)recoveryMagic + ".bin";
      m_temp = m_file + ".tmp";
   }

   eRecoveryReentryPersistStatusT1719 Load(
      SRecoveryReentryIdentityT1719 &identity,
      SRecoveryReentryStateT1719 &buy,
      SRecoveryReentryStateT1719 &sell,
      string &why) const
   {
      why = "";
      if(!Recovery_ShouldReusePersistedStatePure((bool)MQLInfoInteger(MQL_TESTER),
                                                 RecoveryTesterResumeState_))
      {
         why = "Strategy Tester isolation: bỏ qua T17.19 re-entry state từ pass trước";
         return RECOVERY_REENTRY_PERSIST_NOT_FOUND;
      }
      if(m_file == "")
      {
         why = "T17.19 re-entry persistence chưa init";
         return RECOVERY_REENTRY_PERSIST_IO_ERROR;
      }
      if(!FileIsExist(m_file)) return RECOVERY_REENTRY_PERSIST_NOT_FOUND;
      int h = FileOpen(m_file, FILE_READ|FILE_BIN);
      if(h == INVALID_HANDLE)
      {
         why = "không mở được T17.19 re-entry state";
         return RECOVERY_REENTRY_PERSIST_IO_ERROR;
      }
      eRecoveryReentryPersistStatusT1719 status =
         DecodeFile(h, identity, buy, sell, why);
      FileClose(h);
      if(status != RECOVERY_REENTRY_PERSIST_OK) return status;
      return ValidateIdentity(identity, buy, sell, why);
   }

   bool Save(const long nextSequence,
             const SRecoveryReentryStateT1719 &buy,
             const SRecoveryReentryStateT1719 &sell,
             string &why) const
   {
      why = "";
      if(m_file == "")
      {
         why = "T17.19 re-entry persistence chưa init";
         return false;
      }
      FileDelete(m_temp);
      SRecoveryReentryHeaderT1719 header;
      header.magic = BD_T1719_REENTRY_PERSIST_MAGIC;
      header.version = BD_T1719_REENTRY_PERSIST_VERSION;
      header.payloadSize = PayloadSize();
      header.checksum = 0;

      SRecoveryReentryIdentityT1719 identity;
      ZeroMemory(identity);
      identity.accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
      identity.symbolHash = Recovery_ArcsSymbolHash(_Symbol);
      identity.coreMagic = (long)Magic;
      identity.recoveryMagic = (long)RecoveryMagic_;
      identity.semanticHash = Recovery_T1719SemanticFingerprint();
      identity.volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      identity.tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      identity.savedAt = TimeCurrent();
      identity.saveSequence = nextSequence;

      int h = FileOpen(m_temp, FILE_WRITE|FILE_BIN);
      if(h == INVALID_HANDLE)
      {
         why = "không tạo được temp T17.19 re-entry state";
         return false;
      }
      bool ok = FileWriteStruct(h, header) == sizeof(SRecoveryReentryHeaderT1719) &&
                FileWriteStruct(h, identity) == sizeof(SRecoveryReentryIdentityT1719) &&
                FileWriteStruct(h, buy) == sizeof(SRecoveryReentryStateT1719) &&
                FileWriteStruct(h, sell) == sizeof(SRecoveryReentryStateT1719);
      FileFlush(h);
      FileClose(h);
      if(!ok)
      {
         FileDelete(m_temp);
         why = "ghi T17.19 re-entry state thiếu byte";
         return false;
      }

      h = FileOpen(m_temp, FILE_READ|FILE_BIN);
      if(h == INVALID_HANDLE)
      {
         FileDelete(m_temp);
         why = "không verify được temp T17.19 re-entry state";
         return false;
      }
      uchar raw[];
      if(!ReadPayloadRaw(h, raw, why))
      {
         FileClose(h);
         FileDelete(m_temp);
         return false;
      }
      FileClose(h);
      header.checksum = Recovery_ArcsFnv1aBytes(raw);

      h = FileOpen(m_temp, FILE_READ|FILE_WRITE|FILE_BIN);
      if(h == INVALID_HANDLE)
      {
         FileDelete(m_temp);
         why = "không reopen được temp T17.19 re-entry state";
         return false;
      }
      if(!FileSeek(h, 0, SEEK_SET) ||
         FileWriteStruct(h, header) != sizeof(SRecoveryReentryHeaderT1719))
      {
         FileClose(h);
         FileDelete(m_temp);
         why = "không finalize được header T17.19 re-entry";
         return false;
      }
      FileFlush(h);
      ulong finalSize = FileSize(h);
      FileClose(h);
      ulong expected = (ulong)sizeof(SRecoveryReentryHeaderT1719) +
                       (ulong)PayloadSize();
      if(finalSize != expected)
      {
         FileDelete(m_temp);
         why = "temp T17.19 re-entry sai kích thước sau finalize";
         return false;
      }
      if(!FileMove(m_temp, 0, m_file, FILE_REWRITE))
      {
         FileDelete(m_temp);
         why = "atomic replace T17.19 re-entry state thất bại";
         return false;
      }
      return true;
   }
};

#endif // BD_RECOVERY_T1719_REENTRY_PERSISTENCE_MQH
