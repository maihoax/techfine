#property copyright "Phoenix Research Collective"
#property version   "8.0"
#property strict

#include <Trade\Trade.mqh>

//--- Enumerations ----------------------------------------------------------//
enum MarketRegime
  {
   REGIME_MEAN_REVERTING = 0,
   REGIME_RANDOM_WALK    = 1,
   REGIME_TRENDING       = 2,
   REGIME_VOLATILE_CHAOS = 3
  };

enum QuantumState
  {
   QUANTUM_SUPERPOSITION = 0,
   QUANTUM_COHERENT_BULL = 1,
   QUANTUM_COHERENT_BEAR = 2,
   QUANTUM_DECOHERENT    = 3
  };

enum SMCStructure
  {
   SMC_NONE = 0,
   SMC_ORDER_BLOCK_BULLISH,
   SMC_ORDER_BLOCK_BEARISH,
   SMC_FAIR_VALUE_GAP,
   SMC_BREAK_OF_STRUCTURE,
   SMC_LIQUIDITY_SWEEP
  };

//--- Structures ------------------------------------------------------------//
struct HurstAnalysis
  {
   double        exponent;
   double        confidence;
   MarketRegime  regime;
   datetime      calculated;
  };

struct VarianceRatioTest
  {
   double vr_statistics[3];
   double p_values[3];
   bool   trend_confirmed;
   bool   mean_revert_confirmed;
  };

struct QuantumMatrix
  {
   double       coherence_level;
   double       bull_amplitude;
   double       bear_amplitude;
   double       neutral_amplitude;
   double       interference;
   QuantumState state;
  };

struct SafeZone
  {
   double pivot_center;
   double upper;
   double lower;
   double fib_382;
   double fib_618;
   double golden;
   double quality;
   int    touches;
   bool   premium;
  };

struct PatternState
  {
   bool   triple_top;
   bool   triple_bottom;
   bool   rectangle;
   bool   flag;
   bool   failed_break;
   double reliability;
   double targets[3];
  };

struct RiskMatrix
  {
   double equity_at_start;
   double max_drawdown_pct;
   double day_loss_pct;
   double portfolio_heat;
   bool   crisis;
  };

struct SMCData
  {
   SMCStructure structure;
   double       level_high;
   double       level_low;
   datetime     time_detected;
  };

//--- Inputs ----------------------------------------------------------------//
input group   "Position Sizing"
input double  InpBaseLot                 = 0.10;
input double  InpRiskPerTradePercent     = 0.6;
input int     InpMaxPositions            = 3;
input double  InpMaxPortfolioHeatPercent = 2.5;
input double  InpMinRiskReward           = 1.8;

input group   "Hurst Exponent"
input bool    InpEnableHurst             = true;
input int     InpHurstWindow             = 400;
input double  InpHurstMeanThreshold      = 0.45;
input double  InpHurstTrendThreshold     = 0.55;
input int     InpHurstUpdateBars         = 20;

input group   "Variance Ratio Test"
input bool    InpEnableVRT               = true;
input double  InpVRTSignificance         = 0.05;

input group   "Quantum Coherence"
input bool    InpEnableQuantum           = true;
input double  InpCoherenceThreshold      = 0.55;
input double  InpInterferenceThreshold   = 0.35;

input group   "Safe Zone"
input double  InpSafeZoneATRMultiplier   = 1.8;
input double  InpZoneQualityThreshold    = 0.65;
input bool    InpUseGoldenLevel          = true;

input group   "Pattern Recognition"
input bool    InpEnablePatterns          = true;
input double  InpPatternReliabilityMin   = 0.70;
input int     InpPatternLookback         = 200;

input group   "Smart Money Concepts"
input bool    InpEnableSMC               = true;
input double  InpOrderBlockMinPips       = 15.0;

input group   "Risk Control"
input double  InpMaxDrawdownPercent      = 6.0;
input double  InpDailyLossPercent        = 1.8;
input int     InpMagic                   = 885588;

input group   "Telegram"
input bool    InpEnableTelegram          = false;
input string  InpTelegramToken           = "";
input string  InpTelegramChatId          = "";

//--- Globals ----------------------------------------------------------------
CTrade        g_trade;
HurstAnalysis g_hurst;
VarianceRatioTest g_vrt;
QuantumMatrix g_quantum;
SafeZone      g_zone;
PatternState  g_patterns;
RiskMatrix    g_risk;
SMCData       g_smc;

int           g_handleFastEMA_M15 = INVALID_HANDLE;
int           g_handleSlowEMA_M15 = INVALID_HANDLE;
int           g_handleFastEMA_H1  = INVALID_HANDLE;
int           g_handleSlowEMA_H1  = INVALID_HANDLE;
int           g_handleATR_M15     = INVALID_HANDLE;
int           g_handleATR_H1      = INVALID_HANDLE;
int           g_handleRSI_M15     = INVALID_HANDLE;
int           g_handleADX_M15     = INVALID_HANDLE;

double        g_fastEMA_M15[];
double        g_slowEMA_M15[];
double        g_fastEMA_H1[];
double        g_slowEMA_H1[];
double        g_atrM15[];
double        g_atrH1[];
double        g_rsiM15[];
double        g_adxM15[];

double        g_priceSeries[800];
double        g_returnSeries[800];

datetime      g_lastDailyReset = 0;
double        g_dailyPnlStart  = 0.0;

//--- Utility prototypes -----------------------------------------------------//
bool   InitializeIndicators();
bool   RefreshIndicators();
void   UpdateRiskMatrix();
void   ResetDailyStats();
double CalculateAdaptiveLot(double risk_pips);

void   UpdateHurst();
void   UpdateVarianceRatio();
void   UpdateQuantumMatrix();
void   UpdateSafeZone();
void   UpdatePatterns();
void   UpdateSMC();

bool   AllowNewTrade();
void   EvaluateOpportunities();
void   ManageOpenPositions();

bool   ExecuteTrade(int direction,double sl,double tp,string tag);
double ComputeStopLoss(int direction);
double ComputeTakeProfit(int direction,double entry,double sl);

void   SendTelegram(const string message);

//--- Initialization ---------------------------------------------------------//
int OnInit()
  {
   g_trade.SetExpertMagicNumber(InpMagic);
   g_risk.equity_at_start = AccountInfoDouble(ACCOUNT_EQUITY);
   g_risk.max_drawdown_pct = 0.0;
   g_risk.day_loss_pct = 0.0;
   g_lastDailyReset = TimeCurrent();
   g_dailyPnlStart = AccountInfoDouble(ACCOUNT_EQUITY);

   if(!InitializeIndicators())
      return(INIT_FAILED);

   ArrayInitialize(g_priceSeries,0.0);
   ArrayInitialize(g_returnSeries,0.0);

   SendTelegram("Phoenix EA Research Grade initialized");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_handleFastEMA_M15!=INVALID_HANDLE)IndicatorRelease(g_handleFastEMA_M15);
   if(g_handleSlowEMA_M15!=INVALID_HANDLE)IndicatorRelease(g_handleSlowEMA_M15);
   if(g_handleFastEMA_H1!=INVALID_HANDLE) IndicatorRelease(g_handleFastEMA_H1);
   if(g_handleSlowEMA_H1!=INVALID_HANDLE) IndicatorRelease(g_handleSlowEMA_H1);
   if(g_handleATR_M15!=INVALID_HANDLE)    IndicatorRelease(g_handleATR_M15);
   if(g_handleATR_H1!=INVALID_HANDLE)     IndicatorRelease(g_handleATR_H1);
   if(g_handleRSI_M15!=INVALID_HANDLE)    IndicatorRelease(g_handleRSI_M15);
   if(g_handleADX_M15!=INVALID_HANDLE)    IndicatorRelease(g_handleADX_M15);
  }

//--- Main tick --------------------------------------------------------------//
void OnTick()
  {
   if(!RefreshIndicators())
      return;

   datetime now=TimeCurrent();
   if(TimeDay(now)!=TimeDay(g_lastDailyReset))
      ResetDailyStats();

   UpdateRiskMatrix();
   ManageOpenPositions();

   static int lastUpdate=0;
   if((int)TimeCurrent()!=lastUpdate)
     {
      UpdateHurst();
      UpdateVarianceRatio();
      UpdateQuantumMatrix();
      UpdateSafeZone();
      UpdateSMC();
      UpdatePatterns();
      lastUpdate=(int)TimeCurrent();
     }

   if(AllowNewTrade())
      EvaluateOpportunities();
  }

//--- Indicator management ---------------------------------------------------//
bool InitializeIndicators()
  {
   g_handleFastEMA_M15=iMA(_Symbol,PERIOD_M15,20,0,MODE_EMA,PRICE_CLOSE);
   g_handleSlowEMA_M15=iMA(_Symbol,PERIOD_M15,50,0,MODE_EMA,PRICE_CLOSE);
   g_handleFastEMA_H1 =iMA(_Symbol,PERIOD_H1 ,20,0,MODE_EMA,PRICE_CLOSE);
   g_handleSlowEMA_H1 =iMA(_Symbol,PERIOD_H1 ,50,0,MODE_EMA,PRICE_CLOSE);
   g_handleATR_M15    =iATR(_Symbol,PERIOD_M15,14);
   g_handleATR_H1     =iATR(_Symbol,PERIOD_H1 ,14);
   g_handleRSI_M15    =iRSI(_Symbol,PERIOD_M15,14,PRICE_CLOSE);
   g_handleADX_M15    =iADX(_Symbol,PERIOD_M15,14);

   if(g_handleFastEMA_M15==INVALID_HANDLE || g_handleSlowEMA_M15==INVALID_HANDLE ||
      g_handleFastEMA_H1==INVALID_HANDLE  || g_handleSlowEMA_H1==INVALID_HANDLE  ||
      g_handleATR_M15==INVALID_HANDLE     || g_handleATR_H1==INVALID_HANDLE      ||
      g_handleRSI_M15==INVALID_HANDLE     || g_handleADX_M15==INVALID_HANDLE)
     {
      Print("Indicator initialization failed");
      return(false);
     }

   ArraySetAsSeries(g_fastEMA_M15,true);
   ArraySetAsSeries(g_slowEMA_M15,true);
   ArraySetAsSeries(g_fastEMA_H1,true);
   ArraySetAsSeries(g_slowEMA_H1,true);
   ArraySetAsSeries(g_atrM15,true);
   ArraySetAsSeries(g_atrH1,true);
   ArraySetAsSeries(g_rsiM15,true);
   ArraySetAsSeries(g_adxM15,true);
   return(true);
  }

bool RefreshIndicators()
  {
   if(!CopyBuffer(g_handleFastEMA_M15,0,0,100,g_fastEMA_M15) ||
      !CopyBuffer(g_handleSlowEMA_M15,0,0,100,g_slowEMA_M15) ||
      !CopyBuffer(g_handleFastEMA_H1 ,0,0,200,g_fastEMA_H1)  ||
      !CopyBuffer(g_handleSlowEMA_H1 ,0,0,200,g_slowEMA_H1)  ||
      !CopyBuffer(g_handleATR_M15   ,0,0,100,g_atrM15)       ||
      !CopyBuffer(g_handleATR_H1    ,0,0,200,g_atrH1)        ||
      !CopyBuffer(g_handleRSI_M15   ,0,0,100,g_rsiM15)       ||
      !CopyBuffer(g_handleADX_M15   ,0,0,100,g_adxM15))
     {
      Print("Failed refreshing indicator buffers");
      return(false);
     }

   for(int i=0;i<InpHurstWindow && i<ArraySize(g_priceSeries);i++)
     {
      g_priceSeries[i]=iClose(_Symbol,PERIOD_H1,i);
      if(i<InpHurstWindow-1)
         g_returnSeries[i]=0.0;
     }

   return(true);
  }

//--- Risk matrix ------------------------------------------------------------//
void UpdateRiskMatrix()
  {
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdown_pct=(balance-equity)/balance*100.0;
   if(drawdown_pct<0)drawdown_pct=0;
   g_risk.max_drawdown_pct=MathMax(g_risk.max_drawdown_pct,drawdown_pct);

   double day_loss=(g_dailyPnlStart-equity)/g_dailyPnlStart*100.0;
   g_risk.day_loss_pct=day_loss;

   double exposure=0.0;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         exposure+=MathAbs(PositionGetDouble(POSITION_VOLUME))*100.0/AccountInfoDouble(ACCOUNT_BALANCE);
     }
   g_risk.portfolio_heat=exposure;

   g_risk.crisis=(drawdown_pct>InpMaxDrawdownPercent || day_loss>InpDailyLossPercent || exposure>InpMaxPortfolioHeatPercent);
  }

void ResetDailyStats()
  {
   g_lastDailyReset=TimeCurrent();
   g_dailyPnlStart=AccountInfoDouble(ACCOUNT_EQUITY);
  }

//--- Analysis modules -------------------------------------------------------//
void UpdateHurst()
  {
   if(!InpEnableHurst)
      return;
   if(iBars(_Symbol,PERIOD_H1)<InpHurstWindow)
      return;

   static datetime lastCalc=0;
   if(TimeCurrent()-lastCalc<InpHurstUpdateBars*PeriodSeconds(PERIOD_M15))
      return;

   double mean=0.0;
   for(int i=0;i<InpHurstWindow-1;i++)
     {
      double ret=0.0;
      if(g_priceSeries[i+1]>0.0)
         ret=MathLog(g_priceSeries[i]/g_priceSeries[i+1]);
      g_returnSeries[i]=ret;
      mean+=ret;
     }
   mean/=MathMax(1,InpHurstWindow-1);

   double variance=0.0;
   for(int i=0;i<InpHurstWindow-1;i++)
      variance+=MathPow(g_returnSeries[i]-mean,2);
   if(InpHurstWindow>2)
      variance/=double(InpHurstWindow-2);
   double std=MathSqrt(MathMax(variance,1e-12));

   int periods[]={10,20,40,80,160};
   double sumX=0,sumY=0,sumXY=0,sumX2=0;
   int count=0;

   for(int n=0;n<ArraySize(periods);n++)
     {
      int window=periods[n];
      if(window>=InpHurstWindow || window<2)
         continue;

      double cumulative=0,maxDev=0,minDev=0;
      for(int i=0;i<window;i++)
        {
         cumulative+=g_returnSeries[i]-mean;
         maxDev=MathMax(maxDev,cumulative);
         minDev=MathMin(minDev,cumulative);
        }
      double range=maxDev-minDev;
      double rs=(std>0)?range/(std*MathSqrt(window)):0.0;
      if(rs<=0.0) continue;

      double x=MathLog(window);
      double y=MathLog(rs);
      sumX+=x;sumY+=y;sumXY+=x*y;sumX2+=x*x;count++;
     }

   if(count>=3)
     {
      double denominator=count*sumX2-sumX*sumX;
      if(MathAbs(denominator)>1e-9)
        g_hurst.exponent=(count*sumXY-sumX*sumY)/denominator;
     }
   g_hurst.exponent=MathMax(0.0,MathMin(g_hurst.exponent,1.0));

   g_hurst.confidence=MathMin(1.0,count/5.0);

   if(g_hurst.exponent<InpHurstMeanThreshold)
      g_hurst.regime=REGIME_MEAN_REVERTING;
   else if(g_hurst.exponent>InpHurstTrendThreshold)
      g_hurst.regime=REGIME_TRENDING;
   else
      g_hurst.regime=REGIME_RANDOM_WALK;

   g_hurst.calculated=TimeCurrent();
   lastCalc=TimeCurrent();
  }

void UpdateVarianceRatio()
  {
   if(!InpEnableVRT)
      return;

   int lags[3]={2,4,8};
   double baseVar=0.0,mean=0.0;
   int window=200;
   if(window>InpHurstWindow-1)
      window=InpHurstWindow-1;
   if(window<10)
      return;

   for(int i=0;i<window;i++)
      mean+=g_returnSeries[i];
   mean/=window;

   for(int i=0;i<window;i++)
      baseVar+=MathPow(g_returnSeries[i]-mean,2);
   baseVar/=MathMax(1,window-1);

   for(int idx=0;idx<3;idx++)
     {
      int lag=lags[idx];
      if(lag>=window) continue;
      double accum=0.0;int count=0;
      for(int i=0;i<window-lag;i+=lag)
        {
         double block=0.0;
         for(int j=0;j<lag && i+j<window;j++)
            block+=g_returnSeries[i+j];
         accum+=MathPow(block,2);
         count++;
        }
      double varLag=(count>1)?accum/(count-1):0.0;
      double ratio=(lag>0 && baseVar>0)?varLag/(lag*baseVar):1.0;
      g_vrt.vr_statistics[idx]=ratio;
      double stat=MathSqrt(window)*MathAbs(ratio-1.0);
      g_vrt.p_values[idx]=MathMin(1.0,MathMax(0.0,2.0*(1.0-0.5*stat)));
     }

   int significant=0;int trendVotes=0;
   for(int i=0;i<3;i++)
     {
      if(g_vrt.p_values[i]<InpVRTSignificance)
        {
         significant++;
         if(g_vrt.vr_statistics[i]>1.0) trendVotes++;
         if(g_vrt.vr_statistics[i]<1.0) trendVotes--;
        }
     }

   g_vrt.trend_confirmed=(significant>=2 && trendVotes>0);
   g_vrt.mean_revert_confirmed=(significant>=2 && trendVotes<0);
  }

void UpdateQuantumMatrix()
  {
   if(!InpEnableQuantum)
      return;

   double emaDelta=g_fastEMA_M15[0]-g_slowEMA_M15[0];
   double rsi=g_rsiM15[0];
   double adx=g_adxM15[0];

   double bullStrength=0.0;
   double bearStrength=0.0;

   if(emaDelta>0)
      bullStrength=MathMin(1.0,emaDelta/MathMax(g_atrM15[0],_Point));
   else
      bearStrength=MathMin(1.0,-emaDelta/MathMax(g_atrM15[0],_Point));

   if(rsi>50.0)
      bullStrength=0.6*bullStrength+0.4*(rsi-50.0)/50.0;
   else
      bearStrength=0.6*bearStrength+0.4*(50.0-rsi)/50.0;

   double normalization=MathMax(1e-6,bullStrength+bearStrength);
   g_quantum.bull_amplitude=MathSqrt(MathMax(0.0,bullStrength/normalization));
   g_quantum.bear_amplitude=MathSqrt(MathMax(0.0,bearStrength/normalization));
   double neutral=MathMax(0.0,1.0-MathPow(g_quantum.bull_amplitude,2)-MathPow(g_quantum.bear_amplitude,2));
   g_quantum.neutral_amplitude=MathSqrt(neutral);

   double trendFactor=MathMin(1.0,adx/50.0);
   g_quantum.interference=(g_quantum.bull_amplitude-g_quantum.bear_amplitude)*trendFactor;
   g_quantum.coherence_level=MathMin(1.0,MathAbs(g_quantum.interference)+trendFactor*0.6);

   if(g_quantum.coherence_level<0.25)
      g_quantum.state=QUANTUM_DECOHERENT;
   else if(g_quantum.bull_amplitude>g_quantum.bear_amplitude+0.1)
      g_quantum.state=QUANTUM_COHERENT_BULL;
   else if(g_quantum.bear_amplitude>g_quantum.bull_amplitude+0.1)
      g_quantum.state=QUANTUM_COHERENT_BEAR;
   else
      g_quantum.state=QUANTUM_SUPERPOSITION;
  }

void UpdateSafeZone()
  {
   double center=iClose(_Symbol,PERIOD_M15,0);
   double atr=MathMax(g_atrM15[0],_Point*10);
   g_zone.upper=center+InpSafeZoneATRMultiplier*atr;
   g_zone.lower=center-InpSafeZoneATRMultiplier*atr;
   g_zone.pivot_center=center;
   g_zone.fib_382=g_zone.lower+(g_zone.upper-g_zone.lower)*0.382;
   g_zone.fib_618=g_zone.lower+(g_zone.upper-g_zone.lower)*0.618;
   g_zone.golden=g_zone.lower+(g_zone.upper-g_zone.lower)*0.618;

   g_zone.touches=0;
   for(int i=1;i<200;i++)
     {
      double price=iClose(_Symbol,PERIOD_M15,i);
      if(price>=g_zone.lower && price<=g_zone.upper)
         g_zone.touches++;
     }

   g_zone.quality=MathMin(1.0,g_zone.touches/10.0);
   g_zone.premium=(g_zone.quality>=InpZoneQualityThreshold);
  }

void UpdateSMC()
  {
   if(!InpEnableSMC)
      return;

   g_smc.structure=SMC_NONE;
   double minBody=InpOrderBlockMinPips*_Point;
   for(int i=5;i<50;i++)
     {
      double open=iOpen(_Symbol,PERIOD_M15,i);
      double close=iClose(_Symbol,PERIOD_M15,i);
      double body=MathAbs(close-open);
      if(body<minBody)
         continue;

      double high=iHigh(_Symbol,PERIOD_M15,i);
      double low=iLow(_Symbol,PERIOD_M15,i);

      if(close>open && iClose(_Symbol,PERIOD_M15,i-1)>close && iClose(_Symbol,PERIOD_M15,i-2)>close)
        {
         g_smc.structure=SMC_ORDER_BLOCK_BULLISH;
         g_smc.level_low=low;
         g_smc.level_high=high;
         g_smc.time_detected=iTime(_Symbol,PERIOD_M15,i);
         break;
        }
      if(close<open && iClose(_Symbol,PERIOD_M15,i-1)<close && iClose(_Symbol,PERIOD_M15,i-2)<close)
        {
         g_smc.structure=SMC_ORDER_BLOCK_BEARISH;
         g_smc.level_low=low;
         g_smc.level_high=high;
         g_smc.time_detected=iTime(_Symbol,PERIOD_M15,i);
         break;
        }
     }
  }

void UpdatePatterns()
  {
   if(!InpEnablePatterns)
      return;
   g_patterns.triple_top=false;
   g_patterns.triple_bottom=false;
   g_patterns.rectangle=false;
   g_patterns.flag=false;
   g_patterns.failed_break=false;
   g_patterns.reliability=0.0;

   double tolerance=g_atrM15[0];
   double lastHigh=0,lastLow=0;int highs=0,lows=0;
   for(int i=5;i<InpPatternLookback;i++)
     {
      double high=iHigh(_Symbol,PERIOD_M15,i);
      double low=iLow(_Symbol,PERIOD_M15,i);
      bool swingHigh=(high>iHigh(_Symbol,PERIOD_M15,i+1) && high>iHigh(_Symbol,PERIOD_M15,i-1));
      bool swingLow=(low<iLow(_Symbol,PERIOD_M15,i+1) && low<iLow(_Symbol,PERIOD_M15,i-1));

      if(swingHigh)
        {
         if(highs==0) lastHigh=high;
         if(MathAbs(high-lastHigh)<=tolerance)
            highs++;
        }
      if(swingLow)
        {
         if(lows==0) lastLow=low;
         if(MathAbs(low-lastLow)<=tolerance)
            lows++;
        }
     }

   if(highs>=3)
     {
      g_patterns.triple_top=true;
      g_patterns.reliability+=0.3;
      g_patterns.targets[0]=lastHigh-1.0*g_atrM15[0];
      g_patterns.targets[1]=lastHigh-1.6*g_atrM15[0];
      g_patterns.targets[2]=lastHigh-2.4*g_atrM15[0];
     }
   if(lows>=3)
     {
      g_patterns.triple_bottom=true;
      g_patterns.reliability+=0.3;
      g_patterns.targets[0]=lastLow+1.0*g_atrM15[0];
      g_patterns.targets[1]=lastLow+1.6*g_atrM15[0];
      g_patterns.targets[2]=lastLow+2.4*g_atrM15[0];
     }

   if(g_smc.structure!=SMC_NONE)
      g_patterns.reliability+=0.2;
   if(g_zone.premium)
      g_patterns.reliability+=0.2;

   g_patterns.reliability=MathMin(0.95,g_patterns.reliability);
  }

//--- Trading logic ----------------------------------------------------------//
bool AllowNewTrade()
  {
   if(g_risk.crisis)
      return(false);
   if(PositionsTotal()>=InpMaxPositions)
      return(false);
   if(g_risk.day_loss_pct>InpDailyLossPercent)
      return(false);
   return(true);
  }

void EvaluateOpportunities()
  {
   double coherence=(InpEnableQuantum)?g_quantum.coherence_level:0.5;
   double hurstConfidence=(InpEnableHurst)?g_hurst.confidence:0.4;
   double vrtSignal=(g_vrt.trend_confirmed || g_vrt.mean_revert_confirmed)?0.2:0.0;
   double zoneQuality=g_zone.premium?0.2:0.0;
   double patternScore=(g_patterns.reliability>=InpPatternReliabilityMin)?0.2:0.0;

   double score=coherence+hurstConfidence+vrtSignal+zoneQuality+patternScore;

   if(score<1.2)
      return;

   int direction=0;
   if(g_quantum.state==QUANTUM_COHERENT_BULL)
      direction=1;
   else if(g_quantum.state==QUANTUM_COHERENT_BEAR)
      direction=-1;

   if(direction==0)
     {
      if(g_hurst.regime==REGIME_MEAN_REVERTING && g_vrt.mean_revert_confirmed)
        direction=(iClose(_Symbol,PERIOD_M15,0)<=g_zone.fib_382)?1:-1;
      else if(g_hurst.regime==REGIME_TRENDING && g_vrt.trend_confirmed)
        direction=(g_fastEMA_H1[0]>g_slowEMA_H1[0])?1:-1;
     }

   if(direction==0)
      return;

   double sl=ComputeStopLoss(direction);
   if(sl<=0)
      return;
   double entry=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(direction<0)
      entry=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double tp=ComputeTakeProfit(direction,entry,sl);
   if(tp<=0)
      return;

   double riskPips=MathAbs(entry-sl)/_Point;
   double lot=CalculateAdaptiveLot(riskPips);
   if(lot<=0)
      return;

   string tag=StringFormat("PHX_RG_%s",(direction>0)?"BUY":"SELL");
   if(ExecuteTrade(direction,sl,tp,tag))
     {
      string msg=StringFormat("Phoenix RG entry %s lot %.2f SL %.1f TP %.1f score %.2f",tag,lot,sl,tp,score);
      SendTelegram(msg);
     }
  }

double CalculateAdaptiveLot(double risk_pips)
  {
   if(risk_pips<=0)
      return(0.0);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount=balance*InpRiskPerTradePercent/100.0;
   double lot=NormalizeDouble(riskAmount/(risk_pips*SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE)),2);
   lot=MathMax(InpBaseLot/2.0,MathMin(lot,SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)));
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   lot=NormalizeDouble(MathFloor(lot/step)*step,2);
   return(MathMax(step,lot));
  }

double ComputeStopLoss(int direction)
  {
   double atr=MathMax(g_atrM15[0],_Point*10);
   double price=(direction>0)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl=(direction>0)?price-1.5*atr:price+1.5*atr;

   if(direction>0 && g_zone.lower<price)
      sl=MathMin(sl,g_zone.lower-0.5*atr);
   if(direction<0 && g_zone.upper>0)
      sl=MathMax(sl,g_zone.upper+0.5*atr);

   return(sl);
  }

double ComputeTakeProfit(int direction,double entry,double sl)
  {
   double risk=MathAbs(entry-sl);
   double tp=(direction>0)?entry+InpMinRiskReward*risk:entry-InpMinRiskReward*risk;
   if(g_patterns.reliability>=InpPatternReliabilityMin)
     {
      double target=g_patterns.targets[0];
      if(direction>0)
         tp=MathMax(tp,target);
      else
         tp=MathMin(tp,target);
     }
   return(tp);
  }

bool ExecuteTrade(int direction,double sl,double tp,string tag)
  {
   double lot=CalculateAdaptiveLot(MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID)-sl)/_Point);
   if(lot<=0)
      return(false);
   bool result=false;
   if(direction>0)
      result=g_trade.Buy(lot,_Symbol,0,sl,tp,tag);
   else
      result=g_trade.Sell(lot,_Symbol,0,sl,tp,tag);
   if(!result)
      Print("Order failed: ",_LastError);
   return(result);
  }

void ManageOpenPositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic)
         continue;

      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      long   type=PositionGetInteger(POSITION_TYPE);
      double profit=PositionGetDouble(POSITION_PROFIT);

      double atr=MathMax(g_atrM15[0],_Point*10);
      double newSL=PositionGetDouble(POSITION_SL);

      if(type==POSITION_TYPE_BUY)
        {
         double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         if(price-openPrice>1.5*atr)
            newSL=MathMax(newSL,openPrice+0.2*atr);
         if(g_quantum.state==QUANTUM_DECOHERENT && profit>0)
            g_trade.PositionClose(PositionGetTicket(i));
        }
      else if(type==POSITION_TYPE_SELL)
        {
         double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         if(openPrice-price>1.5*atr)
            newSL=MathMin(newSL,openPrice-0.2*atr);
         if(g_quantum.state==QUANTUM_DECOHERENT && profit>0)
            g_trade.PositionClose(PositionGetTicket(i));
        }

      if(MathAbs(newSL-PositionGetDouble(POSITION_SL))>0.5*_Point)
         g_trade.PositionModify(PositionGetTicket(i),newSL,PositionGetDouble(POSITION_TP));
     }
  }

//--- Telegram ---------------------------------------------------------------//
void SendTelegram(const string message)
  {
   if(!InpEnableTelegram || StringLen(InpTelegramToken)==0 || StringLen(InpTelegramChatId)==0)
      return;
   Print("[Telegram] ",message);
  }
