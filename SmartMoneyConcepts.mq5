//+------------------------------------------------------------------+
//|                                       SmartMoneyConcepts.mq5      |
//|                        Based on Smart Money Concepts [LuxAlgo]    |
//|                        Converted to MT5 from PineScript v5        |
//|                        + EA-consumable output buffers             |
//+------------------------------------------------------------------+
#property copyright "Converted from LuxAlgo SMC (CC BY-NC-SA 4.0)"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "1.10"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Buffer indices (for EA consumption via iCustom)                  |
//|                                                                   |
//|  Buffer 0: Internal signal     (+1 = bullish internal BOS/CHoCH, |
//|                                 -1 = bearish internal BOS/CHoCH, |
//|                                  0 = none on this bar)           |
//|  Buffer 1: Internal tag        (1 = BOS, 2 = CHoCH, 0 = none)    |
//|  Buffer 2: Sequence Low        (price - pivot low for SL on BUY) |
//|  Buffer 3: Sequence High       (price - pivot high for SL on SELL)|
//|  Buffer 4: Swing High          (current unbroken major swing hi) |
//|  Buffer 5: Swing Low           (current unbroken major swing lo) |
//+------------------------------------------------------------------+
double BufInternalSignal[];
double BufInternalTag[];
double BufSeqLow[];
double BufSeqHigh[];
double BufSwingHigh[];
double BufSwingLow[];

//+------------------------------------------------------------------+
enum ENUM_MODE { MODE_HISTORICAL=0, MODE_PRESENT=1 };
enum ENUM_STYLE_THEME { STYLE_COLORED=0, STYLE_MONOCHROME=1 };
enum ENUM_STRUCTURE_FILTER { FILTER_ALL=0, FILTER_BOS=1, FILTER_CHOCH=2 };
enum ENUM_OB_FILTER { OB_FILTER_ATR=0, OB_FILTER_RANGE=1 };
enum ENUM_OB_MITIGATION { OB_MIT_CLOSE=0, OB_MIT_HIGHLOW=1 };
enum ENUM_LABEL_SIZE { LABEL_TINY=0, LABEL_SMALL=1, LABEL_NORMAL=2 };
enum ENUM_LINE_STYLE_INPUT { LINE_SOLID=0, LINE_DASHED=1, LINE_DOTTED=2 };

#define BULLISH  +1
#define BEARISH  -1

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                   |
//+------------------------------------------------------------------+
input string sep0="===Smart Money Concepts===";
input ENUM_STYLE_THEME InpStyle=STYLE_COLORED;
input bool InpShowTrend=false;

input string sep1="===Internal Structure===";
input bool InpShowInternals=true;
input ENUM_STRUCTURE_FILTER InpInternalBull=FILTER_ALL;
input color InpInternalBullColor=clrGreen;
input ENUM_STRUCTURE_FILTER InpInternalBear=FILTER_ALL;
input color InpInternalBearColor=clrRed;
input bool InpConfluenceFilter=false;
input ENUM_LABEL_SIZE InpInternalLabelSize=LABEL_TINY;
input int  InpInternalLength=5;                 // Internal swing length

input string sep2="===Swing Structure===";
input bool InpShowStructure=true;
input ENUM_STRUCTURE_FILTER InpSwingBull=FILTER_ALL;
input color InpSwingBullColor=clrGreen;
input ENUM_STRUCTURE_FILTER InpSwingBear=FILTER_ALL;
input color InpSwingBearColor=clrRed;
input ENUM_LABEL_SIZE InpSwingLabelSize=LABEL_SMALL;
input bool InpShowSwings=false;
input int InpSwingsLength=50;
input bool InpShowHighLowSwings=true;

input string sep3="===Order Blocks===";
input bool InpShowInternalOB=true;
input int InpInternalOBSize=5;
input bool InpShowSwingOB=false;
input int InpSwingOBSize=5;
input ENUM_OB_FILTER InpOBFilter=OB_FILTER_ATR;
input ENUM_OB_MITIGATION InpOBMitigation=OB_MIT_HIGHLOW;
input color InpIntBullOBColor=clrDodgerBlue;
input color InpIntBearOBColor=clrLightCoral;
input color InpSwingBullOBColor=clrBlue;
input color InpSwingBearOBColor=clrCrimson;

input string sep4="===Equal Highs/Lows===";
input bool InpShowEQHL=true;
input int InpEQHLLength=3;
input double InpEQHLThreshold=0.1;
input ENUM_LABEL_SIZE InpEQHLLabelSize=LABEL_TINY;

input string sep5="===Fair Value Gaps===";
input bool InpShowFVG=false;
input bool InpFVGAutoThreshold=true;
input color InpFVGBullColor=clrLime;
input color InpFVGBearColor=clrRed;
input int InpFVGExtend=1;

//+------------------------------------------------------------------+
//| DATA STRUCTURES                                                    |
//+------------------------------------------------------------------+
struct PivotPoint { double currentLevel; double lastLevel; bool crossed; datetime barTime; int barIndex; };
struct OrderBlockData { double barHigh; double barLow; datetime barTime; int bias; };
struct FVGData { double top; double bottom; int bias; string topRect; string bottomRect; bool active; };

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                   |
//+------------------------------------------------------------------+
PivotPoint g_swingHigh, g_swingLow, g_internalHigh, g_internalLow, g_equalHigh, g_equalLow;
int g_swingTrendBias=0, g_internalTrendBias=0;
OrderBlockData g_swingOB[], g_internalOB[];
FVGData g_fvg[];
double g_parsedHighs[], g_parsedLows[], g_highs[], g_lows[];
datetime g_times[];
int g_objCount=0;
int g_atrHandle=INVALID_HANDLE;
double g_atrBuffer[];

// live swing/internal tracking for EA output
double g_curSwingHigh=0, g_curSwingLow=0;

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                   |
//+------------------------------------------------------------------+
string ObjName(string prefix) { g_objCount++; return prefix+"_"+IntegerToString(g_objCount)+"_"+IntegerToString(GetTickCount()); }
ENUM_LINE_STYLE GetLS(ENUM_LINE_STYLE_INPUT s) { if(s==LINE_DASHED) return STYLE_DASH; if(s==LINE_DOTTED) return STYLE_DOT; return STYLE_SOLID; }
int GetFS(ENUM_LABEL_SIZE s) { if(s==LABEL_TINY) return 7; if(s==LABEL_SMALL) return 8; return 10; }
void InitPivot(PivotPoint &p) { p.currentLevel=0; p.lastLevel=0; p.crossed=false; p.barTime=0; p.barIndex=0; }

//+------------------------------------------------------------------+
//| DRAWING FUNCTIONS                                                  |
//+------------------------------------------------------------------+
void DrawLine(datetime t1, datetime t2, double price, color clr, ENUM_LINE_STYLE st)
{
   string n=ObjName("SMC_L");
   ObjectCreate(0,n,OBJ_TREND,0,t1,price,t2,price);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_STYLE,st);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
}
void DrawText(datetime t1, double price, string text, color clr, int fontSize, bool above)
{
   string n=ObjName("SMC_T");
   ObjectCreate(0,n,OBJ_TEXT,0,t1,price);
   ObjectSetString(0,n,OBJPROP_TEXT,text);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,above?ANCHOR_LOWER:ANCHOR_UPPER);
}

//+------------------------------------------------------------------+
//| CORE LOGIC FUNCTIONS                                               |
//+------------------------------------------------------------------+
void DetectSwings(int bar, int size, const double &high[], const double &low[],
                  const datetime &time[], PivotPoint &pivotH, PivotPoint &pivotL,
                  bool isInternal, bool isEqualHL, double atr)
{
   if(bar<size*2) return;
   int pivotBar=bar-size;
   if(pivotBar<size) return;

   bool isSH=true, isSL=true;
   for(int i=MathMax(0,pivotBar-size); i<=MathMin(bar,(int)ArraySize(high)-1); i++)
   {
      if(i==pivotBar) continue;
      if(high[i]>high[pivotBar]) isSH=false;
      if(low[i]<low[pivotBar]) isSL=false;
   }

   if(isSH && high[pivotBar]!=pivotH.currentLevel)
   {
      if(isEqualHL && InpShowEQHL && pivotH.currentLevel>0 && atr>0)
      {
         if(MathAbs(pivotH.currentLevel-high[pivotBar])<InpEQHLThreshold*atr)
         {
            color c=(InpStyle==STYLE_MONOCHROME)?clrDimGray:InpSwingBearColor;
            string n=ObjName("SMC_EQ");
            ObjectCreate(0,n,OBJ_TREND,0,pivotH.barTime,pivotH.currentLevel,time[pivotBar],high[pivotBar]);
            ObjectSetInteger(0,n,OBJPROP_COLOR,c); ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DOT);
            ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,n,OBJPROP_BACK,true);
            datetime mt=(datetime)(((long)pivotH.barTime+(long)time[pivotBar])/2);
            DrawText(mt,high[pivotBar],"EQH",c,GetFS(InpEQHLLabelSize),true);
         }
      }
      pivotH.lastLevel=pivotH.currentLevel;
      pivotH.currentLevel=high[pivotBar];
      pivotH.crossed=false;
      pivotH.barTime=time[pivotBar];
      pivotH.barIndex=pivotBar;
      if(!isEqualHL && !isInternal)
      {
         g_curSwingHigh = pivotH.currentLevel;
         if(InpShowSwings)
         {
            string txt=(pivotH.currentLevel>pivotH.lastLevel && pivotH.lastLevel>0)?"HH":"LH";
            color c=(InpStyle==STYLE_MONOCHROME)?clrDimGray:InpSwingBearColor;
            DrawText(time[pivotBar],high[pivotBar],txt,c,7,true);
         }
      }
   }
   if(isSL && low[pivotBar]!=pivotL.currentLevel)
   {
      if(isEqualHL && InpShowEQHL && pivotL.currentLevel>0 && atr>0)
      {
         if(MathAbs(pivotL.currentLevel-low[pivotBar])<InpEQHLThreshold*atr)
         {
            color c=(InpStyle==STYLE_MONOCHROME)?clrSilver:InpSwingBullColor;
            string n=ObjName("SMC_EQ");
            ObjectCreate(0,n,OBJ_TREND,0,pivotL.barTime,pivotL.currentLevel,time[pivotBar],low[pivotBar]);
            ObjectSetInteger(0,n,OBJPROP_COLOR,c); ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DOT);
            ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,n,OBJPROP_BACK,true);
            datetime mt=(datetime)(((long)pivotL.barTime+(long)time[pivotBar])/2);
            DrawText(mt,low[pivotBar],"EQL",c,GetFS(InpEQHLLabelSize),false);
         }
      }
      pivotL.lastLevel=pivotL.currentLevel;
      pivotL.currentLevel=low[pivotBar];
      pivotL.crossed=false;
      pivotL.barTime=time[pivotBar];
      pivotL.barIndex=pivotBar;
      if(!isEqualHL && !isInternal)
      {
         g_curSwingLow = pivotL.currentLevel;
         if(InpShowSwings)
         {
            string txt=(pivotL.currentLevel<pivotL.lastLevel && pivotL.lastLevel>0)?"LL":"HL";
            color c=(InpStyle==STYLE_MONOCHROME)?clrSilver:InpSwingBullColor;
            DrawText(time[pivotBar],low[pivotBar],txt,c,7,false);
         }
      }
   }
}

void ProcessStructure(int bar, const double &close[], const double &high[], const double &low[],
                      const double &open[], const datetime &time[],
                      PivotPoint &pivotH, PivotPoint &pivotL, int &trendBias, bool isInternal,
                      double &outSignal, double &outTag, double &outSeqLow, double &outSeqHigh)
{
   color bullC=(InpStyle==STYLE_MONOCHROME)?clrSilver:(isInternal?InpInternalBullColor:InpSwingBullColor);
   color bearC=(InpStyle==STYLE_MONOCHROME)?clrDimGray:(isInternal?InpInternalBearColor:InpSwingBearColor);
   ENUM_LINE_STYLE ls=isInternal?STYLE_DASH:STYLE_SOLID;
   ENUM_LABEL_SIZE labelSz=isInternal?InpInternalLabelSize:InpSwingLabelSize;

   bool cfBull=true, cfBear=true;
   if(InpConfluenceFilter && isInternal)
   {
      cfBull=(high[bar]-MathMax(close[bar],open[bar]))>(MathMin(close[bar],open[bar])-low[bar]);
      cfBear=(high[bar]-MathMax(close[bar],open[bar]))<(MathMin(close[bar],open[bar])-low[bar]);
   }

   // Bullish break
   bool extra=isInternal?(pivotH.currentLevel!=g_swingHigh.currentLevel && cfBull):true;
   if(pivotH.currentLevel>0 && !pivotH.crossed && extra)
   {
      if(bar>0 && close[bar]>pivotH.currentLevel && close[bar-1]<=pivotH.currentLevel)
      {
         string tag=(trendBias==BEARISH)?"CHoCH":"BOS";
         pivotH.crossed=true; trendBias=BULLISH;
         bool show=false;
         if(isInternal) show=InpShowInternals&&(InpInternalBull==FILTER_ALL||(InpInternalBull==FILTER_BOS&&tag=="BOS")||(InpInternalBull==FILTER_CHOCH&&tag=="CHoCH"));
         else show=InpShowStructure&&(InpSwingBull==FILTER_ALL||(InpSwingBull==FILTER_BOS&&tag=="BOS")||(InpSwingBull==FILTER_CHOCH&&tag=="CHoCH"));
         if(show)
         {
            DrawLine(pivotH.barTime,time[bar],pivotH.currentLevel,bullC,ls);
            datetime mt=(datetime)(((long)pivotH.barTime+(long)time[bar])/2);
            DrawText(mt,pivotH.currentLevel,tag,bullC,GetFS(labelSz),true);
         }

         if(isInternal)
         {
            outSignal  = +1.0;
            outTag     = (tag=="CHoCH") ? 2.0 : 1.0;
            // Sequence low: lowest low between the pivot high bar and the break bar
            double lo = low[pivotH.barIndex];
            for(int k=pivotH.barIndex; k<=bar; k++) if(low[k]<lo) lo=low[k];
            outSeqLow  = lo;
            outSeqHigh = pivotH.currentLevel;
         }

         // On swing structure break the opposite side pivot is invalidated too
         if(!isInternal) pivotL.crossed = true;
      }
   }
   // Bearish break
   extra=isInternal?(pivotL.currentLevel!=g_swingLow.currentLevel && cfBear):true;
   if(pivotL.currentLevel>0 && !pivotL.crossed && extra)
   {
      if(bar>0 && close[bar]<pivotL.currentLevel && close[bar-1]>=pivotL.currentLevel)
      {
         string tag=(trendBias==BULLISH)?"CHoCH":"BOS";
         pivotL.crossed=true; trendBias=BEARISH;
         bool show=false;
         if(isInternal) show=InpShowInternals&&(InpInternalBear==FILTER_ALL||(InpInternalBear==FILTER_BOS&&tag=="BOS")||(InpInternalBear==FILTER_CHOCH&&tag=="CHoCH"));
         else show=InpShowStructure&&(InpSwingBear==FILTER_ALL||(InpSwingBear==FILTER_BOS&&tag=="BOS")||(InpSwingBear==FILTER_CHOCH&&tag=="CHoCH"));
         if(show)
         {
            DrawLine(pivotL.barTime,time[bar],pivotL.currentLevel,bearC,ls);
            datetime mt=(datetime)(((long)pivotL.barTime+(long)time[bar])/2);
            DrawText(mt,pivotL.currentLevel,tag,bearC,GetFS(labelSz),false);
         }

         if(isInternal)
         {
            outSignal  = -1.0;
            outTag     = (tag=="CHoCH") ? 2.0 : 1.0;
            // Sequence high: highest high between the pivot low bar and the break bar
            double hi = high[pivotL.barIndex];
            for(int k=pivotL.barIndex; k<=bar; k++) if(high[k]>hi) hi=high[k];
            outSeqHigh = hi;
            outSeqLow  = pivotL.currentLevel;
         }

         if(!isInternal) pivotH.crossed = true;
      }
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufInternalSignal, INDICATOR_DATA);
   SetIndexBuffer(1, BufInternalTag,    INDICATOR_DATA);
   SetIndexBuffer(2, BufSeqLow,         INDICATOR_DATA);
   SetIndexBuffer(3, BufSeqHigh,        INDICATOR_DATA);
   SetIndexBuffer(4, BufSwingHigh,      INDICATOR_DATA);
   SetIndexBuffer(5, BufSwingLow,       INDICATOR_DATA);

   InitPivot(g_swingHigh); InitPivot(g_swingLow);
   InitPivot(g_internalHigh); InitPivot(g_internalLow);
   InitPivot(g_equalHigh); InitPivot(g_equalLow);
   g_swingTrendBias=0; g_internalTrendBias=0;
   g_curSwingHigh=0; g_curSwingLow=0;
   g_atrHandle=iATR(Symbol(),Period(),200);
   if(g_atrHandle==INVALID_HANDLE) { Print("SMC: ATR handle failed"); return(INIT_FAILED); }
   g_objCount=0;

   IndicatorSetString(INDICATOR_SHORTNAME,"SMC");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   int total=ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--) { string n=ObjectName(0,i); if(StringFind(n,"SMC_")==0) ObjectDelete(0,n); }
   if(g_atrHandle!=INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   ArrayFree(g_parsedHighs); ArrayFree(g_parsedLows);
   ArrayFree(g_highs); ArrayFree(g_lows); ArrayFree(g_times);
   ArrayFree(g_swingOB); ArrayFree(g_internalOB); ArrayFree(g_fvg);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total<InpSwingsLength+10) return(0);

   ArraySetAsSeries(BufInternalSignal,false);
   ArraySetAsSeries(BufInternalTag,   false);
   ArraySetAsSeries(BufSeqLow,        false);
   ArraySetAsSeries(BufSeqHigh,       false);
   ArraySetAsSeries(BufSwingHigh,     false);
   ArraySetAsSeries(BufSwingLow,      false);

   int startBar=prev_calculated;
   if(startBar==0)
   {
      // clean chart objects
      int total=ObjectsTotal(0,0,-1);
      for(int i=total-1;i>=0;i--) { string n=ObjectName(0,i); if(StringFind(n,"SMC_")==0) ObjectDelete(0,n); }

      InitPivot(g_swingHigh); InitPivot(g_swingLow);
      InitPivot(g_internalHigh); InitPivot(g_internalLow);
      InitPivot(g_equalHigh); InitPivot(g_equalLow);
      g_swingTrendBias=0; g_internalTrendBias=0;
      g_curSwingHigh=0; g_curSwingLow=0;
      g_objCount=0;

      for(int i=0;i<rates_total;i++)
      {
         BufInternalSignal[i]=0; BufInternalTag[i]=0;
         BufSeqLow[i]=0; BufSeqHigh[i]=0;
         BufSwingHigh[i]=0; BufSwingLow[i]=0;
      }
      startBar=InpSwingsLength+5;
   }
   else
   {
      startBar=MathMax(prev_calculated-2,InpSwingsLength+5);
   }

   // Copy ATR
   ArrayResize(g_atrBuffer,rates_total);
   ArraySetAsSeries(g_atrBuffer,false);
   if(CopyBuffer(g_atrHandle,0,0,rates_total,g_atrBuffer)<=0) return(0);

   // Main loop
   for(int bar=startBar;bar<rates_total;bar++)
   {
      double atr=g_atrBuffer[bar];
      DetectSwings(bar,InpSwingsLength,high,low,time,g_swingHigh,g_swingLow,false,false,atr);
      DetectSwings(bar,InpInternalLength,high,low,time,g_internalHigh,g_internalLow,true,false,atr);
      if(InpShowEQHL) DetectSwings(bar,InpEQHLLength,high,low,time,g_equalHigh,g_equalLow,false,true,atr);

      double sig=0, tag=0, seqLo=0, seqHi=0;
      if(InpShowInternals)
         ProcessStructure(bar,close,high,low,open,time,g_internalHigh,g_internalLow,g_internalTrendBias,true,sig,tag,seqLo,seqHi);

      double dummyS=0,dummyT=0,dummySL=0,dummySH=0;
      if(InpShowStructure||InpShowHighLowSwings)
         ProcessStructure(bar,close,high,low,open,time,g_swingHigh,g_swingLow,g_swingTrendBias,false,dummyS,dummyT,dummySL,dummySH);

      BufInternalSignal[bar] = sig;
      BufInternalTag[bar]    = tag;
      BufSeqLow[bar]         = seqLo;
      BufSeqHigh[bar]        = seqHi;
      BufSwingHigh[bar]      = g_curSwingHigh;
      BufSwingLow[bar]       = g_curSwingLow;
   }

   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
