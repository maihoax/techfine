# Universal MACD-ATR EA v1.00

Expert Advisor đa năng dựa trên MACD và ATR, được thiết kế theo best practices từ các bài viết MQL5.com để hoạt động hiệu quả trên mọi loại symbol (FX, vàng, indices, crypto) và mọi loại tài khoản (standard, cent, ECN).

---

## 📋 Tổng quan

EA Universal MACD-ATR là một hệ thống giao dịch tự động được xây dựng dựa trên 4 nguồn kiến thức chính từ MQL5.com:

1. **MACD Blueprint** ([Article 10674](https://www.mql5.com/en/articles/10674)) - Triển khai MACD đúng cách với iMACD và CopyBuffer
2. **Fast Food Made of Indicators** ([Article 4318](https://www.mql5.com/en/articles/4318)) - Kỹ thuật lấy dữ liệu indicator/series đúng chuẩn MQL5
3. **Optimizing by Balance Regression** ([Article 3642](https://www.mql5.com/en/articles/3642)) - Tiêu chí tối ưu hóa bền vững
4. **Multi-Symbol Multi-Currency** ([Article 16066](https://www.mql5.com/en/articles/16066)) - Thiết kế đa symbol và account type

### ✨ Đặc điểm chính

- **Đa dụng**: Hoạt động trên mọi symbol (EURUSD, XAUUSD, US30, BTCUSD, etc.)
- **Thích nghi tài khoản**: Tự động chuẩn hóa cho Standard, Cent, ECN
- **Context-Aware**: Nhận diện thị trường trending vs ranging, điều chỉnh chiến lược phù hợp
- **ATR-based Risk**: SL/TP tự động theo biến động thị trường
- **Quản lý vốn chặt chẽ**: Drawdown protection, margin control, position limits
- **State Machine**: Kiến trúc rõ ràng, dễ maintain và mở rộng

---

## 🏗️ Kiến trúc Module

EA được tổ chức theo kiến trúc module hóa với 4 module chính:

### 1. **Indicators.mqh** - Quản lý chỉ báo
```
Include/Universal/Indicators.mqh
```

**Chức năng:**
- Wrapper cho iMACD và iATR với handle management đúng chuẩn
- ArraySetAsSeries và CopyBuffer theo best practices
- Các hàm tiện ích: crossover, zero-line cross, histogram momentum
- Kiểm tra lỗi đầy đủ

**Class:** `CUniversalIndicators`

**Methods chính:**
- `Init()` - Khởi tạo indicators
- `Update()` - Cập nhật buffers
- `GetMACDValues()` - Lấy MACD main/signal/histogram
- `GetATRValue()` - Lấy ATR
- `IsBullishCross()` / `IsBearishCross()` - Phát hiện crossover
- `IsZeroLineCrossUp()` / `IsZeroLineCrossDown()` - Zero-line cross
- `GetHistogramMomentum()` - Đo momentum histogram

### 2. **Signals.mqh** - Logic tín hiệu
```
Include/Universal/Signals.mqh
```

**Chức năng:**
- Market context detection (Trending/Ranging)
- Signal generation dựa theo context
- Pullback entry detection
- ATR filter cho volatility
- Zero-line alignment
- Histogram expansion filter

**Class:** `CUniversalSignals`

**Methods chính:**
- `Init()` - Khởi tạo với indicator reference
- `UpdateContext()` - Phân tích context (gọi mỗi bar mới)
- `GetSignal()` - Lấy tín hiệu giao dịch
- `GetTrendingSignal()` - Tín hiệu cho thị trường trending
- `GetRangingSignal()` - Tín hiệu cho thị trường ranging
- `ShouldExit()` - Kiểm tra điều kiện thoát
- `GetSignalStrength()` - Độ mạnh tín hiệu (0-100%)

**Context Detection Logic:**
- **Trending**: MACD ở cùng phía trục 0 trong >= 70% bars gần đây
- **Ranging**: MACD dao động qua trục 0 trong >= 50% bars gần đây

### 3. **Risk.mqh** - Quản lý rủi ro
```
Include/Universal/Risk.mqh
```

**Chức năng:**
- Position sizing theo % equity và ATR
- Chuẩn hóa cho mọi symbol (tick value, tick size normalization)
- Account type detection (Cent vs Standard)
- SL/TP calculation theo ATR
- Margin management với OrderCalcMargin
- Drawdown protection
- Position limits

**Class:** `CUniversalRisk`

**Methods chính:**
- `Init()` - Khởi tạo risk manager
- `CalculateLotSize()` - Tính lot size dựa trên risk % và SL points
- `CalculateStopLossPoints()` - Tính SL theo ATR
- `CalculateTakeProfitPoints()` - Tính TP theo ATR
- `CalculateBuySL()` / `CalculateSellSL()` - Giá SL cho Buy/Sell
- `CalculateBuyTP()` / `CalculateSellTP()` - Giá TP cho Buy/Sell
- `IsTradingAllowed()` - Kiểm tra drawdown limit
- `IsMarginAvailable()` - Kiểm tra margin availability
- `CanOpenPosition()` - Kiểm tra position limits

**Risk Formula:**
```
Lot Size = (Equity × Risk%) / (SL Points × Point Value)
SL Points = ATR × Multiplier
Point Value = (Tick Value / Tick Size) × Point
```

### 4. **Orders.mqh** - Quản lý lệnh
```
Include/Universal/Orders.mqh
```

**Chức năng:**
- CTrade wrapper với error handling
- ECN mode support (SL/TP sau khi fill)
- Auto-detect execution mode
- Trailing stop function
- Breakeven function
- Position close (single/all)
- Statistics tracking

**Class:** `CUniversalOrders`

**Methods chính:**
- `Init()` - Khởi tạo order manager
- `OpenBuy()` / `OpenSell()` - Mở lệnh Buy/Sell
- `ModifyPosition()` - Sửa SL/TP
- `ClosePosition()` - Đóng lệnh
- `CloseAllPositions()` - Đóng tất cả lệnh
- `TrailingStop()` - Trailing stop cho position
- `MoveToBreakeven()` - Chuyển SL về breakeven
- `GetPositionsCount()` - Đếm số lệnh đang mở

---

## 🎯 Chiến lược giao dịch

### Entry Logic

#### Trending Market
- **Buy Signal:**
  - MACD main cross lên MACD signal
  - MACD main > 0 (bullish bias)
  - Histogram đang expanding (momentum tăng)
  - ATR >= minimum threshold

- **Sell Signal:**
  - MACD main cross xuống MACD signal
  - MACD main < 0 (bearish bias)
  - Histogram đang expanding (momentum tăng)
  - ATR >= minimum threshold

- **Pullback Entry:** Cho phép vào lệnh khi histogram contract rồi re-expand (momentum recovery)

#### Ranging Market
- Giảm tần suất giao dịch
- Yêu cầu zero-line cross để tăng độ tin cậy
- Không vào lệnh khi MACD dao động nhỏ quanh 0

### Exit Logic

1. **Take Profit:** ATR × TP Multiplier (default: 3.0)
2. **Stop Loss:** ATR × SL Multiplier (default: 2.0)
3. **Trailing Stop:** Theo điểm (configurable)
4. **Breakeven:** Khi đạt activation points
5. **Signal Exit:** MACD cross ngược chiều hoặc histogram contracting mạnh

---

## ⚙️ Cài đặt

1. **Copy files vào thư mục MT5:**
   ```
   MQL5/
   ├── Experts/
   │   └── UniversalMACDATR_EA.mq5
   └── Include/
       └── Universal/
           ├── Indicators.mqh
           ├── Signals.mqh
           ├── Risk.mqh
           └── Orders.mqh
   ```

2. **Compile EA:**
   - Mở MetaEditor
   - Mở file `UniversalMACDATR_EA.mq5`
   - Nhấn F7 hoặc Compile button
   - Kiểm tra không có lỗi

3. **Attach vào chart:**
   - Mở chart symbol muốn trade
   - Kéo EA từ Navigator vào chart
   - Cấu hình tham số (xem bên dưới)
   - Enable AutoTrading

---

## 📊 Cấu hình tham số

### General Settings
- **Magic Number** (100001): Số magic để phân biệt lệnh của EA
- **Trade Comment**: Comment cho lệnh

### MACD Settings
- **MACD Fast EMA** (12): Chu kỳ EMA nhanh
- **MACD Slow EMA** (26): Chu kỳ EMA chậm
- **MACD Signal SMA** (9): Chu kỳ Signal line

**Khuyến nghị:**
- FX Major: 12/26/9 (standard)
- Gold: 8/17/9 (nhanh hơn)
- Indices: 12/26/9
- Crypto: 6/13/5 (rất nhanh do volatility cao)

### ATR Settings
- **ATR Period** (14): Chu kỳ ATR
- **ATR Multiplier SL** (2.0): Nhân ATR cho SL
- **ATR Multiplier TP** (3.0): Nhân ATR cho TP
- **Min ATR Points** (0): ATR tối thiểu để trade (0=auto)

**Khuyến nghị:**
- Thị trường ổn định: SL=2.0, TP=3.0
- Thị trường biến động: SL=2.5, TP=4.0
- Range market: SL=1.5, TP=2.0

### Risk Management
- **Risk per Trade %** (1.0): Rủi ro mỗi lệnh (% equity)
- **Max Lot Size** (1.0): Lot tối đa
- **Max Drawdown %** (10.0): Drawdown tối đa (dừng trade)
- **Max Margin %** (50.0): Margin usage tối đa
- **Max Positions** (3): Số lệnh tối đa
- **Max Positions per Symbol** (1): Số lệnh tối đa mỗi symbol

**Khuyến nghị:**
- Conservative: Risk 0.5-1%, MaxDD 5-10%
- Moderate: Risk 1-2%, MaxDD 10-15%
- Aggressive: Risk 2-3%, MaxDD 15-20%

### Signal Settings
- **Context Bars** (10): Số bar để phân tích context
- **Require Zero Align**: Yêu cầu MACD đúng phía trục 0
- **Require Hist Expand**: Yêu cầu histogram expanding
- **Allow Pullback Entry**: Cho phép vào lệnh pullback
- **Min Bars Between Signals** (3): Khoảng cách tối thiểu giữa tín hiệu

### Trade Management
- **Use Trailing**: Bật trailing stop
- **Trailing Points** (200): Khoảng cách trailing (points)
- **Trailing Step** (50): Bước di chuyển trailing (points)
- **Use Breakeven**: Bật breakeven
- **Breakeven Points** (150): Kích hoạt breakeven (points)
- **Breakeven Lock** (10): Lock profit khi breakeven (points)

---

## 🎓 Tối ưu hóa

### Strategy Tester Settings

1. **Period**: Chọn đủ dài (ít nhất 1 năm historical data)
2. **Optimization Mode**: Custom max hoặc Balance
3. **Forward Testing**: Bật, tỷ lệ 1/2 hoặc 1/3

### Parameters to Optimize

**Priority 1 (Quan trọng nhất):**
- Risk per Trade % (0.5 - 3.0, step 0.5)
- ATR Multiplier SL (1.5 - 3.0, step 0.5)
- ATR Multiplier TP (2.0 - 5.0, step 0.5)

**Priority 2:**
- MACD Fast (8 - 16, step 2)
- MACD Slow (20 - 32, step 4)
- Context Bars (5 - 20, step 5)

**Priority 3:**
- Trailing Points
- Breakeven Points
- Max Positions

### Custom Optimization Criterion

Theo Article 3642, sử dụng balance regression để tránh overfit:

```
Custom = Balance - (MaxDrawdown × PenaltyFactor)
```

Hoặc dùng MAR ratio:
```
MAR = CAGR / MaxDrawdown%
```

### Multi-Symbol Optimization

1. **Group similar assets:**
   - FX Majors (EURUSD, GBPUSD, etc.)
   - Gold/Silver
   - Indices (US30, NASDAQ, etc.)
   - Crypto (BTCUSD, ETHUSD, etc.)

2. **Optimize separately** cho mỗi nhóm
3. **Test cross-validation** trên symbols khác trong nhóm
4. **Forward test** ít nhất 3-6 tháng

---

## 💡 Best Practices

### 1. Trước khi Live
- ✅ Backtest ít nhất 1 năm data với quality 99%
- ✅ Forward test ít nhất 3-6 tháng
- ✅ Demo test ít nhất 1 tháng
- ✅ Kiểm tra spread và commission thực tế
- ✅ Test với VPS nếu dùng VPS

### 2. Risk Management
- ✅ Không risk quá 2% mỗi trade
- ✅ Tổng risk tất cả trades không quá 6%
- ✅ Set Max Drawdown phù hợp với risk tolerance
- ✅ Monitor margin level (không dưới 200%)
- ✅ Có capital dự phòng

### 3. Symbol Selection
- ✅ Chọn symbol có spread thấp
- ✅ Liquidity tốt (không gap thường xuyên)
- ✅ Commission hợp lý
- ✅ Trading hours phù hợp

### 4. Timeframe Selection
- ✅ M15/H1: Cho FX majors (balance frequency vs quality)
- ✅ M5/M15: Cho Gold (volatility cao)
- ✅ H1/H4: Cho indices
- ✅ M15/H1: Cho crypto

### 5. Monitoring
- ✅ Check daily: Drawdown, profit, open positions
- ✅ Check weekly: Performance metrics, context detection accuracy
- ✅ Adjust khi market regime thay đổi
- ✅ Stop EA nếu unusual behavior

---

## 🔧 Troubleshooting

### EA không mở lệnh

**Check:**
1. Drawdown có vượt limit không? → Giảm MaxDrawdown hoặc reset peak equity
2. Margin có đủ không? → Giảm lot size hoặc close một số lệnh
3. ATR có thấp hơn MinATR không? → Giảm MinATRPoints hoặc chờ volatility tăng
4. Context có đang Ranging không? → Bình thường, EA giảm trade trong ranging
5. Có đủ bars history không? → Đảm bảo chart có đủ data

### Lot size quá nhỏ

**Fix:**
1. Tăng Risk per Trade %
2. Giảm ATR Multiplier SL (nhưng cẩn thận, SL sẽ gần hơn)
3. Kiểm tra account balance có đủ lớn không

### Trailing stop không hoạt động

**Check:**
1. Use Trailing có enabled không?
2. Trailing Points có phù hợp với symbol không? (convert sang pips)
3. Position có đủ profit để trailing chưa?

### Lệnh bị reject

**Check:**
1. Spread có quá rộng không? → Trade khi spread thấp
2. SL/TP có vi phạm stop level không? → Tăng ATR multiplier
3. Lot size có đúng lot step không? → EA tự normalize, nhưng check symbol specs
4. ECN broker có yêu cầu modify SL/TP sau không? → EA tự detect

### Performance kém

**Check:**
1. Backtest period có representative không?
2. Có overfit không? → Làm forward test
3. Market regime có thay đổi không? → Re-optimize
4. Spread/commission trong test có match live không?

---

## 📈 Metrics để đánh giá

### Essential Metrics
- **Win Rate**: >= 40% (MACD crossover thường 35-50%)
- **Profit Factor**: >= 1.5
- **Max Drawdown**: <= Risk tolerance (e.g., 10%)
- **Recovery Factor**: >= 2.0
- **Sharpe Ratio**: >= 0.5

### Advanced Metrics
- **MAR Ratio** (CAGR/MaxDD): >= 0.5
- **Ulcer Index**: Thấp hơn = tốt hơn
- **Consistency** (số tháng profit / tổng tháng): >= 60%
- **Balance Curve R²**: >= 0.7 (straight line growth)

### Context Metrics
- **Trending Win Rate**: Nên cao hơn Ranging Win Rate
- **Ranging Trades**: Nên ít hơn Trending Trades
- **Pullback Entry Win Rate**: So với normal entry

---

## 📚 Tài liệu tham khảo

1. [MACD Trading Strategies](https://www.mql5.com/en/articles/10674)
2. [Fast Food Made of Indicators](https://www.mql5.com/en/articles/4318)
3. [Evaluating the Efficiency of Optimization](https://www.mql5.com/en/articles/3642)
4. [Multi-Symbol Multi-Currency EA](https://www.mql5.com/en/articles/16066)

---

## 🔐 Disclaimer

EA này được phát triển cho mục đích giáo dục và testing. Không có đảm bảo về profit trong live trading. Luôn:
- Test kỹ trước khi live
- Chỉ trade với vốn có thể chấp nhận mất
- Hiểu rõ risk management
- Tuân thủ quy định broker và địa phương

---

## 📝 Version History

### v1.00 (2025-01-15)
- Initial release
- MACD + ATR based strategy
- Context detection (Trending/Ranging)
- Universal symbol/account support
- Full risk management
- Trailing stop & breakeven
- State machine architecture

---

## 👨‍💻 Support

Nếu có vấn đề hoặc câu hỏi:
1. Đọc kỹ phần Troubleshooting
2. Check logs trong MT5 Expert tab
3. Verify tất cả settings
4. Test trên demo account trước

**Happy Trading!** 📊💰
