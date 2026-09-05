//+------------------------------------------------------------------+
//| JournalT177.mqh — T17.7 C6 Vietnamese human-readable journal    |
//| Pure formatting/reason translation only; no trade side effects.  |
//+------------------------------------------------------------------+
#ifndef BD_JOURNAL_T177_MQH
#define BD_JOURNAL_T177_MQH

bool Journal_T177StartsWithPure(const string text,const string prefix)
{
   return StringLen(text)>=StringLen(prefix) && StringSubstr(text,0,StringLen(prefix))==prefix;
}

string Journal_T177HumanReasonPure(string text)
{
   StringReplace(text,"BLOCK_MAX_CONCURRENT","Đã đạt giới hạn lệnh Pyramid đồng thời");
   StringReplace(text,"BLOCK_CLEAN_CYCLE_EXITED","Chu kỳ sạch đã có lệnh Pyramid thoát; không nhồi lại");
   StringReplace(text,"BLOCK_MAX_ORDERS","Đã đạt giới hạn tổng số lệnh");
   StringReplace(text,"BLOCK_DCA_RESERVE","Đang giữ chỗ cho DCA Core");
   StringReplace(text,"BLOCK_RECOVERY","Recovery cùng phía đang sở hữu chu kỳ");
   StringReplace(text,"BLOCK_PENDING","Đang chờ broker xác nhận lệnh trước");
   StringReplace(text,"BLOCK_TREND","Xu hướng chưa đạt điều kiện nhồi dương");
   StringReplace(text,"BLOCK_TIMING_MUTATION","Chưa qua nến mới/MinuteStop sau biến động gần nhất");
   StringReplace(text,"BLOCK_MIN_PROFIT_ECONOMIC","Lợi nhuận kinh tế chưa đủ biên khóa tối thiểu");
   StringReplace(text,"BLOCK_TP_ROOM","Khoảng còn lại tới TP quá nhỏ");
   StringReplace(text,"BLOCK_FIRST_CORE_IDENTITY","Chưa xác định được lệnh Core đầu campaign");
   StringReplace(text,"BLOCK_FIRST_CORE_DISTANCE","Khoảng cách nhồi dương không hợp lệ");
   StringReplace(text,"BLOCK_GAP","Chưa đủ khoảng giá tới bậc tiếp theo");
   StringReplace(text,"BLOCK_FIXED_LOT_TOTAL_CAP","Lot cố định sẽ vượt trần tổng lot");
   StringReplace(text,"BLOCK_FIXED_LOT_RISK_METADATA","Thiếu dữ liệu broker để tính rủi ro lot cố định");
   StringReplace(text,"BLOCK_FIXED_LOT_PEEL_RESERVE","Nguồn lợi nhuận chưa đủ để tài trợ lot cố định");
   StringReplace(text,"BLOCK_RISK_MODE_ZERO_BUDGET","Ngân sách rủi ro Pyramid bằng 0");
   StringReplace(text,"BLOCK_RISK_BUDGET","Không còn ngân sách rủi ro Pyramid");
   StringReplace(text,"BLOCK_TOTAL_LOTS","Đã đạt trần tổng lot Pyramid/Core");
   StringReplace(text,"BLOCK_VOLUME_GRID","Lot sau chuẩn hóa broker bằng 0");
   StringReplace(text,"CAPACITY_WAIT","Chờ đủ sức chứa layer Recovery");
   StringReplace(text,"RECONCILE_REQUIRED","Cần đối soát trạng thái broker");
   StringReplace(text,"HEDGE_BUILDING","Đang xây Hedge");
   StringReplace(text,"HEDGE_ACTIVE","Hedge đang hoạt động");
   StringReplace(text,"LEG2_WAIT_SAFE","Lệnh 2 đang chờ mức đóng an toàn");
   return text;
}

string Journal_T177LinePure(const string level,
                            const string side,
                            const string state,
                            const string detail,
                            const string metric="")
{
   string out=level;
   if(side!="") out+=" "+side;
   if(state!="") out+=" | "+state;
   if(detail!="") out+=" | "+Journal_T177HumanReasonPure(detail);
   if(metric!="") out+=" | "+metric;
   return out;
}

string Journal_T177NormalizePayloadPure(const string msg)
{
   return Journal_T177HumanReasonPure(msg);
}

#endif // BD_JOURNAL_T177_MQH
