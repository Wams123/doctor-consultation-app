//+------------------------------------------------------------------+
//|                                       SmartMoneyConcepts.mq5      |
//|                        Based on Smart Money Concepts [LuxAlgo]     |
//|                        Converted to MT5 from PineScript v5         |
//+------------------------------------------------------------------+
#property copyright "Converted from LuxAlgo SMC (CC BY-NC-SA 4.0)"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                       |
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
input string sep0="===Smart Money Concepts==="; //--- Smart Money Concepts ---
input ENUM_MODE InpMode=MODE_HISTORICAL;        // Mode
input ENUM_STYLE_THEME InpStyle=STYLE_COLORED;  // Style
input bool InpShowTrend=false;                  // Color Candles

input string sep1="===Internal Structure===";   //--- Internal Structure ---
input bool InpShowInternals=true;               // Show Internal Structure
input ENUM_STRUCTURE_FILTER InpInternalBull=FILTER_ALL; // Bullish Structure
input color InpInternalBullColor=clrGreen;      // Bullish Color
input ENUM_STRUCTURE_FILTER InpInternalBear=FILTER_ALL; // Bearish Structure
input color InpInternalBearColor=clrRed;        // Bearish Color
input bool InpConfluenceFilter=false;           // Confluence Filter
input ENUM_LABEL_SIZE InpInternalLabelSize=LABEL_TINY; // Internal Label Size

input string sep2="===Swing Structure===";      //--- Swing Structure ---
input bool InpShowStructure=true;               // Show Swing Structure
input ENUM_STRUCTURE_FILTER InpSwingBull=FILTER_ALL; // Bullish Structure
input color InpSwingBullColor=clrGreen;         // Bullish Color
input ENUM_STRUCTURE_FILTER InpSwingBear=FILTER_ALL; // Bearish Structure
input color InpSwingBearColor=clrRed;           // Bearish Color
input ENUM_LABEL_SIZE InpSwingLabelSize=LABEL_SMALL; // Swing Label Size
input bool InpShowSwings=false;                 // Show Swing Points
input int InpSwingsLength=50;                   // Swing Length
input bool InpShowHighLowSwings=true;           // Show Strong/Weak High/Low

input string sep3="===Order Blocks===";         //--- Order Blocks ---
input bool InpShowInternalOB=true;              // Internal Order Blocks
input int InpInternalOBSize=5;                  // Internal OB Count
input bool InpShowSwingOB=false;                // Swing Order Blocks
input int InpSwingOBSize=5;                     // Swing OB Count
input ENUM_OB_FILTER InpOBFilter=OB_FILTER_ATR; // Order Block Filter
input ENUM_OB_MITIGATION InpOBMitigation=OB_MIT_HIGHLOW; // Order Block Mitigation
input color InpIntBullOBColor=clrDodgerBlue;    // Internal Bullish OB
input color InpIntBearOBColor=clrLightCoral;    // Internal Bearish OB
input color InpSwingBullOBColor=clrBlue;        // Swing Bullish OB
input color InpSwingBearOBColor=clrCrimson;     // Swing Bearish OB

input string sep4="===Equal Highs/Lows===";     //--- Equal Highs/Lows ---
input bool InpShowEQHL=true;                    // Equal High/Low
input int InpEQHLLength=3;                      // Bars Confirmation
input double InpEQHLThreshold=0.1;              // Threshold
input ENUM_LABEL_SIZE InpEQHLLabelSize=LABEL_TINY; // Label Size

input string sep5="===Fair Value Gaps===";      //--- Fair Value Gaps ---
input bool InpShowFVG=false;                    // Fair Value Gaps
input bool InpFVGAutoThreshold=true;            // Auto Threshold
input color InpFVGBullColor=clrLime;            // Bullish FVG
input color InpFVGBearColor=clrRed;             // Bearish FVG
input int InpFVGExtend=1;                       // Extend FVG (bars)

input string sep6="===Highs & Lows MTF===";     //--- Highs & Lows MTF ---
input bool InpShowDaily=false;                  // Daily
input ENUM_LINE_STYLE_INPUT InpDailyStyle=LINE_SOLID; // Daily Style
input color InpDailyColor=clrDodgerBlue;        // Daily Color
input bool InpShowWeekly=false;                 // Weekly
input ENUM_LINE_STYLE_INPUT InpWeeklyStyle=LINE_SOLID; // Weekly Style
input color InpWeeklyColor=clrDodgerBlue;       // Weekly Color
input bool InpShowMonthly=false;                // Monthly
input ENUM_LINE_STYLE_INPUT InpMonthlyStyle=LINE_SOLID; // Monthly Style
input color InpMonthlyColor=clrDodgerBlue;      // Monthly Color

input string sep7="===Premium & Discount===";   //--- Premium & Discount ---
input bool InpShowPDZones=false;                // Premium/Discount Zones
input color InpPremiumColor=clrRed;             // Premium Zone
input color InpEquilibriumColor=clrGray;        // Equilibrium Zone
input color InpDiscountColor=clrGreen;          // Discount Zone

//+------------------------------------------------------------------+
//| DATA STRUCTURES                                                    |
//+------------------------------------------------------------------+
struct PivotPoint { double currentLevel; double lastLevel; bool crossed; datetime barTime; int barIndex; };
struct OrderBlockData { double barHigh; double barLow; datetime barTime; int bias; };
struct FVGData { double top; double bottom; int bias; string topRect; string bottomRect; bool active; };
struct TrailingData { double top; double bottom; datetime barTime; int barIndex; datetime lastTopTime; datetime lastBottomTime; };

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                   |
//+------------------------------------------------------------------+
PivotPoint g_swingHigh, g_swingLow, g_internalHigh, g_internalLow, g_equalHigh, g_equalLow;
int g_swingTrendBias=0, g_internalTrendBias=0;
TrailingData g_trailing;
OrderBlockData g_swingOB[], g_internalOB[];
FVGData g_fvg[];
double g_parsedHighs[], g_parsedLows[], g_highs[], g_lows[];
datetime g_times[];
int g_objCount=0;
int g_atrHandle=INVALID_HANDLE;
double g_atrBuffer[];


//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                   |
//+------------------------------------------------------------------+
string ObjName(string prefix) { g_objCount++; return prefix+"_"+IntegerToString(g_objCount)+"_"+IntegerToString(GetTickCount()); }
ENUM_LINE_STYLE GetLS(ENUM_LINE_STYLE_INPUT s) { if(s==LINE_DASHED) return STYLE_DASH; if(s==LINE_DOTTED) return STYLE_DOT; return STYLE_SOLID; }
int GetFS(ENUM_LABEL_SIZE s) { if(s==LABEL_TINY) return 7; if(s==LABEL_SMALL) return 8; return 10; }
void InitPivot(PivotPoint &p) { p.currentLevel=0; p.lastLevel=0; p.crossed=false; p.barTime=0; p.barIndex=0; }
void InitTrailing(TrailingData &t) { t.top=0; t.bottom=DBL_MAX; t.barTime=0; t.barIndex=0; t.lastTopTime=0; t.lastBottomTime=0; }

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
void DrawRect(string &name, datetime t1, double p1, datetime t2, double p2, color clr, bool border)
{
   name=ObjName("SMC_R");
   ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,border?1:0);
}
void DrawOBBox(datetime t1, double hi, double lo, color clr, bool border)
{
   string n=ObjName("SMC_OB");
   ObjectCreate(0,n,OBJ_RECTANGLE,0,t1,hi,TimeCurrent(),lo);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_FILL,true);
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,border?1:0);
}
void DrawHLevel(datetime t1, double price, color clr, ENUM_LINE_STYLE_INPUT st, string lbl)
{
   string n=ObjName("SMC_HL");
   ObjectCreate(0,n,OBJ_TREND,0,t1,price,TimeCurrent(),price);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_STYLE,GetLS(st));
   ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,true);
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
   string n2=ObjName("SMC_HLT");
   ObjectCreate(0,n2,OBJ_TEXT,0,TimeCurrent(),price);
   ObjectSetString(0,n2,OBJPROP_TEXT,lbl);
   ObjectSetInteger(0,n2,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n2,OBJPROP_FONTSIZE,8);
}
void DrawZone(datetime t1, double top, double bot, color clr, string lbl)
{
   string n=ObjName("SMC_Z");
   ObjectCreate(0,n,OBJ_RECTANGLE,0,t1,top,TimeCurrent(),bot);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_FILL,true);
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,0);
   string n2=ObjName("SMC_ZT");
   datetime mt=(datetime)(((long)t1+(long)TimeCurrent())/2);
   ObjectCreate(0,n2,OBJ_TEXT,0,mt,(top+bot)/2.0);
   ObjectSetString(0,n2,OBJPROP_TEXT,lbl);
   ObjectSetInteger(0,n2,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n2,OBJPROP_FONTSIZE,8);
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
         g_trailing.top=pivotH.currentLevel;
         g_trailing.barTime=pivotH.barTime;
         g_trailing.barIndex=pivotH.barIndex;
         g_trailing.lastTopTime=pivotH.barTime;
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
         g_trailing.bottom=pivotL.currentLevel;
         g_trailing.barTime=pivotL.barTime;
         g_trailing.barIndex=pivotL.barIndex;
         g_trailing.lastBottomTime=pivotL.barTime;
         if(InpShowSwings)
         {
            string txt=(pivotL.currentLevel<pivotL.lastLevel && pivotL.lastLevel>0)?"LL":"HL";
            color c=(InpStyle==STYLE_MONOCHROME)?clrSilver:InpSwingBullColor;
            DrawText(time[pivotBar],low[pivotBar],txt,c,7,false);
         }
      }
   }
}

void StoreOB(PivotPoint &pivot, bool isInternal, int bias)
{
   int startIdx=pivot.barIndex;
   int endIdx=ArraySize(g_highs)-1;
   if(startIdx<0 || startIdx>=endIdx) return;
   int extremeIdx=startIdx;
   if(bias==BEARISH) { for(int i=startIdx;i<=endIdx;i++) if(g_parsedHighs[i]>g_parsedHighs[extremeIdx]) extremeIdx=i; }
   else { for(int i=startIdx;i<=endIdx;i++) if(g_parsedLows[i]<g_parsedLows[extremeIdx]) extremeIdx=i; }
   OrderBlockData ob;
   ob.barHigh=g_parsedHighs[extremeIdx]; ob.barLow=g_parsedLows[extremeIdx];
   ob.barTime=g_times[extremeIdx]; ob.bias=bias;
   if(isInternal) { int sz=ArraySize(g_internalOB); ArrayResize(g_internalOB,sz+1); for(int i=sz;i>0;i--) g_internalOB[i]=g_internalOB[i-1]; g_internalOB[0]=ob; if(ArraySize(g_internalOB)>100) ArrayResize(g_internalOB,100); }
   else { int sz=ArraySize(g_swingOB); ArrayResize(g_swingOB,sz+1); for(int i=sz;i>0;i--) g_swingOB[i]=g_swingOB[i-1]; g_swingOB[0]=ob; if(ArraySize(g_swingOB)>100) ArrayResize(g_swingOB,100); }
}

void ProcessStructure(int bar, const double &close[], const double &high[], const double &low[],
                      const double &open[], const datetime &time[],
                      PivotPoint &pivotH, PivotPoint &pivotL, int &trendBias, bool isInternal)
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
         if((isInternal&&InpShowInternalOB)||(!isInternal&&InpShowSwingOB)) StoreOB(pivotH,isInternal,BULLISH);
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
         if((isInternal&&InpShowInternalOB)||(!isInternal&&InpShowSwingOB)) StoreOB(pivotL,isInternal,BEARISH);
      }
   }
}

void MitigateOB(int bar, const double &close[], const double &high[], const double &low[], bool isInternal)
{
   OrderBlockData temp[];
   if(isInternal) ArrayCopy(temp,g_internalOB); else ArrayCopy(temp,g_swingOB);
   double bearSrc=(InpOBMitigation==OB_MIT_CLOSE)?close[bar]:high[bar];
   double bullSrc=(InpOBMitigation==OB_MIT_CLOSE)?close[bar]:low[bar];
   OrderBlockData kept[];
   int cnt=0;
   for(int i=0;i<ArraySize(temp);i++)
   {
      bool remove=false;
      if(temp[i].bias==BEARISH && bearSrc>temp[i].barHigh) remove=true;
      if(temp[i].bias==BULLISH && bullSrc<temp[i].barLow) remove=true;
      if(!remove) { ArrayResize(kept,cnt+1); kept[cnt]=temp[i]; cnt++; }
   }
   if(isInternal) { ArrayResize(g_internalOB,cnt); if(cnt>0) ArrayCopy(g_internalOB,kept); }
   else { ArrayResize(g_swingOB,cnt); if(cnt>0) ArrayCopy(g_swingOB,kept); }
}

void DetectFVG(int bar, const double &high[], const double &low[], const double &close[],
               const double &open[], const datetime &time[])
{
   if(bar<3) return;
   double lClose=close[bar-1], lOpen=open[bar-1], cLow=low[bar], cHigh=high[bar], h2=high[bar-2], l2=low[bar-2];
   double delta=(lOpen!=0)?(lClose-lOpen)/(lOpen*100):0;
   double thresh=0;
   if(InpFVGAutoThreshold && bar>1)
   {
      double sum=0; for(int i=1;i<bar;i++) if(open[i]!=0) sum+=MathAbs((close[i]-open[i])/(open[i]*100));
      thresh=(sum/(bar-1))*2;
   }
   int ps=PeriodSeconds();
   datetime endT=time[bar]+InpFVGExtend*ps;
   if(cLow>h2 && lClose>h2 && delta>thresh)
   {
      color c=(InpStyle==STYLE_MONOCHROME)?clrSilver:InpFVGBullColor;
      int sz=ArraySize(g_fvg); ArrayResize(g_fvg,sz+1);
      g_fvg[sz].top=cLow; g_fvg[sz].bottom=h2; g_fvg[sz].bias=BULLISH; g_fvg[sz].active=true;
      DrawRect(g_fvg[sz].topRect,time[bar-1],cLow,endT,(cLow+h2)/2,c,false);
      DrawRect(g_fvg[sz].bottomRect,time[bar-1],(cLow+h2)/2,endT,h2,c,false);
   }
   if(cHigh<l2 && lClose<l2 && -delta>thresh)
   {
      color c=(InpStyle==STYLE_MONOCHROME)?clrDimGray:InpFVGBearColor;
      int sz=ArraySize(g_fvg); ArrayResize(g_fvg,sz+1);
      g_fvg[sz].top=l2; g_fvg[sz].bottom=cHigh; g_fvg[sz].bias=BEARISH; g_fvg[sz].active=true;
      DrawRect(g_fvg[sz].topRect,time[bar-1],l2,endT,(l2+cHigh)/2,c,false);
      DrawRect(g_fvg[sz].bottomRect,time[bar-1],(l2+cHigh)/2,endT,cHigh,c,false);
   }
}

void MitigateFVG(int bar, const double &high[], const double &low[])
{
   for(int i=ArraySize(g_fvg)-1;i>=0;i--)
   {
      if(!g_fvg[i].active) continue;
      if((g_fvg[i].bias==BULLISH && low[bar]<g_fvg[i].bottom)||(g_fvg[i].bias==BEARISH && high[bar]>g_fvg[i].top))
      { ObjectDelete(0,g_fvg[i].topRect); ObjectDelete(0,g_fvg[i].bottomRect); g_fvg[i].active=false; }
   }
}


//+------------------------------------------------------------------+
//| DYNAMIC DRAWING (last bar only)                                    |
//+------------------------------------------------------------------+
void DrawOrderBlocks()
{
   if(InpShowInternalOB)
   {
      int cnt=MathMin(InpInternalOBSize,ArraySize(g_internalOB));
      for(int i=0;i<cnt;i++)
      {
         color c=(InpStyle==STYLE_MONOCHROME)?((g_internalOB[i].bias==BEARISH)?clrDimGray:clrSilver):((g_internalOB[i].bias==BEARISH)?InpIntBearOBColor:InpIntBullOBColor);
         DrawOBBox(g_internalOB[i].barTime,g_internalOB[i].barHigh,g_internalOB[i].barLow,c,false);
      }
   }
   if(InpShowSwingOB)
   {
      int cnt=MathMin(InpSwingOBSize,ArraySize(g_swingOB));
      for(int i=0;i<cnt;i++)
      {
         color c=(InpStyle==STYLE_MONOCHROME)?((g_swingOB[i].bias==BEARISH)?clrDimGray:clrSilver):((g_swingOB[i].bias==BEARISH)?InpSwingBearOBColor:InpSwingBullOBColor);
         DrawOBBox(g_swingOB[i].barTime,g_swingOB[i].barHigh,g_swingOB[i].barLow,c,true);
      }
   }
}

void DrawStrongWeakHL()
{
   if(g_trailing.top<=0 || g_trailing.bottom>=DBL_MAX) return;
   color topC=(InpStyle==STYLE_MONOCHROME)?clrDimGray:InpSwingBearColor;
   color botC=(InpStyle==STYLE_MONOCHROME)?clrSilver:InpSwingBullColor;
   string topTxt=(g_swingTrendBias==BEARISH)?"Strong High":"Weak High";
   string botTxt=(g_swingTrendBias==BULLISH)?"Strong Low":"Weak Low";
   string n1=ObjName("SMC_SH"); ObjectCreate(0,n1,OBJ_TREND,0,g_trailing.lastTopTime,g_trailing.top,TimeCurrent(),g_trailing.top);
   ObjectSetInteger(0,n1,OBJPROP_COLOR,topC); ObjectSetInteger(0,n1,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,n1,OBJPROP_BACK,true);
   DrawText(TimeCurrent(),g_trailing.top,topTxt,topC,7,true);
   string n2=ObjName("SMC_SL"); ObjectCreate(0,n2,OBJ_TREND,0,g_trailing.lastBottomTime,g_trailing.bottom,TimeCurrent(),g_trailing.bottom);
   ObjectSetInteger(0,n2,OBJPROP_COLOR,botC); ObjectSetInteger(0,n2,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,n2,OBJPROP_BACK,true);
   DrawText(TimeCurrent(),g_trailing.bottom,botTxt,botC,7,false);
}

void DrawPDZones()
{
   if(g_trailing.top<=0 || g_trailing.bottom>=DBL_MAX || g_trailing.top<=g_trailing.bottom) return;
   double rng=g_trailing.top-g_trailing.bottom;
   color premC=(InpStyle==STYLE_MONOCHROME)?clrDimGray:InpPremiumColor;
   color discC=(InpStyle==STYLE_MONOCHROME)?clrSilver:InpDiscountColor;
   DrawZone(g_trailing.barTime, g_trailing.top, g_trailing.top-0.05*rng, premC, "Premium");
   DrawZone(g_trailing.barTime, g_trailing.bottom+0.525*rng, g_trailing.bottom+0.475*rng, InpEquilibriumColor, "Equilibrium");
   DrawZone(g_trailing.barTime, g_trailing.bottom+0.05*rng, g_trailing.bottom, discC, "Discount");
}

void DrawMTFLevels(ENUM_TIMEFRAMES tf, ENUM_LINE_STYLE_INPUT st, color clr, string prefix)
{
   if((int)Period()>=(int)tf && tf!=PERIOD_CURRENT) return;
   int shift=iBarShift(Symbol(),tf,TimeCurrent(),true);
   if(shift<1) shift=1;
   double h=iHigh(Symbol(),tf,shift);
   double l=iLow(Symbol(),tf,shift);
   datetime t=iTime(Symbol(),tf,shift);
   if(h>0 && l>0) { DrawHLevel(t,h,clr,st,"P"+prefix+"H"); DrawHLevel(t,l,clr,st,"P"+prefix+"L"); }
}

void CleanDynamic()
{
   int total=ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--)
   {
      string n=ObjectName(0,i);
      if(StringFind(n,"SMC_OB")==0||StringFind(n,"SMC_SH")==0||StringFind(n,"SMC_SL")==0||
         StringFind(n,"SMC_Z")==0||StringFind(n,"SMC_ZT")==0||StringFind(n,"SMC_HL")==0||StringFind(n,"SMC_HLT")==0)
         ObjectDelete(0,n);
   }
}

void CleanAll()
{
   int total=ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;i--) { string n=ObjectName(0,i); if(StringFind(n,"SMC_")==0) ObjectDelete(0,n); }
}

//+------------------------------------------------------------------+
//| INDICATOR EVENT HANDLERS                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   InitPivot(g_swingHigh); InitPivot(g_swingLow);
   InitPivot(g_internalHigh); InitPivot(g_internalLow);
   InitPivot(g_equalHigh); InitPivot(g_equalLow);
   InitTrailing(g_trailing);
   g_swingTrendBias=0; g_internalTrendBias=0;
   g_atrHandle=iATR(Symbol(),Period(),200);
   if(g_atrHandle==INVALID_HANDLE) { Print("ATR handle failed"); return(INIT_FAILED); }
   g_objCount=0;
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   CleanAll();
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

   int startBar=prev_calculated;
   if(startBar==0)
   {
      CleanAll();
      InitPivot(g_swingHigh); InitPivot(g_swingLow);
      InitPivot(g_internalHigh); InitPivot(g_internalLow);
      InitPivot(g_equalHigh); InitPivot(g_equalLow);
      InitTrailing(g_trailing);
      g_swingTrendBias=0; g_internalTrendBias=0;
      ArrayResize(g_swingOB,0); ArrayResize(g_internalOB,0); ArrayResize(g_fvg,0);
      ArrayResize(g_parsedHighs,0); ArrayResize(g_parsedLows,0);
      ArrayResize(g_highs,0); ArrayResize(g_lows,0); ArrayResize(g_times,0);
      g_objCount=0;
      startBar=InpSwingsLength+5;
   }
   else
   {
      startBar=MathMax(prev_calculated-2,InpSwingsLength+5);
      CleanDynamic();
   }

   // Copy ATR
   ArrayResize(g_atrBuffer,rates_total);
   if(CopyBuffer(g_atrHandle,0,0,rates_total,g_atrBuffer)<=0) return(0);
   ArraySetAsSeries(g_atrBuffer,false);

   // Build helper arrays
   ArrayResize(g_parsedHighs,rates_total);
   ArrayResize(g_parsedLows,rates_total);
   ArrayResize(g_highs,rates_total);
   ArrayResize(g_lows,rates_total);
   ArrayResize(g_times,rates_total);
   for(int i=0;i<rates_total;i++)
   {
      g_highs[i]=high[i]; g_lows[i]=low[i]; g_times[i]=time[i];
      double vol=(InpOBFilter==OB_FILTER_ATR)?g_atrBuffer[i]:0;
      if(InpOBFilter==OB_FILTER_RANGE && i>0) { double s=0; for(int j=1;j<=i;j++) s+=MathMax(high[j]-low[j],MathMax(MathAbs(high[j]-close[j-1]),MathAbs(low[j]-close[j-1]))); vol=s/i; }
      bool hvb=(high[i]-low[i])>=(2.0*vol) && vol>0;
      g_parsedHighs[i]=hvb?low[i]:high[i];
      g_parsedLows[i]=hvb?high[i]:low[i];
   }

   // Main loop
   for(int bar=startBar;bar<rates_total;bar++)
   {
      double atr=g_atrBuffer[bar];
      DetectSwings(bar,InpSwingsLength,high,low,time,g_swingHigh,g_swingLow,false,false,atr);
      DetectSwings(bar,5,high,low,time,g_internalHigh,g_internalLow,true,false,atr);
      if(InpShowEQHL) DetectSwings(bar,InpEQHLLength,high,low,time,g_equalHigh,g_equalLow,false,true,atr);
      if(InpShowInternals||InpShowInternalOB||InpShowTrend)
         ProcessStructure(bar,close,high,low,open,time,g_internalHigh,g_internalLow,g_internalTrendBias,true);
      if(InpShowStructure||InpShowSwingOB||InpShowHighLowSwings)
         ProcessStructure(bar,close,high,low,open,time,g_swingHigh,g_swingLow,g_swingTrendBias,false);
      if(InpShowInternalOB) MitigateOB(bar,close,high,low,true);
      if(InpShowSwingOB) MitigateOB(bar,close,high,low,false);
      if(InpShowHighLowSwings||InpShowPDZones)
      {
         if(high[bar]>g_trailing.top||g_trailing.top<=0) { g_trailing.top=high[bar]; g_trailing.lastTopTime=time[bar]; }
         if(low[bar]<g_trailing.bottom||g_trailing.bottom>=DBL_MAX) { g_trailing.bottom=low[bar]; g_trailing.lastBottomTime=time[bar]; }
      }
      if(InpShowFVG) { MitigateFVG(bar,high,low); DetectFVG(bar,high,low,close,open,time); }
   }

   // Draw dynamic elements
   DrawOrderBlocks();
   if(InpShowHighLowSwings) DrawStrongWeakHL();
   if(InpShowPDZones) DrawPDZones();
   if(InpShowDaily) DrawMTFLevels(PERIOD_D1,InpDailyStyle,InpDailyColor,"D");
   if(InpShowWeekly) DrawMTFLevels(PERIOD_W1,InpWeeklyStyle,InpWeeklyColor,"W");
   if(InpShowMonthly) DrawMTFLevels(PERIOD_MN1,InpMonthlyStyle,InpMonthlyColor,"M");

   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
