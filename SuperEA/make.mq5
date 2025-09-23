//+------------------------------------------------------------------+
//|                                                    make.mq5      |
//|  Simple batch-trend EA for XAUUSDc (Exness cent) with Telegram   |
//|  control, batch evaluation, and adaptive risk management         |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

//--- trading inputs
input string         InpSymbol                = "XAUUSDc";
input ENUM_TIMEFRAMES InpTrendTF             = PERIOD_M5;
input int            InpFastMAPeriod          = 20;
input int            InpSlowMAPeriod          = 50;
input double         InpTrendSlopeMinPoints   = 10.0;   // min fast MA delta (points) to confirm trend
input int            InpEntryIntervalSeconds  = 17;
input int            InpTradesPerBatch        = 7;
input double         InpBatchProfitTargetPct  = 0.10;   // % of balance when batch started
input bool           InpAutoStart             = true;
input int            InpMagicNumber           = 9021001;
input double         InpMaxSpreadPoints       = 250.0;
input double         InpMinMarginLevel        = 320.0;
input double         InpMaxLot                = 1.00;
input double         InpMinLot                = 0.01;
input int            InpMaxDeviationPoints    = 80;

//--- risk parameters
input bool           InpUseFixedLot           = false;
input double         InpFixedLot              = 0.05;
input double         InpRiskPerTradePercent   = 1.0;    // risk of balance per trade when fixed lot disabled
input ENUM_TIMEFRAMES InpATRTimeframe        = PERIOD_M5;
input int            InpATRPeriod             = 14;
input double         InpStopATRMultiplier     = 1.5;
input int            InpMinStopPoints         = 400;    // fallback minimum stop in points
input double         InpTPMultiplier          = 2.0;    // TP distance vs stop
input double         InpATRVolatilityLimit    = 5.0;    // pause new batch if ATR above (price units); <=0 disables

//--- Telegram
input string         InpTelegramToken         = "";
input string         InpTelegramChatId        = "";
input int            InpTelegramPollSeconds   = 10;

//--- helper globals
CTrade               g_trade;
string               g_symbol;
int                  g_fastHandle = INVALID_HANDLE;
int                  g_slowHandle = INVALID_HANDLE;
int                  g_atrHandle  = INVALID_HANDLE;

struct BatchState
  {
   bool      active;
   int       id;
   int       tradesOpened;
   datetime  startTime;
   datetime  lastEntryTime;
   double    startBalance;
   double    targetProfitMoney;
   string    tag;
  };

BatchState          g_batch;
int                 g_nextBatchId=1;
bool                g_autoEnabled=false;
bool                g_manualPause=false;
bool                g_marginPause=false;
bool                g_volatilityPause=false;

double              g_equityPeak=0.0;
double              g_maxDrawdown=0.0;
int                 g_batchesCompleted=0;
int                 g_batchesWon=0;
double              g_totalBatchProfit=0.0;
double              g_lastBatchProfit=0.0;

//--- Telegram client -------------------------------------------------
class CTelegramClient
  {
private:
   string   m_token;
   string   m_chatId;
   int      m_pollSeconds;
   long     m_lastUpdateId;
   datetime m_lastPoll;
   string   m_pending[32];
   int      m_pendingCount;
   int      m_pendingIndex;

   string UrlEncode(const string &text)
     {
      string result="";
      int len=StringLen(text);
      for(int i=0;i<len;i++)
        {
         int ch=StringGetCharacter(text,i);
         if((ch>='a' && ch<='z') || (ch>='A' && ch<='Z') || (ch>='0' && ch<='9'))
            result+=CharToString((uchar)ch);
         else if(ch==' ')
            result+="+";
         else if(ch=='_')
            result+="_";
         else
            result+=StringFormat("%%%02X",ch & 0xFF);
        }
      return(result);
     }

   void QueueCommand(const string &cmd)
     {
      if(m_pendingCount>=ArraySize(m_pending))
         return;
      m_pending[m_pendingCount++]=cmd;
     }

   void ParseUpdates(const string &body)
     {
      int pos=0;
      while(true)
        {
         int upd=StringFind(body,"\"update_id\":",pos);
         if(upd==-1) break;
         int idStart=upd+13;
         int idEnd=idStart;
         while(idEnd<StringLen(body) && StringGetCharacter(body,idEnd)>='0' && StringGetCharacter(body,idEnd)<='9')
            idEnd++;
         m_lastUpdateId=StringToInteger(StringSubstr(body,idStart,idEnd-idStart));
         int textIdx=StringFind(body,"\"text\":\"",idEnd);
         if(textIdx==-1)
           {
            pos=idEnd;
            continue;
           }
         int start=textIdx+8;
         int end=start;
         while(end<StringLen(body))
           {
            int ch=StringGetCharacter(body,end);
            if(ch=='\\')
              {
               end+=2;
               continue;
            }
            if(ch=='"')
               break;
            end++;
           }
         string raw=StringSubstr(body,start,end-start);
         raw=StringReplace(raw,"\\/","/");
         raw=StringReplace(raw,"\\n","\n");
         raw=StringReplace(raw,"\\\"","\"");
         QueueCommand(raw);
         pos=end;
        }
     }

public:
                     CTelegramClient():m_pollSeconds(10),m_lastUpdateId(0),m_lastPoll(0),m_pendingCount(0),m_pendingIndex(0)
     {
     }

   void Configure(const string token,const string chatId,const int pollSeconds)
     {
      m_token=token;
      m_chatId=chatId;
      m_pollSeconds=MathMax(2,pollSeconds);
     }

   void Reset()
     {
      m_lastUpdateId=0;
      m_lastPoll=0;
      m_pendingCount=0;
      m_pendingIndex=0;
     }

   bool Enabled() const
     {
      return(StringLen(m_token)>0 && StringLen(m_chatId)>0);
     }

   bool FetchCommand(string &cmd)
     {
      if(m_pendingIndex<m_pendingCount)
        {
         cmd=m_pending[m_pendingIndex++];
         return(true);
        }

      if(!Enabled())
         return(false);

      datetime now=TimeCurrent();
      if(now-m_lastPoll < m_pollSeconds)
         return(false);
      m_lastPoll=now;
      m_pendingCount=0;
      m_pendingIndex=0;

      string url=StringFormat("https://api.telegram.org/bot%s/getUpdates?offset=%d",m_token,(int)(m_lastUpdateId+1));
      char result[];
      string headers="";
      ResetLastError();
      int code=WebRequest("GET",url,"",5000,result,headers);
      if(code<=0)
        {
         PrintFormat("Telegram WebRequest failed. err=%d",GetLastError());
         return(false);
        }
      string body=CharArrayToString(result,0,code);
      ParseUpdates(body);
      if(m_pendingIndex<m_pendingCount)
        {
         cmd=m_pending[m_pendingIndex++];
         return(true);
        }
      return(false);
     }

   void SendMessage(const string &text)
     {
      if(!Enabled()) return;
      string payload=StringFormat("chat_id=%s&text=%s",m_chatId,UrlEncode(text));
      uchar data[];
      StringToCharArray(payload,data,0,StringLen(payload));
      string headers;
      string url=StringFormat("https://api.telegram.org/bot%s/sendMessage",m_token);
      ResetLastError();
      int res=WebRequest("POST",url,"application/x-www-form-urlencoded",5000,data,headers);
      if(res<=0)
         PrintFormat("Telegram sendMessage failed. err=%d",GetLastError());
     }
  };

CTelegramClient     g_telegram;

//--- forward declarations -------------------------------------------
void ResetBatch();
void ActivateBatch(int id,double startBalance,double target,const string &tag);
int  EvaluateTrend();
double CurrentATR();
double ComputeStopDistance();
double NormalizeLot(double lot);
double ComputeOrderLot(double stopDistance);
void TryOpenTrade();
void UpdateBatchStatus();
int  BatchOpenPositionsCount();
double BatchOpenProfit();
double BatchClosedProfit();
void CloseBatchPositions();
void FinishBatch(double totalProfit);
void ProcessTelegram();
void ProcessCommand(const string &cmd);
void SendStatusMessage();
void ManualCloseBatch();
void UpdatePauses();
void UpdatePanel();
string Trim(const string &text);

//--- utility ---------------------------------------------------------
void ResetBatch()
  {
   g_batch.active=false;
   g_batch.id=0;
   g_batch.tradesOpened=0;
   g_batch.startTime=0;
   g_batch.lastEntryTime=0;
   g_batch.startBalance=0.0;
   g_batch.targetProfitMoney=0.0;
   g_batch.tag="";
  }

void ActivateBatch(int id,double startBalance,double target,const string &tag)
  {
   g_batch.active=true;
   g_batch.id=id;
   g_batch.tradesOpened=0;
   g_batch.startTime=TimeCurrent();
   g_batch.lastEntryTime=0;
   g_batch.startBalance=startBalance;
   g_batch.targetProfitMoney=target;
   g_batch.tag=tag;
   g_nextBatchId=id+1;
   PrintFormat("[Batch %d] Started. Target profit %.2f (%.3f%%)",g_batch.id,g_batch.targetProfitMoney,InpBatchProfitTargetPct);
   if(g_telegram.Enabled())
      g_telegram.SendMessage(StringFormat("Batch %d started. Target %.2f USD (%.3f%%)",g_batch.id,g_batch.targetProfitMoney,InpBatchProfitTargetPct));
  }

int OnInit()
  {
   g_symbol=InpSymbol;
   if(!SymbolSelect(g_symbol,true))
     {
      PrintFormat("Failed to select symbol %s",g_symbol);
      return(INIT_FAILED);
     }
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpMaxDeviationPoints);

   g_fastHandle=iMA(g_symbol,InpTrendTF,InpFastMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_slowHandle=iMA(g_symbol,InpTrendTF,InpSlowMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_atrHandle=iATR(g_symbol,InpATRTimeframe,InpATRPeriod);
   if(g_fastHandle==INVALID_HANDLE || g_slowHandle==INVALID_HANDLE || g_atrHandle==INVALID_HANDLE)
     {
      Print("Indicator handle creation failed");
      return(INIT_FAILED);
     }

   g_autoEnabled=InpAutoStart;
   g_equityPeak=AccountInfoDouble(ACCOUNT_EQUITY);
   g_maxDrawdown=0.0;
   ResetBatch();

   g_telegram.Configure(InpTelegramToken,InpTelegramChatId,InpTelegramPollSeconds);
   g_telegram.Reset();
   if(g_telegram.Enabled())
      Print("Telegram control active. Add https://api.telegram.org to WebRequest allowed URLs.");

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_fastHandle!=INVALID_HANDLE) IndicatorRelease(g_fastHandle);
   if(g_slowHandle!=INVALID_HANDLE) IndicatorRelease(g_slowHandle);
   if(g_atrHandle!=INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   Comment("");
  }

int EvaluateTrend()
  {
   double fast[3],slow[3];
   if(CopyBuffer(g_fastHandle,0,0,3,fast)<3) return(0);
   if(CopyBuffer(g_slowHandle,0,0,3,slow)<3) return(0);
   double diffCurrent=(fast[0]-slow[0])/_Point;
   double diffPrev=(fast[1]-slow[1])/_Point;
   if(diffCurrent>InpTrendSlopeMinPoints && diffPrev>0)
      return(1);
   if(diffCurrent<-InpTrendSlopeMinPoints && diffPrev<0)
      return(-1);
   return(0);
  }

double CurrentATR()
  {
   double atr[1];
   if(CopyBuffer(g_atrHandle,0,0,1,atr)<1) return(0.0);
   return(atr[0]);
  }

double ComputeStopDistance()
  {
   double atr=CurrentATR();
   double stop=atr*InpStopATRMultiplier;
   double minStop=InpMinStopPoints*_Point;
   if(stop<=0.0) stop=minStop;
   else stop=MathMax(stop,minStop);
   return(stop);
  }

double NormalizeLot(double lot)
  {
   double minLot=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=0.01;
   lot=MathMax(lot,minLot);
   lot=MathMin(lot,MathMin(maxLot,InpMaxLot));
   int precision=(int)MathRound(MathAbs(MathLog10(step)));
   double quant=MathFloor(lot/step+0.5)*step;
   return(NormalizeDouble(quant,precision+1));
  }

double ComputeOrderLot(double stopDistance)
  {
   if(InpUseFixedLot)
      return(NormalizeLot(InpFixedLot));
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount=balance*(InpRiskPerTradePercent/100.0);
   double tickValue=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_SIZE);
   if(riskAmount<=0.0 || tickValue<=0.0 || tickSize<=0.0 || stopDistance<=0.0)
      return(NormalizeLot(InpMinLot));
   double stopTicks=stopDistance/tickSize;
   if(stopTicks<=0.0) return(0.0);
   double lot=riskAmount/(stopTicks*tickValue);
   lot=MathMax(lot,InpMinLot);
   return(NormalizeLot(lot));
  }

void TryOpenTrade()
  {
   if(!g_autoEnabled || g_manualPause) return;
   if(g_marginPause) return;

   int trend=EvaluateTrend();
   if(trend==0) return;

   double ask=SymbolInfoDouble(g_symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(g_symbol,SYMBOL_BID);
   if(ask<=0.0 || bid<=0.0) return;
   double spread=(ask-bid)/_Point;
   if(spread>InpMaxSpreadPoints) return;

   bool newBatch=!g_batch.active;
   if(newBatch && g_volatilityPause) return;

   int batchId = g_batch.active ? g_batch.id : g_nextBatchId;
   string tag = g_batch.active ? g_batch.tag : StringFormat("BATCH#%04d",batchId);
   double startBalance = g_batch.active ? g_batch.startBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   double targetMoney  = g_batch.active ? g_batch.targetProfitMoney : startBalance*(InpBatchProfitTargetPct/100.0);

   if(g_batch.active && g_batch.tradesOpened>=InpTradesPerBatch) return;
   if(g_batch.active && TimeCurrent()-g_batch.lastEntryTime < InpEntryIntervalSeconds) return;
   if(!g_batch.active && g_batch.lastEntryTime!=0 && TimeCurrent()-g_batch.lastEntryTime < InpEntryIntervalSeconds) return;

   double stopDistance=ComputeStopDistance();
   if(stopDistance<=0.0) return;

   double lot=ComputeOrderLot(stopDistance);
   if(lot<=0.0) return;

   double tpDistance=stopDistance*InpTPMultiplier;
   double sl=0.0,tp=0.0;
   bool ok=false;
   string comment=StringFormat("%s-%s",tag,(trend>0?"BUY":"SELL"));
   if(trend>0)
     {
      sl=ask-stopDistance;
      tp=ask+tpDistance;
      ok=g_trade.Buy(lot,g_symbol,0.0,sl,tp,comment);
     }
   else
     {
      sl=bid+stopDistance;
      tp=bid-tpDistance;
      ok=g_trade.Sell(lot,g_symbol,0.0,sl,tp,comment);
     }

   if(ok)
     {
      if(newBatch)
        ActivateBatch(batchId,startBalance,targetMoney,tag);
      g_batch.tradesOpened++;
      g_batch.lastEntryTime=TimeCurrent();
      PrintFormat("[Batch %d] %s %.2f lots opened. SL %.2f TP %.2f",batchId,(trend>0?"BUY":"SELL"),lot,sl,tp);
     }
   else if(newBatch)
     {
      ResetBatch();
      PrintFormat("Failed to open first trade for batch %d. Retcode %d",batchId,g_trade.ResultRetcode());
     }
  }

int BatchOpenPositionsCount()
  {
   if(!g_batch.active) return(0);
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      string comment=PositionGetString(POSITION_COMMENT);
      if(StringFind(comment,g_batch.tag)==-1) continue;
      count++;
     }
   return(count);
  }

double BatchOpenProfit()
  {
   if(!g_batch.active) return(0.0);
   double profit=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      string comment=PositionGetString(POSITION_COMMENT);
      if(StringFind(comment,g_batch.tag)==-1) continue;
      profit+=PositionGetDouble(POSITION_PROFIT);
     }
   return(profit);
  }

double BatchClosedProfit()
  {
   if(!g_batch.active) return(0.0);
   if(g_batch.startTime==0) return(0.0);
   if(!HistorySelect(g_batch.startTime,TimeCurrent())) return(0.0);
   double profit=0.0;
   int deals=HistoryDealsTotal();
   for(int i=deals-1;i>=0;i--)
     {
      ulong dealTicket=HistoryDealGetTicket(i);
      if(HistoryDealGetString(dealTicket,DEAL_SYMBOL)!=g_symbol) continue;
      string comment=HistoryDealGetString(dealTicket,DEAL_COMMENT);
      if(StringFind(comment,g_batch.tag)==-1) continue;
      long entry=HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT) continue;
      profit+=HistoryDealGetDouble(dealTicket,DEAL_PROFIT);
     }
   return(profit);
  }

void CloseBatchPositions()
  {
   if(!g_batch.active) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=g_symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      string comment=PositionGetString(POSITION_COMMENT);
      if(StringFind(comment,g_batch.tag)==-1) continue;
      if(!g_trade.PositionClose(ticket,0.0,InpMaxDeviationPoints))
         PrintFormat("Failed to close position %I64u. Retcode %d",ticket,g_trade.ResultRetcode());
     }
  }

void FinishBatch(double totalProfit)
  {
   if(!g_batch.active) return;
   g_batchesCompleted++;
   if(totalProfit>0.0) g_batchesWon++;
   g_totalBatchProfit+=totalProfit;
   g_lastBatchProfit=totalProfit;
   PrintFormat("[Batch %d] completed. Profit %.2f",g_batch.id,totalProfit);
   if(g_telegram.Enabled())
     {
      double winRate=g_batchesCompleted>0 ? (100.0*g_batchesWon/g_batchesCompleted) : 0.0;
      g_telegram.SendMessage(StringFormat("Batch %d completed. Profit %.2f USD. WinRate %.2f%%",g_batch.id,totalProfit,winRate));
     }
   ResetBatch();
  }

void UpdateBatchStatus()
  {
   if(!g_batch.active) return;
   double closed=BatchClosedProfit();
   double open=BatchOpenProfit();
   double total=open+closed;
   if(total>=g_batch.targetProfitMoney && BatchOpenPositionsCount()>0)
     {
      CloseBatchPositions();
      closed=BatchClosedProfit();
      if(BatchOpenPositionsCount()==0)
         FinishBatch(closed);
      return;
     }
   if(BatchOpenPositionsCount()==0 && g_batch.tradesOpened>0)
     {
      FinishBatch(closed);
     }
  }

string Trim(const string &text)
  {
   string tmp=text;
   StringTrimLeft(tmp);
   StringTrimRight(tmp);
   return(tmp);
  }

void ProcessCommand(const string &raw)
  {
   string cmd=Trim(raw);
   cmd=StringToLower(cmd);
   if(cmd=="/startea" || cmd=="/start")
     {
      g_autoEnabled=true;
      g_manualPause=false;
      if(g_telegram.Enabled()) g_telegram.SendMessage("EA resumed.");
     }
   else if(cmd=="/stopea" || cmd=="/stop")
     {
      g_autoEnabled=false;
      g_manualPause=true;
      if(g_telegram.Enabled()) g_telegram.SendMessage("EA stopped. No new trades.");
     }
   else if(cmd=="/pauseea" || cmd=="/pause")
     {
      g_manualPause=true;
      if(g_telegram.Enabled()) g_telegram.SendMessage("EA paused.");
     }
   else if(cmd=="/resumeea" || cmd=="/resume")
     {
      g_manualPause=false;
      g_autoEnabled=true;
      if(g_telegram.Enabled()) g_telegram.SendMessage("EA resumed.");
     }
   else if(cmd=="/statusaccount" || cmd=="/status")
     {
      SendStatusMessage();
     }
   else if(cmd=="/manualclosebatch" || cmd=="/closebatch")
     {
      ManualCloseBatch();
     }
   else
     {
      if(g_telegram.Enabled()) g_telegram.SendMessage("Unknown command.");
     }
  }

void ProcessTelegram()
  {
   string cmd;
   while(g_telegram.FetchCommand(cmd))
      ProcessCommand(cmd);
  }

void SendStatusMessage()
  {
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double marginLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double open=BatchOpenProfit();
   double closed=BatchClosedProfit();
   string status=StringFormat("Balance %.2f\nEquity %.2f\nMarginLvl %.1f%%\nAuto:%s ManualPause:%s\nActiveBatch:%s trades %d/%d open %.2f closed %.2f\nTotal batches %d win %% %.2f last %.2f total %.2f",
      balance,equity,marginLevel,
      g_autoEnabled?"ON":"OFF",
      g_manualPause?"YES":"NO",
      g_batch.active?"YES":"NO",
      g_batch.tradesOpened,InpTradesPerBatch,
      open,closed,
      g_batchesCompleted,
      g_batchesCompleted>0?100.0*g_batchesWon/g_batchesCompleted:0.0,
      g_lastBatchProfit,g_totalBatchProfit);
   if(g_telegram.Enabled())
      g_telegram.SendMessage(status);
  }

void ManualCloseBatch()
  {
   if(!g_batch.active)
     {
      if(g_telegram.Enabled()) g_telegram.SendMessage("No active batch to close.");
      return;
     }
   CloseBatchPositions();
   if(g_telegram.Enabled()) g_telegram.SendMessage("Closing batch positions...");
  }

void UpdatePauses()
  {
   double ml=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(ml>0.0 && ml<InpMinMarginLevel) g_marginPause=true; else g_marginPause=false;
   double atr=CurrentATR();
   if(InpATRVolatilityLimit>0.0 && atr>InpATRVolatilityLimit) g_volatilityPause=true; else g_volatilityPause=false;
  }

void UpdatePanel()
  {
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double marginLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double open=BatchOpenProfit();
   double closed=BatchClosedProfit();
   double atr=CurrentATR();
   double winRate=g_batchesCompleted>0 ? (100.0*g_batchesWon/g_batchesCompleted) : 0.0;
   string panel=StringFormat(
      "Auto:%s | Manual:%s | MarginPause:%s | VolPause:%s\n"
      "Balance %.2f | Equity %.2f | ML %.1f%%\n"
      "Batch:%s ID:%d Trades %d/%d Target %.2f Open %.2f Closed %.2f\n"
      "Batches %d Win%% %.2f Last %.2f Total %.2f | ATR %.2f | MaxDD %.2f%%",
      g_autoEnabled?"ON":"OFF",
      g_manualPause?"YES":"NO",
      g_marginPause?"YES":"NO",
      g_volatilityPause?"YES":"NO",
      balance,equity,marginLevel,
      g_batch.active?"YES":"NO",
      g_batch.id,
      g_batch.tradesOpened,InpTradesPerBatch,
      g_batch.targetProfitMoney,
      open,closed,
      g_batchesCompleted,winRate,g_lastBatchProfit,g_totalBatchProfit,atr,g_maxDrawdown);
   Comment(panel);
  }

void OnTick()
  {
   if(_Symbol!=g_symbol) return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity>g_equityPeak) g_equityPeak=equity;
   if(g_equityPeak>0.0)
     {
      double dd=(g_equityPeak-equity)/g_equityPeak*100.0;
      if(dd>g_maxDrawdown) g_maxDrawdown=dd;
     }

   ProcessTelegram();
   UpdatePauses();
   UpdateBatchStatus();
   TryOpenTrade();
   UpdateBatchStatus();
   UpdatePanel();
  }
