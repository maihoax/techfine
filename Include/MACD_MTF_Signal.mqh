//+------------------------------------------------------------------+
//|                                            MACD_MTF_Signal.mqh   |
//|                                    Multi-Timeframe MACD Signal   |
//|                       Optimized for Gold (XAUUSD) Trend Detection |
//+------------------------------------------------------------------+
#property copyright "2025"
#property strict

//+------------------------------------------------------------------+
//| MACD Multi-Timeframe Signal Class                                |
//+------------------------------------------------------------------+
class CMACD_MTF_Signal
{
private:
   string            m_symbol;

   // MACD parameters optimized for Gold
   int               m_fastEMA;
   int               m_slowEMA;
   int               m_signalSMA;

   // Multiple timeframes
   ENUM_TIMEFRAMES   m_timeframes[];
   int               m_handles[];

   // Buffers for MACD values
   double            m_macdMain[];
   double            m_macdSignal[];

   // Slope detection settings
   int               m_slopeBars;        // Number of bars to calculate slope
   double            m_slopeThreshold;   // Minimum slope to consider trending

   // Momentum filter
   bool              m_useMomentumFilter;
   double            m_momentumThreshold;

   int               m_minTimeframesMatch; // Minimum timeframes needed to match

public:
   //--- Constructor
   CMACD_MTF_Signal()
   {
      m_symbol = _Symbol;

      // MACD parameters optimized for Gold
      m_fastEMA = 12;
      m_slowEMA = 26;
      m_signalSMA = 9;

      m_slopeBars = 3;
      m_slopeThreshold = 0.0001;
      m_useMomentumFilter = true;
      m_momentumThreshold = 0.0005;
      m_minTimeframesMatch = 2;

      ArraySetAsSeries(m_macdMain, true);
      ArraySetAsSeries(m_macdSignal, true);
   }

   //--- Destructor
   ~CMACD_MTF_Signal()
   {
      ReleaseHandles();
   }

   //--- Initialize with custom parameters
   bool Init(string symbol,
             int fastEMA = 12,
             int slowEMA = 26,
             int signalSMA = 9,
             int minTFMatch = 2)
   {
      m_symbol = symbol;
      m_fastEMA = fastEMA;
      m_slowEMA = slowEMA;
      m_signalSMA = signalSMA;
      m_minTimeframesMatch = minTFMatch;

      // Setup timeframes for multi-timeframe analysis
      // Optimized timeframes for Gold: M5, M15, H1, H4
      ArrayResize(m_timeframes, 4);
      m_timeframes[0] = PERIOD_M5;
      m_timeframes[1] = PERIOD_M15;
      m_timeframes[2] = PERIOD_H1;
      m_timeframes[3] = PERIOD_H4;

      // Create MACD handles for each timeframe
      ArrayResize(m_handles, ArraySize(m_timeframes));

      for(int i = 0; i < ArraySize(m_timeframes); i++)
      {
         m_handles[i] = iMACD(m_symbol, m_timeframes[i],
                              m_fastEMA, m_slowEMA, m_signalSMA,
                              PRICE_CLOSE);

         if(m_handles[i] == INVALID_HANDLE)
         {
            Print("Failed to create MACD handle for timeframe ",
                  EnumToString(m_timeframes[i]));
            return false;
         }
      }

      return true;
   }

   //--- Release all indicator handles
   void ReleaseHandles()
   {
      for(int i = 0; i < ArraySize(m_handles); i++)
      {
         if(m_handles[i] != INVALID_HANDLE)
            IndicatorRelease(m_handles[i]);
      }
      ArrayFree(m_handles);
   }

   //--- Get trading signal based on multi-timeframe MACD slope analysis
   int GetSignal()
   {
      int upSlopes = 0;
      int downSlopes = 0;
      double totalMomentum = 0.0;

      // Analyze each timeframe
      for(int i = 0; i < ArraySize(m_timeframes); i++)
      {
         double slope = CalculateSlope(m_handles[i]);
         double momentum = CalculateMomentum(m_handles[i]);

         totalMomentum += momentum;

         // Detect slope direction
         if(slope > m_slopeThreshold)
            upSlopes++;
         else if(slope < -m_slopeThreshold)
            downSlopes++;
      }

      // Calculate average momentum
      double avgMomentum = totalMomentum / ArraySize(m_timeframes);

      // Check if we have enough matching timeframes
      if(upSlopes >= m_minTimeframesMatch)
      {
         // Bullish signal - at least 2 timeframes showing upward slope
         if(!m_useMomentumFilter || avgMomentum > m_momentumThreshold)
            return 1; // BUY
      }
      else if(downSlopes >= m_minTimeframesMatch)
      {
         // Bearish signal - at least 2 timeframes showing downward slope
         if(!m_useMomentumFilter || avgMomentum < -m_momentumThreshold)
            return -1; // SELL
      }

      return 0; // No signal
   }

   //--- Calculate slope of MACD main line
   double CalculateSlope(int handle)
   {
      if(CopyBuffer(handle, 0, 0, m_slopeBars + 1, m_macdMain) <= 0)
         return 0.0;

      // Linear regression slope calculation
      double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
      int n = m_slopeBars;

      for(int i = 0; i < n; i++)
      {
         double x = i;
         double y = m_macdMain[n - 1 - i]; // Reverse order for chronological

         sumX += x;
         sumY += y;
         sumXY += x * y;
         sumX2 += x * x;
      }

      // Slope = (n*sumXY - sumX*sumY) / (n*sumX2 - sumX*sumX)
      double denominator = n * sumX2 - sumX * sumX;
      if(denominator == 0)
         return 0.0;

      double slope = (n * sumXY - sumX * sumY) / denominator;
      return slope;
   }

   //--- Calculate momentum (MACD - Signal difference)
   double CalculateMomentum(int handle)
   {
      double macdMain[], macdSignal[];
      ArraySetAsSeries(macdMain, true);
      ArraySetAsSeries(macdSignal, true);

      if(CopyBuffer(handle, 0, 0, 3, macdMain) <= 0)
         return 0.0;
      if(CopyBuffer(handle, 1, 0, 3, macdSignal) <= 0)
         return 0.0;

      // Calculate histogram (MACD - Signal) change
      double histogram0 = macdMain[0] - macdSignal[0];
      double histogram1 = macdMain[1] - macdSignal[1];

      return histogram0 - histogram1; // Momentum as histogram change
   }

   //--- Get signal strength (0-100)
   double GetSignalStrength()
   {
      int upSlopes = 0;
      int downSlopes = 0;

      for(int i = 0; i < ArraySize(m_timeframes); i++)
      {
         double slope = CalculateSlope(m_handles[i]);

         if(slope > m_slopeThreshold)
            upSlopes++;
         else if(slope < -m_slopeThreshold)
            downSlopes++;
      }

      int maxSlopes = MathMax(upSlopes, downSlopes);
      return (double)maxSlopes / ArraySize(m_timeframes) * 100.0;
   }

   //--- Get detailed signal info for UI display
   string GetSignalInfo()
   {
      string info = "MACD MTF Analysis:\n";

      for(int i = 0; i < ArraySize(m_timeframes); i++)
      {
         double slope = CalculateSlope(m_handles[i]);
         double momentum = CalculateMomentum(m_handles[i]);

         string direction = "NEUTRAL";
         if(slope > m_slopeThreshold)
            direction = "UP";
         else if(slope < -m_slopeThreshold)
            direction = "DOWN";

         info += EnumToString(m_timeframes[i]) + ": " + direction +
                 " (Slope: " + DoubleToString(slope, 6) +
                 ", Mom: " + DoubleToString(momentum, 6) + ")\n";
      }

      return info;
   }

   //--- Setters for fine-tuning
   void SetSlopeBars(int bars) { m_slopeBars = bars; }
   void SetSlopeThreshold(double threshold) { m_slopeThreshold = threshold; }
   void SetMomentumFilter(bool use, double threshold = 0.0005)
   {
      m_useMomentumFilter = use;
      m_momentumThreshold = threshold;
   }
   void SetMinTimeframesMatch(int min) { m_minTimeframesMatch = min; }

   //--- Getters
   int GetUpSlopesCount()
   {
      int count = 0;
      for(int i = 0; i < ArraySize(m_timeframes); i++)
      {
         double slope = CalculateSlope(m_handles[i]);
         if(slope > m_slopeThreshold)
            count++;
      }
      return count;
   }

   int GetDownSlopesCount()
   {
      int count = 0;
      for(int i = 0; i < ArraySize(m_timeframes); i++)
      {
         double slope = CalculateSlope(m_handles[i]);
         if(slope < -m_slopeThreshold)
            count++;
      }
      return count;
   }
};
