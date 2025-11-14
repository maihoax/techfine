//+------------------------------------------------------------------+
//|                                    XAUUSD_MACD_Trend_EA.mq5      |
//|                            Gold MACD Multi-Timeframe Trend EA    |
//|                  Advanced Trading System with Complete Safety    |
//+------------------------------------------------------------------+
#property copyright "2025"
#property version   "2.00"
#property description "MACD Multi-Timeframe Trend EA for Gold (XAUUSD)"
#property description "Features: MTF Analysis, Risk Management, Time Filter, Telegram, Google Sheets, Modern UI"
#property strict

// Include all modules
#include <Trade/Trade.mqh>
#include "Include/MACD_MTF_Signal.mqh"
#include "Include/RiskManager.mqh"
#include "Include/TimeFilter.mqh"
#include "Include/TelegramBot.mqh"
#include "Include/GoogleSheets.mqh"
#include "Include/UIPanel.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+

//--- Trading Parameters
input group "=== Trading Settings ==="
input string InpSymbol = "XAUUSDc";              // Trading Symbol
input int InpMagicNumber = 202502;               // Magic Number

//--- MACD Parameters (Optimized for Gold)
input group "=== MACD Multi-Timeframe Settings ==="
input int InpFastEMA = 12;                       // Fast EMA Period
input int InpSlowEMA = 26;                       // Slow EMA Period
input int InpSignalSMA = 9;                      // Signal SMA Period
input int InpMinTimeframesMatch = 2;             // Minimum Timeframes to Match (2-4)

//--- Risk Management
input group "=== Risk Management ==="
input double InpMaxDrawdownPercent = 5.0;        // Max Drawdown % (Stop Trading)
input double InpRiskPerTradePercent = 1.0;       // Risk % Per Trade
input double InpMaxLotSize = 0.01;               // Maximum Lot Size
input int InpATRPeriod = 14;                     // ATR Period for SL
input double InpATRMultiplier = 2.0;             // ATR Multiplier for SL
input double InpMinATR = 100;                    // Minimum ATR (points)
input double InpMaxMarginUsage = 70.0;           // Max Margin Usage %

//--- Time Filter
input group "=== Time Filter ==="
input bool InpUseHourFilter = false;             // Enable Hour Filter
input int InpStartHour = 0;                      // Start Hour (0-23)
input int InpEndHour = 23;                       // End Hour (0-23)
input bool InpUseDayFilter = false;              // Enable Day Filter
input bool InpTradeMonday = true;                // Trade on Monday
input bool InpTradeTuesday = true;               // Trade on Tuesday
input bool InpTradeWednesday = true;             // Trade on Wednesday
input bool InpTradeThursday = true;              // Trade on Thursday
input bool InpTradeFriday = true;                // Trade on Friday
input bool InpUseSessionFilter = false;          // Enable Session Filter (Gold)
input bool InpAllowAsianSession = true;          // Allow Asian Session
input bool InpAllowEuropeanSession = true;       // Allow European Session
input bool InpAllowUSSession = true;             // Allow US Session

//--- Trade Management
input group "=== Trade Management ==="
input bool InpUseTrailingStop = true;            // Enable Trailing Stop
input int InpBreakevenPoints = 300;              // Breakeven Points
input int InpTrailingStepPoints = 100;           // Trailing Step Points
input int InpMaxPositions = 5;                   // Maximum Open Positions

//--- Telegram Settings
input group "=== Telegram Integration ==="
input string InpTelegramToken = "";              // Telegram Bot Token
input long InpTelegramChatID = 0;                // Telegram Chat ID
input bool InpSendSignalAlerts = true;           // Send Signal Alerts

//--- Google Sheets Settings
input group "=== Google Sheets Integration ==="
input string InpGoogleScriptURL = "";            // Google Apps Script URL
input int InpGSUpdateInterval = 300;             // Update Interval (seconds)

//--- UI Settings
input group "=== UI Panel Settings ==="
input bool InpShowPanel = true;                  // Show UI Panel
input int InpPanelX = 20;                        // Panel X Position
input int InpPanelY = 50;                        // Panel Y Position

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade               trade;
CMACD_MTF_Signal     macdSignal;
CRiskManager         riskManager;
CTimeFilter          timeFilter;
CTelegramBot         telegram;
CGoogleSheets        googleSheets;
CUIPanel             uiPanel;

datetime             lastOrderTime = 0;
int                  orderInterval = 15;         // Seconds between orders
bool                 eaEnabled = true;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize MACD Signal
   if(!macdSignal.Init(InpSymbol, InpFastEMA, InpSlowEMA, InpSignalSMA, InpMinTimeframesMatch))
   {
      Print("Failed to initialize MACD Signal");
      return INIT_FAILED;
   }

   // Initialize Risk Manager
   if(!riskManager.Init(InpSymbol, InpMagicNumber, InpMaxDrawdownPercent,
                        InpRiskPerTradePercent, InpMaxLotSize))
   {
      Print("Failed to initialize Risk Manager");
      return INIT_FAILED;
   }

   riskManager.SetATRParameters(InpATRPeriod, InpATRMultiplier, InpMinATR);
   riskManager.SetMarginLimit(InpMaxMarginUsage);

   // Initialize Time Filter
   timeFilter.Init(InpUseHourFilter, InpStartHour, InpEndHour, InpUseDayFilter);
   timeFilter.SetDaysAllowed(InpTradeMonday, InpTradeTuesday, InpTradeWednesday,
                              InpTradeThursday, InpTradeFriday);
   timeFilter.SetSessionFilter(InpUseSessionFilter);
   timeFilter.SetSessionsAllowed(InpAllowAsianSession, InpAllowEuropeanSession,
                                  InpAllowUSSession);

   // Initialize Telegram
   if(InpTelegramToken != "" && InpTelegramChatID != 0)
   {
      if(telegram.Init(InpTelegramToken, InpTelegramChatID))
      {
         telegram.SendMessage("✅ XAUUSD MACD Trend EA Started\nAccount: " +
                             IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)));
      }
   }

   // Initialize Google Sheets
   if(InpGoogleScriptURL != "")
   {
      if(googleSheets.Init(InpGoogleScriptURL, InpGSUpdateInterval))
      {
         Print("Google Sheets integration active");
      }
   }

   // Initialize UI Panel
   if(InpShowPanel)
   {
      uiPanel.Init("MACD_EA_Panel", InpPanelX, InpPanelY);
   }

   // Set timer for periodic updates
   EventSetTimer(1);

   Print("XAUUSD MACD Trend EA initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   if(InpShowPanel)
      uiPanel.DeletePanel();

   if(telegram.IsEnabled())
      telegram.SendMessage("⏹️ EA Stopped\nReason: " + IntegerToString(reason));

   Print("XAUUSD MACD Trend EA stopped");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only trade on the specified symbol
   if(_Symbol != InpSymbol)
      return;

   // Check Telegram commands
   CheckTelegramCommands();

   // Check if trading is allowed by risk manager
   if(!riskManager.IsTradingAllowed() || !eaEnabled)
   {
      UpdateUI();
      return;
   }

   // Check time filter
   if(!timeFilter.IsTradeAllowed())
   {
      UpdateUI();
      return;
   }

   // Check margin availability
   if(!riskManager.IsMarginAvailable())
   {
      UpdateUI();
      return;
   }

   // Get MACD signal
   int signal = macdSignal.GetSignal();
   double signalStrength = macdSignal.GetSignalStrength();

   // Send signal alert if enabled
   if(InpSendSignalAlerts && signal != 0 && telegram.IsEnabled())
   {
      static int lastSignal = 0;
      if(signal != lastSignal)
      {
         string signalText = (signal == 1) ? "BUY" : "SELL";
         telegram.SendSignalNotification(signalText, signalStrength);
         lastSignal = signal;
      }
   }

   // Check if we can open new position
   int openPositions = riskManager.CountPositions();
   if(openPositions >= InpMaxPositions)
   {
      UpdateUI();
      return;
   }

   // Check order interval
   if(TimeCurrent() - lastOrderTime < orderInterval)
   {
      UpdateUI();
      return;
   }

   // Execute trades based on signal
   if(signal == 1) // BUY Signal
   {
      ExecuteBuyOrder(signalStrength);
   }
   else if(signal == -1) // SELL Signal
   {
      ExecuteSellOrder(signalStrength);
   }

   // Manage trailing stops
   if(InpUseTrailingStop)
      ManageTrailingStops();

   // Update UI
   UpdateUI();

   // Update Google Sheets
   UpdateGoogleSheets();
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckTelegramCommands();
   UpdateUI();
   UpdateGoogleSheets();
}

//+------------------------------------------------------------------+
//| Execute Buy Order                                                |
//+------------------------------------------------------------------+
void ExecuteBuyOrder(double signalStrength)
{
   int slPoints = riskManager.GetATRStopLoss();
   if(slPoints <= 0)
      return;

   double lotSize = riskManager.CalculateLotSize(slPoints);
   if(lotSize < SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN))
      return;

   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);

   double sl = NormalizeDouble(ask - slPoints * point, digits);
   double tp = NormalizeDouble(ask + slPoints * 2 * point, digits);

   if(trade.Buy(lotSize, InpSymbol, ask, sl, tp, "MACD MTF Buy"))
   {
      lastOrderTime = TimeCurrent();

      if(telegram.IsEnabled())
         telegram.SendTradeNotification("OPENED", InpSymbol, "BUY", lotSize, ask);

      if(googleSheets.IsEnabled())
         googleSheets.LogTrade("OPEN", InpSymbol, "BUY", lotSize, ask, sl, tp);
   }
}

//+------------------------------------------------------------------+
//| Execute Sell Order                                               |
//+------------------------------------------------------------------+
void ExecuteSellOrder(double signalStrength)
{
   int slPoints = riskManager.GetATRStopLoss();
   if(slPoints <= 0)
      return;

   double lotSize = riskManager.CalculateLotSize(slPoints);
   if(lotSize < SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN))
      return;

   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);

   double sl = NormalizeDouble(bid + slPoints * point, digits);
   double tp = NormalizeDouble(bid - slPoints * 2 * point, digits);

   if(trade.Sell(lotSize, InpSymbol, bid, sl, tp, "MACD MTF Sell"))
   {
      lastOrderTime = TimeCurrent();

      if(telegram.IsEnabled())
         telegram.SendTradeNotification("OPENED", InpSymbol, "SELL", lotSize, bid);

      if(googleSheets.IsEnabled())
         googleSheets.LogTrade("OPEN", InpSymbol, "SELL", lotSize, bid, sl, tp);
   }
}

//+------------------------------------------------------------------+
//| Manage Trailing Stops                                            |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionSelectByIndex(i))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         PositionGetString(POSITION_SYMBOL) != InpSymbol)
         continue;

      ulong ticket = PositionGetInteger(POSITION_TICKET);
      long type = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double currentPrice = (type == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(InpSymbol, SYMBOL_BID) :
                            SymbolInfoDouble(InpSymbol, SYMBOL_ASK);

      double profitPoints = (type == POSITION_TYPE_BUY) ?
                            (currentPrice - entry) / point :
                            (entry - currentPrice) / point;

      if(profitPoints < InpBreakevenPoints)
         continue;

      int steps = (int)((profitPoints - InpBreakevenPoints) / InpTrailingStepPoints);
      double newSL = entry;

      if(steps > 0)
      {
         if(type == POSITION_TYPE_BUY)
            newSL = entry + steps * InpTrailingStepPoints * point;
         else
            newSL = entry - steps * InpTrailingStepPoints * point;
      }

      bool shouldModify = false;
      if(type == POSITION_TYPE_BUY)
      {
         if(newSL > sl + point && newSL < currentPrice)
            shouldModify = true;
      }
      else
      {
         if(newSL < sl - point && newSL > currentPrice)
            shouldModify = true;
      }

      if(shouldModify)
         trade.PositionModify(ticket, NormalizeDouble(newSL, digits), tp);
   }
}

//+------------------------------------------------------------------+
//| Check Telegram Commands                                          |
//+------------------------------------------------------------------+
void CheckTelegramCommands()
{
   if(!telegram.IsEnabled())
      return;

   if(telegram.CheckCommands())
   {
      string cmd = telegram.GetLastCommand();

      if(cmd == "/start" || cmd == "/startEA")
      {
         eaEnabled = true;
         telegram.SendMessage("✅ EA Started");
      }
      else if(cmd == "/stop" || cmd == "/stopEA")
      {
         eaEnabled = false;
         telegram.SendMessage("⏹️ EA Stopped");
      }
      else if(cmd == "/status")
      {
         telegram.SendAccountStatus();
      }
      else if(cmd == "/positions")
      {
         telegram.SendPositionsInfo();
      }
      else if(cmd == "/closeall")
      {
         if(riskManager.CloseAllPositions())
            telegram.SendMessage("✅ All positions closed");
         else
            telegram.SendMessage("❌ Error closing positions");
      }
      else if(cmd == "/signal")
      {
         int signal = macdSignal.GetSignal();
         double strength = macdSignal.GetSignalStrength();
         string signalText = (signal == 1) ? "BUY" :
                            (signal == -1) ? "SELL" : "NEUTRAL";
         telegram.SendSignalNotification(signalText, strength);
      }
      else if(cmd == "/help")
      {
         string help = "📖 *Available Commands:*\n\n";
         help += "/start - Start EA\n";
         help += "/stop - Stop EA\n";
         help += "/status - Account status\n";
         help += "/positions - Open positions\n";
         help += "/signal - Current signal\n";
         help += "/closeall - Close all positions\n";
         help += "/help - Show this help";
         telegram.SendMessage(help);
      }
   }
}

//+------------------------------------------------------------------+
//| Update UI Panel                                                  |
//+------------------------------------------------------------------+
void UpdateUI()
{
   if(!InpShowPanel)
      return;

   int signal = macdSignal.GetSignal();
   double strength = macdSignal.GetSignalStrength();
   string signalText = (signal == 1) ? "BUY" :
                       (signal == -1) ? "SELL" : "NEUTRAL";

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = riskManager.GetTotalProfit();
   int positions = riskManager.CountPositions();
   double drawdown = riskManager.GetCurrentDrawdown();
   double marginUsed = riskManager.GetMarginUsage();

   bool tradingAllowed = eaEnabled && riskManager.IsTradingAllowed() &&
                         timeFilter.IsTradeAllowed();

   string timeFilterStatus = timeFilter.IsTradeAllowed() ? "ALLOWED" : "BLOCKED";

   uiPanel.Update(signalText, strength, balance, equity, profit,
                  positions, drawdown, marginUsed, tradingAllowed,
                  timeFilterStatus);
}

//+------------------------------------------------------------------+
//| Update Google Sheets Statistics                                 |
//+------------------------------------------------------------------+
void UpdateGoogleSheets()
{
   if(!googleSheets.IsEnabled())
      return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = riskManager.GetTotalProfit();
   int positions = riskManager.CountPositions();
   double drawdown = riskManager.GetCurrentDrawdown();

   googleSheets.UpdateStatistics(balance, equity, profit, positions, drawdown);
}
