//+------------------------------------------------------------------+
//|                                              Orders.mqh          |
//|  Quản trị pending, trailing và basket                            |
//+------------------------------------------------------------------+
#pragma once
#include <Trade/Trade.mqh>
#include "Types.mqh"

class CPendingKey
  {
public:
   ENUM_ORDER_TYPE type;
   double          price;
   CPendingKey():type(ORDER_TYPE_BUY_LIMIT),price(0.0){}
   CPendingKey(ENUM_ORDER_TYPE t,double p):type(t),price(p){}
   bool operator==(const CPendingKey &other) const
     {
      return(type==other.type && MathAbs(price-other.price)<1e-5);
     }
  };

class CPendingMap
  {
private:
   CPendingKey   m_keys[256];
   ulong         m_tickets[256];
   int           m_count;
public:
                     CPendingMap():m_count(0)
     {
      ArrayInitialize(m_tickets,0);
     }

   void Clear()
     {
      m_count=0;
      ArrayInitialize(m_tickets,0);
     }

   void RebuildFromTerminal(const string symbol,const int magic)
     {
      Clear();
      for(int i=OrdersTotal()-1;i>=0 && m_count<ArraySize(m_keys);--i)
        {
         if(!OrderSelect(i,SELECT_BY_POS)) continue;
         if(OrderGetString(ORDER_SYMBOL)!=symbol) continue;
         if((int)OrderGetInteger(ORDER_MAGIC)!=magic) continue;
         ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         double price=OrderGetDouble(ORDER_PRICE_OPEN);
         m_keys[m_count]=CPendingKey(type,price);
         m_tickets[m_count]=OrderGetTicket();
         m_count++;
        }
     }

   bool Exists(ENUM_ORDER_TYPE type,double price) const
     {
      for(int i=0;i<m_count;i++)
         if(m_keys[i].type==type && MathAbs(m_keys[i].price-price)<1e-5)
            return(true);
      return(false);
     }
  };

class COrderPlanner
  {
private:
   string         m_symbol;
   int            m_magic;
   double         m_tpFactor;
   double         m_deviation;
   bool           m_allowBuy;
   bool           m_allowSell;
   CPendingMap    m_map;
   CTrade         m_trade;

   double NormalizePrice(double p)
     {
      int digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      return(NormalizeDouble(p,digits));
     }

   bool SendLimit(bool isBuy,double price,double lot,double tpOffset)
     {
      if(lot<=0.0) return(false);
      price=NormalizePrice(price);
      double tp=isBuy?price+tpOffset:price-tpOffset;
      tp=NormalizePrice(tp);
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints((int)m_deviation);
      if(isBuy && m_allowBuy)
        return(m_trade.BuyLimit(lot,price,m_symbol,0.0,tp,ORDER_TIME_GTC,0,"SZ-Limit"));
      if(!isBuy && m_allowSell)
        return(m_trade.SellLimit(lot,price,m_symbol,0.0,tp,ORDER_TIME_GTC,0,"SZ-Limit"));
      return(false);
     }

   bool SendStop(bool isBuy,double price,double lot,double tpOffset)
     {
      if(lot<=0.0) return(false);
      price=NormalizePrice(price);
      double tp=isBuy?price+tpOffset:price-tpOffset;
      tp=NormalizePrice(tp);
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints((int)m_deviation);
      if(isBuy && m_allowBuy)
        return(m_trade.BuyStop(lot,price,m_symbol,0.0,tp,ORDER_TIME_GTC,0,"Trend-Stop"));
      if(!isBuy && m_allowSell)
        return(m_trade.SellStop(lot,price,m_symbol,0.0,tp,ORDER_TIME_GTC,0,"Trend-Stop"));
      return(false);
     }

public:
                     COrderPlanner():m_symbol(_Symbol),m_magic(0),m_tpFactor(10*SymbolInfoDouble(_Symbol,SYMBOL_POINT)),
                     m_deviation(30),m_allowBuy(true),m_allowSell(true)
     {
      m_trade.SetAsyncMode(true);
     }

   void Configure(const string symbol,int magic,double tpFactor,double deviation,bool allowBuy,bool allowSell)
     {
      m_symbol=symbol;
      m_magic=magic;
      m_tpFactor=tpFactor;
      m_deviation=deviation;
      m_allowBuy=allowBuy;
      m_allowSell=allowSell;
     }

   void RefreshMap()
     {
      m_map.RebuildFromTerminal(m_symbol,m_magic);
     }

   void PlanMeanReversion(const ZoneBands &zone,int buyCount,int sellCount,double lotBuy,double lotSell)
     {
      RefreshMap();
      double tpOffset=zone.atr*m_tpFactor;
      if(tpOffset<=0.0) return;
      if(lotBuy<=0.0 && lotSell<=0.0) return;
      for(int i=1;i<=buyCount;i++)
        {
         double price=NormalizePrice(zone.center - zone.gridStep*i);
         if(price<zone.outerDn) break;
         if(lotBuy<=0.0) continue;
         if(!m_map.Exists(ORDER_TYPE_BUY_LIMIT,price))
            SendLimit(true,price,lotBuy,tpOffset);
        }
      for(int i=1;i<=sellCount;i++)
        {
         double price=NormalizePrice(zone.center + zone.gridStep*i);
         if(price>zone.outerUp) break;
         if(lotSell<=0.0) continue;
         if(!m_map.Exists(ORDER_TYPE_SELL_LIMIT,price))
            SendLimit(false,price,lotSell,tpOffset);
        }
     }

   void PlanTrendFollowing(const ZoneBands &zone,bool up,double lot)
     {
      RefreshMap();
      double anchor=NormalizePrice(up?zone.outerUp:zone.outerDn);
      ENUM_ORDER_TYPE type=up?ORDER_TYPE_BUY_STOP:ORDER_TYPE_SELL_STOP;
      if(m_map.Exists(type,anchor)) return;
      double tpOffset=zone.atr*m_tpFactor;
      if(tpOffset<=0.0 || lot<=0.0) return;
      SendStop(up,anchor,lot,tpOffset);
     }

   void CancelOpposite(bool up)
     {
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         if(!OrderSelect(i,SELECT_BY_POS)) continue;
         if(OrderGetString(ORDER_SYMBOL)!=m_symbol) continue;
         if((int)OrderGetInteger(ORDER_MAGIC)!=m_magic) continue;
         ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(up && (type==ORDER_TYPE_SELL_LIMIT || type==ORDER_TYPE_SELL_STOP))
            m_trade.OrderDelete(OrderGetTicket());
         if(!up && (type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP))
            m_trade.OrderDelete(OrderGetTicket());
        }
     }

   void DynamicTrailing(double atrMultiplier)
     {
      double atr=iATR(m_symbol,PERIOD_M3,14,0);
      if(atr<=0.0) return;
      double trail=atrMultiplier*atr;
      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      if(point<=0.0) point=Point();
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((int)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         long type=PositionGetInteger(POSITION_TYPE);
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
         double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
         if(type==POSITION_TYPE_BUY)
           {
            double newSL=MathMax(open,ask-trail);
            if(sl<newSL-point)
               m_trade.PositionModify(ticket,newSL,PositionGetDouble(POSITION_TP));
           }
         else if(type==POSITION_TYPE_SELL)
           {
            double newSL=MathMin(open,bid+trail);
            if(sl>newSL+point || sl==0)
               m_trade.PositionModify(ticket,newSL,PositionGetDouble(POSITION_TP));
           }
        }
     }
  };
