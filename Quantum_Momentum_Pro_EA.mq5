//+------------------------------------------------------------------+
//|                                    Quantum_Momentum_Pro_EA.mq5  |
//|                        Advanced Multi-Tier Risk Management      |
//|                        Beautiful UI + Momentum Breakout System  |
//+------------------------------------------------------------------+
#property copyright "TechFine Trading Systems"
#property version   "1.00"
#property strict
#property description "Quantum Momentum Pro: RSI + Bollinger + Volume momentum system"
#property description "4-Tier Risk Management | Beautiful Dashboard UI"

//---- Input Parameters ============================================
input group "=== TRADING STRATEGY ==="
input ENUM_TIMEFRAMES MainTimeframe      = PERIOD_M15;   // Main Timeframe
input ENUM_TIMEFRAMES FilterTimeframe    = PERIOD_H1;    // Trend Filter TF
input bool   UseMultiTFFilter            = true;         // Multi-TF Confirmation

input group "=== RSI SETTINGS ==="
input int    RSI_Period                  = 14;           // RSI Period
input int    RSI_Oversold                = 30;           // RSI Oversold Level
input int    RSI_Overbought              = 70;           // RSI Overbought Level
input bool   RSI_DivergenceFilter        = true;         // Use RSI Divergence

input group "=== BOLLINGER BANDS ==="
input int    BB_Period                   = 20;           // BB Period
input double BB_Deviation                = 2.0;          // BB Standard Deviation
input bool   RequireBBBreakout           = true;         // Require BB Breakout

input group "=== VOLUME FILTER ==="
input bool   UseVolumeFilter             = true;         // Enable Volume Filter
input double VolumeMultiplier            = 1.5;          // Volume Spike Multiplier

input group "=== RISK TIER 1: CONSERVATIVE ==="
input bool   EnableConservative          = true;         // Enable Conservative
input double Risk_Conservative           = 0.5;          // Risk % (Conservative)
input ulong  Magic_Conservative          = 10001;        // Magic Number

input group "=== RISK TIER 2: MODERATE ==="
input bool   EnableModerate              = true;         // Enable Moderate
input double Risk_Moderate               = 1.0;          // Risk % (Moderate)
input ulong  Magic_Moderate              = 10002;        // Magic Number

input group "=== RISK TIER 3: AGGRESSIVE ==="
input bool   EnableAggressive            = false;        // Enable Aggressive
input double Risk_Aggressive             = 2.0;          // Risk % (Aggressive)
input ulong  Magic_Aggressive            = 10003;        // Magic Number

input group "=== RISK TIER 4: ULTRA ==="
input bool   EnableUltra                 = false;        // Enable Ultra
input double Risk_Ultra                  = 3.0;          // Risk % (Ultra)
input ulong  Magic_Ultra                 = 10004;        // Magic Number

input group "=== TAKE PROFIT LEVELS ==="
input double TP1_Points                  = 100;          // TP1 Points
input double TP2_Points                  = 200;          // TP2 Points
input double TP3_Points                  = 300;          // TP3 Points
input double TP1_ClosePercent            = 40;           // Close % at TP1
input double TP2_ClosePercent            = 30;           // Close % at TP2

input group "=== STOP LOSS & TRAILING ==="
input double SL_Points                   = 150;          // Stop Loss Points
input bool   UseTrailingStop             = true;         // Enable Trailing Stop
input double Trail_Start                 = 50;           // Trail Start (points)
input double Trail_Step                  = 20;           // Trail Step (points)

input group "=== RISK MANAGEMENT ==="
input double MaxDailyLoss                = 5.0;          // Max Daily Loss %
input double MaxDrawdown                 = 10.0;         // Max Drawdown %
input int    MaxTradesPerDay             = 15;           // Max Trades/Day
input int    MaxConcurrentPerTier        = 1;            // Max Positions/Tier

input group "=== SESSION FILTER ==="
input bool   TradeAsianSession           = false;        // Trade Asian (00-08)
input bool   TradeLondonSession          = true;         // Trade London (08-16)
input bool   TradeNYSession              = true;         // Trade NY (13-21)

input group "=== DASHBOARD ==="
input bool   ShowDashboard               = true;         // Show Dashboard
input int    DashboardX                  = 20;           // Dashboard X Position
input int    DashboardY                  = 30;           // Dashboard Y Position
input color  ColorActive                 = clrLimeGreen; // Active Color
input color  ColorWarning                = clrYellow;    // Warning Color
input color  ColorDanger                 = clrRed;       // Danger Color

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
// Indicator handles
int handle_RSI_Main, handle_RSI_Filter;
int handle_BB_Upper, handle_BB_Lower, handle_BB_Middle;

// Risk tiers
struct RiskTier {
    bool     enabled;
    double   riskPercent;
    ulong    magicNumber;
    int      tradesTotal;
    int      tradesWin;
    double   profitTotal;
    datetime lastTradeTime;
    string   name;
};

RiskTier tiers[4];

// Daily tracking
datetime lastBarTime;
int      todayTradesAll = 0;
double   startDayBalance = 0.0;
bool     tradingPaused = false;

// Symbol info
double tickSize, tickValue, pointValue;
double minLot, maxLot, lotStep;

// Performance
struct GlobalStats {
    int    totalTrades;
    int    totalWins;
    double totalProfit;
    double totalLoss;
    double bestTrade;
    double worstTrade;
    double currentDD;
};
GlobalStats stats;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    handle_RSI_Main = iRSI(_Symbol, MainTimeframe, RSI_Period, PRICE_CLOSE);
    handle_RSI_Filter = iRSI(_Symbol, FilterTimeframe, RSI_Period, PRICE_CLOSE);
    handle_BB_Upper = iBands(_Symbol, MainTimeframe, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
    handle_BB_Lower = handle_BB_Upper; // Same handle, different buffers
    handle_BB_Middle = handle_BB_Upper;

    if(handle_RSI_Main == INVALID_HANDLE || handle_BB_Upper == INVALID_HANDLE) {
        Print("ERROR: Failed to initialize indicators");
        return INIT_FAILED;
    }

    // Initialize symbol info
    if(!InitSymbolInfo()) {
        Print("ERROR: Failed to initialize symbol info");
        return INIT_FAILED;
    }

    // Initialize risk tiers
    InitRiskTiers();

    // Initialize tracking
    lastBarTime = iTime(_Symbol, MainTimeframe, 0);
    startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    ZeroMemory(stats);

    // Create dashboard
    if(ShowDashboard) CreateDashboard();

    // Set timer
    EventSetTimer(30);

    Print("╔════════════════════════════════════════╗");
    Print("║   QUANTUM MOMENTUM PRO EA STARTED      ║");
    Print("╠════════════════════════════════════════╣");
    Print("║ Symbol: ", _Symbol);
    Print("║ Timeframe: ", EnumToString(MainTimeframe));
    Print("║ Active Tiers: ", CountActiveTiers());
    Print("╚════════════════════════════════════════╝");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(handle_RSI_Main);
    IndicatorRelease(handle_RSI_Filter);
    IndicatorRelease(handle_BB_Upper);
    EventKillTimer();
    if(ShowDashboard) DeleteDashboard();
    Print("═══ Quantum Momentum Pro EA Stopped ═══");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(ShowDashboard) UpdateDashboard();

    if(!IsTradingAllowed()) {
        ManageAllPositions();
        return;
    }

    ManageAllPositions();

    if(!IsNewBar(MainTimeframe)) return;

    CheckForEntrySignals();
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    CheckDrawdown();
    CheckDailyReset();
}

//+------------------------------------------------------------------+
//| Initialize symbol information                                    |
//+------------------------------------------------------------------+
bool InitSymbolInfo()
{
    tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    return (tickValue > 0 && tickSize > 0);
}

//+------------------------------------------------------------------+
//| Initialize risk tiers                                            |
//+------------------------------------------------------------------+
void InitRiskTiers()
{
    tiers[0].enabled = EnableConservative;
    tiers[0].riskPercent = Risk_Conservative;
    tiers[0].magicNumber = Magic_Conservative;
    tiers[0].name = "CONSERVATIVE";

    tiers[1].enabled = EnableModerate;
    tiers[1].riskPercent = Risk_Moderate;
    tiers[1].magicNumber = Magic_Moderate;
    tiers[1].name = "MODERATE";

    tiers[2].enabled = EnableAggressive;
    tiers[2].riskPercent = Risk_Aggressive;
    tiers[2].magicNumber = Magic_Aggressive;
    tiers[2].name = "AGGRESSIVE";

    tiers[3].enabled = EnableUltra;
    tiers[3].riskPercent = Risk_Ultra;
    tiers[3].magicNumber = Magic_Ultra;
    tiers[3].name = "ULTRA";

    // Load statistics for each tier
    for(int i = 0; i < 4; i++) {
        LoadTierStats(tiers[i]);
    }
}

//+------------------------------------------------------------------+
//| Check if new bar                                                 |
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
//| Check if trading allowed                                         |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
    if(tradingPaused) return false;
    if(todayTradesAll >= MaxTradesPerDay) return false;

    double dailyLoss = (startDayBalance - AccountInfoDouble(ACCOUNT_BALANCE)) / startDayBalance * 100.0;
    if(dailyLoss >= MaxDailyLoss) {
        tradingPaused = true;
        Print("⚠ DAILY LOSS LIMIT REACHED");
        return false;
    }

    if(!IsAllowedSession()) return false;

    return true;
}

//+------------------------------------------------------------------+
//| Check session                                                    |
//+------------------------------------------------------------------+
bool IsAllowedSession()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int hour = dt.hour;

    if(hour >= 0 && hour < 8) return TradeAsianSession;
    if(hour >= 8 && hour < 16) return TradeLondonSession;
    if(hour >= 13 && hour < 21) return TradeNYSession;

    return false;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckForEntrySignals()
{
    // Get indicators
    double rsi_main[], rsi_filter[];
    double bb_upper[], bb_middle[], bb_lower[];

    if(CopyBuffer(handle_RSI_Main, 0, 0, 3, rsi_main) < 3) return;
    if(UseMultiTFFilter && CopyBuffer(handle_RSI_Filter, 0, 0, 2, rsi_filter) < 2) return;

    if(CopyBuffer(handle_BB_Upper, 1, 0, 2, bb_upper) < 2) return;    // Upper band
    if(CopyBuffer(handle_BB_Upper, 0, 0, 2, bb_middle) < 2) return;   // Middle band
    if(CopyBuffer(handle_BB_Upper, 2, 0, 2, bb_lower) < 2) return;    // Lower band

    ArraySetAsSeries(rsi_main, true);
    ArraySetAsSeries(rsi_filter, true);
    ArraySetAsSeries(bb_upper, true);
    ArraySetAsSeries(bb_middle, true);
    ArraySetAsSeries(bb_lower, true);

    // Get price data
    double close[], open[], high[], low[];
    long volume[];

    if(CopyClose(_Symbol, MainTimeframe, 0, 20, close) < 20) return;
    if(CopyOpen(_Symbol, MainTimeframe, 0, 2, open) < 2) return;
    if(CopyHigh(_Symbol, MainTimeframe, 0, 2, high) < 2) return;
    if(CopyLow(_Symbol, MainTimeframe, 0, 2, low) < 2) return;
    if(CopyTickVolume(_Symbol, MainTimeframe, 0, 20, volume) < 20) return;

    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(volume, true);

    // Calculate average volume
    double avgVolume = 0;
    for(int i = 1; i < 20; i++) avgVolume += (double)volume[i];
    avgVolume /= 19.0;

    // Check BUY signal
    if(IsBuySignal(rsi_main, rsi_filter, bb_upper, bb_middle, bb_lower,
                   close, high, low, volume[0], avgVolume)) {
        ExecuteTradesAllTiers(ORDER_TYPE_BUY);
    }
    // Check SELL signal
    else if(IsSellSignal(rsi_main, rsi_filter, bb_upper, bb_middle, bb_lower,
                         close, high, low, volume[0], avgVolume)) {
        ExecuteTradesAllTiers(ORDER_TYPE_SELL);
    }
}

//+------------------------------------------------------------------+
//| Check BUY signal                                                 |
//+------------------------------------------------------------------+
bool IsBuySignal(const double &rsi_main[], const double &rsi_filter[],
                 const double &bb_upper[], const double &bb_middle[], const double &bb_lower[],
                 const double &close[], const double &high[], const double &low[],
                 double currentVolume, double avgVolume)
{
    // 1. RSI oversold recovery
    if(rsi_main[0] < RSI_Oversold) return false;
    if(rsi_main[1] >= RSI_Oversold) return false;  // Just crossed above

    // 2. Multi-TF filter
    if(UseMultiTFFilter && rsi_filter[0] >= RSI_Overbought) return false;

    // 3. Bollinger breakout
    if(RequireBBBreakout) {
        if(close[1] >= bb_lower[1]) return false;  // Previous bar below lower band
        if(close[0] <= bb_lower[0]) return false;  // Current bar above lower band
    }

    // 4. Volume confirmation
    if(UseVolumeFilter && currentVolume < avgVolume * VolumeMultiplier) return false;

    // 5. Price momentum
    if(close[0] <= close[1]) return false;

    return true;
}

//+------------------------------------------------------------------+
//| Check SELL signal                                                |
//+------------------------------------------------------------------+
bool IsSellSignal(const double &rsi_main[], const double &rsi_filter[],
                  const double &bb_upper[], const double &bb_middle[], const double &bb_lower[],
                  const double &close[], const double &high[], const double &low[],
                  double currentVolume, double avgVolume)
{
    // 1. RSI overbought reversal
    if(rsi_main[0] > RSI_Overbought) return false;
    if(rsi_main[1] <= RSI_Overbought) return false;  // Just crossed below

    // 2. Multi-TF filter
    if(UseMultiTFFilter && rsi_filter[0] <= RSI_Oversold) return false;

    // 3. Bollinger breakout
    if(RequireBBBreakout) {
        if(close[1] <= bb_upper[1]) return false;  // Previous bar above upper band
        if(close[0] >= bb_upper[0]) return false;  // Current bar below upper band
    }

    // 4. Volume confirmation
    if(UseVolumeFilter && currentVolume < avgVolume * VolumeMultiplier) return false;

    // 5. Price momentum
    if(close[0] >= close[1]) return false;

    return true;
}

//+------------------------------------------------------------------+
//| Execute trades for all enabled tiers                             |
//+------------------------------------------------------------------+
void ExecuteTradesAllTiers(ENUM_ORDER_TYPE orderType)
{
    for(int i = 0; i < 4; i++) {
        if(!tiers[i].enabled) continue;

        if(CountPositionsByMagic(tiers[i].magicNumber) >= MaxConcurrentPerTier) continue;

        ExecuteTrade(orderType, tiers[i]);
    }
}

//+------------------------------------------------------------------+
//| Execute trade for specific tier                                  |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE orderType, RiskTier &tier)
{
    double price = (orderType == ORDER_TYPE_BUY) ?
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                   SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double slDistance = SL_Points * pointValue;
    double sl = (orderType == ORDER_TYPE_BUY) ? price - slDistance : price + slDistance;

    // Calculate lot size based on risk tier
    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * tier.riskPercent / 100.0;
    double lots = riskMoney / (slDistance / tickSize * tickValue);
    lots = NormalizeDouble(MathFloor(lots / lotStep) * lotStep, 2);
    lots = MathMax(minLot, MathMin(maxLot, lots));

    // Execute trade
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lots;
    request.type = orderType;
    request.price = price;
    request.sl = NormalizeDouble(sl, _Digits);
    request.tp = 0;  // Managed manually
    request.deviation = 30;
    request.magic = tier.magicNumber;
    request.comment = tier.name;

    if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE) {
        Print("✓ ", tier.name, " | ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
              " | Price: ", price, " | Lot: ", lots);
        tier.tradesTotal++;
        todayTradesAll++;
    }
}

//+------------------------------------------------------------------+
//| Manage all positions                                             |
//+------------------------------------------------------------------+
void ManageAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

        ulong magic = PositionGetInteger(POSITION_MAGIC);

        // Find corresponding tier
        for(int j = 0; j < 4; j++) {
            if(tiers[j].magicNumber == magic) {
                ManagePosition(ticket, tiers[j]);
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage individual position                                       |
//+------------------------------------------------------------------+
void ManagePosition(ulong ticket, RiskTier &tier)
{
    if(!PositionSelectByTicket(ticket)) return;

    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentPrice = (posType == POSITION_TYPE_BUY) ?
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    double profit = (posType == POSITION_TYPE_BUY) ?
                    (currentPrice - openPrice) : (openPrice - currentPrice);
    double profitPoints = profit / pointValue;

    // Check take profit levels
    if(profitPoints >= TP3_Points) {
        ClosePosition(ticket);
        return;
    }

    // Trailing stop
    if(UseTrailingStop && profitPoints >= Trail_Start) {
        UpdateTrailingStop(ticket, posType, currentPrice);
    }
}

//+------------------------------------------------------------------+
//| Update trailing stop                                             |
//+------------------------------------------------------------------+
void UpdateTrailingStop(ulong ticket, ENUM_POSITION_TYPE posType, double currentPrice)
{
    if(!PositionSelectByTicket(ticket)) return;

    double currentSL = PositionGetDouble(POSITION_SL);
    double trailDistance = Trail_Step * pointValue;
    double newSL;

    if(posType == POSITION_TYPE_BUY) {
        newSL = currentPrice - trailDistance;
        if(newSL <= currentSL) return;
    } else {
        newSL = currentPrice + trailDistance;
        if(newSL >= currentSL) return;
    }

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.symbol = _Symbol;
    request.sl = NormalizeDouble(newSL, _Digits);
    request.tp = PositionGetDouble(POSITION_TP);

    OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Close position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;

    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                   ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = (request.type == ORDER_TYPE_SELL) ?
                    SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                    SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.deviation = 30;

    if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE) {
        double profit = PositionGetDouble(POSITION_PROFIT);
        UpdateTierStats(PositionGetInteger(POSITION_MAGIC), profit);
    }
}

//+------------------------------------------------------------------+
//| Count positions by magic number                                  |
//+------------------------------------------------------------------+
int CountPositionsByMagic(ulong magic)
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionGetTicket(i)) {
            if(PositionGetInteger(POSITION_MAGIC) == magic) count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Count active tiers                                               |
//+------------------------------------------------------------------+
int CountActiveTiers()
{
    int count = 0;
    for(int i = 0; i < 4; i++) {
        if(tiers[i].enabled) count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Check drawdown                                                   |
//+------------------------------------------------------------------+
void CheckDrawdown()
{
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    if(balance <= 0) return;

    double dd = 100.0 * (balance - equity) / balance;
    stats.currentDD = dd;

    if(dd >= MaxDrawdown && !tradingPaused) {
        tradingPaused = true;
        Print("⛔ MAX DRAWDOWN REACHED: ", NormalizeDouble(dd, 2), "%");
    }

    if(dd < MaxDrawdown * 0.5 && tradingPaused) {
        tradingPaused = false;
        Print("✓ Trading resumed. DD: ", NormalizeDouble(dd, 2), "%");
    }
}

//+------------------------------------------------------------------+
//| Check daily reset                                                |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
    static int lastDay = -1;
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    if(dt.day != lastDay) {
        todayTradesAll = 0;
        startDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        lastDay = dt.day;
    }
}

//+------------------------------------------------------------------+
//| Load tier statistics                                             |
//+------------------------------------------------------------------+
void LoadTierStats(RiskTier &tier)
{
    tier.tradesTotal = 0;
    tier.tradesWin = 0;
    tier.profitTotal = 0.0;
}

//+------------------------------------------------------------------+
//| Update tier statistics                                           |
//+------------------------------------------------------------------+
void UpdateTierStats(ulong magic, double profit)
{
    for(int i = 0; i < 4; i++) {
        if(tiers[i].magicNumber == magic) {
            tiers[i].profitTotal += profit;
            if(profit > 0) tiers[i].tradesWin++;

            stats.totalTrades++;
            if(profit > 0) {
                stats.totalWins++;
                stats.totalProfit += profit;
                if(profit > stats.bestTrade) stats.bestTrade = profit;
            } else {
                stats.totalLoss += MathAbs(profit);
                if(profit < stats.worstTrade) stats.worstTrade = profit;
            }
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Create Dashboard                                                 |
//+------------------------------------------------------------------+
void CreateDashboard()
{
    int x = DashboardX;
    int y = DashboardY;
    int width = 280;
    int height = 320;

    // Background panel
    CreatePanel("QM_Panel_BG", x, y, width, height, C'20,20,30', 2);

    // Header panel
    CreatePanel("QM_Panel_Header", x, y, width, 35, C'45,45,75', 2);

    // Title
    CreateLabel("QM_Title", x + 10, y + 8, "⚡ QUANTUM MOMENTUM PRO", clrWhite, 11, true);

    y += 45;

    // Status section
    CreateLabel("QM_Status_Label", x + 10, y, "STATUS:", clrGray, 8, true);
    CreateLabel("QM_Status_Value", x + 180, y, "ACTIVE", ColorActive, 8, true);
    y += 20;

    CreateLabel("QM_DD_Label", x + 10, y, "Drawdown:", clrGray, 8, false);
    CreateLabel("QM_DD_Value", x + 180, y, "0.0%", ColorActive, 8, false);
    y += 20;

    CreateLabel("QM_Trades_Label", x + 10, y, "Today Trades:", clrGray, 8, false);
    CreateLabel("QM_Trades_Value", x + 180, y, "0", clrWhite, 8, false);
    y += 25;

    // Tier section
    CreateLabel("QM_Tier_Header", x + 10, y, "═══ RISK TIERS ═══", clrGold, 9, true);
    y += 22;

    for(int i = 0; i < 4; i++) {
        string prefix = "QM_Tier" + IntegerToString(i);
        CreateLabel(prefix + "_Name", x + 10, y, tiers[i].name, clrGray, 7, false);
        CreateLabel(prefix + "_Status", x + 120, y, "○", clrGray, 7, false);
        CreateLabel(prefix + "_Stats", x + 140, y, "0/0", clrGray, 7, false);
        CreateLabel(prefix + "_PL", x + 200, y, "+0.00", clrGray, 7, false);
        y += 18;
    }

    y += 10;
    CreateLabel("QM_Performance_Header", x + 10, y, "═══ PERFORMANCE ═══", clrGold, 9, true);
    y += 22;

    CreateLabel("QM_Perf_WinRate", x + 10, y, "Win Rate: 0%", clrWhite, 8, false);
    y += 18;
    CreateLabel("QM_Perf_NetPL", x + 10, y, "Net P/L: $0.00", clrWhite, 8, false);
    y += 18;
    CreateLabel("QM_Perf_Best", x + 10, y, "Best: $0.00", ColorActive, 8, false);
    y += 18;
    CreateLabel("QM_Perf_Worst", x + 10, y, "Worst: $0.00", ColorDanger, 8, false);
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
    // Status
    string status = tradingPaused ? "⛔ PAUSED" : "✓ ACTIVE";
    color statusColor = tradingPaused ? ColorDanger : ColorActive;
    UpdateLabel("QM_Status_Value", status, statusColor);

    // Drawdown
    string ddText = DoubleToString(stats.currentDD, 2) + "%";
    color ddColor = stats.currentDD < 3 ? ColorActive : (stats.currentDD < 7 ? ColorWarning : ColorDanger);
    UpdateLabel("QM_DD_Value", ddText, ddColor);

    // Today trades
    UpdateLabel("QM_Trades_Value", IntegerToString(todayTradesAll), clrWhite);

    // Update tiers
    for(int i = 0; i < 4; i++) {
        string prefix = "QM_Tier" + IntegerToString(i);
        string statusIcon = tiers[i].enabled ? "●" : "○";
        color tierColor = tiers[i].enabled ? ColorActive : clrGray;

        UpdateLabel(prefix + "_Status", statusIcon, tierColor);

        string stats = IntegerToString(tiers[i].tradesWin) + "/" + IntegerToString(tiers[i].tradesTotal);
        UpdateLabel(prefix + "_Stats", stats, clrWhite);

        string plText = (tiers[i].profitTotal >= 0 ? "+" : "") + DoubleToString(tiers[i].profitTotal, 2);
        color plColor = tiers[i].profitTotal >= 0 ? ColorActive : ColorDanger;
        UpdateLabel(prefix + "_PL", plText, plColor);
    }

    // Performance
    double winRate = stats.totalTrades > 0 ? 100.0 * stats.totalWins / stats.totalTrades : 0;
    UpdateLabel("QM_Perf_WinRate", "Win Rate: " + DoubleToString(winRate, 1) + "%", clrWhite);

    double netPL = stats.totalProfit - stats.totalLoss;
    string netPLText = "Net P/L: $" + DoubleToString(netPL, 2);
    color netPLColor = netPL >= 0 ? ColorActive : ColorDanger;
    UpdateLabel("QM_Perf_NetPL", netPLText, netPLColor);

    UpdateLabel("QM_Perf_Best", "Best: $" + DoubleToString(stats.bestTrade, 2), ColorActive);
    UpdateLabel("QM_Perf_Worst", "Worst: $" + DoubleToString(stats.worstTrade, 2), ColorDanger);
}

//+------------------------------------------------------------------+
//| Delete Dashboard                                                 |
//+------------------------------------------------------------------+
void DeleteDashboard()
{
    ObjectsDeleteAll(0, "QM_");
}

//+------------------------------------------------------------------+
//| Create panel helper                                              |
//+------------------------------------------------------------------+
void CreatePanel(string name, int x, int y, int width, int height, color bgColor, int borderWidth)
{
    ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, borderWidth);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Create label helper                                              |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, bool bold)
{
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
    ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
}

//+------------------------------------------------------------------+
//| Update label helper                                              |
//+------------------------------------------------------------------+
void UpdateLabel(string name, string text, color clr = -1)
{
    if(ObjectFind(0, name) < 0) return;
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    if(clr != -1) ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
