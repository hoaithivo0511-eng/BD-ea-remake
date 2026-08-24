#include <iostream>
#include <string>
#include <vector>
#include <utility>
using std::string;

void rep(string &s,const string &a,const string &b){size_t p=0;while((p=s.find(a,p))!=string::npos){s.replace(p,a.size(),b);p+=b.size();}}
string human(string s){
 std::vector<std::pair<string,string>> m={
 {"BLOCK_MAX_CONCURRENT","Đã đạt giới hạn lệnh Pyramid đồng thời"},{"BLOCK_CLEAN_CYCLE_EXITED","Chu kỳ sạch đã có lệnh Pyramid thoát; không nhồi lại"},
 {"BLOCK_MAX_ORDERS","Đã đạt giới hạn tổng số lệnh"},{"BLOCK_DCA_RESERVE","Đang giữ chỗ cho DCA Core"},{"BLOCK_RECOVERY","Recovery cùng phía đang sở hữu chu kỳ"},
 {"BLOCK_PENDING","Đang chờ broker xác nhận lệnh trước"},{"BLOCK_TREND","Xu hướng chưa đạt điều kiện nhồi dương"},{"BLOCK_TIMING_MUTATION","Chưa qua nến mới/MinuteStop sau biến động gần nhất"},
 {"BLOCK_MIN_PROFIT_ECONOMIC","Lợi nhuận kinh tế chưa đủ biên khóa tối thiểu"},{"BLOCK_TP_ROOM","Khoảng còn lại tới TP quá nhỏ"},{"BLOCK_FIRST_CORE_IDENTITY","Chưa xác định được lệnh Core đầu campaign"},
 {"BLOCK_GAP","Chưa đủ khoảng giá tới bậc tiếp theo"},{"BLOCK_FIXED_LOT_PEEL_RESERVE","Nguồn lợi nhuận chưa đủ để tài trợ lot cố định"},{"BLOCK_RISK_BUDGET","Không còn ngân sách rủi ro Pyramid"},
 {"BLOCK_VOLUME_GRID","Lot sau chuẩn hóa broker bằng 0"},{"CAPACITY_WAIT","Chờ đủ sức chứa layer Recovery"},{"RECONCILE_REQUIRED","Cần đối soát trạng thái broker"},
 {"HEDGE_BUILDING","Đang xây Hedge"},{"LEG2_WAIT_SAFE","Lệnh 2 đang chờ mức đóng an toàn"}};
 for(auto &x:m) rep(s,x.first,x.second); return s;
}
string line(const string& level,const string& side,const string& state,const string& detail,const string& metric){string o=level;if(!side.empty())o+=" "+side;if(!state.empty())o+=" | "+state;if(!detail.empty())o+=" | "+human(detail);if(!metric.empty())o+=" | "+metric;return o;}
int main(){int p=0,f=0;auto ck=[&](bool x){x?++p:++f;};
 ck(human("BLOCK_MAX_CONCURRENT").find("giới hạn")!=string::npos); ck(human("BLOCK_CLEAN_CYCLE_EXITED").find("Chu kỳ sạch")!=string::npos);
 ck(human("BLOCK_MAX_ORDERS").find("tổng số lệnh")!=string::npos); ck(human("BLOCK_DCA_RESERVE").find("DCA Core")!=string::npos);
 ck(human("BLOCK_RECOVERY").find("Recovery cùng phía")!=string::npos); ck(human("BLOCK_PENDING").find("broker")!=string::npos);
 ck(human("BLOCK_TREND").find("Xu hướng")!=string::npos); ck(human("BLOCK_TIMING_MUTATION").find("MinuteStop")!=string::npos);
 ck(human("BLOCK_MIN_PROFIT_ECONOMIC").find("Lợi nhuận kinh tế")!=string::npos); ck(human("BLOCK_TP_ROOM").find("TP")!=string::npos);
 ck(human("BLOCK_FIRST_CORE_IDENTITY").find("Core đầu")!=string::npos); ck(human("BLOCK_GAP").find("khoảng giá")!=string::npos);
 ck(human("BLOCK_FIXED_LOT_PEEL_RESERVE").find("tài trợ")!=string::npos); ck(human("BLOCK_RISK_BUDGET").find("ngân sách")!=string::npos);
 ck(human("BLOCK_VOLUME_GRID").find("broker")!=string::npos); ck(human("CAPACITY_WAIT").find("sức chứa")!=string::npos);
 ck(human("RECONCILE_REQUIRED").find("đối soát")!=string::npos); ck(human("HEDGE_BUILDING")=="Đang xây Hedge"); ck(human("LEG2_WAIT_SAFE").find("Lệnh 2")!=string::npos);
 string l=line("CHỜ","BUY","Hedge chưa tăng bậc","BLOCK_GAP","đang=81% mục tiêu=85% còn=4%");
 ck(l.find("CHỜ BUY | Hedge chưa tăng bậc")!=string::npos); ck(l.find("Chưa đủ khoảng giá")!=string::npos); ck(l.find("còn=4%")!=string::npos);
 ck(human("không đổi")=="không đổi"); ck(line("LỖI","SELL","Đối soát","RECONCILE_REQUIRED","").find("LỖI SELL")!=string::npos);
 std::cout<<"T17.7 C6 journal model: "<<p<<" passed, "<<f<<" failed\n"; if(!f)std::cout<<"ALL GREEN\n"; return f?1:0;}
