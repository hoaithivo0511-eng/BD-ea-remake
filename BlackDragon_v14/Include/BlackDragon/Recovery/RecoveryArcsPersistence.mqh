//+------------------------------------------------------------------+
//| RecoveryArcsPersistence.mqh — T16.1 Recovery persistence v4      |
//| Durable layer ownership + protective-close wait + SL/ledger.     |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_PERSISTENCE_MQH
#define BD_RECOVERY_ARCS_PERSISTENCE_MQH

#include "RecoveryArcsTypes.mqh"

#define BD_ARCS_PERSIST_MAGIC   0x36435241
#define BD_ARCS_PERSIST_VERSION 4

enum eArcsPersistStatus
{
   ARCS_PERSIST_OK = 0,
   ARCS_PERSIST_NOT_FOUND,
   ARCS_PERSIST_CORRUPT,
   ARCS_PERSIST_MISMATCH,
   ARCS_PERSIST_IO_ERROR
};

struct SArcsPersistHeader
{
   uint magic;
   uint version;
   uint payloadSize;
   uint checksum;
};

struct SArcsPersistIdentity
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

uint Recovery_ArcsFnv1aBytes(const uchar &bytes[])
{
   uint h = 2166136261;
   for(int i = 0; i < ArraySize(bytes); i++)
   {
      h ^= (uint)bytes[i];
      h *= 16777619;
   }
   return h;
}

uint Recovery_ArcsSymbolHash(const string text)
{
   return Recovery_Fnv1aTextPure(text);
}

class CRecoveryArcsPersistence
{
private:
   string m_file;
   string m_temp;

   uint PayloadSize() const
   {
      return (uint)(sizeof(SArcsPersistIdentity) +
                    2 * sizeof(SArcsDirection) +
                    2 * sizeof(SArcsExternalPending) +
                    2 * BD_ARCS_MAX_LAYERS * sizeof(SArcsLayer));
   }

   bool ReadPayloadRaw(const int handle, uchar &raw[], string &why) const
   {
      uint size = PayloadSize();
      ArrayResize(raw, (int)size);
      if(!FileSeek(handle, (long)sizeof(SArcsPersistHeader), SEEK_SET))
      {
         why = "không thể seek tới payload ARCS";
         return false;
      }
      uint n = FileReadArray(handle, raw, 0, (int)size);
      if(n != size)
      {
         why = "số byte payload ARCS không khớp";
         return false;
      }
      return true;
   }

public:
   void Init(const string symbol,
             const long accountLogin,
             const long coreMagic,
             const long recoveryMagic)
   {
      string token = Recovery_SafeFileToken(symbol);
      m_file = "BlackDragon_Recovery_ARCSv4_" + token + "_" +
               (string)accountLogin + "_" + (string)coreMagic + "_" +
               (string)recoveryMagic + ".bin";
      m_temp = m_file + ".tmp";
   }

   string FileName() const { return m_file; }

   eArcsPersistStatus Load(SArcsPersistIdentity &identity,
                           SArcsDirection &buyDir,
                           SArcsDirection &sellDir,
                           SArcsExternalPending &buyPending,
                           SArcsExternalPending &sellPending,
                           SArcsLayer &buyLayers[],
                           SArcsLayer &sellLayers[],
                           string &why) const
   {
      why = "";
      if(!Recovery_ShouldReusePersistedStatePure((bool)MQLInfoInteger(MQL_TESTER),
                                                 RecoveryTesterResumeState_))
      {
         why = "Strategy Tester isolation: bỏ qua state ARCS từ pass trước";
         return ARCS_PERSIST_NOT_FOUND;
      }
      if(m_file == "")
      {
         why = "ARCS persistence chưa khởi tạo";
         return ARCS_PERSIST_IO_ERROR;
      }
      if(!FileIsExist(m_file)) return ARCS_PERSIST_NOT_FOUND;

      int h = FileOpen(m_file, FILE_READ|FILE_BIN);
      if(h == INVALID_HANDLE)
      {
         why = "không thể mở file state ARCS";
         return ARCS_PERSIST_IO_ERROR;
      }

      ulong expected = (ulong)sizeof(SArcsPersistHeader) + (ulong)PayloadSize();
      if(FileSize(h) != expected)
      {
         FileClose(h);
         why = "kích thước file state ARCS không khớp schema v4";
         return ARCS_PERSIST_CORRUPT;
      }

      SArcsPersistHeader header;
      uint hr = FileReadStruct(h, header);
      if(hr != sizeof(SArcsPersistHeader) ||
         header.magic != BD_ARCS_PERSIST_MAGIC ||
         header.version != BD_ARCS_PERSIST_VERSION ||
         header.payloadSize != PayloadSize())
      {
         FileClose(h);
         why = "header/version ARCS v4 không hợp lệ";
         return ARCS_PERSIST_CORRUPT;
      }

      uchar raw[];
      if(!ReadPayloadRaw(h, raw, why))
      {
         FileClose(h);
         return ARCS_PERSIST_CORRUPT;
      }
      if(Recovery_ArcsFnv1aBytes(raw) != header.checksum)
      {
         FileClose(h);
         why = "checksum ARCS không khớp";
         return ARCS_PERSIST_CORRUPT;
      }

      if(!FileSeek(h, (long)sizeof(SArcsPersistHeader), SEEK_SET))
      {
         FileClose(h);
         why = "không thể seek để decode ARCS";
         return ARCS_PERSIST_IO_ERROR;
      }

      if(FileReadStruct(h, identity) != sizeof(SArcsPersistIdentity) ||
         FileReadStruct(h, buyDir) != sizeof(SArcsDirection) ||
         FileReadStruct(h, sellDir) != sizeof(SArcsDirection) ||
         FileReadStruct(h, buyPending) != sizeof(SArcsExternalPending) ||
         FileReadStruct(h, sellPending) != sizeof(SArcsExternalPending))
      {
         FileClose(h);
         why = "decode metadata ARCS thất bại";
         return ARCS_PERSIST_CORRUPT;
      }

      ArrayResize(buyLayers, BD_ARCS_MAX_LAYERS);
      ArrayResize(sellLayers, BD_ARCS_MAX_LAYERS);
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         if(FileReadStruct(h, buyLayers[i]) != sizeof(SArcsLayer))
         {
            FileClose(h);
            why = "decode BUY layer ARCS thất bại";
            return ARCS_PERSIST_CORRUPT;
         }
      }
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         if(FileReadStruct(h, sellLayers[i]) != sizeof(SArcsLayer))
         {
            FileClose(h);
            why = "decode SELL layer ARCS thất bại";
            return ARCS_PERSIST_CORRUPT;
         }
      }
      FileClose(h);

      if(identity.accountLogin != AccountInfoInteger(ACCOUNT_LOGIN) ||
         identity.symbolHash != Recovery_ArcsSymbolHash(_Symbol) ||
         identity.coreMagic != (long)Magic ||
         identity.recoveryMagic != (long)RecoveryMagic_ ||
         identity.semanticHash != Recovery_T16SemanticFingerprint())
      {
         why = "identity/config ARCS v4 không khớp runtime hiện tại";
         return ARCS_PERSIST_MISMATCH;
      }
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(MathAbs(identity.volumeStep - step) > 1e-12 ||
         MathAbs(identity.tickSize - tick) > 1e-12)
      {
         why = "volume-step/tick-size ARCS không khớp broker hiện tại";
         return ARCS_PERSIST_MISMATCH;
      }
      return ARCS_PERSIST_OK;
   }

   bool Save(const long nextSequence,
             const SArcsDirection &buyDir,
             const SArcsDirection &sellDir,
             const SArcsExternalPending &buyPending,
             const SArcsExternalPending &sellPending,
             SArcsLayer &buyLayers[],
             SArcsLayer &sellLayers[],
             string &why) const
   {
      why = "";
      if(m_file == "") { why = "ARCS persistence chưa khởi tạo"; return false; }
      if(ArraySize(buyLayers) < BD_ARCS_MAX_LAYERS ||
         ArraySize(sellLayers) < BD_ARCS_MAX_LAYERS)
      {
         why = "layer registry ARCS chưa đủ kích thước";
         return false;
      }

      FileDelete(m_temp);
      SArcsPersistHeader header;
      header.magic = BD_ARCS_PERSIST_MAGIC;
      header.version = BD_ARCS_PERSIST_VERSION;
      header.payloadSize = PayloadSize();
      header.checksum = 0;

      SArcsPersistIdentity identity;
      ZeroMemory(identity);
      identity.accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
      identity.symbolHash = Recovery_ArcsSymbolHash(_Symbol);
      identity.coreMagic = (long)Magic;
      identity.recoveryMagic = (long)RecoveryMagic_;
      identity.semanticHash = Recovery_T16SemanticFingerprint();
      identity.volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      identity.tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      identity.savedAt = TimeCurrent();
      identity.saveSequence = nextSequence;

      int h = FileOpen(m_temp, FILE_WRITE|FILE_BIN);
      if(h == INVALID_HANDLE) { why = "không thể tạo temp state ARCS"; return false; }
      bool ok = FileWriteStruct(h, header) == sizeof(SArcsPersistHeader) &&
                FileWriteStruct(h, identity) == sizeof(SArcsPersistIdentity) &&
                FileWriteStruct(h, buyDir) == sizeof(SArcsDirection) &&
                FileWriteStruct(h, sellDir) == sizeof(SArcsDirection) &&
                FileWriteStruct(h, buyPending) == sizeof(SArcsExternalPending) &&
                FileWriteStruct(h, sellPending) == sizeof(SArcsExternalPending);
      for(int i = 0; ok && i < BD_ARCS_MAX_LAYERS; i++)
         ok = FileWriteStruct(h, buyLayers[i]) == sizeof(SArcsLayer);
      for(int i = 0; ok && i < BD_ARCS_MAX_LAYERS; i++)
         ok = FileWriteStruct(h, sellLayers[i]) == sizeof(SArcsLayer);
      FileFlush(h);
      FileClose(h);
      if(!ok)
      {
         FileDelete(m_temp);
         why = "ghi payload ARCS không đủ byte";
         return false;
      }

      h = FileOpen(m_temp, FILE_READ|FILE_BIN);
      if(h == INVALID_HANDLE) { FileDelete(m_temp); why = "không thể verify temp ARCS"; return false; }
      uchar raw[];
      if(!ReadPayloadRaw(h, raw, why))
      {
         FileClose(h); FileDelete(m_temp); return false;
      }
      FileClose(h);
      header.checksum = Recovery_ArcsFnv1aBytes(raw);

      h = FileOpen(m_temp, FILE_READ|FILE_WRITE|FILE_BIN);
      if(h == INVALID_HANDLE) { FileDelete(m_temp); why = "không thể reopen header ARCS"; return false; }
      if(!FileSeek(h, 0, SEEK_SET) ||
         FileWriteStruct(h, header) != sizeof(SArcsPersistHeader))
      {
         FileClose(h); FileDelete(m_temp); why = "không thể finalize header ARCS"; return false;
      }
      FileFlush(h);
      ulong finalSize = FileSize(h);
      FileClose(h);
      ulong expected = (ulong)sizeof(SArcsPersistHeader) + (ulong)PayloadSize();
      if(finalSize != expected)
      {
         FileDelete(m_temp);
         why = "kích thước temp ARCS sau finalize không khớp";
         return false;
      }

      if(!FileMove(m_temp, 0, m_file, FILE_REWRITE))
      {
         FileDelete(m_temp);
         why = "atomic replace state ARCS thất bại";
         return false;
      }
      return true;
   }
};

#endif // BD_RECOVERY_ARCS_PERSISTENCE_MQH
