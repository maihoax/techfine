//+------------------------------------------------------------------+
//|                                                    make.mq5      |
//|  Simple batch-trend EA with Telegram control, batch evaluation,  |
//|  and adaptive risk management across Forex/Metals symbols        |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
#include "include/Types.mqh"
#include "include/Signals.mqh"

enum ENUM_MARKET_PROFILE
  {
   PROFILE_AUTO = 0,
   PROFILE_FOREX,
   PROFILE_METAL
  };

//--- trading inputs
input string         InpSymbol                = "XAUUSDc";
input ENUM_MARKET_PROFILE InpSymbolProfile    = PROFILE_AUTO;
input bool           InpAutoSymbolConfig      = true;
input ENUM_TIMEFRAMES InpTrendTF             = PERIOD_M5;
input ENUM_TIMEFRAMES InpSignalTimeframe     = PERIOD_M3;
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
int                  g_trendAtrHandle = INVALID_HANDLE;

CSignalSuite         g_signalSuite;
TrendContext         g_trendContext;
PatternSignal        g_patternSignal;

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

struct SymbolTraits
  {
   double   point;
   double   pipSize;
   double   pipPoints;
   double   pipValuePerLot;
   double   tickSize;
   double   tickValue;
   double   minLot;
   double   maxLot;
   double   lotStep;
   double   contractSize;
   double   avgSpreadPoints;
  };

struct ProfileLimits
  {
   double   maxSpreadPoints;
   double   minStopPoints;
   double   minStopDistance;
   double   trendSlopeMinPoints;
   double   atrVolatilityLimit;
  };

SymbolTraits        g_symbolTraits;
ProfileLimits       g_limits;
ENUM_MARKET_PROFILE g_resolvedProfile=PROFILE_AUTO;
string              g_profileName="auto";
double              g_lastKnownSpreadPoints=0.0;
double              g_recommendedMaxSpreadPoints=0.0;
double              g_recommendedMinStopPoints=0.0;
double              g_recommendedSlopePoints=0.0;
double              g_recommendedAtrLimit=0.0;

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
         StringReplace(raw,"\\/","/");
         StringReplace(raw,"\\n","\n");
         StringReplace(raw,"\\\"","\"");
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
void LoadSymbolTraits();
ENUM_MARKET_PROFILE ResolveProfile();
string ProfileToString(const ENUM_MARKET_PROFILE profile);
void ConfigureSymbolProfile();
double PipsToPoints(const double pips);
double PointsToPips(const double points);
double CurrentSpreadPoints();
double EstimateBatchTargetMoney(double balance);
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
void LoadSymbolTraits()
  {
   ZeroMemory(g_symbolTraits);
   g_symbolTraits.point=SymbolInfoDouble(g_symbol,SYMBOL_POINT);
   if(g_symbolTraits.point<=0.0)
      g_symbolTraits.point=_Point;
   g_symbolTraits.tickSize=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_SIZE);
   if(g_symbolTraits.tickSize<=0.0)
      g_symbolTraits.tickSize=g_symbolTraits.point;
   g_symbolTraits.tickValue=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_VALUE);
   if(g_symbolTraits.tickValue<=0.0)
      g_symbolTraits.tickValue=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_VALUE_PROFIT);
   g_symbolTraits.minLot=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MIN);
   g_symbolTraits.maxLot=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MAX);
   g_symbolTraits.lotStep=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_STEP);
   if(g_symbolTraits.lotStep<=0.0)
      g_symbolTraits.lotStep=0.01;
   g_symbolTraits.contractSize=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   long digits=SymbolInfoInteger(g_symbol,SYMBOL_DIGITS);
   g_symbolTraits.pipSize=g_symbolTraits.point;
   if(digits==3 || digits==5 || digits==1)
      g_symbolTraits.pipSize=g_symbolTraits.point*10.0;
   g_symbolTraits.pipPoints=(g_symbolTraits.point>0.0)?g_symbolTraits.pipSize/g_symbolTraits.point:1.0;
   double tickRatio=(g_symbolTraits.tickSize>0.0)?g_symbolTraits.pipSize/g_symbolTraits.tickSize:0.0;
   g_symbolTraits.pipValuePerLot=(tickRatio>0.0)?g_symbolTraits.tickValue*tickRatio:0.0;
   double avgSpread=(double)SymbolInfoInteger(g_symbol,SYMBOL_SPREAD);
   if(avgSpread<=0.0)
     {
      double ask=SymbolInfoDouble(g_symbol,SYMBOL_ASK);
      double bid=SymbolInfoDouble(g_symbol,SYMBOL_BID);
      if(ask>0.0 && bid>0.0 && g_symbolTraits.point>0.0)
         avgSpread=(ask-bid)/g_symbolTraits.point;
     }
   g_symbolTraits.avgSpreadPoints=avgSpread;
  }

ENUM_MARKET_PROFILE ResolveProfile()
  {
   if(InpSymbolProfile!=PROFILE_AUTO)
      return(InpSymbolProfile);
   string upper=StringToUpper(g_symbol);
   if(StringFind(upper,"XAU")!=-1 || StringFind(upper,"XAG")!=-1 || StringFind(upper,"XPT")!=-1 || StringFind(upper,"XPD")!=-1 ||
      StringFind(upper,"GOLD")!=-1)
      return(PROFILE_METAL);
   long sector=SymbolInfoInteger(g_symbol,SYMBOL_SECTOR);
   if(sector==SYMBOL_SECTOR_METALS)
      return(PROFILE_METAL);
   return(PROFILE_FOREX);
  }

string ProfileToString(const ENUM_MARKET_PROFILE profile)
  {
   switch(profile)
     {
      case PROFILE_FOREX: return("forex");
      case PROFILE_METAL: return("metal");
      default:            return("auto");
     }
  }

double PipsToPoints(const double pips)
  {
   return(pips*g_symbolTraits.pipPoints);
  }

double PointsToPips(const double points)
  {
   if(g_symbolTraits.pipPoints<=0.0)
      return(0.0);
   return(points/g_symbolTraits.pipPoints);
  }

double CurrentSpreadPoints()
  {
   double ask=SymbolInfoDouble(g_symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(g_symbol,SYMBOL_BID);
   if(ask<=0.0 || bid<=0.0 || g_symbolTraits.point<=0.0)
      return(0.0);
   return((ask-bid)/g_symbolTraits.point);
  }

double EstimateBatchTargetMoney(double balance)
  {
   return(balance*(InpBatchProfitTargetPct/100.0));
  }

void ConfigureSymbolProfile()
  {
   LoadSymbolTraits();
   g_resolvedProfile=ResolveProfile();
   g_profileName=ProfileToString(g_resolvedProfile);

   double spreadPoints=g_symbolTraits.avgSpreadPoints;
   if(spreadPoints<=0.0)
      spreadPoints=CurrentSpreadPoints();
   if(spreadPoints<=0.0)
      spreadPoints=g_symbolTraits.pipPoints*2.0;
   double spreadPips=PointsToPips(spreadPoints);

   double defaultMaxSpreadPips;
   double defaultMinStopPips;
   double defaultSlopePips;
   double defaultAtrLimit;

   if(g_resolvedProfile==PROFILE_METAL)
     {
      defaultMaxSpreadPips=MathMax(spreadPips*1.8,40.0);
      defaultMinStopPips=MathMax(spreadPips*6.0,120.0);
      defaultSlopePips=MathMax(spreadPips*2.5,20.0);
     }
   else
     {
      defaultMaxSpreadPips=MathMax(spreadPips*1.8,2.0);
      defaultMinStopPips=MathMax(spreadPips*6.0,12.0);
      defaultSlopePips=MathMax(spreadPips*2.5,3.0);
     }

   double baselineATR=CurrentATR();
   if(baselineATR<=0.0)
      baselineATR=g_symbolTraits.pipSize*(g_resolvedProfile==PROFILE_METAL?50.0:10.0);
   if(g_resolvedProfile==PROFILE_METAL)
      defaultAtrLimit=baselineATR*3.0;
   else
      defaultAtrLimit=baselineATR*2.5;

   g_recommendedMaxSpreadPoints=PipsToPoints(defaultMaxSpreadPips);
   g_recommendedMinStopPoints=PipsToPoints(defaultMinStopPips);
   g_recommendedSlopePoints=PipsToPoints(defaultSlopePips);
   g_recommendedAtrLimit=defaultAtrLimit;

   if(InpAutoSymbolConfig)
     {
      g_limits.maxSpreadPoints=g_recommendedMaxSpreadPoints;
      g_limits.minStopPoints=g_recommendedMinStopPoints;
      g_limits.trendSlopeMinPoints=g_recommendedSlopePoints;
      g_limits.atrVolatilityLimit=g_recommendedAtrLimit;
     }
   else
     {
      g_limits.maxSpreadPoints=(InpMaxSpreadPoints>0.0)?InpMaxSpreadPoints:g_recommendedMaxSpreadPoints;
      g_limits.minStopPoints=(InpMinStopPoints>0)?InpMinStopPoints:g_recommendedMinStopPoints;
      g_limits.trendSlopeMinPoints=(InpTrendSlopeMinPoints>0)?InpTrendSlopeMinPoints:g_recommendedSlopePoints;
      g_limits.atrVolatilityLimit=(InpATRVolatilityLimit>0.0)?InpATRVolatilityLimit:g_recommendedAtrLimit;
     }

   if(InpAutoSymbolConfig==false)
     {
      if(InpMaxSpreadPoints>0.0) g_limits.maxSpreadPoints=InpMaxSpreadPoints;
      if(InpMinStopPoints>0)     g_limits.minStopPoints=InpMinStopPoints;
      if(InpTrendSlopeMinPoints>0) g_limits.trendSlopeMinPoints=InpTrendSlopeMinPoints;
      if(InpATRVolatilityLimit>0.0) g_limits.atrVolatilityLimit=InpATRVolatilityLimit;
     }

   if(g_limits.maxSpreadPoints<0.0) g_limits.maxSpreadPoints=0.0;
   if(g_limits.minStopPoints<0.0) g_limits.minStopPoints=0.0;
   if(g_limits.trendSlopeMinPoints<=0.0)
      g_limits.trendSlopeMinPoints=MathMax(PipsToPoints(MathMax(spreadPips,1.0)),1.0);

   g_limits.minStopDistance=g_limits.minStopPoints*g_symbolTraits.point;
   g_lastKnownSpreadPoints=spreadPoints;
  }

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
   g_trendAtrHandle=iATR(g_symbol,InpTrendTF,InpATRPeriod);
   if(g_fastHandle==INVALID_HANDLE || g_slowHandle==INVALID_HANDLE || g_atrHandle==INVALID_HANDLE)
     {
      Print("Indicator handle creation failed");
      return(INIT_FAILED);
     }
   if(g_trendAtrHandle==INVALID_HANDLE)
      Print("Warning: failed to create trend ATR handle, slope filter will use fallback ATR.");

   g_signalSuite.Configure(g_symbol,InpTrendTF,InpSignalTimeframe);

   ConfigureSymbolProfile();
   PrintFormat("Symbol %s profile=%s pipSize=%.5f pipValue=%.2f maxSpread=%.1f pts stop>=%.1f pts ATRlimit=%.2f",
               g_symbol,g_profileName,g_symbolTraits.pipSize,g_symbolTraits.pipValuePerLot,
               g_limits.maxSpreadPoints,g_limits.minStopPoints,g_limits.atrVolatilityLimit);

   g_autoEnabled=InpAutoStart;
   g_equityPeak=AccountInfoDouble(ACCOUNT_EQUITY);
   g_maxDrawdown=0.0;
   ResetBatch();

   g_telegram.Configure(InpTelegramToken,InpTelegramChatId,InpTelegramPollSeconds);
   g_telegram.Reset();
   if(g_telegram.Enabled())
      Print("Telegram control active. Add https://api.telegram.org to WebRequest allowed URLs.");

   g_signalSuite.Update();
   g_trendContext=g_signalSuite.Trend();
   g_patternSignal=g_signalSuite.Pattern();

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_fastHandle!=INVALID_HANDLE) IndicatorRelease(g_fastHandle);
   if(g_slowHandle!=INVALID_HANDLE) IndicatorRelease(g_slowHandle);
   if(g_atrHandle!=INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_trendAtrHandle!=INVALID_HANDLE) IndicatorRelease(g_trendAtrHandle);
   Comment("");
  }

int EvaluateTrend()
  {
   int trend=g_trendContext.trendSign;
   double slopeNorm=MathAbs(g_trendContext.slope);
   double thresholdPoints=g_limits.trendSlopeMinPoints>0.0?g_limits.trendSlopeMinPoints:InpTrendSlopeMinPoints;
   double atrHTF=0.0;
   if(g_trendAtrHandle!=INVALID_HANDLE)
     {
      double buf[1];
      if(CopyBuffer(g_trendAtrHandle,0,0,1,buf)>=1)
         atrHTF=buf[0];
     }
   if(atrHTF<=0.0)
      atrHTF=CurrentATR();

   double slopeThresholdNorm=thresholdPoints;
   if(atrHTF>0.0 && g_symbolTraits.point>0.0)
      slopeThresholdNorm=(thresholdPoints*g_symbolTraits.point)/atrHTF;
   if(slopeThresholdNorm<=0.0)
      slopeThresholdNorm=0.05;

   if(trend!=0 && slopeNorm>=slopeThresholdNorm && slopeThresholdNorm>0.0)
      return(trend);

   double fast[3],slow[3];
   if(CopyBuffer(g_fastHandle,0,0,3,fast)<3) return(0);
   if(CopyBuffer(g_slowHandle,0,0,3,slow)<3) return(0);
   double point=(g_symbolTraits.point>0.0)?g_symbolTraits.point:_Point;
   double diffCurrent=(fast[0]-slow[0])/point;
   double diffPrev=(fast[1]-slow[1])/point;
   double threshold=thresholdPoints;
   if(threshold<=0.0)
      threshold=1.0;
   if(diffCurrent>threshold && diffPrev>0)
      return(1);
   if(diffCurrent<-threshold && diffPrev<0)
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
   double minStop=g_limits.minStopDistance;
   if(minStop<=0.0)
      minStop=InpMinStopPoints*_Point;
   if(stop<=0.0) stop=minStop;
   else stop=MathMax(stop,minStop);
   return(stop);
  }

double NormalizeLot(double lot)
  {
   double minLot=(g_symbolTraits.minLot>0.0)?g_symbolTraits.minLot:SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MIN);
   double maxLot=(g_symbolTraits.maxLot>0.0)?g_symbolTraits.maxLot:SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MAX);
   double step =(g_symbolTraits.lotStep>0.0)?g_symbolTraits.lotStep:SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=0.01;
   lot=MathMax(lot,minLot);
   lot=MathMin(lot,MathMin(maxLot,InpMaxLot));
   double precisionRaw=2.0;
   if(step>0.0)
      precisionRaw=MathRound(MathAbs(MathLog(step)/MathLog(10.0)));
   int precision=(int)precisionRaw;
   double quant=MathFloor(lot/step+0.5)*step;
   return(NormalizeDouble(quant,precision+1));
  }

double ComputeOrderLot(double stopDistance)
  {
   if(InpUseFixedLot)
      return(NormalizeLot(InpFixedLot));
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount=balance*(InpRiskPerTradePercent/100.0);
   double tickValue=(g_symbolTraits.tickValue>0.0)?g_symbolTraits.tickValue:SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=(g_symbolTraits.tickSize>0.0)?g_symbolTraits.tickSize:SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_SIZE);
   double minLot=MathMax(InpMinLot,(g_symbolTraits.minLot>0.0)?g_symbolTraits.minLot:SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_MIN));
   if(riskAmount<=0.0 || tickValue<=0.0 || tickSize<=0.0 || stopDistance<=0.0)
      return(NormalizeLot(minLot));
   double stopTicks=stopDistance/tickSize;
   if(stopTicks<=0.0) return(0.0);
   double lot=riskAmount/(stopTicks*tickValue);
   lot=MathMax(lot,minLot);
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
   double point=(g_symbolTraits.point>0.0)?g_symbolTraits.point:_Point;
   double spread=(ask-bid)/point;
   g_lastKnownSpreadPoints=spread;
   double allowedSpread=g_limits.maxSpreadPoints>0.0?g_limits.maxSpreadPoints:InpMaxSpreadPoints;
   if(allowedSpread>0.0 && spread>allowedSpread) return;

   bool newBatch=!g_batch.active;
   if(newBatch && g_volatilityPause) return;

   int batchId = g_batch.active ? g_batch.id : g_nextBatchId;
   string tag = g_batch.active ? g_batch.tag : StringFormat("BATCH#%04d",batchId);
   double startBalance = g_batch.active ? g_batch.startBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   double targetMoney  = g_batch.active ? g_batch.targetProfitMoney : EstimateBatchTargetMoney(startBalance);

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
   double spreadPts=g_lastKnownSpreadPoints;
   double spreadPips=PointsToPips(spreadPts);
   double allowedSpread=g_limits.maxSpreadPoints;
   double allowedSpreadPips=PointsToPips(allowedSpread);
   double minStopPoints=g_limits.minStopPoints;
   double minStopPips=PointsToPips(minStopPoints);
   double pipValue=g_symbolTraits.pipValuePerLot;
   if(pipValue<=0.0)
      pipValue=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_VALUE);
   string rect=g_patternSignal.hasRectangle?"Y":"-";
   string triple=g_patternSignal.hasTriple?"Y":"-";
   string flag=g_patternSignal.hasFlag?"Y":"-";
   string status=StringFormat("Symbol %s (%s)\nBalance %.2f | Equity %.2f | MarginLvl %.1f%%\nSpread %.1f pts (%.2f pip) / Max %.1f pts (%.2f pip)\nPipValue %.2f | Stop>=%.1f pts (%.2f pip)\nAuto:%s ManualPause:%s\nActiveBatch:%s trades %d/%d open %.2f closed %.2f\nTotal batches %d win %% %.2f last %.2f total %.2f\nTrend sign %d slopeNorm %.3f | Pattern R:%s T:%s F:%s strength %.2f",
      g_symbol,g_profileName,
      balance,equity,marginLevel,
      spreadPts,spreadPips,
      allowedSpread,allowedSpreadPips,
      pipValue,
      minStopPoints,minStopPips,
      g_autoEnabled?"ON":"OFF",
      g_manualPause?"YES":"NO",
      g_batch.active?"YES":"NO",
      g_batch.tradesOpened,InpTradesPerBatch,
      open,closed,
      g_batchesCompleted,
      g_batchesCompleted>0?100.0*g_batchesWon/g_batchesCompleted:0.0,
      g_lastBatchProfit,g_totalBatchProfit,
      g_trendContext.trendSign,g_trendContext.slope,
      rect,triple,flag,g_patternSignal.patternStrength);
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
   double atrLimit=g_limits.atrVolatilityLimit>0.0?g_limits.atrVolatilityLimit:InpATRVolatilityLimit;
   if(atrLimit>0.0 && atr>atrLimit) g_volatilityPause=true; else g_volatilityPause=false;
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
   double spreadPts=g_lastKnownSpreadPoints;
   double allowedSpread=g_limits.maxSpreadPoints;
   double spreadPips=PointsToPips(spreadPts);
   double allowedSpreadPips=PointsToPips(allowedSpread);
   double pipValue=g_symbolTraits.pipValuePerLot;
   if(pipValue<=0.0)
      pipValue=SymbolInfoDouble(g_symbol,SYMBOL_TRADE_TICK_VALUE);
   double lotStep=g_symbolTraits.lotStep;
   if(lotStep<=0.0)
      lotStep=SymbolInfoDouble(g_symbol,SYMBOL_VOLUME_STEP);
   if(lotStep<=0.0)
      lotStep=0.01;
   double minStopPoints=g_limits.minStopPoints;
   double minStopPips=PointsToPips(minStopPoints);
   double atrLimit=g_limits.atrVolatilityLimit;
   double targetMoney=g_batch.active?g_batch.targetProfitMoney:EstimateBatchTargetMoney(balance);
   string rect=g_patternSignal.hasRectangle?"Y":"-";
   string triple=g_patternSignal.hasTriple?"Y":"-";
   string flag=g_patternSignal.hasFlag?"Y":"-";
   string panel=StringFormat(
      "%s | Auto:%s | Manual:%s | MarginPause:%s | VolPause:%s\n"
      "Balance %.2f | Equity %.2f | ML %.1f%% | Spread %.1f pts (%.2f pip) / Max %.1f pts (%.2f pip)\n"
      "Profile:%s | PipValue %.2f | LotStep %.3f | Stop>=%.1f pts (%.2f pip) | ATR %.2f / Limit %.2f\n"
      "Batch:%s ID:%d Trades %d/%d Target %.2f Open %.2f Closed %.2f\n"
      "Trend sign %d slopeNorm %.3f | Pattern R:%s T:%s F:%s strength %.2f\n"
      "Batches %d Win%% %.2f Last %.2f Total %.2f | MaxDD %.2f%%",
      g_symbol,
      g_autoEnabled?"ON":"OFF",
      g_manualPause?"YES":"NO",
      g_marginPause?"YES":"NO",
      g_volatilityPause?"YES":"NO",
      balance,equity,marginLevel,
      spreadPts,spreadPips,
      allowedSpread,allowedSpreadPips,
      g_profileName,
      pipValue,
      lotStep,
      minStopPoints,minStopPips,
      atr,atrLimit,
      g_batch.active?"YES":"NO",
      g_batch.id,
      g_batch.tradesOpened,InpTradesPerBatch,
      targetMoney,
      open,closed,
      g_trendContext.trendSign,g_trendContext.slope,
      rect,triple,flag,g_patternSignal.patternStrength,
      g_batchesCompleted,winRate,g_lastBatchProfit,g_totalBatchProfit,g_maxDrawdown);
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

   g_lastKnownSpreadPoints=CurrentSpreadPoints();

   g_signalSuite.Update();
   g_trendContext=g_signalSuite.Trend();
   g_patternSignal=g_signalSuite.Pattern();

   ProcessTelegram();
   UpdatePauses();
   UpdateBatchStatus();
   TryOpenTrade();
   UpdateBatchStatus();
   UpdatePanel();
  }
