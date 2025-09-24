//+------------------------------------------------------------------+
//|                                                   UI.mqh         |
//|  Panel hiển thị và logging                                     |
//+------------------------------------------------------------------+
#pragma once
#include "Types.mqh"

class CTelemetryPanel
  {
private:
   string m_symbol;
public:
                     CTelemetryPanel():m_symbol(_Symbol){}
   void SetSymbol(const string symbol){m_symbol=symbol;}
   void Render(const RouterState &router,const TrendContext &trend,const ZoneBands &zone,const ExposureState &expo,double basket)
     {
      string mode="Neutral";
      if(router.mode==ROUTER_TREND_UP) mode="TrendUp";
      else if(router.mode==ROUTER_TREND_DOWN) mode="TrendDown";
      else if(router.mode==ROUTER_MEAN_REVERSION) mode="MeanRev";
      string text=StringFormat("SuperEA %s\nRouter: %s | GHE %.2f | VRT %.2f\nTrendSign: %d slope %.3f | EMA %.2f | WMA %.2f\nCenter %.2f ATR %.2f Grid %.2f\nBands Inner %.2f/%.2f Mid %.2f/%.2f Outer %.2f/%.2f\nExposure Buys %d(%.2f) Sells %d(%.2f) Net %.2f\nBasket Profit %.2f USD",
         m_symbol,mode,router.ghe,router.vrt,trend.trendSign,trend.slope,trend.ema,trend.wma,
         zone.center,zone.atr,zone.gridStep,
         zone.innerDn,zone.innerUp,zone.midDn,zone.midUp,zone.outerDn,zone.outerUp,
         expo.buys,expo.lotBuys,expo.sells,expo.lotSells,expo.netLots(),
         basket);
      Comment(text);
     }
  };
