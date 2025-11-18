//+------------------------------------------------------------------+
//|                                     Universal_DCA_Grid_EA.mq5    |
//|                      Universal DCA Grid Trading System           |
//|           Two-Way Grid with Trailing Stop & Button Controls      |
//+------------------------------------------------------------------+
#property copyright "2025"
#property version   "1.00"
#property description "Universal DCA Grid EA with button controls"
#property description "Features: Two-way grid, trailing stop, safe fund protection"
#property strict

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_AUTO_START_MODE
{
   AUTO_NONE = 0,           // None (Manual Control)
   AUTO_BUY_ONLY,          // Auto Start Buy Only
   AUTO_SELL_ONLY,         // Auto Start Sell Only
   AUTO_BOTH               // Auto Start Both Directions
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+

//--- Trading Configuration
input group "=== TRADING CONFIGURATION ==="
input double             InpInitialLot = 1.0;                    // Initial Lot Size
input double             InpDCADistance = 20.0;                  // DCA Distance (pips)
input double             InpDCAMultiplier = 1.3;                 // DCA Lot Multiplier
input int                InpMaxGridLevels = 22;                  // Maximum DCA Grid Levels
input double             InpTakeProfit = 50.0;                   // DCA Take Profit ($) - Trailing activates when profit reaches...
input double             InpTrailingDistance = 20.0;             // Trailing Stop Distance (pips)
input double             InpStopLoss = -20000.0;                 // Stop Loss Threshold (close all if P&L below this)
input bool               InpAutoRestart = false;                 // Auto Restart Same Direction (restart grid when position closed)

//--- System Settings
input group "=== SYSTEM SETTINGS ==="
input int                InpBuyMagic = 666666;                   // Buy Magic Number
input int                InpSellMagic = 888888;                  // Sell Magic Number
input bool               InpShowInfo = false;                    // Show Information Panel
input bool               InpShowPNL = true;                      // Show PNL Panel (BUY/SELL PNL below buttons)

//--- Auto Start
input group "=== AUTO START ==="
input ENUM_AUTO_START_MODE InpAutoStartMode = AUTO_NONE;        // Auto Start Mode (hides buttons when enabled)

//--- Button Position
input group "=== BUTTON POSITION ==="
input bool               InpButtonTop = true;                    // Button Anchor - Top (true) or Bottom (false)
input int                InpButtonOffsetTop = 70;                // Button Offset from Top (pixels)
input int                InpButtonOffsetBottom = 70;             // Button Offset from Bottom (pixels)

//--- Safe Fund Protection
input group "=== SAFE FUND PROTECTION ==="
input bool               InpEnableSafeFund = false;              // Enable Safe Fund Protection
input int                InpSafeFundLevel = 17;                  // Safe Fund Threshold (grid levels)
input double             InpSafeFundMinProfit = 0.0;             // Minimum Profit to Close in Safe Mode ($)

//--- Daily Profit Target
input group "=== DAILY PROFIT TARGET ==="
input bool               InpEnableDailyTarget = false;           // Enable Daily Profit Target
input double             InpDailyTarget = 5000.0;                // Daily Profit Target ($)
input bool               InpResetOnRestart = true;               // Reset snapshot on bot restart

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+

// Grid state
bool                     g_buyActive = false;
bool                     g_sellActive = false;
int                      g_buyGridCount = 0;
int                      g_sellGridCount = 0;
double                   g_lastBuyPrice = 0.0;
double                   g_lastSellPrice = 0.0;
double                   g_buyTrailingLevel = 0.0;
double                   g_sellTrailingLevel = 0.0;
bool                     g_buyTrailingActive = false;
bool                     g_sellTrailingActive = false;

// Daily profit tracking
double                   g_dailyStartBalance = 0.0;
datetime                 g_dailyStartTime = 0;

// Symbol info cache
double                   g_point;
double                   g_tickSize;
double                   g_tickValue;
double                   g_lotStep;
double                   g_minLot;
double                   g_maxLot;
int                      g_digits;

// Button objects
string                   g_btnBuy = "BTN_BUY";
string                   g_btnSell = "BTN_SELL";
string                   g_btnCloseBuy = "BTN_CLOSE_BUY";
string                   g_btnCloseSell = "BTN_CLOSE_SELL";
string                   g_btnDeactivateBuy = "BTN_DEACTIVATE_BUY";
string                   g_btnDeactivateSell = "BTN_DEACTIVATE_SELL";
string                   g_lblInfo = "LBL_INFO";
string                   g_lblPNL = "LBL_PNL";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("Universal DCA Grid EA v1.00");
   Print("Initializing for ", _Symbol);
   Print("========================================");

   // Initialize symbol info
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Validate inputs
   if(InpInitialLot < g_minLot || InpInitialLot > g_maxLot)
   {
      Print("ERROR: Initial lot size invalid (", g_minLot, " - ", g_maxLot, ")");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpDCAMultiplier < 1.0)
   {
      Print("ERROR: DCA Multiplier must be >= 1.0");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpMaxGridLevels < 1)
   {
      Print("ERROR: Maximum grid levels must be >= 1");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Initialize daily profit tracking
   if(InpEnableDailyTarget)
   {
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyStartTime = TimeCurrent();
      Print("Daily profit tracking enabled. Start balance: $", DoubleToString(g_dailyStartBalance, 2));
   }

   // Create UI
   CreateButtons();
   UpdateInfoPanel();
   UpdatePNLPanel();

   // Auto start if configured
   if(InpAutoStartMode != AUTO_NONE)
   {
      if(InpAutoStartMode == AUTO_BUY_ONLY || InpAutoStartMode == AUTO_BOTH)
      {
         g_buyActive = true;
         Print("Auto-starting BUY direction");
      }

      if(InpAutoStartMode == AUTO_SELL_ONLY || InpAutoStartMode == AUTO_BOTH)
      {
         g_sellActive = true;
         Print("Auto-starting SELL direction");
      }
   }

   Print("========================================");
   Print("Initialization successful");
   Print("Initial Lot: ", InpInitialLot);
   Print("DCA Distance: ", InpDCADistance, " pips");
   Print("DCA Multiplier: ", InpDCAMultiplier);
   Print("Max Grid Levels: ", InpMaxGridLevels);
   Print("Take Profit: $", InpTakeProfit);
   Print("Trailing Distance: ", InpTrailingDistance, " pips");
   Print("Stop Loss: $", InpStopLoss);
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
   Print("========================================");

   // Remove all objects
   DeleteButtons();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check daily profit target
   if(InpEnableDailyTarget && CheckDailyProfitTarget())
   {
      return; // Stop trading for the day
   }

   // Update panels
   UpdateInfoPanel();
   UpdatePNLPanel();

   // Process BUY direction
   if(g_buyActive)
   {
      ProcessBuyGrid();
      CheckBuyProfitAndTrailing();
      CheckBuyStopLoss();
   }

   // Process SELL direction
   if(g_sellActive)
   {
      ProcessSellGrid();
      CheckSellProfitAndTrailing();
      CheckSellStopLoss();
   }
}

//+------------------------------------------------------------------+
//| Process BUY grid - open new positions when price drops           |
//+------------------------------------------------------------------+
void ProcessBuyGrid()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Count existing buy positions
   int buyCount = CountPositions(InpBuyMagic);

   // If no positions, open first one
   if(buyCount == 0)
   {
      if(OpenBuyPosition(InpInitialLot))
      {
         g_buyGridCount = 1;
         g_lastBuyPrice = ask;
         g_buyTrailingActive = false;
         g_buyTrailingLevel = 0.0;
         Print("BUY Grid started. First position opened at ", ask);
      }
      return;
   }

   // Check if we should open next grid level
   if(buyCount < InpMaxGridLevels)
   {
      double dcaDistance = InpDCADistance * g_point * 10; // Convert pips to price

      // Check safe fund protection
      if(InpEnableSafeFund && buyCount >= InpSafeFundLevel)
      {
         Print("BUY Grid: Safe fund protection active at level ", buyCount);
         return;
      }

      // If price dropped enough from last buy, open new position
      if(ask <= g_lastBuyPrice - dcaDistance)
      {
         // Calculate next lot size
         double nextLot = CalculateNextLot(InpInitialLot, buyCount);

         if(OpenBuyPosition(nextLot))
         {
            g_buyGridCount = buyCount + 1;
            g_lastBuyPrice = ask;
            Print("BUY Grid level ", g_buyGridCount, " opened. Lot: ", nextLot, " Price: ", ask);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Process SELL grid - open new positions when price rises          |
//+------------------------------------------------------------------+
void ProcessSellGrid()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Count existing sell positions
   int sellCount = CountPositions(InpSellMagic);

   // If no positions, open first one
   if(sellCount == 0)
   {
      if(OpenSellPosition(InpInitialLot))
      {
         g_sellGridCount = 1;
         g_lastSellPrice = bid;
         g_sellTrailingActive = false;
         g_sellTrailingLevel = 0.0;
         Print("SELL Grid started. First position opened at ", bid);
      }
      return;
   }

   // Check if we should open next grid level
   if(sellCount < InpMaxGridLevels)
   {
      double dcaDistance = InpDCADistance * g_point * 10; // Convert pips to price

      // Check safe fund protection
      if(InpEnableSafeFund && sellCount >= InpSafeFundLevel)
      {
         Print("SELL Grid: Safe fund protection active at level ", sellCount);
         return;
      }

      // If price rose enough from last sell, open new position
      if(bid >= g_lastSellPrice + dcaDistance)
      {
         // Calculate next lot size
         double nextLot = CalculateNextLot(InpInitialLot, sellCount);

         if(OpenSellPosition(nextLot))
         {
            g_sellGridCount = sellCount + 1;
            g_lastSellPrice = bid;
            Print("SELL Grid level ", g_sellGridCount, " opened. Lot: ", nextLot, " Price: ", bid);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate next lot size based on multiplier                      |
//+------------------------------------------------------------------+
double CalculateNextLot(double initialLot, int level)
{
   double lot = initialLot;

   for(int i = 0; i < level; i++)
   {
      lot *= InpDCAMultiplier;
   }

   // Normalize to lot step
   lot = MathFloor(lot / g_lotStep) * g_lotStep;

   // Ensure within limits
   if(lot < g_minLot) lot = g_minLot;
   if(lot > g_maxLot) lot = g_maxLot;

   return lot;
}

//+------------------------------------------------------------------+
//| Check BUY profit and activate/manage trailing stop               |
//+------------------------------------------------------------------+
void CheckBuyProfitAndTrailing()
{
   double buyProfit = GetDirectionProfit(InpBuyMagic);
   int buyCount = CountPositions(InpBuyMagic);

   // Safe fund protection: close early if in safe mode and profit >= minimum
   if(InpEnableSafeFund && buyCount >= InpSafeFundLevel)
   {
      if(buyProfit >= InpSafeFundMinProfit)
      {
         Print("BUY Safe fund protection triggered! Grid level: ", buyCount, " Profit: $", DoubleToString(buyProfit, 2));
         CloseAllPositions(InpBuyMagic);

         // Reset grid
         g_buyGridCount = 0;
         g_lastBuyPrice = 0.0;
         g_buyTrailingActive = false;
         g_buyTrailingLevel = 0.0;

         // Auto restart if enabled
         if(!InpAutoRestart)
         {
            g_buyActive = false;
         }
         return;
      }
   }

   // Check if we reached take profit to activate trailing
   if(!g_buyTrailingActive && buyProfit >= InpTakeProfit)
   {
      g_buyTrailingActive = true;
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double trailingDistance = InpTrailingDistance * g_point * 10;
      g_buyTrailingLevel = ask - trailingDistance;
      Print("BUY Trailing activated! Profit: $", DoubleToString(buyProfit, 2), " Trailing level: ", g_buyTrailingLevel);
   }

   // Update trailing stop if active
   if(g_buyTrailingActive)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double trailingDistance = InpTrailingDistance * g_point * 10;
      double newTrailingLevel = ask - trailingDistance;

      // Move trailing up if price moved favorably
      if(newTrailingLevel > g_buyTrailingLevel)
      {
         g_buyTrailingLevel = newTrailingLevel;
      }

      // Check if price hit trailing stop
      if(ask <= g_buyTrailingLevel)
      {
         Print("BUY Trailing stop hit! Closing all BUY positions. Profit: $", DoubleToString(buyProfit, 2));
         CloseAllPositions(InpBuyMagic);

         // Reset grid
         g_buyGridCount = 0;
         g_lastBuyPrice = 0.0;
         g_buyTrailingActive = false;
         g_buyTrailingLevel = 0.0;

         // Auto restart if enabled
         if(!InpAutoRestart)
         {
            g_buyActive = false;
         }
      }
   }
   else
   {
      // No trailing active, check for simple take profit
      if(buyProfit >= InpTakeProfit)
      {
         Print("BUY Take profit reached! Closing all BUY positions. Profit: $", DoubleToString(buyProfit, 2));
         CloseAllPositions(InpBuyMagic);

         // Reset grid
         g_buyGridCount = 0;
         g_lastBuyPrice = 0.0;

         // Auto restart if enabled
         if(!InpAutoRestart)
         {
            g_buyActive = false;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check SELL profit and activate/manage trailing stop              |
//+------------------------------------------------------------------+
void CheckSellProfitAndTrailing()
{
   double sellProfit = GetDirectionProfit(InpSellMagic);
   int sellCount = CountPositions(InpSellMagic);

   // Safe fund protection: close early if in safe mode and profit >= minimum
   if(InpEnableSafeFund && sellCount >= InpSafeFundLevel)
   {
      if(sellProfit >= InpSafeFundMinProfit)
      {
         Print("SELL Safe fund protection triggered! Grid level: ", sellCount, " Profit: $", DoubleToString(sellProfit, 2));
         CloseAllPositions(InpSellMagic);

         // Reset grid
         g_sellGridCount = 0;
         g_lastSellPrice = 0.0;
         g_sellTrailingActive = false;
         g_sellTrailingLevel = 0.0;

         // Auto restart if enabled
         if(!InpAutoRestart)
         {
            g_sellActive = false;
         }
         return;
      }
   }

   // Check if we reached take profit to activate trailing
   if(!g_sellTrailingActive && sellProfit >= InpTakeProfit)
   {
      g_sellTrailingActive = true;
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double trailingDistance = InpTrailingDistance * g_point * 10;
      g_sellTrailingLevel = bid + trailingDistance;
      Print("SELL Trailing activated! Profit: $", DoubleToString(sellProfit, 2), " Trailing level: ", g_sellTrailingLevel);
   }

   // Update trailing stop if active
   if(g_sellTrailingActive)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double trailingDistance = InpTrailingDistance * g_point * 10;
      double newTrailingLevel = bid + trailingDistance;

      // Move trailing down if price moved favorably
      if(newTrailingLevel < g_sellTrailingLevel)
      {
         g_sellTrailingLevel = newTrailingLevel;
      }

      // Check if price hit trailing stop
      if(bid >= g_sellTrailingLevel)
      {
         Print("SELL Trailing stop hit! Closing all SELL positions. Profit: $", DoubleToString(sellProfit, 2));
         CloseAllPositions(InpSellMagic);

         // Reset grid
         g_sellGridCount = 0;
         g_lastSellPrice = 0.0;
         g_sellTrailingActive = false;
         g_sellTrailingLevel = 0.0;

         // Auto restart if enabled
         if(!InpAutoRestart)
         {
            g_sellActive = false;
         }
      }
   }
   else
   {
      // No trailing active, check for simple take profit
      if(sellProfit >= InpTakeProfit)
      {
         Print("SELL Take profit reached! Closing all SELL positions. Profit: $", DoubleToString(sellProfit, 2));
         CloseAllPositions(InpSellMagic);

         // Reset grid
         g_sellGridCount = 0;
         g_lastSellPrice = 0.0;

         // Auto restart if enabled
         if(!InpAutoRestart)
         {
            g_sellActive = false;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check BUY stop loss                                              |
//+------------------------------------------------------------------+
void CheckBuyStopLoss()
{
   double buyProfit = GetDirectionProfit(InpBuyMagic);

   if(buyProfit <= InpStopLoss)
   {
      Print("BUY Stop loss hit! Closing all BUY positions. Loss: $", DoubleToString(buyProfit, 2));
      CloseAllPositions(InpBuyMagic);

      // Reset grid
      g_buyGridCount = 0;
      g_lastBuyPrice = 0.0;
      g_buyTrailingActive = false;
      g_buyTrailingLevel = 0.0;

      // Auto restart if enabled
      if(!InpAutoRestart)
      {
         g_buyActive = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Check SELL stop loss                                             |
//+------------------------------------------------------------------+
void CheckSellStopLoss()
{
   double sellProfit = GetDirectionProfit(InpSellMagic);

   if(sellProfit <= InpStopLoss)
   {
      Print("SELL Stop loss hit! Closing all SELL positions. Loss: $", DoubleToString(sellProfit, 2));
      CloseAllPositions(InpSellMagic);

      // Reset grid
      g_sellGridCount = 0;
      g_lastSellPrice = 0.0;
      g_sellTrailingActive = false;
      g_sellTrailingLevel = 0.0;

      // Auto restart if enabled
      if(!InpAutoRestart)
      {
         g_sellActive = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Count positions by magic number                                  |
//+------------------------------------------------------------------+
int CountPositions(int magic)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Get total profit for one direction                               |
//+------------------------------------------------------------------+
double GetDirectionProfit(int magic)
{
   double profit = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }

   return profit;
}

//+------------------------------------------------------------------+
//| Open BUY position                                                |
//+------------------------------------------------------------------+
bool OpenBuyPosition(double lot)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = ORDER_TYPE_BUY;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.deviation = 10;
   request.magic = InpBuyMagic;
   request.comment = "DCA_BUY";

   if(!OrderSend(request, result))
   {
      Print("BUY order failed: ", GetLastError(), " - ", result.comment);
      return false;
   }

   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print("BUY order failed: ", result.retcode, " - ", result.comment);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Open SELL position                                               |
//+------------------------------------------------------------------+
bool OpenSellPosition(double lot)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = ORDER_TYPE_SELL;
   request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.deviation = 10;
   request.magic = InpSellMagic;
   request.comment = "DCA_SELL";

   if(!OrderSend(request, result))
   {
      Print("SELL order failed: ", GetLastError(), " - ", result.comment);
      return false;
   }

   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print("SELL order failed: ", result.retcode, " - ", result.comment);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Close all positions by magic number                              |
//+------------------------------------------------------------------+
void CloseAllPositions(int magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;

      MqlTradeRequest request = {};
      MqlTradeResult result = {};

      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.position = ticket;
      request.volume = PositionGetDouble(POSITION_VOLUME);
      request.deviation = 10;
      request.magic = magic;

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         request.type = ORDER_TYPE_SELL;
         request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      else
      {
         request.type = ORDER_TYPE_BUY;
         request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      }

      OrderSend(request, result);
   }
}

//+------------------------------------------------------------------+
//| Check daily profit target                                        |
//+------------------------------------------------------------------+
bool CheckDailyProfitTarget()
{
   if(!InpEnableDailyTarget)
      return false;

   // Check if new day
   datetime currentTime = TimeCurrent();
   MqlDateTime currentDT, startDT;
   TimeToStruct(currentTime, currentDT);
   TimeToStruct(g_dailyStartTime, startDT);

   if(currentDT.day != startDT.day || currentDT.mon != startDT.mon || currentDT.year != startDT.year)
   {
      // New day - reset
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyStartTime = currentTime;
      Print("New day detected. Resetting daily profit tracking. Balance: $", DoubleToString(g_dailyStartBalance, 2));
      return false;
   }

   // Check profit
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyProfit = currentBalance - g_dailyStartBalance;

   if(dailyProfit >= InpDailyTarget)
   {
      Print("Daily profit target reached! Profit: $", DoubleToString(dailyProfit, 2), " Target: $", InpDailyTarget);

      // Close all positions
      CloseAllPositions(InpBuyMagic);
      CloseAllPositions(InpSellMagic);

      // Deactivate both directions
      g_buyActive = false;
      g_sellActive = false;

      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Create button controls                                           |
//+------------------------------------------------------------------+
void CreateButtons()
{
   int baseY = InpButtonTop ? InpButtonOffsetTop : (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS) - InpButtonOffsetBottom;
   int buttonWidth = 120;
   int buttonHeight = 30;
   int buttonSpacing = 5;
   int x = 10;

   // Only show buttons if not in auto mode
   if(InpAutoStartMode == AUTO_NONE)
   {
      // BUY button
      CreateButton(g_btnBuy, x, baseY, buttonWidth, buttonHeight, "BUY", clrGreen);

      // SELL button
      CreateButton(g_btnSell, x + buttonWidth + buttonSpacing, baseY, buttonWidth, buttonHeight, "SELL", clrRed);

      // Close BUY button
      CreateButton(g_btnCloseBuy, x, baseY + buttonHeight + buttonSpacing, buttonWidth, buttonHeight, "Close BUY", clrDarkGreen);

      // Close SELL button
      CreateButton(g_btnCloseSell, x + buttonWidth + buttonSpacing, baseY + buttonHeight + buttonSpacing, buttonWidth, buttonHeight, "Close SELL", clrDarkRed);

      // Deactivate BUY button
      CreateButton(g_btnDeactivateBuy, x, baseY + (buttonHeight + buttonSpacing) * 2, buttonWidth, buttonHeight, "Deactivate BUY", clrGray);

      // Deactivate SELL button
      CreateButton(g_btnDeactivateSell, x + buttonWidth + buttonSpacing, baseY + (buttonHeight + buttonSpacing) * 2, buttonWidth, buttonHeight, "Deactivate SELL", clrGray);
   }
}

//+------------------------------------------------------------------+
//| Create single button                                             |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int width, int height, string text, color bgColor)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Delete all buttons                                               |
//+------------------------------------------------------------------+
void DeleteButtons()
{
   ObjectDelete(0, g_btnBuy);
   ObjectDelete(0, g_btnSell);
   ObjectDelete(0, g_btnCloseBuy);
   ObjectDelete(0, g_btnCloseSell);
   ObjectDelete(0, g_btnDeactivateBuy);
   ObjectDelete(0, g_btnDeactivateSell);
   ObjectDelete(0, g_lblInfo);
   ObjectDelete(0, g_lblPNL);
}

//+------------------------------------------------------------------+
//| Update information panel                                         |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
   if(!InpShowInfo)
   {
      ObjectDelete(0, g_lblInfo);
      return;
   }

   string info = "";
   info += "=== DCA Grid EA ===\n";
   info += "Symbol: " + _Symbol + "\n";
   info += "BUY Active: " + (g_buyActive ? "YES" : "NO") + "\n";
   info += "SELL Active: " + (g_sellActive ? "YES" : "NO") + "\n";
   info += "BUY Grid: " + IntegerToString(g_buyGridCount) + "/" + IntegerToString(InpMaxGridLevels) + "\n";
   info += "SELL Grid: " + IntegerToString(g_sellGridCount) + "/" + IntegerToString(InpMaxGridLevels) + "\n";
   info += "BUY Trailing: " + (g_buyTrailingActive ? "ACTIVE" : "OFF") + "\n";
   info += "SELL Trailing: " + (g_sellTrailingActive ? "ACTIVE" : "OFF") + "\n";

   ObjectDelete(0, g_lblInfo);
   ObjectCreate(0, g_lblInfo, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_lblInfo, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_lblInfo, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, g_lblInfo, OBJPROP_YDISTANCE, 200);
   ObjectSetInteger(0, g_lblInfo, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, g_lblInfo, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, g_lblInfo, OBJPROP_TEXT, info);
}

//+------------------------------------------------------------------+
//| Update PNL panel                                                 |
//+------------------------------------------------------------------+
void UpdatePNLPanel()
{
   if(!InpShowPNL)
   {
      ObjectDelete(0, g_lblPNL);
      return;
   }

   double buyProfit = GetDirectionProfit(InpBuyMagic);
   double sellProfit = GetDirectionProfit(InpSellMagic);
   double totalProfit = buyProfit + sellProfit;

   string pnl = "";
   pnl += "BUY P&L: $" + DoubleToString(buyProfit, 2) + "\n";
   pnl += "SELL P&L: $" + DoubleToString(sellProfit, 2) + "\n";
   pnl += "Total P&L: $" + DoubleToString(totalProfit, 2);

   color pnlColor = totalProfit >= 0 ? clrLime : clrRed;

   int baseY = InpButtonTop ? InpButtonOffsetTop : (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS) - InpButtonOffsetBottom;

   ObjectDelete(0, g_lblPNL);
   ObjectCreate(0, g_lblPNL, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_lblPNL, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_lblPNL, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, g_lblPNL, OBJPROP_YDISTANCE, baseY + 110);
   ObjectSetInteger(0, g_lblPNL, OBJPROP_COLOR, pnlColor);
   ObjectSetInteger(0, g_lblPNL, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, g_lblPNL, OBJPROP_TEXT, pnl);
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // BUY button
      if(sparam == g_btnBuy)
      {
         g_buyActive = true;
         Print("BUY direction activated");
         ObjectSetInteger(0, g_btnBuy, OBJPROP_STATE, false);
      }

      // SELL button
      else if(sparam == g_btnSell)
      {
         g_sellActive = true;
         Print("SELL direction activated");
         ObjectSetInteger(0, g_btnSell, OBJPROP_STATE, false);
      }

      // Close BUY button
      else if(sparam == g_btnCloseBuy)
      {
         Print("Closing all BUY positions manually");
         CloseAllPositions(InpBuyMagic);
         g_buyGridCount = 0;
         g_lastBuyPrice = 0.0;
         g_buyTrailingActive = false;
         g_buyTrailingLevel = 0.0;
         ObjectSetInteger(0, g_btnCloseBuy, OBJPROP_STATE, false);
      }

      // Close SELL button
      else if(sparam == g_btnCloseSell)
      {
         Print("Closing all SELL positions manually");
         CloseAllPositions(InpSellMagic);
         g_sellGridCount = 0;
         g_lastSellPrice = 0.0;
         g_sellTrailingActive = false;
         g_sellTrailingLevel = 0.0;
         ObjectSetInteger(0, g_btnCloseSell, OBJPROP_STATE, false);
      }

      // Deactivate BUY button
      else if(sparam == g_btnDeactivateBuy)
      {
         Print("Deactivating BUY direction");
         CloseAllPositions(InpBuyMagic);
         g_buyActive = false;
         g_buyGridCount = 0;
         g_lastBuyPrice = 0.0;
         g_buyTrailingActive = false;
         g_buyTrailingLevel = 0.0;
         ObjectSetInteger(0, g_btnDeactivateBuy, OBJPROP_STATE, false);
      }

      // Deactivate SELL button
      else if(sparam == g_btnDeactivateSell)
      {
         Print("Deactivating SELL direction");
         CloseAllPositions(InpSellMagic);
         g_sellActive = false;
         g_sellGridCount = 0;
         g_lastSellPrice = 0.0;
         g_sellTrailingActive = false;
         g_sellTrailingLevel = 0.0;
         ObjectSetInteger(0, g_btnDeactivateSell, OBJPROP_STATE, false);
      }

      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
