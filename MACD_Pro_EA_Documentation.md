# Universal MACD Pro EA - Documentation

## Overview

The **Universal MACD Pro EA** is a professional-grade trading system that significantly improves upon traditional MACD strategies. It features multi-timeframe confirmation, advanced risk management, partial profit taking, and comprehensive trade management.

---

## 🎯 Key Improvements Over Original EA

### 1. **Fixed Critical Bugs**
- ✅ Corrected sell signal logic (original had inverted conditions)
- ✅ Fixed MACD buffer indexing for MT5
- ✅ Proper position management and tracking
- ✅ Correct ternary operator usage in exit logic

### 2. **Enhanced Entry System**
- **Multi-Timeframe Confirmation**: Entry TF + Trend TF + Confirmation TF
- **RSI Filter**: Prevents entries in overbought/oversold conditions
- **Volatility Expansion**: Ensures entries during increasing volatility
- **Adaptive MACD**: Automatically adjusts periods based on market volatility
- **Flexible Entry Window**: Can enter within N bars of signal cross

### 3. **Advanced Risk Management**
- **Daily Loss Limits**: Auto-pause when daily loss exceeds threshold
- **Max Trades Per Day**: Prevents overtrading
- **Recovery Mode**: Reduces risk after drawdown (auto-activates at 50% of max DD)
- **Trading Pause**: Complete stop at maximum drawdown
- **Dynamic Position Sizing**: ATR-based lot calculation with balance risk %

### 4. **Superior Exit Strategy**
- **Partial Profit Taking**: Close 33% at TP1, 33% at TP2, rest at TP3
- **Breakeven Protection**: Auto-move SL to breakeven after TP1
- **ATR-Based Trailing Stop**: Dynamic trailing based on market volatility
- **Opposite Signal Exit**: Close on counter-trend MACD cross
- **Histogram Reversal Exit**: Exit when MACD histogram reverses
- **Time-Based Exit**: Maximum bars in trade protection

### 5. **Professional Features**
- **On-Chart Dashboard**: Real-time statistics and status
- **Session Filters**: Trade only during Asian/London/NY sessions
- **Friday Close Protection**: Avoid holding over weekend
- **News Filter**: Pause trading around high-impact news
- **Performance Tracking**: Win rate, P/L, streak tracking
- **Universal Design**: Works on any symbol (Gold, Forex, Indices)

---

## 📊 Parameter Guide

### Trading Setup
| Parameter | Default | Description |
|-----------|---------|-------------|
| EntryTimeframe | M15 | Primary timeframe for signals |
| TrendTimeframe | H1 | Higher TF for trend filter |
| ConfirmTimeframe | M5 | Lower TF for entry timing |
| TradeOnlyWithTrend | true | Require trend alignment |
| UseMultiTFConfirmation | true | Use 3-TF confirmation |

### MACD Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| MACD_Fast | 12 | Fast EMA period |
| MACD_Slow | 26 | Slow EMA period |
| MACD_Signal | 9 | Signal SMA period |
| UseAdaptiveMACD | true | Auto-adjust based on volatility |
| AdaptiveMultiplier | 0.5 | Strength of adaptation |

### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| RiskPercent | 1.0% | Risk per trade (% of balance) |
| MaxDailyRisk | 3.0% | Max daily loss before pause |
| MaxDrawdown | 8.0% | DD threshold for trading pause |
| RecoveryRiskReduction | 0.5 | Risk multiplier in recovery (50%) |
| MaxTradesPerDay | 10 | Daily trade limit |
| MaxConcurrentTrades | 1 | Max simultaneous positions |

### Partial Profits
| Parameter | Default | Description |
|-----------|---------|-------------|
| UsePartialProfits | true | Enable scale-out strategy |
| PartialClose_TP1 | 33% | Close at first target (2x ATR) |
| PartialClose_TP2 | 33% | Close at second target (4x ATR) |
| MoveToBreakevenAtTP1 | true | Protect capital after TP1 |

### ATR-Based Targets
| Parameter | Default | Description |
|-----------|---------|-------------|
| ATR_StopLoss_Multi | 2.5 | SL distance (2.5x ATR) |
| ATR_TakeProfit1_Multi | 2.0 | First target (2x ATR) |
| ATR_TakeProfit2_Multi | 4.0 | Second target (4x ATR) |
| ATR_TakeProfit3_Multi | 6.0 | Final target (6x ATR) |
| ATR_Trail_Multi | 1.5 | Trailing stop distance |

---

## 🔧 How It Works

### Entry Logic (BUY Example)

```mql5
1. MACD Cross: Main line crosses above Signal line
2. Trend Filter: H1 MACD is bullish (above zero or above signal)
3. Confirmation: M5 MACD is also bullish
4. RSI Filter: RSI < 70 (not overbought)
5. Volatility: Current ATR > Previous ATR
6. Session: Within allowed trading hours
7. News: No high-impact news within buffer
8. Risk Limits: Not exceeding daily/max trade limits
```

### Exit Logic

```mql5
Exit Sequence:
1. TP1 (2x ATR): Close 33% → Move SL to breakeven
2. TP2 (4x ATR): Close 33% of remaining
3. Trailing Stop: Update SL if price moves favorably (1.5x ATR trailing)
4. Opposite Signal: Close all if MACD crosses opposite direction
5. Histogram Reversal: Exit if histogram shows reversal (after breakeven)
6. Time Exit: Close if max bars in trade exceeded
```

---

## 📈 Recommended Settings

### XAUUSD (Gold) - M15
```
EntryTimeframe: M15
TrendTimeframe: H1
ConfirmTimeframe: M5
RiskPercent: 1.0
ATR_StopLoss_Multi: 2.5
TradeAsianSession: false
TradeLondonSession: true
TradeNYSession: true
```

### EURUSD - M15
```
EntryTimeframe: M15
TrendTimeframe: H1
ConfirmTimeframe: M5
RiskPercent: 1.0
ATR_StopLoss_Multi: 2.0
TradeAsianSession: false
TradeLondonSession: true
TradeNYSession: true
```

### GBPUSD - H1
```
EntryTimeframe: H1
TrendTimeframe: H4
ConfirmTimeframe: M15
RiskPercent: 1.0
ATR_StopLoss_Multi: 2.0
TradeAsianSession: false
TradeLondonSession: true
TradeNYSession: true
```

### US30 (Dow Jones) - M15
```
EntryTimeframe: M15
TrendTimeframe: H1
ConfirmTimeframe: M5
RiskPercent: 0.5
ATR_StopLoss_Multi: 3.0
TradeAsianSession: false
TradeLondonSession: false
TradeNYSession: true
```

---

## 🛡️ Risk Management Features

### Recovery Mode
- **Triggers at**: 50% of MaxDrawdown (default: 4% DD)
- **Action**: Reduces risk per trade by 50% (RecoveryRiskReduction)
- **Deactivates**: When DD drops below 2.4% (30% of max)
- **Purpose**: Gradual recovery without aggressive trading

### Trading Pause
- **Triggers at**: MaxDrawdown (default: 8% DD)
- **Action**: Stops all new trades, closes open positions
- **Resumes**: When DD drops below 2.4%
- **Purpose**: Capital preservation during adverse conditions

### Daily Limits
- **Max Daily Risk**: Stops trading when daily loss exceeds 3% (configurable)
- **Max Trades/Day**: Prevents overtrading (default: 10 trades)
- **Reset**: Automatically resets at start of new day

---

## 📊 Dashboard Indicators

The on-chart dashboard displays:

```
=== MACD Pro EA ===
Status: ACTIVE / RECOVERY / PAUSED
Trades: 45 (W:28 L:17)
Win Rate: 62.2%
Net P/L: +1,245.50
Drawdown: 2.3%
Today: 3 trades | +125.00
```

**Status Colors:**
- 🟢 **Green (ACTIVE)**: Normal trading
- 🟠 **Orange (RECOVERY)**: Recovery mode active
- 🔴 **Red (PAUSED)**: Trading suspended

---

## ⚙️ Installation & Setup

### 1. Installation
```
1. Copy Universal_MACD_Pro_EA.mq5 to: MT5/MQL5/Experts/
2. Restart MT5 or click "Refresh" in Navigator
3. Drag EA onto chart
4. Configure settings in Inputs tab
5. Enable "Allow Algo Trading" button
```

### 2. Recommended Chart Setup
```
- Timeframe: M15 (or your EntryTimeframe)
- Template: Clean (EA has built-in dashboard)
- Optional: Add MACD indicator for visual confirmation
  - Fast: 12, Slow: 26, Signal: 9
```

### 3. Backtesting Settings
```
- Mode: Every tick (most accurate)
- Spread: Realistic (3-5 for Gold, 1-2 for EUR/USD)
- Commission: Set your broker's commission
- Execution: Market execution
```

---

## 🔍 Troubleshooting

### EA Not Trading
1. ✅ Check "Allow Algo Trading" is enabled
2. ✅ Verify trading hours match your session filters
3. ✅ Check if Recovery/Pause mode is active
4. ✅ Ensure daily limits not exceeded
5. ✅ Verify broker allows automated trading

### Unexpected Exits
- Check if `ExitOnOppositeSignal` is true
- Verify `ExitOnHistogramReversal` setting
- Review trailing stop settings
- Check news filter timing

### Position Size Too Small/Large
- Adjust `RiskPercent` (default: 1%)
- Check account balance vs. ATR stop distance
- Verify broker's min/max lot sizes
- Review ATR_StopLoss_Multi value

---

## 📈 Performance Optimization

### Conservative Settings (Lower Risk)
```
RiskPercent: 0.5
MaxDrawdown: 5.0
TradeOnlyWithTrend: true
RequireMACD_ZeroCross: true
UseRSIFilter: true
```

### Aggressive Settings (Higher Risk)
```
RiskPercent: 2.0
MaxDrawdown: 12.0
MaxBarsFromCross: 5
RequireMACD_ZeroCross: false
UseMultiTFConfirmation: false
```

### Scalping Mode (Quick Profits)
```
ATR_TakeProfit1_Multi: 1.5
ATR_TakeProfit2_Multi: 2.5
ATR_TakeProfit3_Multi: 4.0
PartialClose_TP1: 50
PartialClose_TP2: 50
```

### Swing Trading Mode (Larger Targets)
```
EntryTimeframe: H1
TrendTimeframe: H4
ATR_TakeProfit1_Multi: 3.0
ATR_TakeProfit2_Multi: 6.0
ATR_TakeProfit3_Multi: 10.0
UseTrailingStop: true
```

---

## 🆚 Comparison: Old vs New EA

| Feature | Original EA | Universal MACD Pro |
|---------|-------------|-------------------|
| Sell Signals | ❌ Broken | ✅ Fixed & Working |
| Entry Timeframes | 1 (M15 only) | 3 (Multi-TF confirmation) |
| Exit Strategies | 2 | 6 (partial TP, trail, signals) |
| Risk Management | Basic | Advanced (daily limits, recovery) |
| Position Management | Simple | Professional (partial close) |
| Dashboard | None | ✅ Real-time stats |
| Session Filters | Friday only | Asian/London/NY |
| News Filter | NFP only | Configurable times |
| Adaptive Logic | Limited | Full ATR-based adaptation |
| Code Quality | Functional | Production-ready |

---

## 📝 Best Practices

### 1. Start Conservative
- Use 0.5-1% risk per trade initially
- Enable all filters (RSI, Trend, Multi-TF)
- Set strict daily limits

### 2. Backtest First
- Run minimum 3-6 months of data
- Test multiple market conditions
- Validate on different symbols

### 3. Monitor Performance
- Review dashboard daily
- Track recovery mode triggers
- Analyze win rate and average R:R

### 4. Gradual Optimization
- Change one parameter at a time
- Document changes and results
- Use forward testing to validate

### 5. Risk Control
- Never exceed 2% per trade
- Set MaxDrawdown conservatively
- Use VPS for 24/5 operation

---

## 📞 Support & Updates

### Version History
- **v2.00** (2025-01-22): Complete redesign with advanced features
- **v1.10** (Original): Basic MACD strategy

### Future Enhancements
- [ ] ML-based entry filtering
- [ ] Correlation matrix for multi-pair trading
- [ ] Advanced news calendar integration
- [ ] Telegram notifications
- [ ] Web dashboard integration

---

## ⚠️ Disclaimer

This EA is for educational and research purposes. Past performance does not guarantee future results. Always:
- Test on demo accounts first
- Understand the strategy completely
- Use proper risk management
- Monitor performance regularly
- Never risk more than you can afford to lose

---

## 📧 Configuration Files

See accompanying files:
- `MACD_Pro_Settings_XAUUSD.set` - Optimized for Gold
- `MACD_Pro_Settings_EURUSD.set` - Optimized for EUR/USD
- `MACD_Pro_Settings_Conservative.set` - Low-risk settings
- `MACD_Pro_Settings_Aggressive.set` - High-risk settings

---

**Happy Trading! 📈**
