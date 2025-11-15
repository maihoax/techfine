//+------------------------------------------------------------------+
//|                                                 Risk.mqh         |
//|                    Universal Risk Management for Multi-Symbol    |
//|      Position Sizing, SL/TP Calculation, Account Type Support    |
//+------------------------------------------------------------------+
#property copyright "2025"
#property strict

#include "Indicators.mqh"
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Universal Risk Manager Class                                     |
//| Handles position sizing, SL/TP, and risk limits for any symbol   |
//+------------------------------------------------------------------+
class CUniversalRisk
{
private:
   // Symbol and account info
   string            m_symbol;
   int               m_magicNumber;
   CSymbolInfo       m_symbolInfo;
   CAccountInfo      m_accountInfo;

   // Reference to indicators (for ATR-based calculations)
   CUniversalIndicators* m_indicators;

   // Risk parameters
   double            m_riskPercentPerTrade;   // Risk % per trade (e.g., 1.0 = 1%)
   double            m_maxLotSize;            // Maximum lot size per trade
   double            m_maxDrawdownPercent;    // Max drawdown % (stop trading)
   double            m_maxMarginPercent;      // Max margin usage %

   // ATR-based SL/TP parameters
   double            m_atrMultiplierSL;       // ATR multiplier for stop loss
   double            m_atrMultiplierTP;       // ATR multiplier for take profit
   double            m_minATRPoints;          // Minimum ATR in points

   // Position limits
   int               m_maxPositions;          // Max open positions
   int               m_maxPositionsPerSymbol; // Max positions per symbol

   // Drawdown tracking
   double            m_peakEquity;
   bool              m_tradingEnabled;

   // Account type normalization
   double            m_accountMultiplier;     // For cent accounts (100) vs standard (1)

public:
   //--- Constructor
   CUniversalRisk()
   {
      m_symbol = _Symbol;
      m_magicNumber = 0;
      m_indicators = NULL;

      // Default risk parameters
      m_riskPercentPerTrade = 1.0;
      m_maxLotSize = 1.0;
      m_maxDrawdownPercent = 10.0;
      m_maxMarginPercent = 50.0;

      // Default ATR parameters
      m_atrMultiplierSL = 2.0;
      m_atrMultiplierTP = 3.0;
      m_minATRPoints = 0.0;

      // Position limits
      m_maxPositions = 5;
      m_maxPositionsPerSymbol = 1;

      // Drawdown tracking
      m_peakEquity = 0.0;
      m_tradingEnabled = true;

      // Account type detection
      m_accountMultiplier = 1.0;
   }

   //--- Initialize risk manager
   bool Init(string symbol,
             int magicNumber,
             CUniversalIndicators* indicators,
             double riskPercent = 1.0,
             double maxLot = 1.0)
   {
      m_symbol = symbol;
      m_magicNumber = magicNumber;
      m_indicators = indicators;
      m_riskPercentPerTrade = riskPercent;
      m_maxLotSize = maxLot;

      // Set symbol for SymbolInfo
      if(!m_symbolInfo.Name(m_symbol))
      {
         Print("ERROR: Failed to set symbol for SymbolInfo: ", m_symbol);
         return false;
      }

      // Refresh symbol and account info
      if(!m_symbolInfo.Refresh() || !m_symbolInfo.RefreshRates())
      {
         Print("ERROR: Failed to refresh symbol info for: ", m_symbol);
         return false;
      }

      m_accountInfo.Refresh();

      // Detect account type (cent vs standard)
      DetectAccountType();

      // Initialize peak equity
      m_peakEquity = m_accountInfo.Equity();

      Print("Risk Manager initialized for ", m_symbol,
            " | Risk: ", m_riskPercentPerTrade, "% | MaxLot: ", m_maxLotSize);

      return true;
   }

   //--- Detect account type and set multiplier
   void DetectAccountType()
   {
      // Heuristic: Check if account currency suggests cent account
      // Cent accounts often have balance 100x higher than standard
      // This is a simplified approach; adjust based on broker specifics

      string accountCurrency = m_accountInfo.Currency();
      double balance = m_accountInfo.Balance();

      // If balance is very high but leverage is typical, might be cent
      // This is broker-dependent, so we use a conservative approach
      // For now, assume multiplier = 1 (standard)
      // User can override if needed

      m_accountMultiplier = 1.0;

      // You can add more sophisticated detection here if needed
      // For example, check broker name or server name
   }

   //--- Calculate position size based on risk and ATR-based SL
   double CalculateLotSize(double stopLossPoints)
   {
      if(stopLossPoints <= 0.0)
      {
         Print("ERROR: Invalid stop loss points: ", stopLossPoints);
         return 0.0;
      }

      // Refresh account info
      m_accountInfo.Refresh();

      // Calculate risk amount in account currency
      double equity = m_accountInfo.Equity();
      double riskAmount = equity * m_riskPercentPerTrade / 100.0;

      // Adjust for cent accounts
      riskAmount /= m_accountMultiplier;

      // Get symbol specifications
      double tickValue = m_symbolInfo.TickValue();
      double tickSize = m_symbolInfo.TickSize();
      double point = m_symbolInfo.Point();

      if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0)
      {
         Print("ERROR: Invalid symbol specifications");
         return 0.0;
      }

      // Calculate lot size
      // Risk = LotSize * StopLossPoints * PointValue
      // PointValue = (TickValue / TickSize) * Point

      double pointValue = (tickValue / tickSize) * point;
      double lotSize = riskAmount / (stopLossPoints * pointValue);

      // Normalize to lot step
      double lotStep = m_symbolInfo.LotsStep();
      lotSize = MathFloor(lotSize / lotStep) * lotStep;

      // Apply limits
      double minLot = m_symbolInfo.LotsMin();
      double maxLot = m_symbolInfo.LotsMax();

      lotSize = MathMax(lotSize, minLot);
      lotSize = MathMin(lotSize, maxLot);
      lotSize = MathMin(lotSize, m_maxLotSize);

      // Additional margin check
      if(!CheckMarginForLot(lotSize))
      {
         // Reduce lot size to fit margin
         double maxLotByMargin = CalculateMaxLotByMargin();
         lotSize = MathMin(lotSize, maxLotByMargin);
      }

      return NormalizeDouble(lotSize, 2);
   }

   //--- Calculate stop loss in points based on ATR
   double CalculateStopLossPoints()
   {
      if(m_indicators == NULL)
      {
         Print("ERROR: Indicators not set in Risk Manager");
         return 0.0;
      }

      double atr = m_indicators.GetATRValue(0);
      double point = m_symbolInfo.Point();

      if(point <= 0.0)
         return 0.0;

      double atrPoints = atr / point;

      // Apply minimum ATR filter
      if(m_minATRPoints > 0.0 && atrPoints < m_minATRPoints)
      {
         return 0.0; // Market too quiet
      }

      // Calculate SL points
      double slPoints = atrPoints * m_atrMultiplierSL;

      return slPoints;
   }

   //--- Calculate take profit in points based on ATR
   double CalculateTakeProfitPoints()
   {
      if(m_indicators == NULL)
         return 0.0;

      double atr = m_indicators.GetATRValue(0);
      double point = m_symbolInfo.Point();

      if(point <= 0.0)
         return 0.0;

      double atrPoints = atr / point;
      double tpPoints = atrPoints * m_atrMultiplierTP;

      return tpPoints;
   }

   //--- Calculate SL price for buy order
   double CalculateBuySL(double entryPrice, double slPoints = 0.0)
   {
      if(slPoints == 0.0)
         slPoints = CalculateStopLossPoints();

      if(slPoints <= 0.0)
         return 0.0;

      double point = m_symbolInfo.Point();
      int digits = m_symbolInfo.Digits();

      double sl = entryPrice - (slPoints * point);
      return NormalizeDouble(sl, digits);
   }

   //--- Calculate SL price for sell order
   double CalculateSellSL(double entryPrice, double slPoints = 0.0)
   {
      if(slPoints == 0.0)
         slPoints = CalculateStopLossPoints();

      if(slPoints <= 0.0)
         return 0.0;

      double point = m_symbolInfo.Point();
      int digits = m_symbolInfo.Digits();

      double sl = entryPrice + (slPoints * point);
      return NormalizeDouble(sl, digits);
   }

   //--- Calculate TP price for buy order
   double CalculateBuyTP(double entryPrice, double tpPoints = 0.0)
   {
      if(tpPoints == 0.0)
         tpPoints = CalculateTakeProfitPoints();

      if(tpPoints <= 0.0)
         return 0.0;

      double point = m_symbolInfo.Point();
      int digits = m_symbolInfo.Digits();

      double tp = entryPrice + (tpPoints * point);
      return NormalizeDouble(tp, digits);
   }

   //--- Calculate TP price for sell order
   double CalculateSellTP(double entryPrice, double tpPoints = 0.0)
   {
      if(tpPoints == 0.0)
         tpPoints = CalculateTakeProfitPoints();

      if(tpPoints <= 0.0)
         return 0.0;

      double point = m_symbolInfo.Point();
      int digits = m_symbolInfo.Digits();

      double tp = entryPrice - (tpPoints * point);
      return NormalizeDouble(tp, digits);
   }

   //--- Check if trading is allowed (drawdown check)
   bool IsTradingAllowed()
   {
      if(!m_tradingEnabled)
         return false;

      m_accountInfo.Refresh();
      double equity = m_accountInfo.Equity();

      // Update peak equity
      if(equity > m_peakEquity)
         m_peakEquity = equity;

      // Calculate current drawdown
      double drawdown = 0.0;
      if(m_peakEquity > 0.0)
         drawdown = (m_peakEquity - equity) / m_peakEquity * 100.0;

      // Check max drawdown
      if(drawdown > m_maxDrawdownPercent)
      {
         m_tradingEnabled = false;
         Print("RISK MANAGER: Max drawdown exceeded! Trading disabled. DD: ",
               DoubleToString(drawdown, 2), "%");
         return false;
      }

      return true;
   }

   //--- Check margin availability
   bool IsMarginAvailable()
   {
      m_accountInfo.Refresh();

      double freeMargin = m_accountInfo.FreeMargin();
      double margin = m_accountInfo.Margin();
      double equity = m_accountInfo.Equity();

      if(equity <= 0.0)
         return false;

      double marginLevel = (margin > 0.0) ? (equity / margin * 100.0) : 0.0;

      // If margin level is too low, don't allow trading
      if(marginLevel > 0.0 && marginLevel < 200.0) // Less than 200% margin level
      {
         Print("RISK MANAGER: Margin level too low: ", DoubleToString(marginLevel, 2), "%");
         return false;
      }

      // Check margin usage percentage
      double marginUsage = (equity > 0.0) ? (margin / equity * 100.0) : 0.0;

      if(marginUsage > m_maxMarginPercent)
      {
         Print("RISK MANAGER: Margin usage too high: ",
               DoubleToString(marginUsage, 2), "%");
         return false;
      }

      return true;
   }

   //--- Check if we can open another position
   bool CanOpenPosition()
   {
      // Check total positions
      int totalPositions = CountPositionsByMagic();
      if(totalPositions >= m_maxPositions)
      {
         Print("RISK MANAGER: Max positions reached: ", totalPositions);
         return false;
      }

      // Check positions for this symbol
      int symbolPositions = CountPositionsBySymbol();
      if(symbolPositions >= m_maxPositionsPerSymbol)
      {
         Print("RISK MANAGER: Max positions for ", m_symbol, " reached: ", symbolPositions);
         return false;
      }

      return true;
   }

   //--- Count positions by magic number
   int CountPositionsByMagic()
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0)
            continue;

         if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber)
            count++;
      }
      return count;
   }

   //--- Count positions for current symbol
   int CountPositionsBySymbol()
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0)
            continue;

         if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
            PositionGetString(POSITION_SYMBOL) == m_symbol)
            count++;
      }
      return count;
   }

   //--- Get current drawdown percentage
   double GetCurrentDrawdown()
   {
      m_accountInfo.Refresh();
      double equity = m_accountInfo.Equity();

      if(m_peakEquity <= 0.0)
         return 0.0;

      return (m_peakEquity - equity) / m_peakEquity * 100.0;
   }

   //--- Check if specific lot size fits margin
   bool CheckMarginForLot(double lotSize)
   {
      m_symbolInfo.RefreshRates();
      m_accountInfo.Refresh();

      double freeMargin = m_accountInfo.FreeMargin();
      double price = m_symbolInfo.Ask(); // Use ask for buy calculation

      // Calculate required margin
      double requiredMargin = 0.0;

      #ifdef __MQL5__
      if(!OrderCalcMargin(ORDER_TYPE_BUY, m_symbol, lotSize, price, requiredMargin))
      {
         Print("ERROR: Failed to calculate margin requirement");
         return false;
      }
      #else
      // MQL4 fallback (if needed)
      requiredMargin = MarketInfo(m_symbol, MODE_MARGINREQUIRED) * lotSize;
      #endif

      // Add safety margin (50%)
      requiredMargin *= 1.5;

      return (freeMargin >= requiredMargin);
   }

   //--- Calculate maximum lot size by available margin
   double CalculateMaxLotByMargin()
   {
      m_symbolInfo.RefreshRates();
      m_accountInfo.Refresh();

      double freeMargin = m_accountInfo.FreeMargin();
      double price = m_symbolInfo.Ask();

      double testLot = m_symbolInfo.LotsMin();
      double requiredMargin = 0.0;

      #ifdef __MQL5__
      if(!OrderCalcMargin(ORDER_TYPE_BUY, m_symbol, testLot, price, requiredMargin))
      {
         return m_symbolInfo.LotsMin();
      }
      #else
      requiredMargin = MarketInfo(m_symbol, MODE_MARGINREQUIRED) * testLot;
      #endif

      if(requiredMargin <= 0.0)
         return m_symbolInfo.LotsMin();

      // Calculate max lot based on free margin (with safety factor)
      double maxLot = (freeMargin * 0.5) / requiredMargin * testLot;

      // Normalize
      double lotStep = m_symbolInfo.LotsStep();
      maxLot = MathFloor(maxLot / lotStep) * lotStep;

      // Apply limits
      maxLot = MathMax(maxLot, m_symbolInfo.LotsMin());
      maxLot = MathMin(maxLot, m_symbolInfo.LotsMax());

      return maxLot;
   }

   //--- Setters
   void SetRiskPercent(double percent) { m_riskPercentPerTrade = percent; }
   void SetMaxLotSize(double lot) { m_maxLotSize = lot; }
   void SetMaxDrawdown(double percent) { m_maxDrawdownPercent = percent; }
   void SetMaxMargin(double percent) { m_maxMarginPercent = percent; }
   void SetATRMultipliers(double slMultiplier, double tpMultiplier)
   {
      m_atrMultiplierSL = slMultiplier;
      m_atrMultiplierTP = tpMultiplier;
   }
   void SetMinATRPoints(double points) { m_minATRPoints = points; }
   void SetMaxPositions(int max) { m_maxPositions = max; }
   void SetMaxPositionsPerSymbol(int max) { m_maxPositionsPerSymbol = max; }
   void EnableTrading(bool enable) { m_tradingEnabled = enable; }
   void ResetPeakEquity() { m_peakEquity = m_accountInfo.Equity(); }
   void SetAccountMultiplier(double multiplier) { m_accountMultiplier = multiplier; }

   //--- Getters
   double GetRiskPercent() const { return m_riskPercentPerTrade; }
   double GetMaxLotSize() const { return m_maxLotSize; }
   double GetMaxDrawdown() const { return m_maxDrawdownPercent; }
   double GetPeakEquity() const { return m_peakEquity; }
   bool IsTradingEnabled() const { return m_tradingEnabled; }
   double GetATRMultiplierSL() const { return m_atrMultiplierSL; }
   double GetATRMultiplierTP() const { return m_atrMultiplierTP; }
};
//+------------------------------------------------------------------+
