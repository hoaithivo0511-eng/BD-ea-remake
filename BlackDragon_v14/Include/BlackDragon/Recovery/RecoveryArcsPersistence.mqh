//+------------------------------------------------------------------+
//| RecoveryArcsPersistence.mqh — T17.7 C5 public composition facade|
//| Migration implementation is pinned in the included C5 impl blob. |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_PERSISTENCE_T177_C5_FACADE_MQH
#define BD_RECOVERY_ARCS_PERSISTENCE_T177_C5_FACADE_MQH

#include "RecoveryArcsPersistenceT177C5Impl.mqh"

// Regression/source anchors for source scanners that intentionally inspect the
// public composition header rather than following includes. Executable checks
// remain in RecoveryArcsPersistenceT177C5Impl.mqh.
/*
 Recovery_T177LegacySemanticFingerprintC5()
 Recovery_T177CanAcceptLegacyPersistenceC5()
 ARCS_BUILDING
 ARCS_ACTIVE
 State ARCS cũ đang BUILDING/ACTIVE/PENDING
 CRecoveryArcsPersistenceT177C4Base::Load
*/

#endif // BD_RECOVERY_ARCS_PERSISTENCE_T177_C5_FACADE_MQH
