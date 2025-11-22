//+------------------------------------------------------------------+
//|                                    Universal_MACD_Pro_EA.mq5     |
//|                        Professional Multi-Timeframe MACD System  |
//|                        Enhanced Risk, Modular Architecture       |
//+------------------------------------------------------------------+
#property copyright "TechFine Trading Systems"
#property version   "2.00"
#property strict
#property description "Universal MACD Pro: Multi-TF confirmation, partial profits, advanced risk"
#property description "Works on any symbol, any timeframe - Gold/Forex optimized"

//---- Input Parameters: TRADING SETUP ------------------------------
input group "=== TRADING SETUP ==="
input ENUM_TIMEFRAMES EntryTimeframe     = PERIOD_M15;   // Entry Timeframe
input ENUM_TIMEFRAMES TrendTimeframe     = PERIOD_H1;    // Trend Filter Timeframe
input ENUM_TIMEFRAMES ConfirmTimeframe   = PERIOD_M5;    // Confirmation Timeframe
input bool   TradeOnlyWithTrend          = true;         // Require Trend Alignment
input bool   UseMultiTFConfirmation      = true;         // Multi-TF Confirmation

//---- Input Parameters: INDICATORS ---------------------------------
input group "=== MACD SETTINGS ==="
input int    MACD_Fast                   = 12;           // MACD Fast EMA
input int    MACD_Slow                   = 26;           // MACD Slow EMA
input int    MACD_Signal                 = 9;            // MACD Signal SMA
input bool   UseAdaptiveMACD             = true;         // Adaptive MACD Periods
input double AdaptiveMultiplier          = 0.5;          // Adaptive Strength (0-1)

input group "=== RSI FILTER ==="
input bool   UseRSIFilter                = true;         // Enable RSI Filter
input int    RSI_Period                  = 14;           // RSI Period
input int    RSI_Overbought              = 70;           // RSI Overbought Level
input int    RSI_Oversold                = 30;           // RSI Oversold Level

input group "=== ATR SETTINGS ==="
input int    ATR_Period                  = 14;           // ATR Period
input double ATR_StopLoss_Multi          = 2.5;          // SL: ATR Multiplier
input double ATR_TakeProfit1_Multi       = 2.0;          // TP1: ATR Multiplier
input double ATR_TakeProfit2_Multi       = 4.0;          // TP2: ATR Multiplier
input double ATR_TakeProfit3_Multi       = 6.0;          // TP3: ATR Multiplier
input double ATR_Trail_Multi             = 1.5;          // Trail: ATR Multiplier

//---- Input Parameters: RISK MANAGEMENT ----------------------------
input group "=== RISK MANAGEMENT ==="
input double RiskPercent                 = 1.0;          // Risk Per Trade (%)
input double MaxDailyRisk                = 3.0;          // Max Daily Loss (%)
input double MaxDrawdown                 = 8.0;          // Max Drawdown Pause (%)
input double RecoveryRiskReduction       = 0.5;          // Risk Reduction in Recovery Mode
input int    MaxTradesPerDay             = 10;           // Max Trades Per Day
input int    MaxConcurrentTrades         = 1;            // Max Concurrent Positions

//---- Input Parameters: PARTIAL PROFITS ----------------------------
input group "=== PARTIAL PROFIT TAKING ==="
input bool   UsePartialProfits           = true;         // Enable Partial Profits
input double PartialClose_TP1            = 33.0;         // Close % at TP1
input double PartialClose_TP2            = 33.0;         // Close % at TP2 (of remaining)
input bool   MoveToBreakevenAtTP1        = true;         // Breakeven After TP1

//---- Input Parameters: TRADING SESSIONS ---------------------------
input group "=== SESSION FILTERS ==="
input bool   TradeAsianSession           = false;        // Trade Asian (00-08 GMT)
input bool   TradeLondonSession          = true;         // Trade London (08-16 GMT)
input bool   TradeNYSession              = true;         // Trade NY (13-21 GMT)
input bool   AvoidFridayAfter            = true;         // Avoid Friday After Hour
input int    FridayCloseHour             = 20;           // Friday Close Hour (GMT)

//---- Input Parameters: NEWS FILTER --------------------------------
input group "=== NEWS FILTER ==="
input bool   UseNewsFilter               = true;         // Enable News Filter
input int    NewsBufferMinutes           = 60;           // Minutes Before/After News

//---- Input Parameters: SIGNAL FILTERS -----------------------------
input group "=== ENTRY FILTERS ==="
input bool   RequireVolatilityExpansion  = true;         // Require Vol Expansion
input bool   RequireMACD_ZeroCross       = false;        // Require Zero Line Cross
input double MinMACDHistogram            = 0.0;          // Min Histogram Value (0=off)
input int    MaxBarsFromCross            = 3;            // Max Bars Since Cross

//---- Input Parameters: EXIT STRATEGY ------------------------------
input group "=== EXIT STRATEGY ==="
input bool   ExitOnOppositeSignal        = true;         // Exit on Opposite Signal
input bool   ExitOnHistogramReversal     = true;         // Exit on Histo Reversal
input bool   UseTrailingStop             = true;         // Enable Trailing Stop
input bool   UseTimeBasedExit            = false;        // Enable Time Exit
input int    MaxBarsInTrade              = 100;          // Max Bars in Trade

//---- Input Parameters: SYSTEM -------------------------------------
input group "=== SYSTEM ==="
input ulong  MagicNumber                 = 202512001;    // Magic Number
input string TradeComment                = "MACD_Pro";   // Trade Comment
input bool   ShowDashboard               = true;         // Show Dashboard
input int    DashboardCorner             = 1;            // Corner (0-3)
input color  DashboardColor              = clrLimeGreen; // Dashboard Color

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
// Indicator handles
int handle_ATR, handle_RSI;
int handle_MACD_Entry, handle_MACD_Trend, handle_MACD_Confirm;

// Trade tracking
datetime lastBarTime;
datetime lastTradeTime;
int      todayTrades = 0;
double   todayPnL = 0.0;
double   startDayBalance = 0.0;
bool     recoveryMode = false;
bool     tradingPaused = false;

// Symbol info cache
double tickSize, tickValue, pointValue;
double minLot, maxLot, lotStep;

// Performance tracking
struct TradeStats {
    int    totalTrades;
    int    winTrades;
    int    lossTrades;
    double totalProfit;
    double totalLoss;
    double largestWin;
    double largestLoss;
    double currentStreak;
};
TradeStats stats;

// Position tracking structure
struct PositionInfo {
    ulong  ticket;
    double openPrice;
    double initialLots;
    double currentLots;
    int    tp1Hit;
    int    tp2Hit;
    bool   atBreakeven;
    datetime openTime;
};
PositionInfo currentPosition;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    handle_ATR = iATR(_Symbol, EntryTimeframe, ATR_Period);
    handle_RSI = iRSI(_Symbol, EntryTimeframe, RSI_Period, PRICE_CLOSE);

    handle_MACD_Entry = iMACD(_Symbol, EntryTimeframe, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
    handle_MACD_Trend = iMACD(_Symbol, TrendTimeframe, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
    handle_MACD_Confirm = iMACD(_Symbol, ConfirmTimeframe, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);

    // Validate handles
    if(handle_ATR == INVALID_HANDLE || handle_RSI == INVALID_HANDLE ||
       handle_MACD_Entry == INVALID_HANDLE || handle_MACD_Trend == INVALID_HANDLE ||
       handle_MACD_Confirm == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicator handles");
        return INIT_FAILED;
    }

    // Initialize symbol properties
    if(!InitializeSymbolInfo())
    {
        Print("ERROR: Failed to initialize symbol info");
        return INIT_FAILED;
    }

    // Initialize tracking
    lastBarTime = iTime(_Symbol, EntryTimeframe, 0);
    startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    ResetDailyCounters();

    // Load statistics
    LoadStatistics();

    // Set timer for monitoring
    EventSetTimer(60);

    Print("=== Universal MACD Pro EA Initialized ===");
    Print("Symbol: ", _Symbol, " | Entry TF: ", EnumToString(EntryTimeframe));
    Print("Risk: ", RiskPercent, "% | Max DD: ", MaxDrawdown, "%");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicators
    IndicatorRelease(handle_ATR);
    IndicatorRelease(handle_RSI);
    IndicatorRelease(handle_MACD_Entry);
    IndicatorRelease(handle_MACD_Trend);
    IndicatorRelease(handle_MACD_Confirm);

    // Kill timer
    EventKillTimer();

    // Clean dashboard
    if(ShowDashboard) DeleteDashboard();

    // Save statistics
    SaveStatistics();

    Print("=== Universal MACD Pro EA Stopped ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Update dashboard
    if(ShowDashboard) UpdateDashboard();

    // Check if trading is allowed
    if(!IsTradingAllowed()) {
        ManageOpenPositions(); // Still manage exits
        return;
    }

    // Manage existing positions
    if(HasOpenPosition()) {
        ManageOpenPositions();
        return;
    }

    // Check for new bar
    if(!IsNewBar(EntryTimeframe)) return;

    // Look for entry signals
    CheckForEntrySignals();
}

//+------------------------------------------------------------------+
//| Timer function for monitoring                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Check drawdown
    CheckDrawdown();

    // Reset daily counters at new day
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    static int lastDay = -1;
    if(dt.day != lastDay) {
        ResetDailyCounters();
        lastDay = dt.day;
    }
}

//+------------------------------------------------------------------+
//| Initialize symbol information                                    |
//+------------------------------------------------------------------+
bool InitializeSymbolInfo()
{
    tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if(tickValue <= 0 || tickSize <= 0) {
        Print("ERROR: Invalid symbol tick data");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                          |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES tf)
{
    datetime currentBar = iTime(_Symbol, tf, 0);
    if(currentBar != lastBarTime) {
        lastBarTime = currentBar;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
    // Check if paused
    if(tradingPaused) {
        return false;
    }

    // Check recovery mode
    if(recoveryMode) {
        // In recovery, only allow trades with reduced risk
        Print("INFO: Recovery mode active - reduced risk");
    }

    // Check max concurrent trades
    if(CountOpenPositions() >= MaxConcurrentTrades) {
        return false;
    }

    // Check daily limits
    if(todayTrades >= MaxTradesPerDay) {
        return false;
    }

    // Check daily loss limit
    double dailyPnL = CalculateDailyPnL();
    if(dailyPnL <= -MaxDailyRisk * startDayBalance / 100.0) {
        Print("WARNING: Daily loss limit reached");
        tradingPaused = true;
        return false;
    }

    // Check session filters
    if(!IsAllowedSession()) {
        return false;
    }

    // Check news filter
    if(UseNewsFilter && IsNewsTime()) {
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Check if current session is allowed                              |
//+------------------------------------------------------------------+
bool IsAllowedSession()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    // Friday filter
    if(AvoidFridayAfter && dt.day_of_week == 5 && dt.hour >= FridayCloseHour) {
        return false;
    }

    int hour = dt.hour;

    // Asian: 00-08
    if(hour >= 0 && hour < 8) return TradeAsianSession;

    // London: 08-16
    if(hour >= 8 && hour < 16) return TradeLondonSession;

    // NY: 13-21 (overlaps with London)
    if(hour >= 13 && hour < 21) return TradeNYSession;

    return false;
}

//+------------------------------------------------------------------+
//| Check if news time (simplified - real implementation needs calendar)|
//+------------------------------------------------------------------+
bool IsNewsTime()
{
    // Simplified news filter - check economic calendar
    // In production, use CalendarValueByEvent or external news feed

    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    // Avoid typical high-impact news times (8:30, 10:00, 14:00, 15:30 GMT)
    int minute = dt.hour * 60 + dt.min;
    int newsBuffer = NewsBufferMinutes;

    int newsTimes[] = {510, 600, 840, 930}; // 8:30, 10:00, 14:00, 15:30 in minutes

    for(int i = 0; i < ArraySize(newsTimes); i++) {
        if(MathAbs(minute - newsTimes[i]) <= newsBuffer) {
            return true;
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckForEntrySignals()
{
    // Get current ATR
    double atr[];
    if(CopyBuffer(handle_ATR, 0, 0, 2, atr) < 2) return;
    ArraySetAsSeries(atr, true);

    // Get adaptive MACD periods if enabled
    int fast = MACD_Fast;
    int slow = MACD_Slow;

    if(UseAdaptiveMACD) {
        CalculateAdaptiveMACD(atr[0], fast, slow);
    }

    // Get MACD values for entry timeframe
    double macd_main[], macd_signal[], macd_histo[];
    if(!GetMACDValues(handle_MACD_Entry, 3, macd_main, macd_signal, macd_histo)) return;

    // Get trend timeframe MACD if required
    double macd_trend[], signal_trend[], histo_trend[];
    if(TradeOnlyWithTrend) {
        if(!GetMACDValues(handle_MACD_Trend, 2, macd_trend, signal_trend, histo_trend)) return;
    }

    // Get confirmation timeframe MACD if required
    double macd_confirm[], signal_confirm[], histo_confirm[];
    if(UseMultiTFConfirmation) {
        if(!GetMACDValues(handle_MACD_Confirm, 2, macd_confirm, signal_confirm, histo_confirm)) return;
    }

    // Get RSI if filter enabled
    double rsi[];
    if(UseRSIFilter) {
        if(CopyBuffer(handle_RSI, 0, 0, 2, rsi) < 2) return;
        ArraySetAsSeries(rsi, true);
    }

    // Check for BUY signal
    if(IsBuySignal(macd_main, macd_signal, macd_histo,
                   macd_trend, signal_trend, histo_trend,
                   macd_confirm, signal_confirm, histo_confirm,
                   rsi, atr)) {
        ExecuteBuy(atr[0]);
    }
    // Check for SELL signal
    else if(IsSellSignal(macd_main, macd_signal, macd_histo,
                         macd_trend, signal_trend, histo_trend,
                         macd_confirm, signal_confirm, histo_confirm,
                         rsi, atr)) {
        ExecuteSell(atr[0]);
    }
}

//+------------------------------------------------------------------+
//| Calculate adaptive MACD periods                                  |
//+------------------------------------------------------------------+
void CalculateAdaptiveMACD(double currentATR, int &fast, int &slow)
{
    // Get longer-term ATR for comparison
    double atrLong[];
    if(CopyBuffer(handle_ATR, 0, 0, 100, atrLong) < 100) return;

    double avgATR = 0;
    for(int i = 0; i < 100; i++) avgATR += atrLong[i];
    avgATR /= 100.0;

    if(avgATR <= 0) return;

    // Calculate adaptation factor (0.5 to 2.0)
    double adaptFactor = currentATR / avgATR;
    adaptFactor = MathMax(0.5, MathMin(2.0, adaptFactor));

    // Adjust periods inversely (high volatility = shorter periods)
    double adjustment = 1.0 + (1.0 - adaptFactor) * AdaptiveMultiplier;

    fast = (int)MathRound(MACD_Fast * adjustment);
    slow = (int)MathRound(MACD_Slow * adjustment);

    fast = MathMax(5, MathMin(30, fast));
    slow = MathMax(15, MathMin(60, slow));
}

//+------------------------------------------------------------------+
//| Get MACD values into arrays                                      |
//+------------------------------------------------------------------+
bool GetMACDValues(int handle, int count, double &main[], double &signal[], double &histo[])
{
    if(CopyBuffer(handle, 0, 0, count, main) < count) return false;
    if(CopyBuffer(handle, 1, 0, count, signal) < count) return false;
    if(CopyBuffer(handle, 2, 0, count, histo) < count) return false; // Histogram is buffer 2 in MT5 MACD

    ArraySetAsSeries(main, true);
    ArraySetAsSeries(signal, true);
    ArraySetAsSeries(histo, true);

    return true;
}

//+------------------------------------------------------------------+
//| Check for BUY signal                                             |
//+------------------------------------------------------------------+
bool IsBuySignal(const double &macd[], const double &signal[], const double &histo[],
                 const double &macd_trend[], const double &signal_trend[], const double &histo_trend[],
                 const double &macd_confirm[], const double &signal_confirm[], const double &histo_confirm[],
                 const double &rsi[], const double &atr[])
{
    // 1. MACD Cross: Main crosses above Signal
    bool macdCross = (macd[0] > signal[0] && macd[1] <= signal[1]);

    // Allow entry within MaxBarsFromCross
    if(!macdCross && MaxBarsFromCross > 0) {
        for(int i = 1; i <= MaxBarsFromCross; i++) {
            if(i >= ArraySize(macd)) break;
            if(macd[i] > signal[i] && macd[i+1] <= signal[i+1]) {
                macdCross = true;
                break;
            }
        }
    }

    if(!macdCross) return false;

    // 2. MACD Position: Above zero if required
    if(RequireMACD_ZeroCross && macd[0] <= 0) return false;

    // 3. Histogram: Positive and above minimum
    if(histo[0] <= MinMACDHistogram) return false;

    // 4. Trend alignment
    if(TradeOnlyWithTrend) {
        if(macd_trend[0] <= 0 || macd_trend[0] <= signal_trend[0]) return false;
    }

    // 5. Multi-TF confirmation
    if(UseMultiTFConfirmation) {
        if(macd_confirm[0] <= signal_confirm[0]) return false;
    }

    // 6. RSI filter: Not overbought
    if(UseRSIFilter) {
        if(rsi[0] >= RSI_Overbought) return false;
    }

    // 7. Volatility expansion
    if(RequireVolatilityExpansion) {
        if(atr[0] <= atr[1]) return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Check for SELL signal                                            |
//+------------------------------------------------------------------+
bool IsSellSignal(const double &macd[], const double &signal[], const double &histo[],
                  const double &macd_trend[], const double &signal_trend[], const double &histo_trend[],
                  const double &macd_confirm[], const double &signal_confirm[], const double &histo_confirm[],
                  const double &rsi[], const double &atr[])
{
    // 1. MACD Cross: Main crosses below Signal
    bool macdCross = (macd[0] < signal[0] && macd[1] >= signal[1]);

    // Allow entry within MaxBarsFromCross
    if(!macdCross && MaxBarsFromCross > 0) {
        for(int i = 1; i <= MaxBarsFromCross; i++) {
            if(i >= ArraySize(macd)) break;
            if(macd[i] < signal[i] && macd[i+1] >= signal[i+1]) {
                macdCross = true;
                break;
            }
        }
    }

    if(!macdCross) return false;

    // 2. MACD Position: Below zero if required
    if(RequireMACD_ZeroCross && macd[0] >= 0) return false;

    // 3. Histogram: Negative and below minimum
    if(histo[0] >= -MinMACDHistogram) return false;

    // 4. Trend alignment
    if(TradeOnlyWithTrend) {
        if(macd_trend[0] >= 0 || macd_trend[0] >= signal_trend[0]) return false;
    }

    // 5. Multi-TF confirmation
    if(UseMultiTFConfirmation) {
        if(macd_confirm[0] >= signal_confirm[0]) return false;
    }

    // 6. RSI filter: Not oversold
    if(UseRSIFilter) {
        if(rsi[0] <= RSI_Oversold) return false;
    }

    // 7. Volatility expansion
    if(RequireVolatilityExpansion) {
        if(atr[0] <= atr[1]) return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Execute BUY trade                                                |
//+------------------------------------------------------------------+
void ExecuteBuy(double atr)
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = price - ATR_StopLoss_Multi * atr;
    double tp1 = price + ATR_TakeProfit1_Multi * atr;
    double tp2 = price + ATR_TakeProfit2_Multi * atr;
    double tp3 = price + ATR_TakeProfit3_Multi * atr;

    // Calculate lot size
    double lots = CalculateLotSize(atr);
    if(lots < minLot) {
        Print("ERROR: Calculated lot size too small: ", lots);
        return;
    }

    // Normalize prices
    sl = NormalizeDouble(sl, _Digits);
    tp1 = NormalizeDouble(tp1, _Digits);
    tp2 = NormalizeDouble(tp2, _Digits);
    tp3 = NormalizeDouble(tp3, _Digits);

    // Open position
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lots;
    request.type = ORDER_TYPE_BUY;
    request.price = price;
    request.sl = sl;
    request.tp = UsePartialProfits ? 0 : tp3; // No TP if using partials
    request.deviation = 30;
    request.magic = MagicNumber;
    request.comment = TradeComment;

    if(!OrderSend(request, result)) {
        Print("ERROR: Buy order failed. Error: ", result.retcode, " - ", result.comment);
        return;
    }

    if(result.retcode == TRADE_RETCODE_DONE) {
        Print("SUCCESS: BUY executed at ", price, " | Lot: ", lots, " | SL: ", sl);

        // Track position
        currentPosition.ticket = result.order;
        currentPosition.openPrice = price;
        currentPosition.initialLots = lots;
        currentPosition.currentLots = lots;
        currentPosition.tp1Hit = 0;
        currentPosition.tp2Hit = 0;
        currentPosition.atBreakeven = false;
        currentPosition.openTime = TimeCurrent();

        todayTrades++;
        lastTradeTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Execute SELL trade                                               |
//+------------------------------------------------------------------+
void ExecuteSell(double atr)
{
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = price + ATR_StopLoss_Multi * atr;
    double tp1 = price - ATR_TakeProfit1_Multi * atr;
    double tp2 = price - ATR_TakeProfit2_Multi * atr;
    double tp3 = price - ATR_TakeProfit3_Multi * atr;

    // Calculate lot size
    double lots = CalculateLotSize(atr);
    if(lots < minLot) {
        Print("ERROR: Calculated lot size too small: ", lots);
        return;
    }

    // Normalize prices
    sl = NormalizeDouble(sl, _Digits);
    tp1 = NormalizeDouble(tp1, _Digits);
    tp2 = NormalizeDouble(tp2, _Digits);
    tp3 = NormalizeDouble(tp3, _Digits);

    // Open position
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lots;
    request.type = ORDER_TYPE_SELL;
    request.price = price;
    request.sl = sl;
    request.tp = UsePartialProfits ? 0 : tp3;
    request.deviation = 30;
    request.magic = MagicNumber;
    request.comment = TradeComment;

    if(!OrderSend(request, result)) {
        Print("ERROR: Sell order failed. Error: ", result.retcode, " - ", result.comment);
        return;
    }

    if(result.retcode == TRADE_RETCODE_DONE) {
        Print("SUCCESS: SELL executed at ", price, " | Lot: ", lots, " | SL: ", sl);

        // Track position
        currentPosition.ticket = result.order;
        currentPosition.openPrice = price;
        currentPosition.initialLots = lots;
        currentPosition.currentLots = lots;
        currentPosition.tp1Hit = 0;
        currentPosition.tp2Hit = 0;
        currentPosition.atBreakeven = false;
        currentPosition.openTime = TimeCurrent();

        todayTrades++;
        lastTradeTime = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk                            |
//+------------------------------------------------------------------+
double CalculateLotSize(double atr)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk = RiskPercent;

    // Reduce risk in recovery mode
    if(recoveryMode) {
        risk *= RecoveryRiskReduction;
    }

    double riskMoney = balance * risk / 100.0;
    double stopLossPips = ATR_StopLoss_Multi * atr;

    // Calculate lot size
    double lots = riskMoney / (stopLossPips / tickSize * tickValue);

    // Round to lot step
    lots = MathFloor(lots / lotStep) * lotStep;

    // Validate
    lots = MathMax(minLot, MathMin(maxLot, lots));

    return lots;
}

//+------------------------------------------------------------------+
//| Check if has open position                                       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    return PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == MagicNumber;
}

//+------------------------------------------------------------------+
//| Count open positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket)) {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber) {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    if(!PositionSelect(_Symbol)) return;
    if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) return;

    double currentPrice;
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    if(posType == POSITION_TYPE_BUY) {
        currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    } else {
        currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    }

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);

    // Get current ATR
    double atr[];
    if(CopyBuffer(handle_ATR, 0, 0, 1, atr) < 1) return;

    // 1. Check partial profit targets
    if(UsePartialProfits) {
        CheckPartialProfits(posType, currentPrice, openPrice, atr[0]);
    }

    // 2. Move to breakeven after TP1
    if(MoveToBreakevenAtTP1 && !currentPosition.atBreakeven && currentPosition.tp1Hit) {
        MoveToBreakeven(posType, openPrice);
    }

    // 3. Trailing stop
    if(UseTrailingStop) {
        UpdateTrailingStop(posType, currentPrice, currentSL, atr[0]);
    }

    // 4. Exit on opposite signal
    if(ExitOnOppositeSignal) {
        CheckOppositeSignalExit(posType);
    }

    // 5. Exit on histogram reversal
    if(ExitOnHistogramReversal) {
        CheckHistogramReversalExit(posType);
    }

    // 6. Time-based exit
    if(UseTimeBasedExit) {
        CheckTimeBasedExit();
    }
}

//+------------------------------------------------------------------+
//| Check and execute partial profits                                |
//+------------------------------------------------------------------+
void CheckPartialProfits(ENUM_POSITION_TYPE posType, double currentPrice, double openPrice, double atr)
{
    double tp1 = openPrice + (posType == POSITION_TYPE_BUY ? 1 : -1) * ATR_TakeProfit1_Multi * atr;
    double tp2 = openPrice + (posType == POSITION_TYPE_BUY ? 1 : -1) * ATR_TakeProfit2_Multi * atr;

    // Check TP1
    if(!currentPosition.tp1Hit) {
        bool tp1Reached = (posType == POSITION_TYPE_BUY && currentPrice >= tp1) ||
                         (posType == POSITION_TYPE_SELL && currentPrice <= tp1);

        if(tp1Reached) {
            double closeVolume = NormalizeDouble(currentPosition.currentLots * PartialClose_TP1 / 100.0, 2);
            if(closeVolume >= minLot && ClosePartialPosition(closeVolume)) {
                currentPosition.tp1Hit = 1;
                currentPosition.currentLots -= closeVolume;
                Print("INFO: TP1 Hit - Partial close: ", closeVolume);
            }
        }
    }

    // Check TP2
    if(currentPosition.tp1Hit && !currentPosition.tp2Hit) {
        bool tp2Reached = (posType == POSITION_TYPE_BUY && currentPrice >= tp2) ||
                         (posType == POSITION_TYPE_SELL && currentPrice <= tp2);

        if(tp2Reached) {
            double closeVolume = NormalizeDouble(currentPosition.currentLots * PartialClose_TP2 / 100.0, 2);
            if(closeVolume >= minLot && ClosePartialPosition(closeVolume)) {
                currentPosition.tp2Hit = 1;
                currentPosition.currentLots -= closeVolume;
                Print("INFO: TP2 Hit - Partial close: ", closeVolume);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close partial position                                           |
//+------------------------------------------------------------------+
bool ClosePartialPosition(double volume)
{
    if(!PositionSelect(_Symbol)) return false;

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = volume;
    request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ?
                    SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                    SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.deviation = 30;
    request.magic = MagicNumber;

    if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE) {
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Move stop loss to breakeven                                      |
//+------------------------------------------------------------------+
void MoveToBreakeven(ENUM_POSITION_TYPE posType, double openPrice)
{
    if(!PositionSelect(_Symbol)) return;

    double breakeven = NormalizeDouble(openPrice, _Digits);
    double currentSL = PositionGetDouble(POSITION_SL);

    // Only move if beneficial
    bool shouldMove = (posType == POSITION_TYPE_BUY && breakeven > currentSL) ||
                     (posType == POSITION_TYPE_SELL && breakeven < currentSL);

    if(!shouldMove) return;

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_SLTP;
    request.symbol = _Symbol;
    request.sl = breakeven;
    request.tp = PositionGetDouble(POSITION_TP);
    request.magic = MagicNumber;

    if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE) {
        currentPosition.atBreakeven = true;
        Print("INFO: Moved to breakeven at ", breakeven);
    }
}

//+------------------------------------------------------------------+
//| Update trailing stop                                             |
//+------------------------------------------------------------------+
void UpdateTrailingStop(ENUM_POSITION_TYPE posType, double currentPrice, double currentSL, double atr)
{
    double trailDistance = ATR_Trail_Multi * atr;
    double newSL;

    if(posType == POSITION_TYPE_BUY) {
        newSL = currentPrice - trailDistance;
        if(newSL <= currentSL) return; // Only move up
    } else {
        newSL = currentPrice + trailDistance;
        if(newSL >= currentSL) return; // Only move down
    }

    newSL = NormalizeDouble(newSL, _Digits);

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_SLTP;
    request.symbol = _Symbol;
    request.sl = newSL;
    request.tp = PositionGetDouble(POSITION_TP);
    request.magic = MagicNumber;

    if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE) {
        Print("INFO: Trailing stop updated to ", newSL);
    }
}

//+------------------------------------------------------------------+
//| Check for opposite signal exit                                   |
//+------------------------------------------------------------------+
void CheckOppositeSignalExit(ENUM_POSITION_TYPE posType)
{
    double macd[], signal[], histo[];
    if(!GetMACDValues(handle_MACD_Entry, 2, macd, signal, histo)) return;

    bool oppositeSignal = false;

    if(posType == POSITION_TYPE_BUY) {
        // Exit long on bearish cross
        oppositeSignal = (macd[0] < signal[0] && macd[1] >= signal[1]);
    } else {
        // Exit short on bullish cross
        oppositeSignal = (macd[0] > signal[0] && macd[1] <= signal[1]);
    }

    if(oppositeSignal) {
        ClosePosition("Opposite signal");
    }
}

//+------------------------------------------------------------------+
//| Check for histogram reversal exit                                |
//+------------------------------------------------------------------+
void CheckHistogramReversalExit(ENUM_POSITION_TYPE posType)
{
    double macd[], signal[], histo[];
    if(!GetMACDValues(handle_MACD_Entry, 3, macd, signal, histo)) return;

    bool histoReversal = false;

    if(posType == POSITION_TYPE_BUY) {
        // Histogram turning down
        histoReversal = (histo[0] < histo[1] && histo[1] >= histo[2]);
    } else {
        // Histogram turning up
        histoReversal = (histo[0] > histo[1] && histo[1] <= histo[2]);
    }

    // Only exit if past breakeven
    if(histoReversal && currentPosition.atBreakeven) {
        ClosePosition("Histogram reversal");
    }
}

//+------------------------------------------------------------------+
//| Check time-based exit                                            |
//+------------------------------------------------------------------+
void CheckTimeBasedExit()
{
    int barsSinceOpen = Bars(_Symbol, EntryTimeframe, currentPosition.openTime, TimeCurrent());

    if(barsSinceOpen >= MaxBarsInTrade) {
        ClosePosition("Time-based exit");
    }
}

//+------------------------------------------------------------------+
//| Close position with reason                                       |
//+------------------------------------------------------------------+
void ClosePosition(string reason)
{
    if(!PositionSelect(_Symbol)) return;

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ?
                    SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                    SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.deviation = 30;
    request.magic = MagicNumber;

    if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE) {
        Print("INFO: Position closed - ", reason);

        // Update statistics
        double profit = PositionGetDouble(POSITION_PROFIT);
        UpdateStatistics(profit);

        // Reset tracking
        ZeroMemory(currentPosition);
    }
}

//+------------------------------------------------------------------+
//| Check drawdown and activate recovery/pause                       |
//+------------------------------------------------------------------+
void CheckDrawdown()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    if(balance <= 0) return;

    double dd = 100.0 * (balance - equity) / balance;

    // Activate recovery mode at 50% of max DD
    if(dd >= MaxDrawdown * 0.5 && !recoveryMode) {
        recoveryMode = true;
        Print("WARNING: Recovery mode activated. DD: ", NormalizeDouble(dd, 2), "%");
    }

    // Pause trading at max DD
    if(dd >= MaxDrawdown && !tradingPaused) {
        tradingPaused = true;
        recoveryMode = false;
        Print("CRITICAL: Trading paused. DD: ", NormalizeDouble(dd, 2), "%");

        // Close open positions
        ClosePosition("Max drawdown reached");
    }

    // Resume when DD drops below 30% of max
    if(dd < MaxDrawdown * 0.3) {
        if(tradingPaused) {
            tradingPaused = false;
            Print("INFO: Trading resumed. DD: ", NormalizeDouble(dd, 2), "%");
        }
        if(recoveryMode) {
            recoveryMode = false;
            Print("INFO: Recovery mode deactivated. DD: ", NormalizeDouble(dd, 2), "%");
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate daily P&L                                              |
//+------------------------------------------------------------------+
double CalculateDailyPnL()
{
    // Simplified - in production, track all today's closed trades
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    return currentBalance - startDayBalance;
}

//+------------------------------------------------------------------+
//| Reset daily counters                                             |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
    todayTrades = 0;
    todayPnL = 0.0;
    startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
}

//+------------------------------------------------------------------+
//| Update statistics after trade close                              |
//+------------------------------------------------------------------+
void UpdateStatistics(double profit)
{
    stats.totalTrades++;

    if(profit > 0) {
        stats.winTrades++;
        stats.totalProfit += profit;
        stats.largestWin = MathMax(stats.largestWin, profit);
        stats.currentStreak = (stats.currentStreak > 0) ? stats.currentStreak + 1 : 1;
    } else {
        stats.lossTrades++;
        stats.totalLoss += MathAbs(profit);
        stats.largestLoss = MathMax(stats.largestLoss, MathAbs(profit));
        stats.currentStreak = (stats.currentStreak < 0) ? stats.currentStreak - 1 : -1;
    }
}

//+------------------------------------------------------------------+
//| Load statistics from file                                        |
//+------------------------------------------------------------------+
void LoadStatistics()
{
    // Initialize to zero
    ZeroMemory(stats);

    // In production, load from file
    // For now, just initialize
}

//+------------------------------------------------------------------+
//| Save statistics to file                                          |
//+------------------------------------------------------------------+
void SaveStatistics()
{
    // In production, save to CSV or binary file
}

//+------------------------------------------------------------------+
//| Create dashboard on chart                                        |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    if(!ShowDashboard) return;

    int x = 10, y = 20;
    int yStep = 18;
    string prefix = "MACD_Dashboard_";

    // Title
    CreateLabel(prefix + "Title", x, y, "=== MACD Pro EA ===", clrWhite, 10, DashboardCorner);
    y += yStep + 5;

    // Status
    CreateLabel(prefix + "Status", x, y, "Status: ", clrGray, 8, DashboardCorner);
    y += yStep;

    // Statistics
    CreateLabel(prefix + "Stats", x, y, "Trades: ", clrGray, 8, DashboardCorner);
    y += yStep;

    CreateLabel(prefix + "WinRate", x, y, "Win Rate: ", clrGray, 8, DashboardCorner);
    y += yStep;

    CreateLabel(prefix + "Profit", x, y, "Net P/L: ", clrGray, 8, DashboardCorner);
    y += yStep;

    CreateLabel(prefix + "DD", x, y, "Drawdown: ", clrGray, 8, DashboardCorner);
    y += yStep;

    CreateLabel(prefix + "Today", x, y, "Today: ", clrGray, 8, DashboardCorner);
}

//+------------------------------------------------------------------+
//| Update dashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
    if(!ShowDashboard) return;

    string prefix = "MACD_Dashboard_";

    // Status
    string status = tradingPaused ? "PAUSED" : (recoveryMode ? "RECOVERY" : "ACTIVE");
    color statusColor = tradingPaused ? clrRed : (recoveryMode ? clrOrange : clrLimeGreen);
    UpdateLabel(prefix + "Status", "Status: " + status, statusColor);

    // Statistics
    int totalTrades = stats.totalTrades;
    double winRate = totalTrades > 0 ? 100.0 * stats.winTrades / totalTrades : 0;
    double netPL = stats.totalProfit - stats.totalLoss;

    UpdateLabel(prefix + "Stats", "Trades: " + IntegerToString(totalTrades) +
                " (W:" + IntegerToString(stats.winTrades) + " L:" + IntegerToString(stats.lossTrades) + ")");

    UpdateLabel(prefix + "WinRate", "Win Rate: " + DoubleToString(winRate, 1) + "%",
                winRate >= 50 ? clrLimeGreen : clrOrange);

    UpdateLabel(prefix + "Profit", "Net P/L: " + DoubleToString(netPL, 2),
                netPL >= 0 ? clrLimeGreen : clrRed);

    // Drawdown
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dd = balance > 0 ? 100.0 * (balance - equity) / balance : 0;

    UpdateLabel(prefix + "DD", "Drawdown: " + DoubleToString(dd, 2) + "%",
                dd < 3 ? clrLimeGreen : (dd < 5 ? clrOrange : clrRed));

    // Today
    UpdateLabel(prefix + "Today", "Today: " + IntegerToString(todayTrades) + " trades | " +
                DoubleToString(CalculateDailyPnL(), 2));
}

//+------------------------------------------------------------------+
//| Delete dashboard                                                 |
//+------------------------------------------------------------------+
void DeleteDashboard()
{
    string prefix = "MACD_Dashboard_";
    ObjectDelete(0, prefix + "Title");
    ObjectDelete(0, prefix + "Status");
    ObjectDelete(0, prefix + "Stats");
    ObjectDelete(0, prefix + "WinRate");
    ObjectDelete(0, prefix + "Profit");
    ObjectDelete(0, prefix + "DD");
    ObjectDelete(0, prefix + "Today");
}

//+------------------------------------------------------------------+
//| Create label helper                                              |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, int corner)
{
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
    ObjectSetString(0, name, OBJPROP_FONT, "Courier New");
}

//+------------------------------------------------------------------+
//| Update label helper                                              |
//+------------------------------------------------------------------+
void UpdateLabel(string name, string text, color clr = clrGray)
{
    if(ObjectFind(0, name) < 0) return;
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
