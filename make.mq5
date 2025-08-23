#property copyright "2025"
#property version   "1.01"
#property strict

#include <Trade/Trade.mqh>

/*
   Trend-based batch trader for XAUUSDc (Exness Cent Account)
   - enters in trending direction using moving averages
   - opens one order every EntryInterval seconds until BatchSize is reached
   - closes entire batch when profit target is hit
   - filters entries using ATR to avoid choppy markets
   - risk is controlled via ATR-based stop and equity drawdown check
   - supports basic Telegram remote commands
*/

CTrade trade;

input string InpSymbol = "XAUUSDc";          // Trading symbol
input ENUM_TIMEFRAMES InpTF = PERIOD_M5;       // Timeframe for calculations
input int FastMA = 20;                         // Fast MA period
input int SlowMA = 50;                         // Slow MA period
input double LotSize = 0.01;                   // Max lot size for cent account
input double RiskPerTradePercent = 1.0;        // Risk % of balance per trade
input int    ATRPeriod = 14;                   // ATR period
input double ATRMultiplier = 2.0;              // ATR multiple for stops
input double MinATR = 100;                     // Minimum ATR (points) to trade
input double MaxDrawdownPercent = 5.0;         // Stop trading on this equity DD

input int EntryInterval = 17;                  // Seconds between entries
input int BatchSize = 7;                       // Orders per batch
input double BatchProfitPercent = 0.1;         // % balance profit to close batch
input double VolatilityThreshold = 100;        // Price change (points) to block new batch

input bool   UseTrailing = true;               // Enable multi-level trailing stop
input int    BreakevenPoints = 300;            // Profit points to move SL to breakeven
input int    TrailingStepPoints = 100;         // Points for each further trailing step

input string TelegramToken = "";              // Telegram bot token
input long   TelegramChatID = 0;               // Telegram chat id

input int Magic = 202501;                      // Magic number

int    handleFast;
int    handleSlow;
double fastBuffer[];
double slowBuffer[];
datetime lastOrderTime = 0;
double batchStartBalance = 0;
bool   eaEnabled = true;
bool   allowNewBatch = true;
double lastPrice = 0;
int    lastUpdateId = 0;
int    handleATR;
double atrBuffer[];
double peakEquity = 0;

//--- utility prototypes
int    CountBatchPositions();
double BatchProfit();
void   CloseBatch();
bool   MarketVolatile();
void   CheckTelegramCommands();
void   SendTelegramMessage(string msg);
string UrlEncode(string text);
void   ManageTrailingStops();

int OnInit()
{
   handleFast = iMA(InpSymbol, InpTF, FastMA, 0, MODE_EMA, PRICE_CLOSE);
   if(handleFast == INVALID_HANDLE)
      return(INIT_FAILED);

   handleSlow = iMA(InpSymbol, InpTF, SlowMA, 0, MODE_EMA, PRICE_CLOSE);
   if(handleSlow == INVALID_HANDLE)
      return(INIT_FAILED);

   handleATR = iATR(InpSymbol, InpTF, ATRPeriod);
   if(handleATR == INVALID_HANDLE)
      return(INIT_FAILED);

   ArraySetAsSeries(fastBuffer, true);
   ArraySetAsSeries(slowBuffer, true);
   ArraySetAsSeries(atrBuffer, true);

   trade.SetExpertMagicNumber(Magic);

   EventSetTimer(1);
   peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(handleFast != INVALID_HANDLE)
      IndicatorRelease(handleFast);
   if(handleSlow != INVALID_HANDLE)
      IndicatorRelease(handleSlow);

   if(handleATR != INVALID_HANDLE)
      IndicatorRelease(handleATR);
}

void OnTick()
{
   if(_Symbol != InpSymbol || !eaEnabled)
      return;

   CheckTelegramCommands();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > peakEquity)
      peakEquity = equity;
   double dd = (peakEquity - equity) / peakEquity * 100.0;
   if(dd > MaxDrawdownPercent)
   {
      eaEnabled = false;
      SendTelegramMessage("Max drawdown reached");
      return;
   }

   if(CopyBuffer(handleFast, 0, 0, 2, fastBuffer) <= 0)
      return;
   if(CopyBuffer(handleSlow, 0, 0, 2, slowBuffer) <= 0)
      return;
   if(CopyBuffer(handleATR, 0, 0, 1, atrBuffer) <= 0)
      return;

   double fastPrev = fastBuffer[1];
   double fastCurr = fastBuffer[0];
   double slowPrev = slowBuffer[1];
   double slowCurr = slowBuffer[0];
   double point    = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   int    digits   = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);
   double atr      = atrBuffer[0] / point;

   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);

   bool trendingUp = (fastCurr > slowCurr && fastPrev > slowPrev);
   bool trendingDown = (fastCurr < slowCurr && fastPrev < slowPrev);

   if(atr < MinATR)
      return;

   int openPositions = CountBatchPositions();

   if(openPositions == 0)
   {
      allowNewBatch = !MarketVolatile();
      if(allowNewBatch)
         batchStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   }

   if(TimeCurrent() - lastOrderTime >= EntryInterval && openPositions < BatchSize && allowNewBatch)
   {
      int slPoints = (int)(atr * ATRMultiplier);
      int tpPoints = slPoints * 2;
      double lot = LotSize;
      if(RiskPerTradePercent > 0 && slPoints > 0)
      {
         double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPerTradePercent / 100.0;
         double tickValue = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_VALUE);
         if(tickValue > 0)
            lot = MathMin(LotSize, NormalizeDouble(risk/(slPoints*point*tickValue), 2));
      }

      if(trendingUp)
      {
         trade.Buy(lot, InpSymbol, 0.0,
                   NormalizeDouble(bid - slPoints*point, digits),
                   NormalizeDouble(bid + tpPoints*point, digits));
         lastOrderTime = TimeCurrent();
      }
      else if(trendingDown)
      {
         trade.Sell(lot, InpSymbol, 0.0,
                    NormalizeDouble(ask + slPoints*point, digits),
                    NormalizeDouble(ask - tpPoints*point, digits));
         lastOrderTime = TimeCurrent();
      }
   }

   if(UseTrailing)
      ManageTrailingStops();

   double profit = BatchProfit();
   if(openPositions > 0 && profit >= batchStartBalance * BatchProfitPercent / 100.0)
   {
      CloseBatch();
      allowNewBatch = true;
   }

   lastPrice = bid;
}

void OnTimer()
{
   CheckTelegramCommands();
}

//--- multi-level trailing stop manager
void ManageTrailingStops()
{
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionSelectByIndex(i))
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != Magic ||
         PositionGetString(POSITION_SYMBOL) != InpSymbol)
         continue;

      ulong  ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      long   type   = (long)PositionGetInteger(POSITION_TYPE);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double price  = (type==POSITION_TYPE_BUY ? bid : ask);
      double profitPoints = (type==POSITION_TYPE_BUY ? price - entry : entry - price) / point;

      if(profitPoints < BreakevenPoints)
         continue;

      int steps = (int)((profitPoints - BreakevenPoints) / TrailingStepPoints);
      double newSL = entry;
      if(steps > 0)
      {
         if(type==POSITION_TYPE_BUY)
            newSL = entry + steps * TrailingStepPoints * point;
         else
            newSL = entry - steps * TrailingStepPoints * point;
      }

      if(type==POSITION_TYPE_BUY)
      {
         if(newSL > sl + point && newSL < price)
            trade.PositionModify(ticket, NormalizeDouble(newSL, digits), tp);
      }
      else
      {
         if(newSL < sl - point && newSL > price)
            trade.PositionModify(ticket, NormalizeDouble(newSL, digits), tp);
      }
   }
}

//--- count positions belonging to current EA
int CountBatchPositions()
{
   int total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByIndex(i))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == Magic &&
            PositionGetString(POSITION_SYMBOL) == InpSymbol)
            total++;
      }
   }
   return total;
}

//--- calculate profit of current batch
double BatchProfit()
{
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByIndex(i))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == Magic &&
            PositionGetString(POSITION_SYMBOL) == InpSymbol)
            total += PositionGetDouble(POSITION_PROFIT);
      }
   }
   return total;
}

//--- close all positions in batch
void CloseBatch()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByIndex(i))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == Magic &&
            PositionGetString(POSITION_SYMBOL) == InpSymbol)
         {
            ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
            trade.PositionClose(ticket);
         }
      }
   }
}

//--- simple volatility check
bool MarketVolatile()
{
   if(lastPrice == 0)
      return false;
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   double change = MathAbs(bid - lastPrice);
   return (change > VolatilityThreshold * point);
}

//--- Telegram communication
void CheckTelegramCommands()
{
   if(TelegramToken == "" || TelegramChatID == 0)
      return;

   string url = "https://api.telegram.org/bot" + TelegramToken +
                "/getUpdates?offset=" + IntegerToString(lastUpdateId + 1);
   char result[];
   string headers;
   int timeout = 5000;
   int res = WebRequest("GET", url, "", 0, result, headers, timeout);
   if(res <= 0)
      return;
   string json = CharArrayToString(result);

   if(StringFind(json, "/startEA") >= 0)
   {
      eaEnabled = true;
      SendTelegramMessage("EA started");
   }
   if(StringFind(json, "/stopEA") >= 0)
   {
      eaEnabled = false;
      SendTelegramMessage("EA stopped");
   }
   if(StringFind(json, "/statusAccount") >= 0)
   {
      string info = "Balance:" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) +
                    " Equity:" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2);
      SendTelegramMessage(info);
   }
   if(StringFind(json, "/manualCloseBatch") >= 0)
   {
      CloseBatch();
      SendTelegramMessage("Batch closed");
   }

   string pattern = CharToString(34) + "update_id" + CharToString(34) + ":";
   int p = StringFind(json, pattern);
   if(p >= 0)
      lastUpdateId = (int)StringToInteger(StringSubstr(json, p + 11, 10));
}

void SendTelegramMessage(string msg)
{
   if(TelegramToken == "" || TelegramChatID == 0)
      return;
   string url = "https://api.telegram.org/bot" + TelegramToken +
                "/sendMessage?chat_id=" + IntegerToString((int)TelegramChatID) +
                "&text=" + UrlEncode(msg);
   char result[];
   string headers;
   int timeout = 5000;
   WebRequest("GET", url, "", 0, result, headers, timeout);
}

string UrlEncode(string text)
{
   StringReplace(text, " ", "%20");
   return text;
}

