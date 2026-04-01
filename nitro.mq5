#property copyright "2025"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

/*
   Nitro EA - adaptive trend scalper for gold pairs on M5
   ------------------------------------------------------
   - uses multi-timeframe moving average structure to align trades with trend
   - ATR volatility gate and spread guard prevent trading in choppy sessions
   - risk is managed dynamically by position sizing from stop-loss distance
   - supports basket level equity target, partial profits and advanced trailing
   - includes optional news/schedule blackout windows and Telegram remote switch
*/

input string InpSymbol                  = "XAUUSDc";       // Trading symbol
input ENUM_TIMEFRAMES InpSignalTF       = PERIOD_M5;        // Signal timeframe
input ENUM_TIMEFRAMES InpTrendTF        = PERIOD_H1;        // Trend timeframe for bias
input int    FastMAPeriod               = 21;               // Fast MA period (signal)
input int    SlowMAPeriod               = 55;               // Slow MA period (signal)
input int    TrendMAPeriod              = 200;              // Trend MA period (higher TF)
input ENUM_MA_METHOD InpMAMethod        = MODE_EMA;         // Moving average method
input double RiskPerTradePercent        = 1.2;              // Risk per trade (% of balance)
input double MaxDailyDrawdownPercent    = 4.0;              // Daily equity DD to stop trading
input int    ATRPeriod                  = 14;               // ATR period for stop distance
input double ATRMultiplier              = 2.4;              // ATR multiple for SL
input double MinATRPoints               = 80;               // Minimum ATR (points) to trade
input double MaxSpreadPoints            = 180;              // Maximum spread (points)
input int    CooldownMinutes            = 20;               // Minutes between new entries
input int    MaxPositions               = 4;                // Maximum concurrent positions
input double BasketTargetPercent        = 0.35;             // Close basket when % balance reached
input double BasketStopPercent          = -1.2;             // Close basket when loss % balance reached
input double BreakEvenPoints            = 250;              // Move SL to BE after profit points
input double TrailStartPoints           = 320;              // Start trailing at profit points
input double TrailStepPoints            = 120;              // Step for trailing in points
input double PartialCloseTriggerPoints  = 400;              // Points to trigger partial close
input double PartialClosePercent        = 40.0;             // % of volume to close when triggered
input bool   AllowBuy                   = true;             // Allow long trades
input bool   AllowSell                  = true;             // Allow short trades
input int    Magic                      = 202503;           // Magic number
input bool   UseTimerForCommands        = true;             // Run Telegram/news checks on timer
input int    CommandIntervalSec         = 5;                // Timer interval (seconds)
input string TelegramToken              = "";              // Telegram bot token
input long   TelegramChatID             = 0;                // Telegram chat id

CTrade trade;

int      handleFast = INVALID_HANDLE;
int      handleSlow = INVALID_HANDLE;
int      handleTrend = INVALID_HANDLE;
int      handleATR = INVALID_HANDLE;
double   fastBuffer[];
double   slowBuffer[];
double   trendBuffer[];
double   atrBuffer[];
datetime lastSignalTime = 0;
datetime tradingDay = 0;
double   startDayEquity = 0.0;
bool     tradingEnabled = true;
int      lastUpdateId = 0;

typedef struct
{
   datetime start;
   datetime end;
} BLACKOUT_WINDOW;

#define MAX_BLACKOUT 5
BLACKOUT_WINDOW blackout[MAX_BLACKOUT];
int blackoutCount = 0;

//--- utility prototypes
bool   InitializeIndicators();
void   ReleaseIndicators();
void   RefreshIndicatorBuffers();
bool   IsSpreadAcceptable();
bool   IsAtrSufficient();
int    TrendDirection();
int    SignalDirection();
int    CountPositions(int direction = 0);
double BasketProfit();
void   UpdateDailyRiskGuard();
void   ManagePositions();
void   CheckBasketTargets();
bool   UpdateTradingState();
void   HandleEntry();
void   PrepareBlackoutSchedule();
bool   InBlackout();
void   CheckTelegramCommands();
void   SendTelegramMessage(const string text);
string UrlEncode(const string src);
double CalculatePositionSize(double stopPoints);
void   ApplyPartialClose(const string symbol, const ulong ticket, const double entryPrice, const double currentPrice, const long type);

//--- lifecycle
int OnInit()
{
   trade.SetExpertMagicNumber(Magic);

   if(!InitializeIndicators())
      return(INIT_FAILED);

   ArraySetAsSeries(fastBuffer, true);
   ArraySetAsSeries(slowBuffer, true);
   ArraySetAsSeries(trendBuffer, true);
   ArraySetAsSeries(atrBuffer, true);

   PrepareBlackoutSchedule();
   tradingDay = iTime(InpSymbol, PERIOD_D1, 0);
   startDayEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(UseTimerForCommands)
      EventSetTimer(CommandIntervalSec);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(UseTimerForCommands)
      EventKillTimer();
   ReleaseIndicators();
}

void OnTick()
{
   if(Symbol() != InpSymbol)
      return;

   ManagePositions();
   CheckBasketTargets();

   bool canTrade = UpdateTradingState();

   if(!canTrade || InBlackout())
      return;

   HandleEntry();
}

void OnTimer()
{
   if(!UseTimerForCommands)
      return;

   if(TelegramToken != "" && TelegramChatID != 0)
      CheckTelegramCommands();
}

//--- indicator setup
bool InitializeIndicators()
{
   handleFast = iMA(InpSymbol, InpSignalTF, FastMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   handleSlow = iMA(InpSymbol, InpSignalTF, SlowMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   handleTrend = iMA(InpSymbol, InpTrendTF, TrendMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   handleATR = iATR(InpSymbol, InpSignalTF, ATRPeriod);

   if(handleFast == INVALID_HANDLE || handleSlow == INVALID_HANDLE ||
      handleTrend == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print(__FUNCTION__, ": indicator handle error");
      return false;
   }

   return true;
}

void ReleaseIndicators()
{
   if(handleFast != INVALID_HANDLE)
      IndicatorRelease(handleFast);
   if(handleSlow != INVALID_HANDLE)
      IndicatorRelease(handleSlow);
   if(handleTrend != INVALID_HANDLE)
      IndicatorRelease(handleTrend);
   if(handleATR != INVALID_HANDLE)
      IndicatorRelease(handleATR);
}

void RefreshIndicatorBuffers()
{
   if(CopyBuffer(handleFast, 0, 0, 3, fastBuffer) <= 0)
      ArrayInitialize(fastBuffer, 0.0);
   if(CopyBuffer(handleSlow, 0, 0, 3, slowBuffer) <= 0)
      ArrayInitialize(slowBuffer, 0.0);
   if(CopyBuffer(handleTrend, 0, 0, 3, trendBuffer) <= 0)
      ArrayInitialize(trendBuffer, 0.0);
   if(CopyBuffer(handleATR, 0, 0, 3, atrBuffer) <= 0)
      ArrayInitialize(atrBuffer, 0.0);
}

bool IsSpreadAcceptable()
{
   double spread = (SymbolInfoDouble(InpSymbol, SYMBOL_ASK) - SymbolInfoDouble(InpSymbol, SYMBOL_BID)) / _Point;
   return (spread <= MaxSpreadPoints);
}

bool IsAtrSufficient()
{
   RefreshIndicatorBuffers();
   double atrPoints = atrBuffer[0] / _Point;
   return (atrPoints >= MinATRPoints);
}

int TrendDirection()
{
   double slope = trendBuffer[0] - trendBuffer[1];
   if(trendBuffer[0] > trendBuffer[1] && slope > 0)
      return 1;
   if(trendBuffer[0] < trendBuffer[1] && slope < 0)
      return -1;
   return 0;
}

int SignalDirection()
{
   if(fastBuffer[0] > slowBuffer[0] && fastBuffer[1] <= slowBuffer[1])
      return 1;
   if(fastBuffer[0] < slowBuffer[0] && fastBuffer[1] >= slowBuffer[1])
      return -1;
   return 0;
}

int CountPositions(int direction)
{
   int total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!PositionSelectByIndex(i))
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != Magic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      if(direction == 0)
         total++;
      else if(direction > 0 && type == POSITION_TYPE_BUY)
         total++;
      else if(direction < 0 && type == POSITION_TYPE_SELL)
         total++;
   }
   return total;
}

double BasketProfit()
{
   double sum = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!PositionSelectByIndex(i))
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != Magic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol)
         continue;

      sum += PositionGetDouble(POSITION_PROFIT);
   }
   return sum;
}

void UpdateDailyRiskGuard()
{
   datetime currentDay = iTime(InpSymbol, PERIOD_D1, 0);
   if(currentDay != tradingDay)
   {
      tradingDay = currentDay;
      startDayEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      tradingEnabled = true;
      SendTelegramMessage("New day detected - trading reset");
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(startDayEquity <= 0)
      startDayEquity = equity;

   double dd = (startDayEquity - equity) / startDayEquity * 100.0;
   if(dd >= MaxDailyDrawdownPercent)
   {
      tradingEnabled = false;
      SendTelegramMessage("Daily drawdown limit reached. Trading paused.");
   }
}

void ManagePositions()
{
   UpdateDailyRiskGuard();

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!PositionSelectByIndex(i))
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != Magic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol)
         continue;

      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      long type = PositionGetInteger(POSITION_TYPE);
      double sl = PositionGetDouble(POSITION_SL);
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(InpSymbol, SYMBOL_BID) : SymbolInfoDouble(InpSymbol, SYMBOL_ASK);

      double profitPoints = (type == POSITION_TYPE_BUY) ? (currentPrice - entryPrice) / _Point : (entryPrice - currentPrice) / _Point;

      //--- break even
      if(BreakEvenPoints > 0 && profitPoints >= BreakEvenPoints)
      {
         double newSL = (type == POSITION_TYPE_BUY) ? entryPrice + (10 * _Point) : entryPrice - (10 * _Point);
         if((type == POSITION_TYPE_BUY && (sl < entryPrice || sl == 0.0)) ||
            (type == POSITION_TYPE_SELL && (sl > entryPrice || sl == 0.0)))
         {
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
      }

      //--- trailing stop
      if(TrailStartPoints > 0 && TrailStepPoints > 0 && profitPoints >= TrailStartPoints)
      {
         double trailPrice = (type == POSITION_TYPE_BUY) ? currentPrice - TrailStepPoints * _Point : currentPrice + TrailStepPoints * _Point;
         if(type == POSITION_TYPE_BUY)
         {
            if(sl < trailPrice)
               trade.PositionModify(ticket, trailPrice, PositionGetDouble(POSITION_TP));
         }
         else
         {
            if(sl == 0.0 || sl > trailPrice)
               trade.PositionModify(ticket, trailPrice, PositionGetDouble(POSITION_TP));
         }
      }

      //--- partial close
      ApplyPartialClose(InpSymbol, ticket, entryPrice, currentPrice, type);
   }
}

void CheckBasketTargets()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double basketProfit = BasketProfit();

   if(balance <= 0)
      return;

   double percent = (basketProfit / balance) * 100.0;

   if(BasketTargetPercent > 0 && percent >= BasketTargetPercent)
   {
      SendTelegramMessage("Basket target reached - closing all positions");
      for(int i = PositionsTotal() - 1; i >= 0; --i)
      {
         if(!PositionSelectByIndex(i))
            continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != Magic)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != InpSymbol)
            continue;

         ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
         trade.PositionClose(ticket);
      }
      lastSignalTime = TimeCurrent();
      return;
   }

   if(BasketStopPercent < 0 && percent <= BasketStopPercent)
   {
      SendTelegramMessage("Basket stop hit - closing all positions");
      for(int i = PositionsTotal() - 1; i >= 0; --i)
      {
         if(!PositionSelectByIndex(i))
            continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != Magic)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != InpSymbol)
            continue;

         ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
         trade.PositionClose(ticket);
      }
      tradingEnabled = false;
   }
}

bool UpdateTradingState()
{
   UpdateDailyRiskGuard();

   if(!tradingEnabled)
      return false;

   if(!IsSpreadAcceptable())
      return false;

   if(!IsAtrSufficient())
      return false;

   return true;
}

void HandleEntry()
{
   if(CountPositions(0) >= MaxPositions)
      return;

   if(lastSignalTime != 0 && (TimeCurrent() - lastSignalTime) < CooldownMinutes * 60)
      return;

   RefreshIndicatorBuffers();
   int trendDir = TrendDirection();
   int signalDir = SignalDirection();

   if(trendDir == 0 || signalDir == 0 || trendDir != signalDir)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick))
      return;

   double atrPoints = atrBuffer[0] / _Point;
   double stopPoints = atrPoints * ATRMultiplier;
   if(stopPoints <= 0)
      return;

   double lot = CalculatePositionSize(stopPoints);
   if(lot <= 0)
      return;

   double price = (signalDir > 0) ? tick.ask : tick.bid;
   double sl = (signalDir > 0) ? price - stopPoints * _Point : price + stopPoints * _Point;
   double tp = (signalDir > 0) ? price + stopPoints * 1.8 * _Point
                               : price - stopPoints * 1.8 * _Point;

   if(signalDir > 0 && !AllowBuy)
      return;
   if(signalDir < 0 && !AllowSell)
      return;

   bool result = false;
   if(signalDir > 0)
      result = trade.Buy(lot, InpSymbol, price, sl, tp, "Nitro long");
   else
      result = trade.Sell(lot, InpSymbol, price, sl, tp, "Nitro short");

   if(result)
   {
      lastSignalTime = TimeCurrent();
      SendTelegramMessage((signalDir > 0) ? "Nitro opened long" : "Nitro opened short");
   }
   else
   {
      Print("Order failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
}

void PrepareBlackoutSchedule()
{
   blackoutCount = 0;
}

bool InBlackout()
{
   datetime now = TimeCurrent();
   for(int i = 0; i < blackoutCount; ++i)
   {
      if(now >= blackout[i].start && now <= blackout[i].end)
         return true;
   }
   return false;
}

void CheckTelegramCommands()
{
   if(TelegramToken == "" || TelegramChatID == 0)
      return;

   string url = "https://api.telegram.org/bot" + TelegramToken +
                "/getUpdates?timeout=5&offset=" + IntegerToString(lastUpdateId + 1);
   char result[];
   string headers;
   int timeout = 5000;
   int res = WebRequest("GET", url, "", 0, result, headers, timeout);
   if(res <= 0)
      return;

   string json = CharArrayToString(result);

   int idx = StringFind(json, "\"update_id\":");
   if(idx >= 0)
      lastUpdateId = (int)StringToInteger(StringSubstr(json, idx + 12, 10));

   if(StringFind(json, "/startEA") >= 0)
   {
      tradingEnabled = true;
      SendTelegramMessage("Nitro EA resumed");
   }
   if(StringFind(json, "/stopEA") >= 0)
   {
      tradingEnabled = false;
      SendTelegramMessage("Nitro EA paused");
   }
   if(StringFind(json, "/statusAccount") >= 0)
   {
      string status = "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) +
                      " Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) +
                      " Positions: " + IntegerToString(CountPositions(0));
      SendTelegramMessage(status);
   }
   if(StringFind(json, "/closeAll") >= 0)
   {
      for(int i = PositionsTotal() - 1; i >= 0; --i)
      {
         if(!PositionSelectByIndex(i))
            continue;
         if((int)PositionGetInteger(POSITION_MAGIC) != Magic)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != InpSymbol)
            continue;
         trade.PositionClose((ulong)PositionGetInteger(POSITION_TICKET));
      }
      SendTelegramMessage("All Nitro positions closed");
   }
}

void SendTelegramMessage(const string text)
{
   if(TelegramToken == "" || TelegramChatID == 0)
      return;

   string url = "https://api.telegram.org/bot" + TelegramToken +
                "/sendMessage?chat_id=" + IntegerToString((int)TelegramChatID) +
                "&text=" + UrlEncode(text);
   char result[];
   string headers;
   WebRequest("GET", url, "", 0, result, headers, 5000);
}

string UrlEncode(const string src)
{
   string encoded = src;
   StringReplace(encoded, " ", "%20");
   StringReplace(encoded, "\n", "%0A");
   return encoded;
}

double CalculatePositionSize(double stopPoints)
{
   if(stopPoints <= 0)
      return 0.0;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPerTradePercent / 100.0;

   double tickValue = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);

   if(tickValue <= 0 || tickSize <= 0)
      return minLot;

   double stopValuePerLot = (stopPoints * _Point / tickSize) * tickValue;
   if(stopValuePerLot <= 0)
      return minLot;

   double lots = riskMoney / stopValuePerLot;
   lots = MathFloor(lots / lotStep) * lotStep;

   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;

   return NormalizeDouble(lots, (int)SymbolInfoInteger(InpSymbol, SYMBOL_VOLUME_DIGITS));
}

void ApplyPartialClose(const string symbol, const ulong ticket, const double entryPrice, const double currentPrice, const long type)
{
   if(PartialClosePercent <= 0 || PartialCloseTriggerPoints <= 0)
      return;

   double profitPoints = (type == POSITION_TYPE_BUY) ? (currentPrice - entryPrice) / _Point : (entryPrice - currentPrice) / _Point;
   if(profitPoints < PartialCloseTriggerPoints)
      return;

   double volume = PositionGetDouble(POSITION_VOLUME);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   double closeLots = volume * (PartialClosePercent / 100.0);
   closeLots = MathFloor(closeLots / lotStep) * lotStep;

   if(closeLots < minLot)
      return;

   if(type == POSITION_TYPE_BUY)
      trade.PositionClosePartial(ticket, closeLots, SymbolInfoDouble(symbol, SYMBOL_BID));
   else
      trade.PositionClosePartial(ticket, closeLots, SymbolInfoDouble(symbol, SYMBOL_ASK));
}
