# XAUUSD MACD Multi-Timeframe Trend EA

Hệ thống EA MQL5 chuyên nghiệp cho giao dịch vàng (XAUUSD) sử dụng chiến lược MACD đa khung thời gian với quản lý rủi ro hoàn chỉnh.

## Tính năng chính

### 1. Hệ thống Entry - MACD Đa khung thời gian
- ✅ Phân tích MACD trên 4 khung thời gian: M5, M15, H1, H4
- ✅ Phát hiện sườn dốc tương đồng (slope detection) bằng linear regression
- ✅ Đo động lượng (momentum) để confirm tín hiệu
- ✅ Cấu hình tối ưu cho vàng với MACD (12, 26, 9)
- ✅ Tín hiệu mua/bán khi có ít nhất 2 khung thời gian tương đồng

### 2. Quản lý rủi ro toàn diện
- ✅ **Drawdown Protection**: Tự động dừng trading khi DD vượt ngưỡng
- ✅ **Dynamic Lot Sizing**: Tính toán lot size dựa trên % risk và ATR
- ✅ **ATR-based Stop Loss**: SL linh hoạt theo biến động thị trường
- ✅ **Margin Control**: Kiểm soát margin usage, giới hạn tối đa 70%
- ✅ **Multi-tier Trailing Stop**: Breakeven + trailing theo bước

### 3. Bộ lọc thời gian (Time Filter)
- ✅ Lọc theo giờ trong ngày (Hour Filter)
- ✅ Lọc theo ngày trong tuần (Day Filter)
- ✅ Lọc theo phiên giao dịch (Asian, European, US Sessions)
- ✅ Tối ưu hóa thời gian trade cho thị trường vàng

### 4. Tích hợp Telegram
- ✅ Điều khiển EA từ xa qua bot Telegram
- ✅ Nhận thông báo tín hiệu, trade, và cảnh báo
- ✅ Các lệnh: /start, /stop, /status, /positions, /signal, /closeall, /help
- ✅ Format markdown đẹp, dễ đọc

### 5. Tích hợp Google Sheets
- ✅ Xác thực tài khoản MT5 qua Account ID
- ✅ Tracking balance, equity, profit realtime
- ✅ Lưu lịch sử giao dịch tự động
- ✅ Báo cáo thống kê chi tiết

### 6. Panel UI hiện đại
- ✅ Hiển thị thông tin realtime trên biểu đồ
- ✅ Trading status, signal strength, account info
- ✅ Risk metrics: Drawdown, Margin usage
- ✅ Time filter status
- ✅ Màu sắc trực quan: xanh (tích cực), đỏ (tiêu cực)

## Cấu trúc dự án

```
techfine/
├── XAUUSD_MACD_Trend_EA.mq5       # File EA chính
├── Include/
│   ├── MACD_MTF_Signal.mqh        # Module MACD đa khung thời gian
│   ├── RiskManager.mqh            # Module quản lý rủi ro
│   ├── TimeFilter.mqh             # Module lọc thời gian
│   ├── TelegramBot.mqh            # Module Telegram
│   ├── GoogleSheets.mqh           # Module Google Sheets
│   └── UIPanel.mqh                # Module UI Panel
├── make.mq5                       # EA phiên bản cũ (tham khảo)
└── README.md                      # File này
```

## Cài đặt

### 1. Copy files vào MT5
```
C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\[TerminalID]\MQL5\Experts\
```

Copy toàn bộ thư mục `Include` vào:
```
C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\[TerminalID]\MQL5\
```

### 2. Compile trong MetaEditor
- Mở MetaEditor (F4 trong MT5)
- Mở file `XAUUSD_MACD_Trend_EA.mq5`
- Nhấn Compile (F7)
- Kiểm tra không có lỗi

### 3. Cấu hình WebRequest (Bắt buộc cho Telegram & Google Sheets)
- Tools → Options → Expert Advisors
- Tick "Allow WebRequest for listed URL"
- Thêm URLs:
  ```
  https://api.telegram.org
  https://script.google.com
  https://script.googleusercontent.com
  ```

## Cấu hình Telegram Bot

### Bước 1: Tạo Bot
1. Mở Telegram, tìm @BotFather
2. Gửi `/newbot`
3. Đặt tên bot (ví dụ: "My Gold EA Bot")
4. Đặt username (ví dụ: "my_gold_ea_bot")
5. Lưu **Token** (dạng: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`)

### Bước 2: Lấy Chat ID
1. Tìm bot vừa tạo trên Telegram
2. Gửi tin nhắn: `/start`
3. Truy cập: `https://api.telegram.org/bot[YOUR_TOKEN]/getUpdates`
4. Tìm `"chat":{"id":123456789}` → Lưu **Chat ID**

### Bước 3: Cấu hình trong EA
- `InpTelegramToken`: Paste token từ BotFather
- `InpTelegramChatID`: Paste chat ID

## Cấu hình Google Sheets

### Bước 1: Tạo Google Sheet
1. Tạo Google Sheet mới
2. Đặt tên sheet: "TradingLog"

### Bước 2: Tạo Apps Script
1. Trong Google Sheet: Extensions → Apps Script
2. Xóa code mặc định, paste code từ file `GoogleSheets.mqh` (phần comment cuối file)
3. Deploy → New deployment → Web app
   - Execute as: Me
   - Who has access: Anyone
4. Copy **Web App URL** (dạng: `https://script.google.com/macros/s/...`)

### Bước 3: Cấu hình trong EA
- `InpGoogleScriptURL`: Paste Web App URL
- `InpGSUpdateInterval`: 300 (5 phút)

## Tham số đề xuất cho XAUUSD

### Trading Settings
```
InpSymbol = "XAUUSDc"              // Hoặc "XAUUSD"
InpMagicNumber = 202502
```

### MACD Settings (Tối ưu cho vàng)
```
InpFastEMA = 12
InpSlowEMA = 26
InpSignalSMA = 9
InpMinTimeframesMatch = 2          // 2-3 khung thời gian
```

### Risk Management (Bảo thủ)
```
InpMaxDrawdownPercent = 5.0        // Dừng ở 5% DD
InpRiskPerTradePercent = 1.0       // Risk 1% mỗi lệnh
InpMaxLotSize = 0.01               // Cent account: 0.01
InpATRPeriod = 14
InpATRMultiplier = 2.0
InpMinATR = 100
InpMaxMarginUsage = 70.0
```

### Time Filter (Trading 24/5)
```
InpUseHourFilter = false           // Tắt nếu trade cả ngày
InpUseDayFilter = false            // Tắt nếu trade cả tuần
InpUseSessionFilter = true         // Bật session filter
InpAllowAsianSession = false       // Tắt Asian (ít biến động)
InpAllowEuropeanSession = true     // Bật European
InpAllowUSSession = true           // Bật US
```

### Trailing Stop
```
InpUseTrailingStop = true
InpBreakevenPoints = 300           // 30 pips cho vàng
InpTrailingStepPoints = 100        // 10 pips step
InpMaxPositions = 5
```

## Lệnh Telegram

| Lệnh | Mô tả |
|------|-------|
| `/start` hoặc `/startEA` | Bật EA |
| `/stop` hoặc `/stopEA` | Tắt EA |
| `/status` | Xem balance, equity, margin |
| `/positions` | Xem các lệnh đang mở |
| `/signal` | Xem tín hiệu MACD hiện tại |
| `/closeall` | Đóng tất cả lệnh |
| `/help` | Danh sách lệnh |

## Chiến lược MACD Multi-Timeframe

### Nguyên lý hoạt động
1. **Thu thập dữ liệu**: MACD trên M5, M15, H1, H4
2. **Tính toán slope**: Linear regression trên 3 nến gần nhất
3. **Phát hiện trend**: Đếm số khung thời gian có slope cùng chiều
4. **Confirm momentum**: Histogram MACD tăng/giảm
5. **Signal**:
   - BUY: ≥2 khung có slope UP + momentum dương
   - SELL: ≥2 khung có slope DOWN + momentum âm

### Ví dụ
```
M5:  Slope = +0.0015 (UP)
M15: Slope = +0.0012 (UP)
H1:  Slope = +0.0008 (UP)
H4:  Slope = -0.0002 (DOWN)

→ 3/4 khung UP → Signal: BUY
```

## Testing & Optimization

### Strategy Tester
1. View → Strategy Tester
2. Select: XAUUSD_MACD_Trend_EA.ex5
3. Symbol: XAUUSD
4. Period: M5 (hoặc bất kỳ)
5. Date: 2024-01-01 đến nay
6. Optimization:
   - `InpMinTimeframesMatch`: 2-4
   - `InpATRMultiplier`: 1.5-3.0
   - `InpBreakevenPoints`: 200-500

### Backtest Tips
- Dữ liệu chất lượng cao (tick data)
- Spread thực tế (20-30 points cho vàng)
- Commission: $0 (cent account thường free)
- Test ít nhất 3-6 tháng dữ liệu

## Troubleshooting

### EA không giao dịch
- ✅ Kiểm tra `eaEnabled = true` (dùng Telegram `/start`)
- ✅ Drawdown chưa vượt ngưỡng
- ✅ Time filter cho phép (kiểm tra UI panel)
- ✅ Margin còn đủ (< 70%)
- ✅ Có tín hiệu MACD (dùng `/signal`)

### Telegram không hoạt động
- ✅ WebRequest đã enable cho `api.telegram.org`
- ✅ Token và Chat ID đúng
- ✅ Bot đã `/start` với user
- ✅ Kiểm tra Journal log

### Google Sheets không update
- ✅ WebRequest đã enable cho `script.google.com`
- ✅ Apps Script đã deploy đúng (Anyone access)
- ✅ URL đúng format
- ✅ Account ID verification passed

## Cảnh báo rủi ro

⚠️ **QUAN TRỌNG**:
- EA này là công cụ hỗ trợ, KHÔNG đảm bảo lợi nhuận
- Luôn test trên demo trước khi live
- Không sử dụng toàn bộ vốn, chỉ trade số tiền có thể chấp nhận mất
- Vàng có biến động cao, cần quản lý rủi ro chặt chẽ
- Theo dõi thường xuyên, không để EA chạy vô tội vạ

## Changelog

### Version 2.00 (2025)
- ✅ Xây dựng lại từ đầu với kiến trúc module hóa
- ✅ MACD Multi-Timeframe Signal (M5, M15, H1, H4)
- ✅ Slope detection + Momentum confirmation
- ✅ Advanced Risk Manager (DD, Margin, Dynamic Lot)
- ✅ Time Filter (Hour, Day, Session)
- ✅ Enhanced Telegram Bot
- ✅ Google Sheets Integration
- ✅ Modern UI Panel

### Version 1.01 (2024)
- Phiên bản cũ với MA crossover

## Hỗ trợ

Nếu cần hỗ trợ:
1. Kiểm tra phần **Troubleshooting**
2. Xem log trong MT5 Journal
3. Test trên Strategy Tester
4. Đọc kỹ file README này

## License

Copyright © 2025. All rights reserved.

---

**Chúc bạn giao dịch thành công!** 🚀📈
