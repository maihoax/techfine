//+------------------------------------------------------------------+
//|                                               Orders.mqh         |
//|                     Universal Order Management with CTrade       |
//|        Error Handling, ECN Support, Trailing, Position Close     |
//+------------------------------------------------------------------+
#property copyright "2025"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//+------------------------------------------------------------------+
//| Universal Order Manager Class                                    |
//| Handles all order operations with proper error handling          |
//+------------------------------------------------------------------+
class CUniversalOrders
{
private:
   // Trading objects
   CTrade            m_trade;
   CPositionInfo     m_position;
   COrderInfo        m_order;

   // Symbol and magic number
   string            m_symbol;
   int               m_magicNumber;

   // Trading parameters
   ulong             m_deviation;         // Slippage in points
   ENUM_ORDER_TYPE_FILLING m_fillType;   // Fill type for orders

   // ECN mode support
   bool              m_isECN;             // ECN broker (SL/TP after fill)
   bool              m_autoDetectECN;     // Auto-detect ECN mode

   // Retry logic
   int               m_maxRetries;
   int               m_retryDelayMs;

   // Last operation result
   uint              m_lastRetcode;
   string            m_lastComment;

   // Statistics
   int               m_totalOrders;
   int               m_successfulOrders;
   int               m_failedOrders;

public:
   //--- Constructor
   CUniversalOrders()
   {
      m_symbol = _Symbol;
      m_magicNumber = 0;
      m_deviation = 10;
      m_fillType = ORDER_FILLING_FOK;

      m_isECN = false;
      m_autoDetectECN = true;

      m_maxRetries = 3;
      m_retryDelayMs = 100;

      m_lastRetcode = 0;
      m_lastComment = "";

      m_totalOrders = 0;
      m_successfulOrders = 0;
      m_failedOrders = 0;
   }

   //--- Initialize order manager
   bool Init(string symbol, int magicNumber, ulong deviation = 10)
   {
      m_symbol = symbol;
      m_magicNumber = magicNumber;
      m_deviation = deviation;

      // Set trade parameters
      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetDeviationInPoints(m_deviation);
      m_trade.SetTypeFilling(m_fillType);
      m_trade.SetAsyncMode(false); // Synchronous mode for reliability

      // Auto-detect ECN mode if enabled
      if(m_autoDetectECN)
      {
         DetectECNMode();
      }

      Print("Order Manager initialized for ", m_symbol,
            " | Magic: ", m_magicNumber,
            " | ECN Mode: ", (m_isECN ? "Yes" : "No"));

      return true;
   }

   //--- Detect if broker is ECN (requires SL/TP after fill)
   void DetectECNMode()
   {
      // Try to get symbol properties
      ENUM_SYMBOL_TRADE_EXECUTION execMode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_EXEMODE);

      // ECN/Market execution typically requires SL/TP modification after fill
      if(execMode == SYMBOL_TRADE_EXECUTION_MARKET)
      {
         m_isECN = true;
         Print("ECN/Market execution detected for ", m_symbol);
      }
      else
      {
         m_isECN = false;
      }
   }

   //--- Open Buy position
   bool OpenBuy(double lotSize, double sl = 0.0, double tp = 0.0, string comment = "")
   {
      m_totalOrders++;

      double price = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      bool result = false;

      if(m_isECN)
      {
         // ECN: Open without SL/TP, then modify
         result = m_trade.Buy(lotSize, m_symbol, price, 0.0, 0.0, comment);

         if(result && (sl > 0.0 || tp > 0.0))
         {
            // Get the ticket of the just-opened position
            ulong ticket = m_trade.ResultOrder();
            if(ticket > 0)
            {
               Sleep(m_retryDelayMs);
               result = ModifyPosition(ticket, sl, tp);
            }
         }
      }
      else
      {
         // Standard: Open with SL/TP
         result = m_trade.Buy(lotSize, m_symbol, price, sl, tp, comment);
      }

      // Handle result
      if(result)
      {
         m_successfulOrders++;
         m_lastRetcode = m_trade.ResultRetcode();
         m_lastComment = "Buy order opened successfully";
         Print("BUY opened: ", m_symbol, " Lot: ", lotSize, " Price: ", price,
               " SL: ", sl, " TP: ", tp);
         return true;
      }
      else
      {
         m_failedOrders++;
         m_lastRetcode = m_trade.ResultRetcode();
         m_lastComment = m_trade.ResultRetcodeDescription();
         Print("ERROR: Buy order failed - ", m_lastComment,
               " (", m_lastRetcode, ")");
         return false;
      }
   }

   //--- Open Sell position
   bool OpenSell(double lotSize, double sl = 0.0, double tp = 0.0, string comment = "")
   {
      m_totalOrders++;

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      bool result = false;

      if(m_isECN)
      {
         // ECN: Open without SL/TP, then modify
         result = m_trade.Sell(lotSize, m_symbol, price, 0.0, 0.0, comment);

         if(result && (sl > 0.0 || tp > 0.0))
         {
            // Get the ticket of the just-opened position
            ulong ticket = m_trade.ResultOrder();
            if(ticket > 0)
            {
               Sleep(m_retryDelayMs);
               result = ModifyPosition(ticket, sl, tp);
            }
         }
      }
      else
      {
         // Standard: Open with SL/TP
         result = m_trade.Sell(lotSize, m_symbol, price, sl, tp, comment);
      }

      // Handle result
      if(result)
      {
         m_successfulOrders++;
         m_lastRetcode = m_trade.ResultRetcode();
         m_lastComment = "Sell order opened successfully";
         Print("SELL opened: ", m_symbol, " Lot: ", lotSize, " Price: ", price,
               " SL: ", sl, " TP: ", tp);
         return true;
      }
      else
      {
         m_failedOrders++;
         m_lastRetcode = m_trade.ResultRetcode();
         m_lastComment = m_trade.ResultRetcodeDescription();
         Print("ERROR: Sell order failed - ", m_lastComment,
               " (", m_lastRetcode, ")");
         return false;
      }
   }

   //--- Modify position SL/TP
   bool ModifyPosition(ulong ticket, double sl, double tp)
   {
      if(!m_position.SelectByTicket(ticket))
      {
         Print("ERROR: Cannot select position #", ticket);
         return false;
      }

      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      bool result = m_trade.PositionModify(ticket, sl, tp);

      if(result)
      {
         Print("Position #", ticket, " modified - SL: ", sl, " TP: ", tp);
         return true;
      }
      else
      {
         m_lastRetcode = m_trade.ResultRetcode();
         m_lastComment = m_trade.ResultRetcodeDescription();
         Print("ERROR: Position modify failed - ", m_lastComment);
         return false;
      }
   }

   //--- Close position by ticket
   bool ClosePosition(ulong ticket)
   {
      if(!m_position.SelectByTicket(ticket))
      {
         Print("ERROR: Cannot select position #", ticket);
         return false;
      }

      bool result = m_trade.PositionClose(ticket);

      if(result)
      {
         Print("Position #", ticket, " closed");
         return true;
      }
      else
      {
         m_lastRetcode = m_trade.ResultRetcode();
         m_lastComment = m_trade.ResultRetcodeDescription();
         Print("ERROR: Position close failed - ", m_lastComment);
         return false;
      }
   }

   //--- Close all positions for this symbol and magic
   int CloseAllPositions()
   {
      int closed = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0)
            continue;

         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber)
            continue;

         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         if(ClosePosition(ticket))
            closed++;

         Sleep(100); // Small delay between closes
      }

      Print("Closed ", closed, " position(s) for ", m_symbol);
      return closed;
   }

   //--- Trailing stop for position
   bool TrailingStop(ulong ticket, double trailPoints, double stepPoints)
   {
      if(!m_position.SelectByTicket(ticket))
         return false;

      // Only trail positions from our EA
      if(m_position.Magic() != m_magicNumber || m_position.Symbol() != m_symbol)
         return false;

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)m_position.Type();
      double openPrice = m_position.PriceOpen();
      double currentSL = m_position.StopLoss();
      double currentTP = m_position.TakeProfit();

      double newSL = 0.0;
      bool shouldModify = false;

      if(posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double trailLevel = bid - trailPoints * point;

         // Check if we should trail
         if(bid > openPrice + trailPoints * point)
         {
            if(currentSL < trailLevel - stepPoints * point)
            {
               newSL = trailLevel;
               shouldModify = true;
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double trailLevel = ask + trailPoints * point;

         // Check if we should trail
         if(ask < openPrice - trailPoints * point)
         {
            if(currentSL > trailLevel + stepPoints * point || currentSL == 0.0)
            {
               newSL = trailLevel;
               shouldModify = true;
            }
         }
      }

      if(shouldModify)
      {
         newSL = NormalizeDouble(newSL, digits);
         return ModifyPosition(ticket, newSL, currentTP);
      }

      return false;
   }

   //--- Breakeven for position
   bool MoveToBreakeven(ulong ticket, double activationPoints, double lockPoints = 0.0)
   {
      if(!m_position.SelectByTicket(ticket))
         return false;

      // Only process positions from our EA
      if(m_position.Magic() != m_magicNumber || m_position.Symbol() != m_symbol)
         return false;

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)m_position.Type();
      double openPrice = m_position.PriceOpen();
      double currentSL = m_position.StopLoss();
      double currentTP = m_position.TakeProfit();

      double newSL = 0.0;
      bool shouldModify = false;

      if(posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

         // Check if profit reached activation level
         if(bid >= openPrice + activationPoints * point)
         {
            // Move SL to breakeven + lock points
            newSL = openPrice + lockPoints * point;

            // Only modify if new SL is better than current
            if(currentSL < newSL)
               shouldModify = true;
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

         // Check if profit reached activation level
         if(ask <= openPrice - activationPoints * point)
         {
            // Move SL to breakeven - lock points
            newSL = openPrice - lockPoints * point;

            // Only modify if new SL is better than current
            if(currentSL > newSL || currentSL == 0.0)
               shouldModify = true;
         }
      }

      if(shouldModify)
      {
         newSL = NormalizeDouble(newSL, digits);
         return ModifyPosition(ticket, newSL, currentTP);
      }

      return false;
   }

   //--- Get total positions for this symbol and magic
   int GetPositionsCount()
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

   //--- Get total profit for all positions
   double GetTotalProfit()
   {
      double totalProfit = 0.0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0)
            continue;

         if(PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
            PositionGetString(POSITION_SYMBOL) == m_symbol)
         {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
         }
      }

      return totalProfit;
   }

   //--- Check if position exists by ticket
   bool PositionExists(ulong ticket)
   {
      return m_position.SelectByTicket(ticket);
   }

   //--- Get position info by ticket
   bool GetPositionInfo(ulong ticket,
                        ENUM_POSITION_TYPE &type,
                        double &lot,
                        double &openPrice,
                        double &sl,
                        double &tp,
                        double &profit)
   {
      if(!m_position.SelectByTicket(ticket))
         return false;

      type = (ENUM_POSITION_TYPE)m_position.Type();
      lot = m_position.Volume();
      openPrice = m_position.PriceOpen();
      sl = m_position.StopLoss();
      tp = m_position.TakeProfit();
      profit = m_position.Profit();

      return true;
   }

   //--- Setters
   void SetDeviation(ulong deviation) { m_deviation = deviation; m_trade.SetDeviationInPoints(deviation); }
   void SetFillType(ENUM_ORDER_TYPE_FILLING fillType) { m_fillType = fillType; m_trade.SetTypeFilling(fillType); }
   void SetECNMode(bool isECN) { m_isECN = isECN; m_autoDetectECN = false; }
   void SetMaxRetries(int retries) { m_maxRetries = retries; }
   void SetRetryDelay(int delayMs) { m_retryDelayMs = delayMs; }

   //--- Getters
   uint GetLastRetcode() const { return m_lastRetcode; }
   string GetLastComment() const { return m_lastComment; }
   int GetTotalOrders() const { return m_totalOrders; }
   int GetSuccessfulOrders() const { return m_successfulOrders; }
   int GetFailedOrders() const { return m_failedOrders; }
   double GetSuccessRate() const
   {
      if(m_totalOrders == 0)
         return 0.0;
      return (double)m_successfulOrders / m_totalOrders * 100.0;
   }
   bool IsECNMode() const { return m_isECN; }
};
//+------------------------------------------------------------------+
