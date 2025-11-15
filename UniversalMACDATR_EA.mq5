//+------------------------------------------------------------------+
//|                                      UniversalMACDATR_EA.mq5     |
//|                      Universal MACD-ATR Trading System           |
//|           Multi-Symbol, Multi-Account, Context-Aware Strategy    |
//+------------------------------------------------------------------+
#property copyright "2025"
#property version   "1.00"
#property description "Universal MACD-ATR EA for all symbols and account types"
#property description "Based on MQL5 best practices: MACD blueprint, ATR-based risk,"
#property description "context detection, balance regression optimization"
#property strict

//--- Include universal modules
#include "Include/Universal/Indicators.mqh"
#include "Include/Universal/Signals.mqh"
#include "Include/Universal/Risk.mqh"
#include "Include/Universal/Orders.mqh"

//+------------------------------------------------------------------+
//| EA State Machine                                                 |
//+------------------------------------------------------------------+
enum ENUM_EA_STATE
{
   STATE_INIT = 0,          // Initializing
   STATE_WAIT_BAR,          // Waiting for new bar
   STATE_SIGNAL,            // Checking for signals
   STATE_EXECUTE,           // Executing orders
   STATE_MANAGE,            // Managing positions
   STATE_ERROR              // Error state
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+

//--- General Settings
input group "=== General Settings ==="
input int                InpMagicNumber = 100001;           // Magic Number
input string             InpTradeComment = "Universal-MACD-ATR";  // Trade Comment

//--- MACD Settings
input group "=== MACD Settings ==="
input int                InpMACDFast = 12;                  // MACD Fast EMA
input int                InpMACDSlow = 26;                  // MACD Slow EMA
input int                InpMACDSignal = 9;                 // MACD Signal SMA

//--- ATR Settings
input group "=== ATR Settings ==="
input int                InpATRPeriod = 14;                 // ATR Period
input double             InpATRMultiplierSL = 2.0;          // ATR Multiplier for SL
input double             InpATRMultiplierTP = 3.0;          // ATR Multiplier for TP
input double             InpMinATRPoints = 0;               // Min ATR Points (0=auto)

//--- Risk Management
input group "=== Risk Management ==="
input double             InpRiskPercent = 1.0;              // Risk per Trade (%)
input double             InpMaxLotSize = 1.0;               // Maximum Lot Size
input double             InpMaxDrawdownPercent = 10.0;      // Max Drawdown (%)
input double             InpMaxMarginPercent = 50.0;        // Max Margin Usage (%)
input int                InpMaxPositions = 3;               // Max Total Positions
input int                InpMaxPositionsPerSymbol = 1;      // Max Positions per Symbol

//--- Signal Settings
input group "=== Signal Settings ==="
input int                InpContextBars = 10;               // Bars for Context Detection
input bool               InpRequireZeroAlign = true;        // Require Zero-Line Alignment
input bool               InpRequireHistExpand = true;       // Require Histogram Expansion
input bool               InpAllowPullbackEntry = true;      // Allow Pullback Entries
input int                InpMinBarsBetweenSignals = 3;      // Min Bars Between Signals

//--- Trade Management
input group "=== Trade Management ==="
input bool               InpUseTrailing = true;             // Use Trailing Stop
input double             InpTrailingPoints = 200;           // Trailing Stop (points)
input double             InpTrailingStep = 50;              // Trailing Step (points)
input bool               InpUseBreakeven = true;            // Use Breakeven
input double             InpBreakevenPoints = 150;          // Breakeven Activation (points)
input double             InpBreakevenLock = 10;             // Breakeven Lock (points)

//--- Advanced Settings
input group "=== Advanced Settings ==="
input bool               InpEnableLogging = true;           // Enable Detailed Logging
input ENUM_TIMEFRAMES    InpTimeframe = PERIOD_CURRENT;     // Timeframe (CURRENT=chart)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+

// EA state
ENUM_EA_STATE            g_eaState = STATE_INIT;
datetime                 g_lastBarTime = 0;
bool                     g_initialized = false;

// Module instances
CUniversalIndicators     g_indicators;
CUniversalSignals        g_signals;
CUniversalRisk          g_risk;
CUniversalOrders        g_orders;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("Universal MACD-ATR EA v1.00");
   Print("Initializing for ", _Symbol, " on ", EnumToString(InpTimeframe));
   Print("========================================");

   // Initialize indicators
   if(!g_indicators.Init(_Symbol, InpTimeframe, InpMACDFast, InpMACDSlow, InpMACDSignal, InpATRPeriod))
   {
      Print("ERROR: Failed to initialize indicators");
      g_eaState = STATE_ERROR;
      return INIT_FAILED;
   }

   // Initialize signals
   if(!g_signals.Init(&g_indicators, InpMinATRPoints))
   {
      Print("ERROR: Failed to initialize signals");
      g_eaState = STATE_ERROR;
      return INIT_FAILED;
   }

   // Configure signal parameters
   g_signals.SetContextBars(InpContextBars);
   g_signals.SetZeroLineAlignment(InpRequireZeroAlign);
   g_signals.SetHistogramExpansionFilter(InpRequireHistExpand);
   g_signals.SetPullbackEntry(InpAllowPullbackEntry, 3);
   g_signals.SetMinBarsBetweenSignals(InpMinBarsBetweenSignals);

   // Initialize risk manager
   if(!g_risk.Init(_Symbol, InpMagicNumber, &g_indicators, InpRiskPercent, InpMaxLotSize))
   {
      Print("ERROR: Failed to initialize risk manager");
      g_eaState = STATE_ERROR;
      return INIT_FAILED;
   }

   // Configure risk parameters
   g_risk.SetMaxDrawdown(InpMaxDrawdownPercent);
   g_risk.SetMaxMargin(InpMaxMarginPercent);
   g_risk.SetATRMultipliers(InpATRMultiplierSL, InpATRMultiplierTP);
   g_risk.SetMinATRPoints(InpMinATRPoints);
   g_risk.SetMaxPositions(InpMaxPositions);
   g_risk.SetMaxPositionsPerSymbol(InpMaxPositionsPerSymbol);

   // Initialize order manager
   if(!g_orders.Init(_Symbol, InpMagicNumber, 10))
   {
      Print("ERROR: Failed to initialize order manager");
      g_eaState = STATE_ERROR;
      return INIT_FAILED;
   }

   // Set initial state
   g_eaState = STATE_WAIT_BAR;
   g_lastBarTime = iTime(_Symbol, InpTimeframe, 0);
   g_initialized = true;

   Print("========================================");
   Print("Initialization successful");
   Print("Magic Number: ", InpMagicNumber);
   Print("Risk per Trade: ", InpRiskPercent, "%");
   Print("Max Drawdown: ", InpMaxDrawdownPercent, "%");
   Print("ATR SL Multiplier: ", InpATRMultiplierSL);
   Print("ATR TP Multiplier: ", InpATRMultiplierTP);
   Print("========================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("========================================");
   Print("EA stopping. Reason: ", reason);
   Print("Total Orders: ", g_orders.GetTotalOrders());
   Print("Successful: ", g_orders.GetSuccessfulOrders());
   Print("Failed: ", g_orders.GetFailedOrders());
   Print("Success Rate: ", DoubleToString(g_orders.GetSuccessRate(), 2), "%");
   Print("========================================");

   // Release resources
   g_indicators.Release();
   g_initialized = false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized || g_eaState == STATE_ERROR)
      return;

   // State machine
   switch(g_eaState)
   {
      case STATE_WAIT_BAR:
         StateWaitBar();
         break;

      case STATE_SIGNAL:
         StateSignal();
         break;

      case STATE_EXECUTE:
         StateExecute();
         break;

      case STATE_MANAGE:
         StateManage();
         break;

      default:
         g_eaState = STATE_WAIT_BAR;
         break;
   }
}

//+------------------------------------------------------------------+
//| State: Wait for new bar                                          |
//+------------------------------------------------------------------+
void StateWaitBar()
{
   datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);

   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;

      // New bar detected - update context and check signals
      g_signals.UpdateContext();

      if(InpEnableLogging)
      {
         Print("New bar - Context: ", g_signals.GetContextString());
      }

      g_eaState = STATE_SIGNAL;
   }
   else
   {
      // No new bar - manage existing positions
      g_eaState = STATE_MANAGE;
   }
}

//+------------------------------------------------------------------+
//| State: Check for trading signals                                 |
//+------------------------------------------------------------------+
void StateSignal()
{
   // Check if trading is allowed
   if(!g_risk.IsTradingAllowed())
   {
      if(InpEnableLogging)
         Print("Trading not allowed - Drawdown limit");
      g_eaState = STATE_MANAGE;
      return;
   }

   if(!g_risk.IsMarginAvailable())
   {
      if(InpEnableLogging)
         Print("Trading not allowed - Margin limit");
      g_eaState = STATE_MANAGE;
      return;
   }

   if(!g_risk.CanOpenPosition())
   {
      if(InpEnableLogging)
         Print("Trading not allowed - Position limit");
      g_eaState = STATE_MANAGE;
      return;
   }

   // Get signal
   ENUM_SIGNAL_TYPE signal = g_signals.GetSignal();

   if(signal == SIGNAL_BUY)
   {
      if(InpEnableLogging)
      {
         double strength = g_signals.GetSignalStrength();
         Print("BUY Signal detected - Strength: ", DoubleToString(strength, 1), "%");
      }

      ExecuteBuyOrder();
   }
   else if(signal == SIGNAL_SELL)
   {
      if(InpEnableLogging)
      {
         double strength = g_signals.GetSignalStrength();
         Print("SELL Signal detected - Strength: ", DoubleToString(strength, 1), "%");
      }

      ExecuteSellOrder();
   }

   // Always manage positions after checking signals
   g_eaState = STATE_MANAGE;
}

//+------------------------------------------------------------------+
//| State: Execute orders (placeholder)                              |
//+------------------------------------------------------------------+
void StateExecute()
{
   // This state can be used for advanced order execution logic
   // For now, we execute directly in StateSignal
   g_eaState = STATE_MANAGE;
}

//+------------------------------------------------------------------+
//| State: Manage open positions                                     |
//+------------------------------------------------------------------+
void StateManage()
{
   // Manage trailing stops
   if(InpUseTrailing)
   {
      ManageTrailingStops();
   }

   // Manage breakeven
   if(InpUseBreakeven)
   {
      ManageBreakeven();
   }

   // Check for exit signals
   CheckExitSignals();

   // Return to waiting for new bar
   g_eaState = STATE_WAIT_BAR;
}

//+------------------------------------------------------------------+
//| Execute Buy Order                                                |
//+------------------------------------------------------------------+
void ExecuteBuyOrder()
{
   // Calculate SL/TP
   double slPoints = g_risk.CalculateStopLossPoints();

   if(slPoints <= 0.0)
   {
      Print("WARNING: Invalid SL calculation - skipping trade");
      return;
   }

   // Calculate lot size
   double lotSize = g_risk.CalculateLotSize(slPoints);

   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("WARNING: Lot size too small - skipping trade");
      return;
   }

   // Get current price
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Calculate SL and TP prices
   double sl = g_risk.CalculateBuySL(ask, slPoints);
   double tp = g_risk.CalculateBuyTP(ask);

   // Execute order
   if(g_orders.OpenBuy(lotSize, sl, tp, InpTradeComment))
   {
      Print("BUY executed: Lot=", lotSize, " SL=", sl, " TP=", tp);
   }
   else
   {
      Print("BUY failed: ", g_orders.GetLastComment());
   }
}

//+------------------------------------------------------------------+
//| Execute Sell Order                                               |
//+------------------------------------------------------------------+
void ExecuteSellOrder()
{
   // Calculate SL/TP
   double slPoints = g_risk.CalculateStopLossPoints();

   if(slPoints <= 0.0)
   {
      Print("WARNING: Invalid SL calculation - skipping trade");
      return;
   }

   // Calculate lot size
   double lotSize = g_risk.CalculateLotSize(slPoints);

   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("WARNING: Lot size too small - skipping trade");
      return;
   }

   // Get current price
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Calculate SL and TP prices
   double sl = g_risk.CalculateSellSL(bid, slPoints);
   double tp = g_risk.CalculateSellTP(bid);

   // Execute order
   if(g_orders.OpenSell(lotSize, sl, tp, InpTradeComment))
   {
      Print("SELL executed: Lot=", lotSize, " SL=", sl, " TP=", tp);
   }
   else
   {
      Print("SELL failed: ", g_orders.GetLastComment());
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stops for all positions                          |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      // Apply trailing stop
      g_orders.TrailingStop(ticket, InpTrailingPoints, InpTrailingStep);
   }
}

//+------------------------------------------------------------------+
//| Manage breakeven for all positions                               |
//+------------------------------------------------------------------+
void ManageBreakeven()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      // Move to breakeven
      g_orders.MoveToBreakeven(ticket, InpBreakevenPoints, InpBreakevenLock);
   }
}

//+------------------------------------------------------------------+
//| Check for exit signals and close positions                       |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      // Get position type
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Check if we should exit
      bool shouldExit = false;

      if(posType == POSITION_TYPE_BUY)
      {
         shouldExit = g_signals.ShouldExit(true);
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         shouldExit = g_signals.ShouldExit(false);
      }

      if(shouldExit)
      {
         if(g_orders.ClosePosition(ticket))
         {
            Print("Position #", ticket, " closed by exit signal");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Chart Event Handler (for future UI integration)                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Future: Add UI panel controls here
}

//+------------------------------------------------------------------+
