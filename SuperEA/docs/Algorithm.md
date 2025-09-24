# Thuật toán Batch Trend EA cho XAUUSDc (Exness Cent)

## 1. Mục tiêu tổng quan
Chiến lược tập trung vào **giao dịch theo xu hướng đơn giản** với cơ chế **batch** 7 lệnh. EA nhận diện xu hướng bằng bộ đôi EMA nhanh/chậm, mở lệnh cách nhau tối thiểu 17 giây cho tới khi đủ số lượng trong batch. Khi tổng lợi nhuận (thực + thả nổi) đạt ngưỡng cấu hình, toàn bộ batch được đóng để khóa lãi và chuẩn bị chu kỳ mới.

## 2. Chu trình giao dịch
1. **Xác nhận xu hướng**: EMA(20) vs EMA(50) trên M5. Độ lệch nhanh-chậm phải vượt ngưỡng tối thiểu (đơn vị point) để tránh nhiễu sideway.
2. **Điều kiện mở lệnh**:
   - Spread và Margin Level nằm trong ngưỡng cho phép.
   - Volatility (ATR) thấp hơn ngưỡng `InpATRVolatilityLimit` nếu chưa có batch hoạt động.
   - Mỗi lệnh cách nhau ≥ 17 giây, tối đa 7 lệnh/batch.
3. **Đặt SL/TP**: khoảng cách SL = max(ATR × `InpStopATRMultiplier`, `InpMinStopPoints`), TP = SL × `InpTPMultiplier`.
4. **Lot size**: nếu bật chế độ động, khối lượng = %rủi ro × Balance ÷ (StopTicks × TickValue), tự động chuẩn hóa theo bước lot của XAUUSDc. Có thể chuyển sang lot cố định qua `InpUseFixedLot`.
5. **Đóng batch**:
   - Khi lợi nhuận tích lũy của batch ≥ `InpBatchProfitTargetPct` × Balance lúc mở batch.
   - Hoặc khi tất cả vị thế đã đóng (ví dụ bị SL). EA ghi nhận PnL để đánh giá.

## 3. Quản trị rủi ro & tối ưu
- **Margin guard**: nếu Margin Level < `InpMinMarginLevel`, EA tạm dừng mở lệnh mới.
- **Volatility pause**: ATR vượt ngưỡng cấu hình ⇒ không khởi động batch mới (batch đang chạy vẫn được quản lý bình thường).
- **Giới hạn spread**: tránh vào lệnh trong giai đoạn spread nới rộng của XAUUSDc cent.
- **Theo dõi drawdown**: EA lưu đỉnh equity và tính drawdown lớn nhất để đánh giá mức chịu đựng vốn.

## 4. Đánh giá hiệu quả
EA duy trì các thống kê sau (hiển thị trên comment panel và trả lời qua Telegram `/status`):
- Tổng số batch hoàn thành, số batch thắng và tỷ lệ thắng (%).
- Tổng lợi nhuận cộng dồn và lợi nhuận batch gần nhất.
- Độ sâu drawdown lớn nhất kể từ khi chạy EA.
- Thông tin batch hiện tại: số lệnh, profit mở/đóng, mục tiêu lợi nhuận USD.
Các số liệu này cho phép đánh giá xác suất thắng cần thiết và tối ưu thông số (ATR, RR, % risk) để đạt mục tiêu lợi nhuận ngay cả khi tỷ lệ batch thua cao tới 30%.

## 5. Điều khiển từ xa (Telegram)
EA tích hợp client Telegram:
- `/startEA`, `/resume`: bật giao dịch tự động.
- `/stopEA`, `/pauseEA`: tạm dừng batch mới.
- `/statusAccount`: báo cáo balance, equity, margin, thống kê batch.
- `/manualCloseBatch`: đóng toàn bộ vị thế trong batch hiện tại và để EA tự ghi nhận kết quả.
Yêu cầu thêm `https://api.telegram.org` vào danh sách WebRequest trong MT5.

## 6. Tối ưu cho Exness XAUUSDc
- **Lot tối thiểu 0.01** và bước 0.01 được áp dụng tự động khi chuẩn hóa lot.
- Giá vàng trên tài khoản cent có tick size nhỏ (0.01) nên mọi SL/TP đều quy đổi bằng `_Point` để tương thích.
- Spread cao trong phiên Á: có thể tăng `InpMaxSpreadPoints` hoặc giới hạn thời gian chạy để giữ chi phí hợp lý.

Chiến lược đơn giản nhưng được kiểm soát chặt qua batch, margin, ATR và thống kê. Người dùng có thể điều chỉnh ngưỡng rủi ro/lợi nhuận để đảm bảo kỳ vọng dương ngay khi tỷ lệ batch thua lên tới 30%, đồng thời sử dụng số liệu drawdown để đánh giá hiệu quả dài hạn.
