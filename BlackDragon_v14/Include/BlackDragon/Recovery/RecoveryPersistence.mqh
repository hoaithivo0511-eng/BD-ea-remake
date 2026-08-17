//+------------------------------------------------------------------+
//| RecoveryPersistence.mqh — T9 durable Recovery state store        |
//| Invariants: Recovery OFF never mutates this file; payload is     |
//|             versioned, checksummed and staged temp-to-final replaced.      |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_PERSISTENCE_MQH
#define BD_RECOVERY_PERSISTENCE_MQH

#include <BlackDragon/Types.mqh>
#include "RecoveryRegistry.mqh"
#include "RecoveryExit.mqh"

#define BD_RECOVERY_PERSIST_MAGIC   0x39524442
#define BD_RECOVERY_PERSIST_VERSION 1

enum eRecoveryPersistLoadStatus
{
   recovery_PERSIST_OK = 0,
   recovery_PERSIST_NOT_FOUND,
   recovery_PERSIST_CORRUPT,
   recovery_PERSIST_MISMATCH,
   recovery_PERSIST_IO_ERROR
};

struct SRecoveryPersistHeader
{
   uint magic;
   uint version;
   uint payloadSize;
   uint checksum;
};

struct SRecoveryPersistPending
{
   bool             active;
   int              cycleKey;
   eExecCommandType commandType;
   long             ownerMagic;
   ulong            ticket;
   long             targetUnits;
   long             observedUnitsBefore;
   double           targetPrice;
   datetime         startedAt;
   int              generation;
   int              bundleId;
};

struct SRecoveryPersistPayload
{
   long                     accountLogin;
   uint                     symbolHash;
   long                     coreMagic;
   long                     recoveryMagic;
   double                   volumeStep;
   double                   tickSize;
   int                      startAfterDca;
   datetime                 savedAt;
   long                     saveSequence;
   ulong                    lastDealTicket;
   long                     lastDealTimeMsc;

   SRecoveryCycle           buyCycle;
   SRecoveryCycle           sellCycle;
   SRecoveryT5CycleRuntime  buyT5;
   SRecoveryT5CycleRuntime  sellT5;
   int                      buyT5CycleSerial;
   int                      sellT5CycleSerial;
   long                     buyHedgeRealizedBaseline;
   long                     sellHedgeRealizedBaseline;
   double                   buyAnchorWeighted;
   double                   sellAnchorWeighted;
   long                     buyAnchorUnits;
   long                     sellAnchorUnits;
   long                     buyRehedgeAnchorTicks;
   long                     sellRehedgeAnchorTicks;
   double                   buyLockTargetPrice;
   double                   sellLockTargetPrice;
   SRecoveryPersistPending  buyPending;
   SRecoveryPersistPending  sellPending;
};

uint Recovery_Fnv1aBytes(const uchar &bytes[])
{
   uint h = 2166136261;
   for(int i = 0; i < ArraySize(bytes); i++)
   {
      h ^= (uint)bytes[i];
      h *= 16777619;
   }
   return h;
}

uint Recovery_StringHash(const string text)
{
   uint h = 2166136261;
   int n = StringLen(text);
   for(int i = 0; i < n; i++)
   {
      ushort ch = (ushort)StringGetCharacter(text, i);
      h ^= (uint)(ch & 0x00ff); h *= 16777619;
      h ^= (uint)((ch >> 8) & 0x00ff); h *= 16777619;
   }
   return h;
}

string Recovery_SafeFileToken(const string text)
{
   string out = "";
   for(int i = 0; i < StringLen(text); i++)
   {
      ushort ch = (ushort)StringGetCharacter(text, i);
      bool ok = (ch >= '0' && ch <= '9') ||
                (ch >= 'A' && ch <= 'Z') ||
                (ch >= 'a' && ch <= 'z') || ch == '_' || ch == '-' || ch == '.';
      out += ok ? ShortToString(ch) : "_";
   }
   return out == "" ? "symbol" : out;
}

void Recovery_PendingInit(SRecoveryPersistPending &p)
{
   p.active = false;
   p.cycleKey = 0;
   p.commandType = EXEC_CMD_LEGACY;
   p.ownerMagic = 0;
   p.ticket = 0;
   p.targetUnits = 0;
   p.observedUnitsBefore = 0;
   p.targetPrice = 0.0;
   p.startedAt = 0;
   p.generation = 0;
   p.bundleId = 0;
}

bool Recovery_PersistStateValueValid(const eRecoveryState state)
{
   return state >= recovery_CORE_ONLY && state <= recovery_COMPLETED;
}

bool Recovery_PersistCycleBasicValid(const SRecoveryCycle &c,
                                     const eRecoveryCoreDirection dir)
{
   if(c.direction != dir || c.cycleKey != Recovery_CycleKey(dir)) return false;
   if(!Recovery_PersistStateValueValid(c.state) || c.cycleSerial < 1) return false;
   if(c.coreCount < 0 || c.coreLots < 0.0 || c.activeHedgeLots < 0.0) return false;
   if(c.bundleTargetUnits < 0 || c.bundleBaselineActiveUnits < 0 || c.bundleConfirmedUnits < 0) return false;
   if(c.bundleConfirmedUnits > c.bundleTargetUnits && c.bundleTargetUnits > 0) return false;
   if(c.hedgeGeneration < 0 || c.bundleId < 0 || c.bundleSubmittedChildren < 0) return false;
   return true;
}

bool Recovery_PersistPendingBasicValid(const SRecoveryPersistPending &p,
                                       const eRecoveryCoreDirection dir)
{
   if(!p.active) return true;
   if(p.cycleKey != Recovery_CycleKey(dir)) return false;
   if(p.commandType == EXEC_CMD_LEGACY) return false;
   if(p.ownerMagic <= 0 || p.targetUnits < 0 || p.observedUnitsBefore < 0) return false;
   return true;
}

bool Recovery_PersistPayloadIdentityValid(const SRecoveryPersistPayload &p,
                                          const long accountLogin,
                                          const uint symbolHash,
                                          const long coreMagic,
                                          const long recoveryMagic,
                                          const double volumeStep,
                                          const double tickSize,
                                          const int startAfterDca)
{
   if(p.accountLogin != accountLogin || p.symbolHash != symbolHash ||
      p.coreMagic != coreMagic || p.recoveryMagic != recoveryMagic ||
      p.startAfterDca != startAfterDca)
      return false;
   if(MathAbs(p.volumeStep - volumeStep) > 1e-12 || MathAbs(p.tickSize - tickSize) > 1e-12)
      return false;
   if(!Recovery_PersistCycleBasicValid(p.buyCycle, recovery_CORE_BUY) ||
      !Recovery_PersistCycleBasicValid(p.sellCycle, recovery_CORE_SELL))
      return false;
   if(!Recovery_PersistPendingBasicValid(p.buyPending, recovery_CORE_BUY) ||
      !Recovery_PersistPendingBasicValid(p.sellPending, recovery_CORE_SELL))
      return false;
   return true;
}

bool Recovery_PendingVolumeEffectConfirmed(const bool isOpen,
                                           const long beforeUnits,
                                           const long targetUnits,
                                           const long currentUnits)
{
   if(beforeUnits < 0 || targetUnits <= 0 || currentUnits < 0) return false;
   if(isOpen) return currentUnits >= beforeUnits + targetUnits;
   long expected = beforeUnits > targetUnits ? beforeUnits - targetUnits : 0;
   return currentUnits <= expected;
}

class CRecoveryPersistence
{
private:
   string m_file;
   string m_temp;

   bool ReadPayloadBytes(const int handle, const uint payloadSize,
                         uchar &raw[], string &why) const
   {
      ArrayResize(raw, (int)payloadSize);
      if(!FileSeek(handle, (long)sizeof(SRecoveryPersistHeader), SEEK_SET))
      {
         why = "cannot seek to Recovery payload";
         return false;
      }
      uint read = FileReadArray(handle, raw, 0, (int)payloadSize);
      if(read != payloadSize)
      {
         why = "Recovery payload byte count mismatch";
         return false;
      }
      return true;
   }

public:
   void Init(const string symbol, const long accountLogin,
             const long coreMagic, const long recoveryMagic)
   {
      string token = Recovery_SafeFileToken(symbol);
      m_file = "BlackDragon_Recovery_" + token + "_" +
               (string)accountLogin + "_" + (string)coreMagic + "_" +
               (string)recoveryMagic + ".bin";
      m_temp = m_file + ".tmp";
   }

   string FileName() const { return m_file; }

   eRecoveryPersistLoadStatus Load(SRecoveryPersistPayload &payload,
                                   string &why) const
   {
      why = "";
      if(m_file == "") { why = "Recovery persistence not initialized"; return recovery_PERSIST_IO_ERROR; }
      if(!FileIsExist(m_file)) return recovery_PERSIST_NOT_FOUND;

      int h = FileOpen(m_file, FILE_READ|FILE_BIN);
      if(h == INVALID_HANDLE)
      {
         why = "cannot open Recovery state file";
         return recovery_PERSIST_IO_ERROR;
      }

      ulong expectedSize = (ulong)sizeof(SRecoveryPersistHeader) + (ulong)sizeof(SRecoveryPersistPayload);
      if(FileSize(h) != expectedSize)
      {
         FileClose(h);
         why = "Recovery state size mismatch";
         return recovery_PERSIST_CORRUPT;
      }

      SRecoveryPersistHeader header;
      uint hread = FileReadStruct(h, header);
      if(hread != sizeof(SRecoveryPersistHeader) ||
         header.magic != BD_RECOVERY_PERSIST_MAGIC ||
         header.version != BD_RECOVERY_PERSIST_VERSION ||
         header.payloadSize != sizeof(SRecoveryPersistPayload))
      {
         FileClose(h);
         why = "Recovery state header/version mismatch";
         return recovery_PERSIST_CORRUPT;
      }

      uchar raw[];
      if(!ReadPayloadBytes(h, header.payloadSize, raw, why))
      {
         FileClose(h);
         return recovery_PERSIST_CORRUPT;
      }
      uint checksum = Recovery_Fnv1aBytes(raw);
      if(checksum != header.checksum)
      {
         FileClose(h);
         why = "Recovery state checksum mismatch";
         return recovery_PERSIST_CORRUPT;
      }

      if(!FileSeek(h, (long)sizeof(SRecoveryPersistHeader), SEEK_SET))
      {
         FileClose(h);
         why = "cannot seek for Recovery payload decode";
         return recovery_PERSIST_IO_ERROR;
      }
      uint pread = FileReadStruct(h, payload);
      FileClose(h);
      if(pread != sizeof(SRecoveryPersistPayload))
      {
         why = "Recovery payload decode byte count mismatch";
         return recovery_PERSIST_CORRUPT;
      }
      return recovery_PERSIST_OK;
   }

   bool Save(const SRecoveryPersistPayload &payload, string &why) const
   {
      why = "";
      if(m_file == "") { why = "Recovery persistence not initialized"; return false; }
      FileDelete(m_temp);

      SRecoveryPersistHeader header;
      header.magic = BD_RECOVERY_PERSIST_MAGIC;
      header.version = BD_RECOVERY_PERSIST_VERSION;
      header.payloadSize = sizeof(SRecoveryPersistPayload);
      header.checksum = 0;

      int h = FileOpen(m_temp, FILE_WRITE|FILE_BIN);
      if(h == INVALID_HANDLE) { why = "cannot create Recovery temp state"; return false; }
      uint hw = FileWriteStruct(h, header);
      uint pw = FileWriteStruct(h, payload);
      FileFlush(h);
      FileClose(h);
      if(hw != sizeof(SRecoveryPersistHeader) || pw != sizeof(SRecoveryPersistPayload))
      {
         FileDelete(m_temp);
         why = "Recovery state write byte count mismatch";
         return false;
      }

      h = FileOpen(m_temp, FILE_READ|FILE_BIN);
      if(h == INVALID_HANDLE) { FileDelete(m_temp); why = "cannot verify Recovery temp state"; return false; }
      uchar raw[];
      if(!ReadPayloadBytes(h, header.payloadSize, raw, why))
      {
         FileClose(h); FileDelete(m_temp); return false;
      }
      FileClose(h);
      header.checksum = Recovery_Fnv1aBytes(raw);

      h = FileOpen(m_temp, FILE_READ|FILE_WRITE|FILE_BIN);
      if(h == INVALID_HANDLE) { FileDelete(m_temp); why = "cannot reopen Recovery temp header"; return false; }
      if(!FileSeek(h, 0, SEEK_SET))
      {
         FileClose(h); FileDelete(m_temp); why = "cannot seek Recovery temp header"; return false;
      }
      hw = FileWriteStruct(h, header);
      FileFlush(h);
      ulong finalTempSize = FileSize(h);
      FileClose(h);
      ulong expectedSize = (ulong)sizeof(SRecoveryPersistHeader) + (ulong)sizeof(SRecoveryPersistPayload);
      if(hw != sizeof(SRecoveryPersistHeader) || finalTempSize != expectedSize)
      {
         FileDelete(m_temp);
         why = "Recovery temp final size/header mismatch";
         return false;
      }

      if(!FileMove(m_temp, 0, m_file, FILE_REWRITE))
      {
         FileDelete(m_temp);
         why = "Recovery staged replace failed";
         return false;
      }
      return true;
   }
};

#endif // BD_RECOVERY_PERSISTENCE_MQH
