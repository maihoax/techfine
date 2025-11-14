//+------------------------------------------------------------------+
//|                                              RiskManager.mqh     |
//|                            Advanced Risk Management System       |
//|           Drawdown Protection, Margin Control, Dynamic Lot Size  |
//+------------------------------------------------------------------+
#property copyright "2025"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Risk Manager Class                                               |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   string            m_symbol;
   int               m_magicNumber;
   CTrade            m_trade;

   // Risk parameters
   double            m_maxDrawdownPercent;
   double            m_riskPerTradePercent;
   double            m_maxLotSize;
   double            m_minLotSize;

   // Margin safety
   double            m_maxMarginUsagePercent;
   double            m_marginSafetyFactor;

   // Drawdown tracking
   double            m_peakEquity;
   bool              m_tradingEnabled;

   // ATR-based stops
   int               m_atrHandle;
   int               m_atrPeriod;
   double            m_atrMultiplier;
   double            m_minATR;
   double            m_atrBuffer[];

public:
   //--- Constructor
   CRiskManager()
   {
      m_symbol = _Symbol;
      m_magicNumber = 0;

      m_maxDrawdownPercent = 5.0;
      m_riskPerTradePercent = 1.0;
      m_maxLotSize = 0.01;
      m_minLotSize = 0.01;

      m_maxMarginUsagePercent = 70.0;
      m_marginSafetyFactor = 1.5;

      m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_tradingEnabled = true;

      m_atrPeriod = 14;
      m_atrMultiplier = 2.0;
      m_minATR = 100;
      m_atrHandle = INVALID_HANDLE;

      ArraySetAsSeries(m_atrBuffer, true);
   }

   //--- Destructor
   ~CRiskManager()
   {
      if(m_atrHandle != INVALID_HANDLE)
         IndicatorRelease(m_atrHandle);
   }

   //--- Initialize
   bool Init(string symbol,
             int magicNumber,
             double maxDD = 5.0,
             double riskPerTrade = 1.0,
             double maxLot = 0.01)
   {
      m_symbol = symbol;
      m_magicNumber = magicNumber;
      m_maxDrawdownPercent = maxDD;
      m_riskPerTradePercent = riskPerTrade;
      m_maxLotSize = maxLot;

      // Get symbol lot limits
      m_minLotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

      // Create ATR handle
      m_atrHandle = iATR(m_symbol, PERIOD_CURRENT, m_atrPeriod);
      if(m_atrHandle == INVALID_HANDLE)
      {
         Print("Failed to create ATR indicator handle");
         return false;
      }

      m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      return true;
   }

   //--- Check if trading is allowed (Drawdown check)
   bool IsTradingAllowed()
   {
      if(!m_tradingEnabled)
         return false;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      // Update peak equity
      if(equity > m_peakEquity)
         m_peakEquity = equity;

      // Calculate current drawdown
      double currentDD = 0.0;
      if(m_peakEquity > 0)
         currentDD = (m_peakEquity - equity) / m_peakEquity * 100.0;

      // Check if max drawdown exceeded
      if(currentDD > m_maxDrawdownPercent)
      {
         m_tradingEnabled = false;
         Print("RISK MANAGER: Max drawdown exceeded! Trading disabled. DD: ",
               DoubleToString(currentDD, 2), "%");
         return false;
      }

      return true;
   }

   //--- Check margin availability
   bool IsMarginAvailable()
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(equity <= 0)
         return false;

      double marginUsage = (equity - freeMargin) / equity * 100.0;

      if(marginUsage > m_maxMarginUsagePercent)
      {
         Print("RISK MANAGER: Margin usage too high: ",
               DoubleToString(marginUsage, 2), "%");
         return false;
      }

      return true;
   }

   //--- Calculate dynamic lot size based on risk
   double CalculateLotSize(double stopLossPoints)
   {
      if(stopLossPoints <= 0)
         return m_minLotSize;

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = balance * m_riskPerTradePercent / 100.0;

      double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      if(tickValue <= 0 || tickSize <= 0 || point <= 0)
         return m_minLotSize;

      // Calculate lot size based on risk
      double lotSize = riskAmount / (stopLossPoints * point / tickSize * tickValue);

      // Apply margin safety factor
      double availableMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double marginRequired = MarketInfo(m_symbol, MODE_MARGINREQUIRED);
      if(marginRequired > 0)
      {
         double maxLotByMargin = (availableMargin / m_marginSafetyFactor) / marginRequired;
         lotSize = MathMin(lotSize, maxLotByMargin);
      }

      // Normalize lot size
      double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      lotSize = MathFloor(lotSize / lotStep) * lotStep;

      // Apply limits
      lotSize = MathMax(lotSize, m_minLotSize);
      lotSize = MathMin(lotSize, m_maxLotSize);

      return NormalizeDouble(lotSize, 2);
   }

   //--- Get ATR-based stop loss points
   int GetATRStopLoss()
   {
      if(CopyBuffer(m_atrHandle, 0, 0, 1, m_atrBuffer) <= 0)
         return 0;

      double atr = m_atrBuffer[0];
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      if(point <= 0)
         return 0;

      double atrPoints = atr / point;

      // Check minimum ATR filter
      if(atrPoints < m_minATR)
         return 0; // Market too quiet

      return (int)(atrPoints * m_atrMultiplier);
   }

   //--- Get current drawdown percentage
   double GetCurrentDrawdown()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peakEquity <= 0)
         return 0.0;

      return (m_peakEquity - equity) / m_peakEquity * 100.0;
   }

   //--- Get margin usage percentage
   double GetMarginUsage()
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(equity <= 0)
         return 0.0;

      return (equity - freeMargin) / equity * 100.0;
   }

   //--- Count positions managed by this EA
   int CountPositions()
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionSelectByIndex(i))
         {
            if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
               PositionGetString(POSITION_SYMBOL) == m_symbol)
               count++;
         }
      }
      return count;
   }

   //--- Get total profit of all positions
   double GetTotalProfit()
   {
      double profit = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionSelectByIndex(i))
         {
            if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
               PositionGetString(POSITION_SYMBOL) == m_symbol)
               profit += PositionGetDouble(POSITION_PROFIT);
         }
      }
      return profit;
   }

   //--- Close all positions
   bool CloseAllPositions()
   {
      bool result = true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionSelectByIndex(i))
         {
            if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
               PositionGetString(POSITION_SYMBOL) == m_symbol)
            {
               ulong ticket = PositionGetInteger(POSITION_TICKET);
               if(!m_trade.PositionClose(ticket))
                  result = false;
            }
         }
      }
      return result;
   }

   //--- Setters
   void SetMaxDrawdown(double percent) { m_maxDrawdownPercent = percent; }
   void SetRiskPerTrade(double percent) { m_riskPerTradePercent = percent; }
   void SetMaxLotSize(double lot) { m_maxLotSize = lot; }
   void SetATRParameters(int period, double multiplier, double minATR)
   {
      m_atrPeriod = period;
      m_atrMultiplier = multiplier;
      m_minATR = minATR;
   }
   void SetMarginLimit(double percent) { m_maxMarginUsagePercent = percent; }
   void EnableTrading(bool enable) { m_tradingEnabled = enable; }
   void ResetPeakEquity() { m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY); }

   //--- Getters
   bool IsTradingEnabled() { return m_tradingEnabled; }
   double GetPeakEquity() { return m_peakEquity; }
   double GetMaxDrawdown() { return m_maxDrawdownPercent; }
   double GetRiskPerTrade() { return m_riskPerTradePercent; }
};
