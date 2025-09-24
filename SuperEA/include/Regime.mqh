//+------------------------------------------------------------------+
//|                                               Regime.mqh         |
//|  Router thị trường dựa trên GHE/VRT                             |
//+------------------------------------------------------------------+
#pragma once
#include "Types.mqh"

class CRegimeRouter
  {
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_htf;
   ENUM_TIMEFRAMES  m_ltf;
   int              m_gheWindow;
   int              m_vrtLag;
   int              m_vrtWindow;
   RouterState      m_state;

   double LogReturn(const MqlRates &curr,const MqlRates &prev) const
     {
      double p1=(curr.open+curr.close)/2.0;
      double p0=(prev.open+prev.close)/2.0;
      if(p0<=0.0 || p1<=0.0) return(0.0);
      return(MathLog(p1/p0));
     }

   double ComputeHurst(const double &series[])
     {
      int n=ArraySize(series);
      if(n<8) return(0.5);
      double mean=0.0;
      for(int i=0;i<n;i++) mean+=series[i];
      mean/=n;
      double variance=0.0;
      for(int i=0;i<n;i++) variance+=(series[i]-mean)*(series[i]-mean);
      if(variance<=0.0) return(0.5);

      double rescaled=0.0;
      int segments=3;
      int segSize=n/segments;
      if(segSize<2) segSize=2;
      for(int s=0;s<segments;s++)
        {
         double cMean=0.0;
         int start=s*segSize;
         int end=MathMin(start+segSize,n);
         if(start>=end) break;
         for(int i=start;i<end;i++) cMean+=series[i];
         cMean/=(end-start);

         double running=0.0;
         double maxVal=-DBL_MAX;
         double minVal= DBL_MAX;
         for(int i=start;i<end;i++)
           {
            running += series[i]-cMean;
            if(running>maxVal) maxVal=running;
            if(running<minVal) minVal=running;
           }
         double range=maxVal-minVal;
         double stdSegment=0.0;
         for(int i=start;i<end;i++) stdSegment+=(series[i]-cMean)*(series[i]-cMean);
         stdSegment=MathSqrt(stdSegment/MathMax(1,end-start-1));
         if(stdSegment>0.0) rescaled += MathLog(range/stdSegment);
        }

      double logN=MathLog(segSize);
      if(logN<=0.0) return(0.5);
      double H=rescaled/(segments*logN);
      return(MathMax(0.0,MathMin(1.0,H))); // clamp 0..1
     }

   double ComputeVarianceRatio(const double &series[])
     {
      int n=ArraySize(series);
      if(n<m_vrtLag+1) return(1.0);
      double mean=0.0;
      for(int i=0;i<n;i++) mean+=series[i];
      mean/=n;
      double var1=0.0;
      for(int i=1;i<n;i++)
        {
         double diff=series[i]-series[i-1];
         var1+=diff*diff;
        }
      if(var1<=0.0) return(1.0);
      var1/= (n-1);

      double varLag=0.0;
      for(int i=m_vrtLag;i<n;i++)
        {
         double diff=series[i]-series[i-m_vrtLag];
         varLag+=diff*diff;
        }
      varLag/= (n-m_vrtLag);
      double ratio= (varLag/(m_vrtLag)) / var1;
      return(ratio);
     }

public:
                     CRegimeRouter():m_symbol(_Symbol),m_htf(PERIOD_H1),m_ltf(PERIOD_M3),
                     m_gheWindow(160),m_vrtLag(4),m_vrtWindow(120)
     {
      m_state.mode=ROUTER_NEUTRAL;
      m_state.ghe=0.5;
      m_state.vrt=1.0;
     }

   void Configure(const string symbol,ENUM_TIMEFRAMES htf,ENUM_TIMEFRAMES ltf,int gheWindow,int vrtLag,int vrtWindow)
     {
      m_symbol=symbol;
      m_htf=htf;
      m_ltf=ltf;
      m_gheWindow=gheWindow;
      m_vrtLag=vrtLag;
      m_vrtWindow=vrtWindow;
     }

   const RouterState &Update()
     {
      // collect HTF returns for Hurst
      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      if(CopyRates(m_symbol,m_htf,0,m_gheWindow+1,rates)<m_gheWindow+1)
        {
         m_state.mode=ROUTER_NEUTRAL;
         return(m_state);
        }
      double gheSeries[];
      ArrayResize(gheSeries,m_gheWindow);
      double trendBias=0.0;
      for(int i=0;i<m_gheWindow;i++)
        {
         gheSeries[i]=LogReturn(rates[i],rates[i+1]);
         trendBias+=gheSeries[i];
        }
      m_state.ghe=ComputeHurst(gheSeries);

      // collect LTF returns for VRT
      ArraySetAsSeries(rates,true);
      if(CopyRates(m_symbol,m_ltf,0,m_vrtWindow+1,rates)<m_vrtWindow+1)
        {
         m_state.mode=ROUTER_NEUTRAL;
         return(m_state);
        }
      double vrtSeries[];
      ArrayResize(vrtSeries,m_vrtWindow);
      for(int i=0;i<m_vrtWindow;i++)
        vrtSeries[i]=LogReturn(rates[i],rates[i+1]);
      m_state.vrt=ComputeVarianceRatio(vrtSeries);

      // decision map
      double biasThreshold=0.0002;
      if(m_state.ghe>0.55)
        {
         if(trendBias>biasThreshold && m_state.vrt>0.95)
            m_state.mode=ROUTER_TREND_UP;
         else if(trendBias<-biasThreshold && m_state.vrt>0.95)
            m_state.mode=ROUTER_TREND_DOWN;
         else
            m_state.mode=ROUTER_NEUTRAL;
        }
      else if(m_state.ghe<0.45 && m_state.vrt<0.95)
        m_state.mode=ROUTER_MEAN_REVERSION;
      else
        m_state.mode=ROUTER_NEUTRAL;

      return(m_state);
     }

   const RouterState &State() const {return m_state;}
  };
