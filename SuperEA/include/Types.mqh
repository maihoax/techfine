//+------------------------------------------------------------------+
//|                                              Types.mqh           |
//|  Định nghĩa chung cho SuperEA                                   |
//+------------------------------------------------------------------+
#pragma once

enum ENUM_ROUTER_MODE
  {
   ROUTER_TREND_UP = 1,
   ROUTER_TREND_DOWN = -1,
   ROUTER_MEAN_REVERSION = 2,
   ROUTER_NEUTRAL = 0
  };

struct PatternSignal
  {
   bool    hasRectangle;
   bool    hasTriple;
   bool    hasFlag;
   double  rectangleHigh;
   double  rectangleLow;
   double  patternStrength;
  };

struct TrendContext
  {
   int     trendSign;   // -1,0,1
   double  slope;
   double  ema;
   double  wma;
  };

struct ZoneBands
  {
   double  center;
   double  atr;
   double  innerUp;
   double  innerDn;
   double  midUp;
   double  midDn;
   double  outerUp;
   double  outerDn;
   double  gridStep;
   datetime lastBuild;
  };

struct ExposureState
  {
   int     buys;
   int     sells;
   double  lotBuys;
   double  lotSells;
   double  netLots() const {return lotBuys - lotSells;}
  };

struct RouterState
  {
   ENUM_ROUTER_MODE mode;
   double           ghe;
   double           vrt;
  };
