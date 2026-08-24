//+------------------------------------------------------------------+
//| RecoveryArcsStackT177HedgeLadder.mqh — T17.7 C4 runtime         |
//| Executable broker-unit ladder over verified C1/C2/C3/T17.6.     |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_T177_HEDGE_LADDER_MQH
#define BD_RECOVERY_ARCS_STACK_T177_HEDGE_LADDER_MQH

#include "RecoveryArcsStackT177Scheduler.mqh"
#include "RecoveryT177HedgeLadder.mqh"

class CRecoveryArcsStackT177C4 : public CRecoveryArcsStackT17
{
private:
   double m_c4Coverage[];
   double m_c4Gap[];
   uint   m_c4PlanHash[2];

   int C4Idx(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? 0 : 1;
   }

   int HeartbeatC4() const
   {
      return Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_);
   }

   void LogWaitC4(const eRecoveryCoreDirection dir,
                  const int generation,
                  const string reason)
   {
      Log_WarnEvery("Recovery",
                    "t177c4wait" + (string)Recovery_CycleKey(dir) + "g" + (string)generation,
                    "CHỜ " + Recovery_DirectionName(dir) +
                    " | Hedge chưa tăng bậc | " + reason,
                    HeartbeatC4());
   }

   bool BuildPercentLadderC4(string &why)
   {
      why = "";
      ArrayResize(m_c4Coverage,0);
      ArrayResize(m_c4Gap,0);
      if(HedgePyramidMode_ == hedge_pyramid_TAT) return true;

      double raw[];
      if(!Pyramid_ParsePositiveSequence(HedgePyramidCoverageSequence_,raw))
      { why="không đọc được chuỗi coverage Hedge Pyramid"; return false; }
      if(Pyramid_NormalizeCoverageTargetsPure(raw,
                                              HedgeVolumePercent_,
                                              HedgePyramidMaxCoveragePercent_,
                                              m_c4Coverage)<=0)
      { why="không còn bậc coverage hợp lệ sau khi áp target/trần"; return false; }
      if(ArraySize(m_c4Coverage)>1)
      {
         if(!Pyramid_ParsePositiveSequence(HedgePyramidGapSequence_,m_c4Gap))
         { why="không đọc được chuỗi khoảng cách Hedge Pyramid"; return false; }
      }
      return true;
   }

   long RetainedBeforeGenerationC4(const eRecoveryCoreDirection dir,
                                   const long liveGenerationUnits) const
   {
      long total=Recovery_ArcsTotalHedgeUnits(dir,m_volumeStep);
      long retained=total-liveGenerationUnits;
      return retained>0?retained:0;
   }

   bool BuildExecutablePlanC4(const eRecoveryCoreDirection dir,
                              const long liveGenerationUnits,
                              const SRecoveryBundleVolumeMeta &meta,
                              SRecoveryT177HedgeStage &plan[],
                              long &coreUnits,
                              long &retainedUnits,
                              long &finalRawUnits) const
   {
      coreUnits=Recovery_ArcsCoreUnits(dir,m_volumeStep);
      retainedUnits=RetainedBeforeGenerationC4(dir,liveGenerationUnits);
      finalRawUnits=0;
      ArrayResize(plan,0);
      if(coreUnits<=0||ArraySize(m_c4Coverage)<=0) return false;
      finalRawUnits=Recovery_T177FinalGenerationRawUnitsPure(coreUnits,
                                                             retainedUnits,
                                                             m_c4Coverage[ArraySize(m_c4Coverage)-1]);
      Recovery_T177BuildExecutableHedgeLadderPure(m_c4Coverage,
                                                  m_c4Gap,
                                                  coreUnits,
                                                  retainedUnits,
                                                  meta.minUnits,
                                                  plan);
      return true;
   }

   uint PlanHashC4(const eRecoveryCoreDirection dir,
                   const long coreUnits,
                   const long retainedUnits,
                   const long finalRawUnits,
                   const SRecoveryT177HedgeStage &plan[]) const
   {
      string text=(string)(int)dir+"|"+(string)coreUnits+"|"+(string)retainedUnits+
                  "|"+(string)finalRawUnits+"|";
      for(int i=0;i<ArraySize(plan);i++)
      {
         text+=(string)plan[i].sourceIndex+":"+
               DoubleToString(plan[i].requestedCoverage,6)+":"+
               (string)plan[i].generationTargetUnits+":"+
               DoubleToString(plan[i].gapFromPreviousPips,6)+";";
      }
      return Recovery_Fnv1aTextPure(text);
   }

   string SkippedStagesC4(const long coreUnits,
                          const long retainedUnits,
                          const long minUnits,
                          const long finalRawUnits,
                          const SRecoveryT177HedgeStage &plan[]) const
   {
      string skipped="";
      for(int i=0;i<ArraySize(m_c4Coverage);i++)
      {
         if(Recovery_T177StageSourceKeptPure(i,plan)) continue;
         long desired=Recovery_T177CoverageTotalUnitsPure(coreUnits,m_c4Coverage[i]);
         long raw=desired>retainedUnits?desired-retainedUnits:0;
         string reason="đã đủ";
         if(raw>0)
         {
            long planned=(minUnits>0&&raw<minUnits)?minUnits:raw;
            if(planned>finalRawUnits) reason="vượt target cuối do lot tối thiểu";
            else reason="trùng lot thực thi";
         }
         if(skipped!="") skipped+=",";
         skipped+=DoubleToString(m_c4Coverage[i],2)+"%("+reason+")";
      }
      return skipped;
   }

   void LogPlanC4(const eRecoveryCoreDirection dir,
                  const int generation,
                  const SRecoveryBundleVolumeMeta &meta,
                  const long coreUnits,
                  const long retainedUnits,
                  const long finalRawUnits,
                  const SRecoveryT177HedgeStage &plan[])
   {
      int di=C4Idx(dir);
      uint h=PlanHashC4(dir,coreUnits,retainedUnits,finalRawUnits,plan);
      if(m_c4PlanHash[di]==h) return;
      m_c4PlanHash[di]=h;

      double requested=HedgeVolumePercent_;
      double effective=Recovery_T177EffectiveFinalCoveragePercentPure(HedgeVolumePercent_,
                                                                       HedgePyramidMaxCoveragePercent_);
      string stages="";
      for(int i=0;i<ArraySize(plan);i++)
      {
         if(stages!="") stages+=",";
         stages+=DoubleToString(plan[i].requestedCoverage,2)+"%→"+
                 DoubleToString(Recovery_UnitsToVolume(plan[i].totalTargetUnits,
                                                       meta.volumeStep),2)+"L";
         if(i>0)
            stages+="(gap "+DoubleToString(plan[i].gapFromPreviousPips,2)+")";
      }
      if(stages=="") stages="không có bậc mới thực thi được";
      string skipped=SkippedStagesC4(coreUnits,retainedUnits,meta.minUnits,finalRawUnits,plan);
      string msg="Hedge ladder "+Recovery_DirectionName(dir)+" G"+(string)generation+
                 " | target yêu cầu="+DoubleToString(requested,2)+
                 "% hiệu lực="+DoubleToString(effective,2)+
                 "% | bậc="+stages;
      if(skipped!="") msg+=" | bỏ="+skipped;
      Log_Info("Recovery",msg);
   }

   bool HedgeGapHitC4(const eRecoveryCoreDirection dir,
                      const EAContext &ctx,
                      const double anchor,
                      const double gapPips) const
   {
      double gap=Recovery_PipsToPricePure(gapPips,m_isGold,_Point,_Digits);
      if(dir==recovery_CORE_BUY) return ctx.bid<=anchor-gap;
      return ctx.ask>=anchor+gap;
   }

   bool CurrentHedgeProfitableC4(const eRecoveryCoreDirection dir,
                                 const EAContext &ctx,
                                 SArcsLayerSnapshot &snap,
                                 string &why)
   {
      SArcsPosition pos[];
      if(!Recovery_ArcsLayerSnapshot(dir,
                                     m_dir[C4Idx(dir)].generationCount,
                                     m_volumeStep,m_tickSize,
                                     pos,snap,why)) return false;
      return dir==recovery_CORE_BUY?ctx.ask<snap.netBE:ctx.bid>snap.netBE;
   }

   bool ActivateCurrentVolumeC4(const eRecoveryCoreDirection dir,
                                const int li,
                                SArcsLayer &l,
                                const long live,
                                string &why)
   {
      if(live<=0) return false;
      l.targetUnits=live;
      l.openedUnits=live;
      l.remainingUnits=live;
      l.state=ARCS_LAYER_ACTIVE;
      PutLayer(dir,li,l);
      m_dir[C4Idx(dir)].phase=ARCS_ACTIVE;
      m_dirty=true;
      return Save(why);
   }

   bool TpPriorityRequiresActivationC4(const eRecoveryCoreDirection dir,
                                       const EAContext &ctx,
                                       const int li,
                                       SArcsLayer &l,
                                       const long live,
                                       string &why)
   {
      if(live<=0) return false;
      SArcsPosition pos[];
      SArcsLayerSnapshot snap;
      string local="";
      if(!Recovery_ArcsLayerSnapshot(dir,l.generation,m_volumeStep,
                                     m_tickSize,pos,snap,local)) return false;
      if(Recovery_VirtualHedgeTpHit(dir,snap.netBE,ctx.bid,ctx.ask,m_tpDistancePrice))
      {
         why="ưu tiên TP: dừng tăng coverage và dùng volume Hedge hiện tại";
         ActivateCurrentVolumeC4(dir,li,l,live,local);
         return true;
      }
      return false;
   }

   bool ProjectedRoomAllowsC4(const eRecoveryCoreDirection dir,
                              const EAContext &ctx,
                              const SArcsLayerSnapshot &snap,
                              const long addUnits) const
   {
      if(HedgePyramidMinRoomToTPPips_<=0.0||addUnits<=0) return true;
      double addLots=Recovery_UnitsToVolume(addUnits,m_volumeStep);
      if(addLots<=0.0||snap.lots<=0.0) return false;
      double entry=dir==recovery_CORE_BUY?ctx.bid:ctx.ask;
      double projectedLots=snap.lots+addLots;
      double projectedBE=(snap.weightedEntry*snap.lots+entry*addLots)/projectedLots;
      double target=dir==recovery_CORE_BUY?projectedBE-m_tpDistancePrice:
                                           projectedBE+m_tpDistancePrice;
      double pip=Recovery_PipSizePure(m_isGold,_Point,_Digits);
      if(pip<=0.0) return false;
      double room=dir==recovery_CORE_BUY?(ctx.ask-target)/pip:(target-ctx.bid)/pip;
      return room+1e-9>=HedgePyramidMinRoomToTPPips_;
   }

   bool FullMarginReserveAllowsC4(const eRecoveryCoreDirection dir,
                                  const long remainingUnits,
                                  const SRecoveryBundleVolumeMeta &meta,
                                  string &why) const
   {
      why="";
      if(!HedgePyramidReserveFullTarget_||remainingUnits<=0) return true;
      int hedgeDir=Recovery_HedgeDirection(dir);
      ENUM_ORDER_TYPE type=hedgeDir==0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol,tick))
      { why="không đọc được giá để kiểm tra margin target Hedge"; return false; }
      double price=hedgeDir==0?tick.ask:tick.bid;
      long left=remainingUnits;
      double required=0.0;
      while(left>0)
      {
         long child=Recovery_BundleNextChildUnits(left,meta.minUnits,meta.maxOrderUnits);
         if(child<=0)
         { why="target Hedge không chia được theo giới hạn lot broker"; return false; }
         double margin=0.0;
         double volume=Recovery_UnitsToVolume(child,meta.volumeStep);
         if(!OrderCalcMargin(type,_Symbol,volume,price,margin)||margin<0.0)
         { why="không tính được margin target Hedge"; return false; }
         required+=margin;
         left-=child;
      }
      double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(free+1e-8<required)
      {
         why="Free Margin="+DoubleToString(free,2)+
             " < cần="+DoubleToString(required,2)+" để hoàn tất target Hedge";
         return false;
      }
      return true;
   }

   bool DriveBuildingC4(CExecutionLayer &exec,
                        const eRecoveryCoreDirection dir,
                        const EAContext &ctx,
                        string &why)
   {
      why="";
      int di=C4Idx(dir);
      if(m_dir[di].phase!=ARCS_BUILDING) return false;
      int li=m_dir[di].activeLayer;
      SArcsLayer l;
      GetLayer(dir,li,l);
      if(!l.used||l.state!=ARCS_LAYER_BUILDING)
      {
         LatchReconcile(dir,"C4 BUILDING không có layer hợp lệ");
         why="C4 BUILDING active layer invalid";
         return true;
      }

      int key=Recovery_CycleKey(dir);
      exec.ReconcileCycle(key);
      if(exec.HasReconcileRequired(key))
      {
         LatchReconcile(dir,"C4 execution journal cần đối soát khi mở Hedge");
         why="C4 Hedge execution reconcile required";
         return true;
      }

      long live=Recovery_ArcsLayerUnits(dir,l.generation,m_volumeStep);
      if(live>l.targetUnits)
      {
         LatchReconcile(dir,"C4 live generation vượt target đã persist");
         why="C4 generation over persisted target";
         return true;
      }
      l.openedUnits=live;
      l.remainingUnits=live;
      PutLayer(dir,li,l);

      SRecoveryBundleVolumeMeta meta;
      string local="";
      if(!Recovery_ReadBundleVolumeMeta(_Symbol,meta,local))
      {
         LogWaitC4(dir,l.generation,local);
         return false;
      }

      SRecoveryT177HedgeStage plan[];
      long coreUnits=0,retainedUnits=0,finalRawUnits=0;
      if(!BuildExecutablePlanC4(dir,live,meta,plan,coreUnits,retainedUnits,finalRawUnits))
      {
         LogWaitC4(dir,l.generation,"không dựng được ladder từ Core hiện tại");
         return false;
      }
      LogPlanC4(dir,l.generation,meta,coreUnits,retainedUnits,finalRawUnits,plan);

      long computedFinal=finalRawUnits;
      if(meta.minUnits>0&&computedFinal>0&&computedFinal<meta.minUnits)
         computedFinal=0; // absolute cap wins over broker-min inflation
      long finalTarget=Recovery_T176RebasedGenerationTargetPure(live,computedFinal);
      if(finalTarget<=0&&live<=0)
      {
         LogWaitC4(dir,l.generation,
                   "phần còn thiếu tới target cuối nhỏ hơn lot tối thiểu broker; không vượt hard cap");
         return false;
      }
      if(finalTarget!=l.targetUnits)
      {
         long old=l.targetUnits;
         l.targetUnits=finalTarget;
         PutLayer(dir,li,l);
         m_dirty=true;
         if(!Save(why)) return true;
         Log_Info("Recovery","Hedge target "+Recovery_DirectionName(dir)+
                  " G"+(string)l.generation+
                  " | cũ="+DoubleToString(Recovery_UnitsToVolume(old,m_volumeStep),2)+
                  "L mới="+DoubleToString(Recovery_UnitsToVolume(finalTarget,m_volumeStep),2)+
                  "L live="+DoubleToString(Recovery_UnitsToVolume(live,m_volumeStep),2)+"L");
      }

      if(live==l.targetUnits)
      {
         l.state=ARCS_LAYER_ACTIVE;
         PutLayer(dir,li,l);
         m_dir[di].phase=ARCS_ACTIVE;
         m_dirty=true;
         Save(why);
         return true;
      }
      if(exec.HasPendingForCycle(key)) return true;
      if(TpPriorityRequiresActivationC4(dir,ctx,li,l,live,why)) return true;

      int stage=-1;
      long previousTarget=0;
      for(int i=0;i<ArraySize(plan);i++)
      {
         if(live<plan[i].generationTargetUnits)
         { stage=i; break; }
         previousTarget=plan[i].generationTargetUnits;
      }
      if(stage<0)
      {
         if(live>0) return ActivateCurrentVolumeC4(dir,li,l,live,why);
         LogWaitC4(dir,l.generation,"không còn bậc thực thi nào cần mở");
         return false;
      }

      bool continuingPartialStage=live>previousTarget;
      if(!continuingPartialStage&&live>0)
      {
         SArcsPosition pos[];
         Recovery_ArcsBuildLayerPositions(dir,l.generation,m_volumeStep,pos);
         if(ArraySize(pos)<=0)
         {
            LatchReconcile(dir,"C4 không tìm thấy Hedge anchor cho bậc kế tiếp");
            why="C4 missing stage anchor";
            return true;
         }
         datetime lastStageOpen=pos[ArraySize(pos)-1].openTime;
         datetime lastStageBar=(lastStageOpen>=ctx.barTime)?ctx.barTime:0;
         if(!Pyramid_AddTimingAllowsPure(lastStageOpen,lastStageBar,
                                         ctx.now,ctx.barTime,MinuteStop))
         {
            LogWaitC4(dir,l.generation,"chờ nến mới/MinuteStop trước bậc Hedge tiếp theo");
            return false;
         }

         double gapPips=plan[stage].gapFromPreviousPips;
         double anchor=pos[ArraySize(pos)-1].openPrice;
         if(!HedgeGapHitC4(dir,ctx,anchor,gapPips))
         {
            LogWaitC4(dir,l.generation,
                      "đang="+DoubleToString(Recovery_T177ActualCoveragePercentPure(coreUnits,
                                                                                   retainedUnits+live),2)+
                      "% mục tiêu bậc="+DoubleToString(plan[stage].effectiveCoverage,2)+
                      "% | còn chờ Hedge đi thuận "+DoubleToString(gapPips,2)+" pip");
            return false;
         }
         if(HedgePyramidLockBeforeAdd_)
         {
            SArcsLayerSnapshot snap;
            string snapWhy="";
            if(!CurrentHedgeProfitableC4(dir,ctx,snap,snapWhy))
            {
               LogWaitC4(dir,l.generation,"Hedge hiện tại chưa có lợi nhuận ròng; chưa tăng bậc");
               return false;
            }
         }
      }

      long remainingStage=plan[stage].generationTargetUnits-live;
      if(remainingStage<=0) return false;
      if(live>0)
      {
         SArcsPosition pos[];
         SArcsLayerSnapshot snap;
         string snapWhy="";
         if(!Recovery_ArcsLayerSnapshot(dir,l.generation,m_volumeStep,
                                        m_tickSize,pos,snap,snapWhy))
         {
            LatchReconcile(dir,snapWhy);
            why=snapWhy;
            return true;
         }
         if(!ProjectedRoomAllowsC4(dir,ctx,snap,remainingStage))
         {
            why="ưu tiên TP: khoảng còn lại tới TP không đủ để tăng Hedge";
            return ActivateCurrentVolumeC4(dir,li,l,live,local);
         }
      }

      if(live==0&&!FullMarginReserveAllowsC4(dir,l.targetUnits,meta,local))
      {
         LogWaitC4(dir,l.generation,local);
         return false;
      }

      long child=Recovery_BundleNextChildUnits(remainingStage,
                                               meta.minUnits,
                                               meta.maxOrderUnits);
      if(child<=0)
      {
         LogWaitC4(dir,l.generation,"phần còn lại của bậc không tạo được lot hợp lệ");
         return false;
      }
      int hedgeDir=Recovery_HedgeDirection(dir);
      long existingDirectional=Recovery_DirectionalExposureUnits(_Symbol,hedgeDir,meta.volumeStep);
      if(!Recovery_VolumeLimitAllows(child,existingDirectional,meta.volumeLimitUnits))
      {
         LogWaitC4(dir,l.generation,"SYMBOL_VOLUME_LIMIT chưa cho phép mở thêm Hedge");
         return false;
      }
      if(!Recovery_ChildMarginPreflight(_Symbol,hedgeDir,child,meta.volumeStep,local))
      {
         LogWaitC4(dir,l.generation,local);
         return false;
      }

      double volume=Recovery_UnitsToVolume(child,meta.volumeStep);
      SArcsPosition pos[];
      int childNo=1+Recovery_ArcsBuildLayerPositions(dir,l.generation,m_volumeStep,pos);
      int effectiveStageNo=stage+1;
      string comment="BDR|C="+(string)key+
                     "|G="+(string)l.generation+
                     "|B="+(string)l.bundleId+
                     "|P="+(string)effectiveStageNo+
                     "|N="+(string)childNo;
      if(!SaveBeforeMutation(why)) return true;
      bool accepted=exec.OpenMarketOwned(hedgeDir,volume,
                                         (long)RecoveryMagic_,key,
                                         EXEC_CMD_RECOVERY_OPEN,
                                         EXEC_RECONCILE_FAIL_CLOSED,
                                         comment);
      eRecoveryT165CapacityDisposition disposition=
         Recovery_T165CapacityDispositionPure(true,accepted,
                                               exec.HasReconcileRequired(key));
      if(disposition==RECOVERY_T165_CAPACITY_RECONCILE)
      {
         LatchReconcile(dir,"C4 không xác định được kết quả mở Hedge");
         why="C4 Hedge child outcome ambiguous";
         return true;
      }
      if(disposition==RECOVERY_T165_CAPACITY_WAIT_NO_EFFECT)
      {
         LogWaitC4(dir,l.generation,"broker từ chối child với kết quả xác định; chưa có mutation");
         return false;
      }
      Log_Info("Recovery","MỞ "+Recovery_DirectionName(dir)+
               " | Hedge bậc "+(string)effectiveStageNo+
               " | target yêu cầu="+DoubleToString(plan[stage].requestedCoverage,2)+
               "% hiệu lực="+DoubleToString(plan[stage].effectiveCoverage,2)+
               "% | child="+DoubleToString(volume,2)+" lot");
      return true;
   }

public:
   CRecoveryArcsStackT177C4(void) : CRecoveryArcsStackT17()
   {
      m_c4PlanHash[0]=0;
      m_c4PlanHash[1]=0;
   }

   bool Init()
   {
      if(!CRecoveryArcsStackT17::Init()) return false;
      string why="";
      if(!BuildPercentLadderC4(why))
      {
         Log_Error("Recovery","C4 Hedge ladder config invalid: "+why);
         return false;
      }
      if(HedgePyramidMode_!=hedge_pyramid_TAT)
      {
         double effective=Recovery_T177EffectiveFinalCoveragePercentPure(HedgeVolumePercent_,
                                                                          HedgePyramidMaxCoveragePercent_);
         Log_Info("Recovery","Hedge target | yêu cầu="+DoubleToString(HedgeVolumePercent_,2)+
                  "% hard cap="+DoubleToString(HedgePyramidMaxCoveragePercent_,2)+
                  "% hiệu lực="+DoubleToString(effective,2)+
                  "% | C5 sẽ đổi tên public input, C4 giữ tương thích .set hiện tại");
      }
      return true;
   }

   bool Drive(CExecutionLayer &exec,const EAContext &ctx,string &why)
   {
      if(HedgePyramidMode_!=hedge_pyramid_TAT)
      {
         if(m_dir[0].phase==ARCS_BUILDING)
            return DriveBuildingC4(exec,recovery_CORE_BUY,ctx,why);
         if(m_dir[1].phase==ARCS_BUILDING)
            return DriveBuildingC4(exec,recovery_CORE_SELL,ctx,why);
      }
      return CRecoveryArcsStackT17::Drive(exec,ctx,why);
   }
};

#endif // BD_RECOVERY_ARCS_STACK_T177_HEDGE_LADDER_MQH
