//+------------------------------------------------------------------+
//|                                              Signals.mqh         |
//|                   Universal Signal Logic with Context Detection  |
//|         MACD-based signals with Trending/Range market context    |
//+------------------------------------------------------------------+
#property copyright "2025"
#property strict

#include "Indicators.mqh"

//+------------------------------------------------------------------+
//| Market Context Enumeration                                       |
//+------------------------------------------------------------------+
enum ENUM_MARKET_CONTEXT
{
   CONTEXT_UNKNOWN = 0,     // Unknown or initializing
   CONTEXT_TRENDING = 1,    // Clear trend detected
   CONTEXT_RANGING = 2      // Ranging/sideways market
};

//+------------------------------------------------------------------+
//| Signal Type Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE = 0,         // No signal
   SIGNAL_BUY = 1,          // Buy signal
   SIGNAL_SELL = -1         // Sell signal
};

//+------------------------------------------------------------------+
//| Universal Signals Class                                          |
//| Generates trading signals based on MACD and market context       |
//+------------------------------------------------------------------+
class CUniversalSignals
{
private:
   // Reference to indicators
   CUniversalIndicators* m_indicators;

   // Market context parameters
   ENUM_MARKET_CONTEXT m_currentContext;
   int               m_contextBars;           // Bars to analyze for context
   double            m_trendingThreshold;     // MACD consistency for trending
   double            m_rangingThreshold;      // MACD oscillation for ranging

   // Signal filters
   bool              m_requireZeroLineAlignment;  // Require MACD on correct side of zero
   bool              m_requireHistogramExpansion; // Require expanding histogram
   double            m_minATRFilter;              // Minimum ATR to allow signals
   int               m_minBarsBetweenSignals;     // Cooldown between signals

   // State tracking
   datetime          m_lastSignalTime;
   int               m_lastSignalType;

   // Pullback detection
   bool              m_allowPullbackEntry;
   int               m_pullbackBars;

public:
   //--- Constructor
   CUniversalSignals()
   {
      m_indicators = NULL;
      m_currentContext = CONTEXT_UNKNOWN;

      // Default context detection parameters
      m_contextBars = 10;
      m_trendingThreshold = 0.7;  // 70% bars with consistent MACD direction
      m_rangingThreshold = 0.5;   // 50% bars with MACD oscillating

      // Default signal filters
      m_requireZeroLineAlignment = true;
      m_requireHistogramExpansion = true;
      m_minATRFilter = 0.0;        // Will be set based on symbol
      m_minBarsBetweenSignals = 3;

      // State
      m_lastSignalTime = 0;
      m_lastSignalType = SIGNAL_NONE;

      // Pullback settings
      m_allowPullbackEntry = true;
      m_pullbackBars = 3;
   }

   //--- Initialize with indicator reference
   bool Init(CUniversalIndicators* indicators,
             double minATRPoints = 0.0)
   {
      if(indicators == NULL || !indicators.IsInitialized())
      {
         Print("ERROR: Invalid indicators reference in Signals.Init()");
         return false;
      }

      m_indicators = indicators;
      m_minATRFilter = minATRPoints;

      Print("Signals initialized successfully");
      return true;
   }

   //--- Update market context (call periodically, e.g., on new bar)
   void UpdateContext()
   {
      if(m_indicators == NULL)
         return;

      int bullishBars = 0;
      int bearishBars = 0;
      int oscillatingBars = 0;

      // Analyze recent bars to determine context
      for(int i = 1; i <= m_contextBars; i++)
      {
         double main = m_indicators.GetMACDMain(i);
         double prevMain = m_indicators.GetMACDMain(i + 1);

         // Count bars where MACD stays on same side of zero
         if(main > 0.0 && prevMain > 0.0)
            bullishBars++;
         else if(main < 0.0 && prevMain < 0.0)
            bearishBars++;
         else
            oscillatingBars++;
      }

      // Determine context based on consistency
      double trendRatio = (double)MathMax(bullishBars, bearishBars) / m_contextBars;
      double rangeRatio = (double)oscillatingBars / m_contextBars;

      if(trendRatio >= m_trendingThreshold)
      {
         m_currentContext = CONTEXT_TRENDING;
      }
      else if(rangeRatio >= m_rangingThreshold)
      {
         m_currentContext = CONTEXT_RANGING;
      }
      else
      {
         m_currentContext = CONTEXT_UNKNOWN;
      }
   }

   //--- Get current trading signal
   ENUM_SIGNAL_TYPE GetSignal()
   {
      if(m_indicators == NULL)
         return SIGNAL_NONE;

      // Update indicators first
      if(!m_indicators.Update())
         return SIGNAL_NONE;

      // Check ATR filter (avoid trading in low volatility)
      double currentATR = m_indicators.GetATRValue(0);
      if(m_minATRFilter > 0.0 && currentATR < m_minATRFilter)
      {
         return SIGNAL_NONE; // Market too quiet
      }

      // Check cooldown between signals
      if(m_minBarsBetweenSignals > 0)
      {
         datetime currentTime = iTime(m_indicators.GetSymbol(), m_indicators.GetTimeframe(), 0);
         if(currentTime - m_lastSignalTime < m_minBarsBetweenSignals * PeriodSeconds(m_indicators.GetTimeframe()))
         {
            return SIGNAL_NONE;
         }
      }

      // Generate signal based on context
      ENUM_SIGNAL_TYPE signal = SIGNAL_NONE;

      if(m_currentContext == CONTEXT_TRENDING)
      {
         signal = GetTrendingSignal();
      }
      else if(m_currentContext == CONTEXT_RANGING)
      {
         signal = GetRangingSignal();
      }
      else
      {
         // Unknown context - use basic signal
         signal = GetBasicSignal();
      }

      // Update state if signal generated
      if(signal != SIGNAL_NONE)
      {
         m_lastSignalTime = iTime(m_indicators.GetSymbol(), m_indicators.GetTimeframe(), 0);
         m_lastSignalType = signal;
      }

      return signal;
   }

   //--- Get signal in trending context
   ENUM_SIGNAL_TYPE GetTrendingSignal()
   {
      // In trending mode: prioritize trend-following entries
      // Entry conditions:
      // 1. MACD cross in trend direction
      // 2. MACD aligned with zero line (bullish > 0, bearish < 0)
      // 3. Histogram expanding (strengthening momentum)
      // OR pullback entry: histogram contracts then re-expands

      bool bullishCross = m_indicators.IsBullishCross();
      bool bearishCross = m_indicators.IsBearishCross();

      // Check basic cross
      if(bullishCross)
      {
         // Verify alignment with zero line
         if(m_requireZeroLineAlignment && !m_indicators.IsMACDAboveZero())
            return SIGNAL_NONE;

         // Verify histogram expansion (strengthening)
         if(m_requireHistogramExpansion && !m_indicators.IsHistogramExpanding())
         {
            // Allow if it's a pullback re-entry
            if(!IsPullbackReEntry(true))
               return SIGNAL_NONE;
         }

         return SIGNAL_BUY;
      }
      else if(bearishCross)
      {
         // Verify alignment with zero line
         if(m_requireZeroLineAlignment && !m_indicators.IsMACDBelowZero())
            return SIGNAL_NONE;

         // Verify histogram expansion (strengthening)
         if(m_requireHistogramExpansion && !m_indicators.IsHistogramExpanding())
         {
            // Allow if it's a pullback re-entry
            if(!IsPullbackReEntry(false))
               return SIGNAL_NONE;
         }

         return SIGNAL_SELL;
      }

      // Check for pullback entries (no cross, but momentum resuming)
      if(m_allowPullbackEntry)
      {
         if(CheckPullbackEntry(true))
            return SIGNAL_BUY;

         if(CheckPullbackEntry(false))
            return SIGNAL_SELL;
      }

      return SIGNAL_NONE;
   }

   //--- Get signal in ranging context
   ENUM_SIGNAL_TYPE GetRangingSignal()
   {
      // In ranging mode: reduce frequency, require stronger confirmation
      // Only take signals at extreme MACD levels (mean reversion approach)
      // Or require zero-line cross for higher conviction

      // Require zero-line cross for ranging signals (higher conviction)
      if(m_indicators.IsZeroLineCrossUp() && m_indicators.IsBullishCross())
      {
         return SIGNAL_BUY;
      }

      if(m_indicators.IsZeroLineCrossDown() && m_indicators.IsBearishCross())
      {
         return SIGNAL_SELL;
      }

      // In ranging market, be more conservative
      return SIGNAL_NONE;
   }

   //--- Get basic signal (when context is unknown)
   ENUM_SIGNAL_TYPE GetBasicSignal()
   {
      // Basic MACD crossover with zero-line filter

      bool bullishCross = m_indicators.IsBullishCross();
      bool bearishCross = m_indicators.IsBearishCross();

      if(bullishCross)
      {
         // Prefer entries when MACD is above zero
         if(m_indicators.IsMACDAboveZero() || m_indicators.IsZeroLineCrossUp())
            return SIGNAL_BUY;
      }
      else if(bearishCross)
      {
         // Prefer entries when MACD is below zero
         if(m_indicators.IsMACDBelowZero() || m_indicators.IsZeroLineCrossDown())
            return SIGNAL_SELL;
      }

      return SIGNAL_NONE;
   }

   //--- Check if current is a pullback re-entry
   bool IsPullbackReEntry(bool bullish)
   {
      if(!m_allowPullbackEntry)
         return false;

      // Check if histogram contracted and is now re-expanding
      // This suggests a pullback in trend followed by resumption

      if(bullish)
      {
         // For bullish: MACD should be above zero
         if(!m_indicators.IsMACDAboveZero())
            return false;

         // Histogram should be expanding now
         if(!m_indicators.IsHistogramExpanding())
            return false;

         // Check if it contracted recently
         bool wasContracting = false;
         for(int i = 1; i <= m_pullbackBars; i++)
         {
            double hist = m_indicators.GetMACDHistogram(i);
            double prevHist = m_indicators.GetMACDHistogram(i + 1);

            if(MathAbs(hist) < MathAbs(prevHist))
            {
               wasContracting = true;
               break;
            }
         }

         return wasContracting;
      }
      else
      {
         // For bearish: MACD should be below zero
         if(!m_indicators.IsMACDBelowZero())
            return false;

         // Histogram should be expanding now
         if(!m_indicators.IsHistogramExpanding())
            return false;

         // Check if it contracted recently
         bool wasContracting = false;
         for(int i = 1; i <= m_pullbackBars; i++)
         {
            double hist = m_indicators.GetMACDHistogram(i);
            double prevHist = m_indicators.GetMACDHistogram(i + 1);

            if(MathAbs(hist) < MathAbs(prevHist))
            {
               wasContracting = true;
               break;
            }
         }

         return wasContracting;
      }

      return false;
   }

   //--- Check for pullback entry opportunity
   bool CheckPullbackEntry(bool bullish)
   {
      if(bullish)
      {
         // Bullish pullback entry:
         // - MACD above zero (bullish bias)
         // - MACD main above signal (aligned)
         // - Histogram was contracting, now expanding

         if(!m_indicators.IsMACDAboveZero())
            return false;

         double main = m_indicators.GetMACDMain(0);
         double signal = m_indicators.GetMACDSignal(0);

         if(main <= signal)
            return false;

         return IsPullbackReEntry(true);
      }
      else
      {
         // Bearish pullback entry:
         // - MACD below zero (bearish bias)
         // - MACD main below signal (aligned)
         // - Histogram was contracting, now expanding

         if(!m_indicators.IsMACDBelowZero())
            return false;

         double main = m_indicators.GetMACDMain(0);
         double signal = m_indicators.GetMACDSignal(0);

         if(main >= signal)
            return false;

         return IsPullbackReEntry(false);
      }

      return false;
   }

   //--- Get signal strength (0-100)
   double GetSignalStrength()
   {
      if(m_indicators == NULL)
         return 0.0;

      double strength = 0.0;

      // Factor 1: Histogram size (larger = stronger)
      double hist = MathAbs(m_indicators.GetMACDHistogram(0));
      double avgHist = 0.0;
      for(int i = 0; i < 10; i++)
         avgHist += MathAbs(m_indicators.GetMACDHistogram(i));
      avgHist /= 10.0;

      if(avgHist > 0.0)
         strength += (hist / avgHist) * 30.0;

      // Factor 2: MACD alignment with zero (stronger if aligned)
      if(m_indicators.IsMACDAligned())
         strength += 30.0;

      // Factor 3: Histogram expansion
      if(m_indicators.IsHistogramExpanding())
         strength += 20.0;

      // Factor 4: Context match
      if(m_currentContext == CONTEXT_TRENDING)
         strength += 20.0;

      return MathMin(strength, 100.0);
   }

   //--- Get exit signal (based on MACD reversal)
   bool ShouldExit(bool isLongPosition)
   {
      if(m_indicators == NULL)
         return false;

      if(isLongPosition)
      {
         // Exit long if MACD crosses down or crosses below zero
         if(m_indicators.IsBearishCross() || m_indicators.IsZeroLineCrossDown())
            return true;

         // Also exit if histogram starts contracting significantly
         if(m_indicators.IsHistogramContracting())
         {
            double momentum = m_indicators.GetHistogramMomentum();
            // If contracting fast, exit
            if(momentum < -0.0001)
               return true;
         }
      }
      else
      {
         // Exit short if MACD crosses up or crosses above zero
         if(m_indicators.IsBullishCross() || m_indicators.IsZeroLineCrossUp())
            return true;

         // Also exit if histogram starts contracting significantly
         if(m_indicators.IsHistogramContracting())
         {
            double momentum = m_indicators.GetHistogramMomentum();
            // If contracting fast, exit
            if(momentum < -0.0001)
               return true;
         }
      }

      return false;
   }

   //--- Getters
   ENUM_MARKET_CONTEXT GetCurrentContext() const { return m_currentContext; }
   string GetContextString() const
   {
      switch(m_currentContext)
      {
         case CONTEXT_TRENDING: return "TRENDING";
         case CONTEXT_RANGING: return "RANGING";
         default: return "UNKNOWN";
      }
   }

   //--- Setters
   void SetContextBars(int bars) { m_contextBars = bars; }
   void SetTrendingThreshold(double threshold) { m_trendingThreshold = threshold; }
   void SetRangingThreshold(double threshold) { m_rangingThreshold = threshold; }
   void SetZeroLineAlignment(bool require) { m_requireZeroLineAlignment = require; }
   void SetHistogramExpansionFilter(bool require) { m_requireHistogramExpansion = require; }
   void SetMinATRFilter(double minATR) { m_minATRFilter = minATR; }
   void SetMinBarsBetweenSignals(int bars) { m_minBarsBetweenSignals = bars; }
   void SetPullbackEntry(bool allow, int bars = 3)
   {
      m_allowPullbackEntry = allow;
      m_pullbackBars = bars;
   }
};
//+------------------------------------------------------------------+
