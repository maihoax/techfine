//+------------------------------------------------------------------+
//|                                                 Risk.mqh         |
//|  Quản trị lot, hedge và basket                                  |
//+------------------------------------------------------------------+
#pragma once
#include <Trade/Trade.mqh>
#include "Types.mqh"

class CRiskManager
  {
private:
   string   m_symbol;
   int      m_magic;
   double   m_baseLot;
   double   m_multL1;
   double   m_multL2;
   double   m_multL3;
   int      m_capL1;
   int      m_capL2;
   int      m_capL3;
   double   m_lotCapL1;
   double   m_lotCapL2;
   double   m_lotCapL3;
   double   m_maxLots;
   double   m_mlMin;
   double   m_hedgeGamma;
   double   m_pauseMargin;
   CTrade   m_trade;

   double NormalizeLot(double lot)
     {
      double step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      if(step<=0.0) return(MathMax(0.0,lot));
      int precision=(int)MathMax(0.0,MathRound(MathLog(1.0/step)/MathLog(10.0)));
      double quant=MathFloor(MathMax(0.0,lot)/step+1e-8)*step;
      return(NormalizeDouble(quant,precision));
     }

public:
                     CRiskManager():m_symbol(_Symbol),m_magic(0),m_baseLot(0.10),m_multL1(1.2),m_multL2(2.5),m_multL3(6.0),
                     m_capL1(12),m_capL2(60),m_capL3(120),m_lotCapL1(0.6),m_lotCapL2(2.4),m_lotCapL3(6.0),
                     m_maxLots(10.0),m_mlMin(300.0),m_hedgeGamma(0.3),m_pauseMargin(250.0)
     {
      m_trade.SetAsyncMode(true);
     }

   void Configure(const string symbol,int magic,double baseLot,double mult1,double mult2,double mult3,
                  int cap1,int cap2,int cap3,double lotCap1,double lotCap2,double lotCap3,
                  double maxLots,double mlMin,double hedgeGamma,double pauseMargin)
     {
      m_symbol=symbol;
      m_magic=magic;
      m_baseLot=baseLot;
      m_multL1=mult1;
      m_multL2=mult2;
      m_multL3=mult3;
      m_capL1=cap1;
      m_capL2=cap2;
      m_capL3=cap3;
      m_lotCapL1=lotCap1;
      m_lotCapL2=lotCap2;
      m_lotCapL3=lotCap3;
      m_maxLots=maxLots;
      m_mlMin=mlMin;
      m_hedgeGamma=hedgeGamma;
      m_pauseMargin=pauseMargin;
     }

   ExposureState Exposure() const
     {
      ExposureState st;
      st.buys=0;
      st.sells=0;
      st.lotBuys=0.0;
      st.lotSells=0.0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         double lot=PositionGetDouble(POSITION_VOLUME);
         if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
           {
            st.buys++;
            st.lotBuys+=lot;
           }
         else
           {
            st.sells++;
            st.lotSells+=lot;
           }
        }
      return(st);
     }

   bool MarginOk() const
     {
      double ml=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml<=0.0) return(false);
      return(ml>=m_mlMin);
     }

   double NextLot(bool isBuy,const ExposureState &st)
     {
      int count=isBuy?st.buys:st.sells;
      double lotBase=m_baseLot;
      double multiplier=m_multL1;
      double lotCap=m_lotCapL1;
      int    cap=m_capL1;
      double total=st.lotBuys+st.lotSells;
      if(total>=m_lotCapL3 || (st.buys+st.sells)>=m_capL3)
        {
         multiplier=m_multL3;
         lotCap=m_lotCapL3;
         cap=m_capL3;
        }
      else if(total>=m_lotCapL2 || (st.buys+st.sells)>=m_capL2)
        {
         multiplier=m_multL2;
         lotCap=m_lotCapL2;
         cap=m_capL2;
        }
      if(count>=cap) return(0.0);
      double lot=lotBase*MathPow(multiplier,count);
      lot=MathMin(lot,lotCap);
      if(total+lot>m_maxLots) lot=MathMax(0.0,m_maxLots-total);
      return(NormalizeLot(lot));
     }

   void HedgeIfNeeded(const ZoneBands &zone,const RouterState &router,const ExposureState &st)
     {
      if(router.mode==ROUTER_MEAN_REVERSION || router.mode==ROUTER_NEUTRAL)
         return;
      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      double net=st.netLots();
      double hedgeLot=0.0;
      if(router.mode==ROUTER_TREND_UP && bid>zone.outerUp && net<0)
         hedgeLot=MathAbs(net)*m_hedgeGamma;
      if(router.mode==ROUTER_TREND_DOWN && ask<zone.outerDn && net>0)
         hedgeLot=MathAbs(net)*m_hedgeGamma;
      hedgeLot=NormalizeLot(hedgeLot);
      if(hedgeLot<=0.0) return;
      if(router.mode==ROUTER_TREND_UP)
         m_trade.Buy(hedgeLot,m_symbol,ask,0.0,ask+zone.atr,"HedgeUp");
      else
         m_trade.Sell(hedgeLot,m_symbol,bid,0.0,bid-zone.atr,"HedgeDown");
     }

   double BasketProfit() const
     {
      double profit=0.0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         profit+=PositionGetDouble(POSITION_PROFIT);
        }
      return(profit);
     }

   void CloseBasket()
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         m_trade.PositionClose(ticket,10);
        }
     }

   bool ShouldPause() const
     {
      double ml=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      return(ml<m_pauseMargin);
     }
  };
