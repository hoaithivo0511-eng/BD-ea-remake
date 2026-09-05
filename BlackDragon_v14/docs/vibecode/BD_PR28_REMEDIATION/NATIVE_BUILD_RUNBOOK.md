# Native build và tiếp tục verification

## Backend cần có

Dùng VPS Windows/MetaTrader đã có của project thông qua kết nối VibeMQL5 được bật trong phiên làm việc, hoặc Windows GitHub Actions có quyền đọc đúng nhánh candidate. Phiên tạo checkpoint chỉ có Linux/g++/Python; không có MetaEditor, MT5, Wine, CLI VibeMQL5 hay tool gọi worker. Không có EX5 được biên dịch trong phiên này.

## Lệnh compile trên Windows đã cài MetaEditor

Áp patch lên đúng baseline, commit candidate, kiểm `git status` sạch. Giữ bản làm việc riêng, không dùng thư mục terminal đang giao dịch. Script không cài phần mềm, không đăng nhập account, không chạy EA và không bật trading.

```powershell
.\BlackDragon_v14\Scripts\BlackDragon\Tests\BuildCandidate.ps1 `
  -RepositoryRoot 'C:\work\BD-ea-remake' `
  -MetaEditor 'C:\Program Files\MetaTrader 5\metaeditor64.exe' `
  -OutputDirectory 'C:\work\bd-t1724-native-build'
```

OutputDirectory phải chưa tồn tại. Script tạo staging riêng, chuyển .mq5/.mqh từ UTF-8 sang UTF-16LE BOM, lưu hash trước/sau; compile probe, 33 scripts và EA. Mỗi output/log phải mới, log phải có 0 errors/0 warnings, EX5 không rỗng. Kết quả thành công tạo `BlackDragon.ex5`, compile logs, `SOURCE_MANIFEST.json`, `BUILD_MANIFEST.json` cùng các EX5 script.

Script PowerShell đã được viết và kiểm tra source, **chưa chạy trong Windows**. Lỗi syntax/compiler phát hiện ở lượt native phải được sửa trong candidate mới rồi chạy lại các gate bị ảnh hưởng.

Compile PASS không tự cho native tests, Tester, migration hoặc release PASS. Chạy native matrix theo `.github/workflows/verify-current.yml`; cash suite mới kỳ vọng 30/0. Native async cần callback injection/runtime thật; sync fallback trong Tester không chứng minh async lifecycle.

## Provenance cần gửi lại

- Repo, commit SHA/tree; dirty false hoặc danh sách hash tree thực tế đầy đủ.
- MetaEditor version/hash và compile probe log.
- EA + 33 suite compile logs 0/0, EX5 hash/bytes.
- 33 suite runtime logs đã đối chiếu expected count của workflow.
- Nếu từ Actions: run ID/attempt, numeric job ID, Windows runner, artifact hash/size, source HEAD khớp.
- Tester reports, broker profile, .set, dataset/timeframe/model và end-date completion; restart/crash trace riêng.

Không đưa account secret vào evidence. Không dùng binary cũ để lấp output thiếu.

## State migration và rollback

Candidate writer dùng PY protection disk v2 để lưu retry; reader có nhánh v1. Sao lưu file state trước thử migration trong terminal kiểm thử. Kiểm header/count/checksum, deadline/budget và obligation sau reload; thử file truncated, checksum sai, crash trước/sau atomic replace. Không xóa state để ép khởi động. Với open/pending state, không rollback sang binary chỉ hiểu v1; dùng bản tương thích hoặc reconcile/settle theo quy trình trước.
