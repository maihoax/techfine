//+------------------------------------------------------------------+
//|                                              Signals.mqh         |
//|  Lọc tín hiệu xu hướng & mô hình cấu trúc                       |
//+------------------------------------------------------------------+
#pragma once
#include "Types.mqh"

class CSignalSuite
  {
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_htf;
   ENUM_TIMEFRAMES  m_ltf;
   int              m_atrPeriodHTF;
   int              m_emaPeriod;
   int              m_wmaPeriod;
   int              m_slopeLookback;
   int              m_rectangleBars;
   int              m_patternBars;
   double           m_falseBreakMax;
   double           m_impulseFactor;
   double           m_pullbackFib;
   int              m_rsxPeriod;
   int              m_rsiPeriod;
   TrendContext     m_trend;
   PatternSignal    m_pattern;
   int              m_emaHandle;
   int              m_wmaHandle;
   int              m_atrHandle;
   int              m_rsxHandle;
   int              m_rsiHandle;
   int              m_atrPatternHandle;

   bool LoadRates(ENUM_TIMEFRAMES tf,int bars,MqlRates &rates[]) const
     {
      ArraySetAsSeries(rates,true);
      return(CopyRates(m_symbol,tf,0,bars,rates)>=bars);
     }

   double NormalizeSlope(double slope,double atr)
     {
      if(atr<=0.0) return(0.0);
      return(slope/atr);
     }

   void EvaluateTrend()
     {
      if(m_emaHandle==INVALID_HANDLE)
         m_emaHandle=iMA(m_symbol,m_htf,m_emaPeriod,0,MODE_EMA,PRICE_CLOSE);
      if(m_wmaHandle==INVALID_HANDLE)
         m_wmaHandle=iMA(m_symbol,m_htf,m_wmaPeriod,0,MODE_LWMA,PRICE_CLOSE);
      if(m_atrHandle==INVALID_HANDLE)
         m_atrHandle=iATR(m_symbol,m_htf,m_atrPeriodHTF);

      if(m_emaHandle==INVALID_HANDLE || m_wmaHandle==INVALID_HANDLE || m_atrHandle==INVALID_HANDLE)
        {
         m_trend.trendSign=0;
         return;
        }

      double emaBuffer[];
      double wmaBuffer[];
      double atrBuffer[];
      if(CopyBuffer(m_emaHandle,0,0,m_slopeLookback+1,emaBuffer)<m_slopeLookback+1) return;
      if(CopyBuffer(m_wmaHandle,0,0,1,wmaBuffer)<1) return;
      if(CopyBuffer(m_atrHandle,0,0,1,atrBuffer)<1) return;

      double slope = (emaBuffer[0]-emaBuffer[m_slopeLookback])/(double)m_slopeLookback;
      double slopeNorm = NormalizeSlope(slope,atrBuffer[0]);
      double price=SymbolInfoDouble(m_symbol,SYMBOL_BID);

      m_trend.slope=slopeNorm;
      m_trend.ema=emaBuffer[0];
      m_trend.wma=wmaBuffer[0];
      m_trend.trendSign=0;

      if(price>m_trend.ema && m_trend.ema>m_trend.wma && slopeNorm>0.05)
         m_trend.trendSign=1;
      else if(price<m_trend.ema && m_trend.ema<m_trend.wma && slopeNorm<-0.05)
         m_trend.trendSign=-1;
     }

   void EvaluateRectangle(MqlRates &rates[])
     {
      int total=ArraySize(rates);
      double hi=rates[0].high;
      double lo=rates[0].low;
      for(int i=1;i<total;i++)
        {
         if(rates[i].high>hi) hi=rates[i].high;
         if(rates[i].low<lo) lo=rates[i].low;
        }
      double width=hi-lo;
      if(width<=0.0) return;
      int inside=0;
      for(int i=0;i<total;i++)
        if(rates[i].close>=lo && rates[i].close<=hi) inside++;
      double coverage=(double)inside/(double)total;
      if(coverage>=0.60)
        {
         m_pattern.hasRectangle=true;
         m_pattern.rectangleHigh=hi;
         m_pattern.rectangleLow=lo;
         m_pattern.patternStrength+=coverage;
        }
     }

   void EvaluateTriple(MqlRates &rates[])
     {
      int total=ArraySize(rates);
      if(total<MathMax(9,m_patternBars+1)) return;
      if(m_atrPatternHandle==INVALID_HANDLE)
         m_atrPatternHandle=iATR(m_symbol,m_ltf,m_patternBars);
      if(m_atrPatternHandle==INVALID_HANDLE) return;
      double atrBuf[];
      if(CopyBuffer(m_atrPatternHandle,0,0,1,atrBuf)<1) return;
      double atr=atrBuf[0];
      int peaks=0, troughs=0;
      double tolerance=0.6*atr;
      int falseBreaks=0;
      for(int i=1;i<total-1;i++)
        {
         bool peak=(rates[i].high>rates[i-1].high && rates[i].high>rates[i+1].high);
         bool trough=(rates[i].low<rates[i-1].low && rates[i].low<rates[i+1].low);
         if(peak)
           {
            peaks++;
            if(MathAbs(rates[i].high-rates[0].high)>tolerance) falseBreaks++;
           }
         if(trough)
           {
            troughs++;
            if(MathAbs(rates[i].low-rates[0].low)>tolerance) falseBreaks++;
           }
        }
      if(falseBreaks<=m_falseBreakMax && (peaks>=3 || troughs>=3))
        {
         m_pattern.hasTriple=true;
         m_pattern.patternStrength+=0.5;
        }
     }

   void EvaluateFlag(MqlRates &rates[])
     {
      int total=ArraySize(rates);
      if(total<MathMax(10,m_patternBars+1)) return;
      if(m_atrPatternHandle==INVALID_HANDLE)
         m_atrPatternHandle=iATR(m_symbol,m_ltf,m_patternBars);
      if(m_atrPatternHandle==INVALID_HANDLE) return;
      double atrBuf[];
      if(CopyBuffer(m_atrPatternHandle,0,0,1,atrBuf)<1) return;
      double atr=atrBuf[0];
      double impulse=MathAbs(rates[0].close-rates[m_patternBars].close);
      if(impulse< m_impulseFactor*atr) return;
      double pullback=MathAbs(rates[m_patternBars].close-rates[m_patternBars/2].close);
      if(pullback>m_pullbackFib*impulse) return;
      m_pattern.hasFlag=true;
      m_pattern.patternStrength+=0.4;
     }

   void EvaluateEnergy()
     {
      if(m_rsxHandle==INVALID_HANDLE)
         m_rsxHandle=iRSX(m_symbol,m_ltf,m_rsxPeriod,PRICE_CLOSE);
      if(m_rsiHandle==INVALID_HANDLE)
         m_rsiHandle=iRSI(m_symbol,m_ltf,m_rsiPeriod,PRICE_CLOSE);
      if(m_rsxHandle==INVALID_HANDLE || m_rsiHandle==INVALID_HANDLE) return;
      double rsx[], rsi[];
      if(CopyBuffer(m_rsxHandle,0,0,5,rsx)<5) return;
      if(CopyBuffer(m_rsiHandle,0,0,5,rsi)<5) return;
      double rsxVal=rsx[0];
      double rsiVal=rsi[0];
      if(rsxVal>55 && rsiVal>55)
         m_pattern.patternStrength+=0.2;
      else if(rsxVal<45 && rsiVal<45)
         m_pattern.patternStrength+=0.2;
     }

public:
                     CSignalSuite():m_symbol(_Symbol),m_htf(PERIOD_H1),m_ltf(PERIOD_M3),
                     m_atrPeriodHTF(14),m_emaPeriod(100),m_wmaPeriod(200),m_slopeLookback(40),
                     m_rectangleBars(120),m_patternBars(20),m_falseBreakMax(2),m_impulseFactor(2.0),
                     m_pullbackFib(0.62),m_rsxPeriod(14),m_rsiPeriod(14),
                     m_emaHandle(INVALID_HANDLE),m_wmaHandle(INVALID_HANDLE),m_atrHandle(INVALID_HANDLE),
                     m_rsxHandle(INVALID_HANDLE),m_rsiHandle(INVALID_HANDLE),m_atrPatternHandle(INVALID_HANDLE)
     {
      ZeroMemory(m_trend);
      ZeroMemory(m_pattern);
     }

   void Configure(const string symbol,ENUM_TIMEFRAMES htf,ENUM_TIMEFRAMES ltf)
     {
      m_symbol=symbol;
      m_htf=htf;
      m_ltf=ltf;
     }

   void Update()
     {
      ZeroMemory(m_pattern);
      EvaluateTrend();
      MqlRates rates[];
      if(!LoadRates(m_ltf,m_rectangleBars,rates)) return;
      EvaluateRectangle(rates);
      EvaluateTriple(rates);
      EvaluateFlag(rates);
      EvaluateEnergy();
     }

   const TrendContext &Trend() const {return m_trend;}
   const PatternSignal &Pattern() const {return m_pattern;}
  };
