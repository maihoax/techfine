//+------------------------------------------------------------------+
//|                                           Indicators.mqh         |
//|                     Universal Indicator Wrapper for MACD & ATR   |
//|              Based on MQL5 Best Practices from mql5.com Articles |
//+------------------------------------------------------------------+
#property copyright "2025"
#property strict

//+------------------------------------------------------------------+
//| Universal Indicators Class                                       |
//| Handles MACD and ATR with proper MQL5 buffer management         |
//+------------------------------------------------------------------+
class CUniversalIndicators
{
private:
   // Symbol and timeframe
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   // MACD parameters and handle
   int               m_macdFastEMA;
   int               m_macdSlowEMA;
   int               m_macdSignalSMA;
   ENUM_APPLIED_PRICE m_macdPrice;
   int               m_macdHandle;

   // ATR parameters and handle
   int               m_atrPeriod;
   int               m_atrHandle;

   // Buffers for MACD (properly set as series)
   double            m_macdMainBuffer[];
   double            m_macdSignalBuffer[];
   double            m_macdHistBuffer[];

   // Buffers for ATR
   double            m_atrBuffer[];

   // Previous values for cross detection
   double            m_prevMacdMain;
   double            m_prevMacdSignal;

   // Initialization flag
   bool              m_initialized;

public:
   //--- Constructor
   CUniversalIndicators()
   {
      m_symbol = _Symbol;
      m_timeframe = PERIOD_CURRENT;

      // Default MACD parameters (12/26/9 standard)
      m_macdFastEMA = 12;
      m_macdSlowEMA = 26;
      m_macdSignalSMA = 9;
      m_macdPrice = PRICE_CLOSE;
      m_macdHandle = INVALID_HANDLE;

      // Default ATR parameters
      m_atrPeriod = 14;
      m_atrHandle = INVALID_HANDLE;

      // Set buffers as series (index 0 = most recent)
      ArraySetAsSeries(m_macdMainBuffer, true);
      ArraySetAsSeries(m_macdSignalBuffer, true);
      ArraySetAsSeries(m_macdHistBuffer, true);
      ArraySetAsSeries(m_atrBuffer, true);

      m_prevMacdMain = 0.0;
      m_prevMacdSignal = 0.0;
      m_initialized = false;
   }

   //--- Destructor
   ~CUniversalIndicators()
   {
      Release();
   }

   //--- Initialize indicators with custom parameters
   bool Init(string symbol = NULL,
             ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
             int macdFast = 12,
             int macdSlow = 26,
             int macdSignal = 9,
             int atrPeriod = 14)
   {
      // Set symbol (NULL means current symbol)
      m_symbol = (symbol == NULL) ? _Symbol : symbol;
      m_timeframe = timeframe;

      // Set MACD parameters
      m_macdFastEMA = macdFast;
      m_macdSlowEMA = macdSlow;
      m_macdSignalSMA = macdSignal;

      // Set ATR parameters
      m_atrPeriod = atrPeriod;

      // Create MACD handle
      m_macdHandle = iMACD(m_symbol, m_timeframe,
                           m_macdFastEMA, m_macdSlowEMA, m_macdSignalSMA,
                           m_macdPrice);

      if(m_macdHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create MACD indicator handle for ", m_symbol);
         return false;
      }

      // Create ATR handle
      m_atrHandle = iATR(m_symbol, m_timeframe, m_atrPeriod);

      if(m_atrHandle == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create ATR indicator handle for ", m_symbol);
         IndicatorRelease(m_macdHandle);
         m_macdHandle = INVALID_HANDLE;
         return false;
      }

      // Wait for indicators to calculate initial values
      // This is important for proper initialization
      int attempts = 0;
      while(attempts < 10)
      {
         if(BarsCalculated(m_macdHandle) > 0 && BarsCalculated(m_atrHandle) > 0)
            break;
         Sleep(100);
         attempts++;
      }

      if(BarsCalculated(m_macdHandle) <= 0 || BarsCalculated(m_atrHandle) <= 0)
      {
         Print("ERROR: Indicators not ready after waiting");
         Release();
         return false;
      }

      m_initialized = true;
      Print("Indicators initialized successfully for ", m_symbol, " ", EnumToString(m_timeframe));
      return true;
   }

   //--- Release indicator handles
   void Release()
   {
      if(m_macdHandle != INVALID_HANDLE)
      {
         IndicatorRelease(m_macdHandle);
         m_macdHandle = INVALID_HANDLE;
      }

      if(m_atrHandle != INVALID_HANDLE)
      {
         IndicatorRelease(m_atrHandle);
         m_atrHandle = INVALID_HANDLE;
      }

      m_initialized = false;
   }

   //--- Update indicator buffers (call this on each tick or new bar)
   bool Update()
   {
      if(!m_initialized)
         return false;

      // Copy MACD buffers (main, signal, histogram)
      // Buffer 0 = MACD Main Line
      // Buffer 1 = MACD Signal Line
      if(CopyBuffer(m_macdHandle, 0, 0, 3, m_macdMainBuffer) <= 0)
      {
         Print("ERROR: Failed to copy MACD main buffer");
         return false;
      }

      if(CopyBuffer(m_macdHandle, 1, 0, 3, m_macdSignalBuffer) <= 0)
      {
         Print("ERROR: Failed to copy MACD signal buffer");
         return false;
      }

      // Calculate histogram manually (MACD Main - Signal)
      ArrayResize(m_macdHistBuffer, 3);
      for(int i = 0; i < 3; i++)
      {
         m_macdHistBuffer[i] = m_macdMainBuffer[i] - m_macdSignalBuffer[i];
      }

      // Copy ATR buffer
      if(CopyBuffer(m_atrHandle, 0, 0, 2, m_atrBuffer) <= 0)
      {
         Print("ERROR: Failed to copy ATR buffer");
         return false;
      }

      return true;
   }

   //--- Get MACD values at specified bar
   bool GetMACDValues(int bar, double &main, double &signal, double &histogram)
   {
      if(!m_initialized || bar >= ArraySize(m_macdMainBuffer))
         return false;

      main = m_macdMainBuffer[bar];
      signal = m_macdSignalBuffer[bar];
      histogram = m_macdHistBuffer[bar];

      return true;
   }

   //--- Get ATR value at specified bar
   double GetATRValue(int bar = 0)
   {
      if(!m_initialized || bar >= ArraySize(m_atrBuffer))
         return 0.0;

      return m_atrBuffer[bar];
   }

   //--- Check if MACD main is above zero line
   bool IsMACDAboveZero(int bar = 0)
   {
      if(!m_initialized || bar >= ArraySize(m_macdMainBuffer))
         return false;

      return m_macdMainBuffer[bar] > 0.0;
   }

   //--- Check if MACD main is below zero line
   bool IsMACDBelowZero(int bar = 0)
   {
      if(!m_initialized || bar >= ArraySize(m_macdMainBuffer))
         return false;

      return m_macdMainBuffer[bar] < 0.0;
   }

   //--- Check for bullish crossover (MACD main crosses above signal)
   bool IsBullishCross()
   {
      if(!m_initialized || ArraySize(m_macdMainBuffer) < 2)
         return false;

      // Current: main > signal, Previous: main <= signal
      return (m_macdMainBuffer[0] > m_macdSignalBuffer[0] &&
              m_macdMainBuffer[1] <= m_macdSignalBuffer[1]);
   }

   //--- Check for bearish crossover (MACD main crosses below signal)
   bool IsBearishCross()
   {
      if(!m_initialized || ArraySize(m_macdMainBuffer) < 2)
         return false;

      // Current: main < signal, Previous: main >= signal
      return (m_macdMainBuffer[0] < m_macdSignalBuffer[0] &&
              m_macdMainBuffer[1] >= m_macdSignalBuffer[1]);
   }

   //--- Check for zero line cross up (MACD main crosses above 0)
   bool IsZeroLineCrossUp()
   {
      if(!m_initialized || ArraySize(m_macdMainBuffer) < 2)
         return false;

      return (m_macdMainBuffer[0] > 0.0 && m_macdMainBuffer[1] <= 0.0);
   }

   //--- Check for zero line cross down (MACD main crosses below 0)
   bool IsZeroLineCrossDown()
   {
      if(!m_initialized || ArraySize(m_macdMainBuffer) < 2)
         return false;

      return (m_macdMainBuffer[0] < 0.0 && m_macdMainBuffer[1] >= 0.0);
   }

   //--- Get histogram expansion/contraction (for momentum analysis)
   // Returns: > 0 expanding (strengthening), < 0 contracting (weakening)
   double GetHistogramMomentum()
   {
      if(!m_initialized || ArraySize(m_macdHistBuffer) < 2)
         return 0.0;

      return MathAbs(m_macdHistBuffer[0]) - MathAbs(m_macdHistBuffer[1]);
   }

   //--- Check if histogram is expanding (strengthening trend)
   bool IsHistogramExpanding()
   {
      return GetHistogramMomentum() > 0.0;
   }

   //--- Check if histogram is contracting (weakening trend)
   bool IsHistogramContracting()
   {
      return GetHistogramMomentum() < 0.0;
   }

   //--- Get MACD direction (for trend context)
   // Returns: +1 bullish bias, -1 bearish bias, 0 neutral
   int GetMACDDirection()
   {
      if(!m_initialized)
         return 0;

      if(m_macdMainBuffer[0] > 0.0)
         return 1;  // Bullish bias
      else if(m_macdMainBuffer[0] < 0.0)
         return -1; // Bearish bias

      return 0; // Neutral
   }

   //--- Check if MACD is aligned (main and signal on same side of zero)
   bool IsMACDAligned()
   {
      if(!m_initialized)
         return false;

      return (m_macdMainBuffer[0] > 0.0 && m_macdSignalBuffer[0] > 0.0) ||
             (m_macdMainBuffer[0] < 0.0 && m_macdSignalBuffer[0] < 0.0);
   }

   //--- Getters
   bool IsInitialized() const { return m_initialized; }
   string GetSymbol() const { return m_symbol; }
   ENUM_TIMEFRAMES GetTimeframe() const { return m_timeframe; }

   //--- Get raw buffer values (for advanced analysis)
   double GetMACDMain(int bar = 0)
   {
      if(!m_initialized || bar >= ArraySize(m_macdMainBuffer))
         return 0.0;
      return m_macdMainBuffer[bar];
   }

   double GetMACDSignal(int bar = 0)
   {
      if(!m_initialized || bar >= ArraySize(m_macdSignalBuffer))
         return 0.0;
      return m_macdSignalBuffer[bar];
   }

   double GetMACDHistogram(int bar = 0)
   {
      if(!m_initialized || bar >= ArraySize(m_macdHistBuffer))
         return 0.0;
      return m_macdHistBuffer[bar];
   }
};
//+------------------------------------------------------------------+
