# Universal DCA Grid EA

## Mô tả
EA DCA (Dollar Cost Averaging) Grid tự động giao dịch hai chiều với trailing stop và giao diện điều khiển bằng các nút trên chart.

## Tính năng chính

### 1. DCA Grid System
- Hệ thống lưới DCA hai chiều độc lập (BUY/SELL)
- Mở lệnh mới khi giá đi ngược xu hướng theo khoảng cách DCA
- Tăng lot size theo hệ số nhân (multiplier)
- Giới hạn số lượng grid levels tối đa

### 2. Trailing Stop
- Tự động kích hoạt khi profit đạt ngưỡng
- Trailing stop theo giá với khoảng cách cố định
- Đóng tất cả lệnh khi giá chạm trailing level

### 3. Giao diện điều khiển
- **BUY**: Kích hoạt grid BUY
- **SELL**: Kích hoạt grid SELL
- **Close BUY**: Đóng tất cả lệnh BUY và restart grid
- **Close SELL**: Đóng tất cả lệnh SELL và restart grid
- **Deactivate BUY**: Đóng tất cả lệnh BUY và dừng hẳn
- **Deactivate SELL**: Đóng tất cả lệnh SELL và dừng hẳn
- **PNL Panel**: Hiển thị P&L theo từng chiều
- **Info Panel**: Hiển thị trạng thái EA

### 4. Safe Fund Protection
- Dừng mở lệnh mới khi đạt ngưỡng grid level
- Đóng sớm khi profit >= minimum profit trong safe mode
- Bảo vệ tài khoản khỏi drawdown quá lớn

### 5. Daily Profit Target
- Tự động dừng giao dịch khi đạt profit mục tiêu trong ngày
- Reset tự động vào ngày mới
- Đóng tất cả lệnh khi đạt target

### 6. Auto Restart
- Tự động restart grid sau khi đóng lệnh
- Có thể tắt để điều khiển manual

### 7. Auto Start
- Tự động bắt đầu khi khởi động EA
- 4 chế độ: None, Buy Only, Sell Only, Both

## Cấu hình

### Trading Configuration

| Tham số | Mặc định | Mô tả |
|---------|----------|-------|
| Initial Lot Size | 1.0 | Lot size của lệnh đầu tiên |
| DCA Distance | 20.0 pips | Khoảng cách giữa các lệnh DCA |
| DCA Lot Multiplier | 1.3 | Hệ số nhân lot size cho lệnh tiếp theo |
| Maximum DCA Grid Levels | 22 | Số lượng lệnh tối đa trong grid |
| Take Profit | $50.0 | Profit để kích hoạt trailing stop |
| Trailing Distance | 20.0 pips | Khoảng cách trailing stop |
| Stop Loss | -$20000.0 | Ngưỡng loss để đóng tất cả lệnh |
| Auto Restart | false | Tự động restart grid sau khi đóng |

### System Settings

| Tham số | Mặc định | Mô tả |
|---------|----------|-------|
| Buy Magic Number | 666666 | Magic number cho lệnh BUY |
| Sell Magic Number | 888888 | Magic number cho lệnh SELL |
| Show Information Panel | false | Hiển thị panel thông tin |
| Show PNL Panel | true | Hiển thị panel P&L |

### Safe Fund Protection

| Tham số | Mặc định | Mô tả |
|---------|----------|-------|
| Enable Safe Fund Protection | false | Bật/tắt safe fund protection |
| Safe Fund Threshold | 17 | Ngưỡng grid level để kích hoạt |
| Minimum Profit to Close | $0.0 | Profit tối thiểu để đóng trong safe mode |

### Daily Profit Target

| Tham số | Mặc định | Mô tả |
|---------|----------|-------|
| Enable Daily Profit Target | false | Bật/tắt daily profit target |
| Daily Profit Target | $5000.0 | Mục tiêu profit mỗi ngày |
| Reset on Restart | true | Reset snapshot khi restart EA |

## Cách sử dụng

### Bước 1: Cài đặt EA
1. Copy file `Universal_DCA_Grid_EA.mq5` vào folder `MQL5/Experts/`
2. Compile EA trong MetaEditor
3. Restart MT5 nếu cần

### Bước 2: Gắn EA vào Chart
1. Kéo EA từ Navigator vào chart
2. Điều chỉnh các tham số theo ý muốn
3. Bấm OK

### Bước 3: Điều khiển EA
- Bấm **BUY** để kích hoạt grid BUY
- Bấm **SELL** để kích hoạt grid SELL
- Bấm **Close BUY/SELL** để đóng và restart
- Bấm **Deactivate BUY/SELL** để đóng và dừng hẳn

## Cách tính toán

### Tổng Lot khi Full Grid
```
Total Lot = Initial Lot × (1 + Multiplier + Multiplier² + ... + Multiplier^(n-1))
```

Với:
- Initial Lot = 1.0
- Multiplier = 1.3
- Max Levels = 22

→ Total Lot ≈ 241 lots

### Vốn cần thiết
Để tính vốn cần thiết, sử dụng công thức:
```
Required Margin = Total Lot × Contract Size × Price / Leverage
```

### Số giá có thể chịu được
```
Max Price Move = Max Levels × DCA Distance
```

Với:
- Max Levels = 22
- DCA Distance = 20 pips

→ Max Price Move = 440 pips = 44.0 giá (đối với XAUUSD)

## Lưu ý quan trọng

### ⚠️ Quản lý rủi ro
- **Không** sử dụng lot size quá lớn so với vốn
- **Luôn** tính toán tổng lot khi full grid
- **Đảm bảo** vốn đủ để chịu được tối thiểu 50% max grid levels
- **Sử dụng** Safe Fund Protection để giảm rủi ro

### ⚠️ Cài đặt Stop Loss
- Stop Loss phải là số âm (ví dụ: -20000)
- Đảm bảo Stop Loss phù hợp với vốn và rủi ro có thể chấp nhận

### ⚠️ DCA Distance
- Khoảng cách DCA quá nhỏ → Mở lệnh quá nhanh → Cháy tài khoản
- Khoảng cách DCA quá lớn → Ít lệnh → Profit thấp
- Khuyến nghị: 20-50 pips cho XAUUSD

### ⚠️ Multiplier
- Multiplier càng lớn → Lot size tăng nhanh → Rủi ro cao
- Multiplier càng nhỏ → Profit chậm → An toàn hơn
- Khuyến nghị: 1.2 - 1.5

## Ví dụ cấu hình

### Conservative (An toàn)
```
Initial Lot: 0.01
DCA Distance: 50 pips
DCA Multiplier: 1.2
Max Grid Levels: 15
Take Profit: $20
Stop Loss: -$500
```

### Moderate (Trung bình)
```
Initial Lot: 0.1
DCA Distance: 30 pips
DCA Multiplier: 1.3
Max Grid Levels: 20
Take Profit: $50
Stop Loss: -$2000
```

### Aggressive (Mạo hiểm)
```
Initial Lot: 1.0
DCA Distance: 20 pips
DCA Multiplier: 1.5
Max Grid Levels: 22
Take Profit: $100
Stop Loss: -$20000
```

## Troubleshooting

### EA không mở lệnh
- Kiểm tra AutoTrading đã bật chưa (nút Algo trên toolbar)
- Kiểm tra đã bấm BUY hoặc SELL chưa
- Kiểm tra log xem có lỗi gì không

### Lưới không đều
- Do độ trượt giá (slippage)
- Do độ trễ mạng từ máy tính đến server
- Bình thường, không ảnh hưởng nhiều

### EA không hiển thị nút
- Kiểm tra Auto Start Mode có phải là None không
- Nếu chọn Auto Start, nút sẽ bị ẩn

## Support
Nếu có vấn đề hoặc câu hỏi, vui lòng liên hệ qua GitHub Issues.

## License
MIT License

## Disclaimer
**CẢNH BÁO:** Giao dịch forex/CFD có rủi ro cao. Bạn có thể mất toàn bộ số tiền đầu tư. Chỉ giao dịch với số tiền mà bạn có thể chấp nhận mất. EA này chỉ mang tính chất tham khảo, không đảm bảo lợi nhuận. Người dùng tự chịu trách nhiệm về kết quả giao dịch.
