//+------------------------------------------------------------------+
//| RecoveryArcsPersistence.mqh — T17.7 C5 safe fingerprint migrate |
//| Old v4 payload is accepted only at a non-active semantic boundary.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_PERSISTENCE_T177_C5_WRAPPER_MQH
#define BD_RECOVERY_ARCS_PERSISTENCE_T177_C5_WRAPPER_MQH

#define CRecoveryArcsPersistence CRecoveryArcsPersistenceT177C4Base
#include "RecoveryArcsPersistenceT177C4Base.mqh"
#undef CRecoveryArcsPersistence

bool Recovery_T177LegacyPersistPhaseSafePure(const eArcsPhase phase)
{
   return phase == ARCS_IDLE || phase == ARCS_ARMED ||
          phase == ARCS_REVERSAL_HOLD;
}

bool Recovery_T177LegacyPersistLayerSafePure(const eArcsLayerState state)
{
   return state == ARCS_LAYER_EMPTY || state == ARCS_LAYER_CLOSED;
}

class CRecoveryArcsPersistence : public CRecoveryArcsPersistenceT177C4Base
{
private:
   bool LegacyPayloadBoundarySafe(const SArcsDirection &buyDir,
                                  const SArcsDirection &sellDir,
                                  const SArcsExternalPending &buyPending,
                                  const SArcsExternalPending &sellPending,
                                  const SArcsLayer &buyLayers[],
                                  const SArcsLayer &sellLayers[]) const
   {
      if(buyPending.active || sellPending.active) return false;
      if(!Recovery_T177LegacyPersistPhaseSafePure(buyDir.phase) ||
         !Recovery_T177LegacyPersistPhaseSafePure(sellDir.phase))
         return false;
      if(ArraySize(buyLayers) < BD_ARCS_MAX_LAYERS ||
         ArraySize(sellLayers) < BD_ARCS_MAX_LAYERS)
         return false;
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         if(!Recovery_T177LegacyPersistLayerSafePure(buyLayers[i].state) ||
            !Recovery_T177LegacyPersistLayerSafePure(sellLayers[i].state))
            return false;
      }
      return true;
   }

public:
   eArcsPersistStatus Load(SArcsPersistIdentity &identity,
                           SArcsDirection &buyDir,
                           SArcsDirection &sellDir,
                           SArcsExternalPending &buyPending,
                           SArcsExternalPending &sellPending,
                           SArcsLayer &buyLayers[],
                           SArcsLayer &sellLayers[],
                           string &why) const
   {
      eArcsPersistStatus st = CRecoveryArcsPersistenceT177C4Base::Load(
         identity, buyDir, sellDir, buyPending, sellPending,
         buyLayers, sellLayers, why);
      if(st != ARCS_PERSIST_MISMATCH) return st;
      if(!Recovery_T177CanAcceptLegacyPersistenceC5()) return st;
      if(identity.accountLogin != AccountInfoInteger(ACCOUNT_LOGIN) ||
         identity.symbolHash != Recovery_ArcsSymbolHash(_Symbol) ||
         identity.coreMagic != (long)Magic ||
         identity.recoveryMagic != (long)RecoveryMagic_ ||
         identity.semanticHash != Recovery_T177LegacySemanticFingerprintC5())
         return st;
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(MathAbs(identity.volumeStep - step) > 1e-12 ||
         MathAbs(identity.tickSize - tick) > 1e-12)
         return st;
      if(!LegacyPayloadBoundarySafe(buyDir, sellDir, buyPending, sellPending,
                                    buyLayers, sellLayers))
      {
         why = "State ARCS cũ đang BUILDING/ACTIVE/PENDING; cần đưa Recovery về biên sạch trước khi migrate T17.7";
         return ARCS_PERSIST_MISMATCH;
      }
      why = "";
      Print("[BD:Cấu hình] THÔNG TIN | Đã nhận state ARCS cũ tại biên an toàn | lần lưu kế tiếp dùng fingerprint T17.7");
      return ARCS_PERSIST_OK;
   }
};

#endif // BD_RECOVERY_ARCS_PERSISTENCE_T177_C5_WRAPPER_MQH
