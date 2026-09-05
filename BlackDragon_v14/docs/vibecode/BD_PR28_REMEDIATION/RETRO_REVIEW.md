# T17.24 retro checkpoint

- Nested history selection thay selected list là hiệu ứng toàn chương trình. Snapshot ID trước khi gọi HistoryDealSelect/HistorySelectByPosition trong batch; khóa bằng fixture reset-list thực sự, không mock history như container bất biến.
- Scope accounting cần immutable opening ownership; close-actor magic không đủ. Seed/callback phải cùng reducer và cùng validity.
- Day retry phải ghi nhận attempted day trước history failure; nếu không rollover invalidation hủy backoff mỗi tick.
- Definitive reject cần identity và absence-of-effect proof. Nonce, observed fill, live volume và live SL có thể bác bỏ no-effect classification.
- Save-before-ACK và v1/v2 source code không thay thế native crash/migration evidence.
- Scope chuyển implementation cần update contract checker trỏ đúng implementation, giữ historical tests và numeric independent counterexamples. Không sửa expected chỉ để xanh.
- Model-source, production-body host adapters, native compile, native script và Strategy Tester là các tầng khác nhau; giữ UNTESTABLE khi thiếu backend.
- Performance optimization code không tự tạo ra benchmark PASS. B1 native chưa freeze; candidate cần tách và đo trước nghiệm thu.

Guard execution chi tiết còn pending trong TEST_EXECUTION.json. Canonical vkmql-check không có trong môi trường; không có retro PASS tổng thể được tuyên bố.
