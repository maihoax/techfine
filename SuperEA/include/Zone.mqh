//+------------------------------------------------------------------+
//|                                                Zone.mqh          |
//|  Safe-Zone và quản lý envelopes                                 |
//+------------------------------------------------------------------+
#pragma once
#include "Types.mqh"

class CSafeZone
  {
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_ltf;
   int              m_atrPeriod;
   double           m_kSafe;
   double           m_gridFactor;
   int              m_rectBars;
   int              m_rebuildPeriod;
   int              m_envelopeHandle;
   ZoneBands        m_zone;

   bool LoadRates(MqlRates &rates[]) const
     {
      ArraySetAsSeries(rates,true);
      return(CopyRates(m_symbol,m_ltf,0,m_rectBars,rates)>=m_rectBars);
     }

   bool DetectRectangle(MqlRates &rates[],double &hi,double &lo,double &coverage)
     {
      int total=ArraySize(rates);
      hi=rates[0].high;
      lo=rates[0].low;
      for(int i=1;i<total;i++)
        {
         if(rates[i].high>hi) hi=rates[i].high;
         if(rates[i].low<lo) lo=rates[i].low;
        }
      int inside=0;
      for(int i=0;i<total;i++)
        if(rates[i].close>=lo && rates[i].close<=hi) inside++;
      coverage=(double)inside/(double)total;
      return(coverage>=0.55);
     }

   double RollingMedian(int bars)
     {
      MqlRates rates[];
      if(CopyRates(m_symbol,m_ltf,0,bars,rates)<bars)
         return(SymbolInfoDouble(m_symbol,SYMBOL_BID));
      double tmp[];
      ArrayResize(tmp,bars);
      for(int i=0;i<bars;i++) tmp[i]=(rates[i].high+rates[i].low+rates[i].close)/3.0;
      ArraySort(tmp,WHOLE_ARRAY,0,MODE_ASCEND);
      return(tmp[bars/2]);
     }

   void ApplyEnvelopeBias()
     {
      if(m_envelopeHandle==INVALID_HANDLE)
        m_envelopeHandle=iEnvelopes(m_symbol,m_ltf,m_atrPeriod,0,MODE_EMA,PRICE_CLOSE,0.2,MODE_UPPER);
      if(m_envelopeHandle==INVALID_HANDLE) return;
      double envUp[], envDn[];
      if(CopyBuffer(m_envelopeHandle,0,0,1,envUp)<1) return;
      if(CopyBuffer(m_envelopeHandle,1,0,1,envDn)<1) return;
      m_zone.outerUp=MathMax(m_zone.outerUp,envUp[0]);
      m_zone.outerDn=MathMin(m_zone.outerDn,envDn[0]);
     }

public:
                     CSafeZone():m_symbol(_Symbol),m_ltf(PERIOD_M3),m_atrPeriod(14),
                     m_kSafe(1.2),m_gridFactor(0.8),m_rectBars(120),m_rebuildPeriod(10),
                     m_envelopeHandle(INVALID_HANDLE)
     {
      ZeroMemory(m_zone);
     }

   void Configure(const string symbol,ENUM_TIMEFRAMES ltf,int atrPeriod,double kSafe,double gridFactor,int rectBars,int rebuild)
     {
      m_symbol=symbol;
      m_ltf=ltf;
      m_atrPeriod=atrPeriod;
      m_kSafe=kSafe;
      m_gridFactor=gridFactor;
      m_rectBars=rectBars;
      m_rebuildPeriod=rebuild;
     }

   bool NeedsRebuild(datetime current)
     {
      if(m_zone.lastBuild==0) return(true);
      return((current-m_zone.lastBuild)>=m_rebuildPeriod*PeriodSeconds(m_ltf));
     }

   const ZoneBands &Rebuild()
     {
      double atr=iATR(m_symbol,m_ltf,m_atrPeriod,0);
      if(atr<=0.0)
        {
         m_zone.atr=0.0;
         return(m_zone);
        }
      m_zone.atr=atr;

      MqlRates rates[];
      double hi=0,lo=0,coverage=0;
      double center=0.0;
      if(LoadRates(rates) && DetectRectangle(rates,hi,lo,coverage))
         center=0.5*(hi+lo);
      else
         center=RollingMedian(m_rectBars);
      m_zone.center=center;

      double radius=m_kSafe*atr;
      m_zone.innerUp=center+0.33*radius;
      m_zone.innerDn=center-0.33*radius;
      m_zone.midUp=center+0.66*radius;
      m_zone.midDn=center-0.66*radius;
      m_zone.outerUp=center+radius;
      m_zone.outerDn=center-radius;
      m_zone.gridStep=m_gridFactor*atr;
      ApplyEnvelopeBias();
      m_zone.lastBuild=TimeCurrent();
      return(m_zone);
     }

   const ZoneBands &State() const {return m_zone;}
  };
