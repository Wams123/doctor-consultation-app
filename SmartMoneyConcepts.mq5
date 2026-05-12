//+------------------------------------------------------------------+
//|                                       SmartMoneyConcepts.mq5      |
//|        Based on Smart Money Concepts [LuxAlgo] - MT5 Port         |
//|        With EA-readable output buffers for BOS/CHoCH signals      |
//+------------------------------------------------------------------+
#property copyright "Converted from LuxAlgo SMC (CC BY-NC-SA 4.0)"
#property link      "https://creativecommons.org/licenses/by-nc-sa/4.0/"
#property version   "2.00"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Buffer Layout for EA (via iCustom):                              |
//|  Buffer 0: InternalSignal  (+1=bullBOS/CHoCH, -1=bearBOS/CHoCH) |
//|  Buffer 1: InternalTag     (1=BOS, 2=CHoCH, 0=none)             |
//|  Buffer 2: SeqLow          (lowest low of BOS/CHoCH leg for SL)  |
//|  Buffer 3: SeqHigh         (highest high of BOS/CHoCH leg for SL)|
//|  Buffer 4: SwingHigh       (current major swing high for TP)     |
//|  Buffer 5: SwingLow        (current major swing low for TP)      |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                       |
//+------------------------------------------------------------------+
enum ENUM_STYLE_THEME     { STYLE_COLORED=0, STYLE_MONOCHROME=1 };
enum ENUM_STRUCTURE_FILTER{ FILTER_ALL=0, FILTER_BOS=1, FILTER_CHOCH=2 };
enum ENUM_LABEL_SIZE      { LABEL_TINY=0, LABEL_SMALL=1, LABEL_NORMAL=2 };

#define BULLISH  +1
#define BEARISH  -1

//+------------------------------------------------------------------+
//| INPUTS                                                             |
//+------------------------------------------------------------------+
input string sep0="=== Smart Money Concepts ===";
input ENUM_STYLE_THEME InpStyle=STYLE_COLORED;           // Style

input string sep1="=== Internal Structure ===";
input bool InpShowInternals=true;                        // Show Internal Structure
input ENUM_STRUCTURE_FILTER InpInternalBull=FILTER_ALL;  // Bullish Internal Filter
input color InpInternalBullColor=clrGreen;               // Bullish Internal Color
input ENUM_STRUCTURE_FILTER InpInternalBear=FILTER_ALL;  // Bearish Internal Filter
input color InpInternalBearColor=clrRed;                 // Bearish Internal Color
input bool InpConfluenceFilter=false;                    // Confluence Filter
input ENUM_LABEL_SIZE InpInternalLabelSize=LABEL_TINY;   // Internal Label Size
input int  InpInternalLength=5;                          // Internal Swing Length

input string sep2="=== Swing Structure ===";
input bool InpShowStructure=true;                        // Show Swing Structure
input ENUM_STRUCTURE_FILTER InpSwingBull=FILTER_ALL;     // Bullish Swing Filter
input color InpSwingBullColor=clrGreen;                  // Bullish Swing Color
input ENUM_STRUCTURE_FILTER InpSwingBear=FILTER_ALL;     // Bearish Swing Filter
input color InpSwingBearColor=clrRed;                    // Bearish Swing Color
input ENUM_LABEL_SIZE InpSwingLabelSize=LABEL_SMALL;     // Swing Label Size
input bool InpShowSwings=false;                          // Show Swing Labels (HH/HL/LH/LL)
input int  InpSwingsLength=50;                           // Swing Length
input bool InpShowHighLowSwings=true;                    // Show Strong/Weak HL

input string sep3="=== Equal Highs/Lows ===";
input bool InpShowEQHL=true;                             // Show EQH/EQL
input int  InpEQHLLength=3;                              // EQ Bars Confirmation
input double InpEQHLThreshold=0.1;                       // EQ Threshold (ATR mult)
input ENUM_LABEL_SIZE InpEQHLLabelSize=LABEL_TINY;       // EQ Label Size

//+------------------------------------------------------------------+
//| DATA STRUCTURES                                                    |
//+------------------------------------------------------------------+
struct PivotPoint
{
   double   currentLevel;
   double   lastLevel;
   bool     crossed;
   datetime barTime;
   int      barIndex;
};

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS                                                  |
//+------------------------------------------------------------------+
double BufSignal[];    // 0
double BufTag[];       // 1
double BufSeqLow[];    // 2
double BufSeqHigh[];   // 3
double BufSwingHigh[]; // 4
double BufSwingLow[];  // 5

//+------------------------------------------------------------------+
//| GLOBALS                                                            |
//+------------------------------------------------------------------+
PivotPoint g_swingHigh, g_swingLow;
PivotPoint g_internalHigh, g_internalLow;
PivotPoint g_equalHigh, g_equalLow;
int g_swingTrendBias=0, g_internalTrendBias=0;
double g_curSwingHigh=0, g_curSwingLow=0;
int g_atrHandle=INVALID_HANDLE;
double g_atrBuffer[];
int g_objCount=0;

//+------------------------------------------------------------------+
//| HELPERS                                                            |
//+------------------------------------------------------------------+
string ObjName(string prefix)
{
   g_objCount++;
   return prefix+"_"+IntegerToString(g_objCount)+"_"+IntegerToString(GetTickCount());
}

int GetFS(ENUM_LABEL_SIZE s)
{
   if(s==LABEL_TINY) return 7;
   if(s==LABEL_SMALL) return 8;
   return 10;
}

void InitPivot(PivotPoint &p)
{
   p.currentLevel=0; p.lastLevel=0; p.crossed=false; p.barTime=0; p.barIndex=0;
}



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
//| DETECT SWING PIVOTS                                                |
//+------------------------------------------------------------------+
void DetectSwings(int bar, int size, const double &high[], const double &low[],
                  const datetime &time[], PivotPoint &pivotH, PivotPoint &pivotL,
                  bool isInternal, bool isEqualHL, double atr)
{
   if(bar < size*2) return;
   int pivotBar = bar - size;
   if(pivotBar < size) return;

   bool isSH=true, isSL=true;
   int checkStart = MathMax(0, pivotBar-size);
   int checkEnd   = MathMin(bar, (int)ArraySize(high)-1);

   for(int i=checkStart; i<=checkEnd; i++)
   {
      if(i==pivotBar) continue;
      if(high[i] > high[pivotBar]) isSH=false;
      if(low[i]  < low[pivotBar])  isSL=false;
   }

   // Swing High detected
   if(isSH && high[pivotBar] != pivotH.currentLevel)
   {
      // Equal Highs detection
      if(isEqualHL && InpShowEQHL && pivotH.currentLevel>0 && atr>0)
      {
         if(MathAbs(pivotH.currentLevel - high[pivotBar]) < InpEQHLThreshold*atr)
         {
            color c = (InpStyle==STYLE_MONOCHROME) ? clrDimGray : InpSwingBearColor;
            string n = ObjName("SMC_EQ");
            ObjectCreate(0,n,OBJ_TREND,0,pivotH.barTime,pivotH.currentLevel,time[pivotBar],high[pivotBar]);
            ObjectSetInteger(0,n,OBJPROP_COLOR,c);
            ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DOT);
            ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
            ObjectSetInteger(0,n,OBJPROP_BACK,true);
            datetime mt = (datetime)(((long)pivotH.barTime+(long)time[pivotBar])/2);
            DrawText(mt, high[pivotBar], "EQH", c, GetFS(InpEQHLLabelSize), true);
         }
      }

      pivotH.lastLevel    = pivotH.currentLevel;
      pivotH.currentLevel = high[pivotBar];
      pivotH.crossed      = false;
      pivotH.barTime      = time[pivotBar];
      pivotH.barIndex     = pivotBar;

      // Update swing high for TP (only major swings)
      if(!isEqualHL && !isInternal)
      {
         g_curSwingHigh = pivotH.currentLevel;
         if(InpShowSwings)
         {
            string txt = (pivotH.currentLevel>pivotH.lastLevel && pivotH.lastLevel>0) ? "HH" : "LH";
            color c = (InpStyle==STYLE_MONOCHROME) ? clrDimGray : InpSwingBearColor;
            DrawText(time[pivotBar], high[pivotBar], txt, c, 7, true);
         }
      }
   }

   // Swing Low detected
   if(isSL && low[pivotBar] != pivotL.currentLevel)
   {
      // Equal Lows detection
      if(isEqualHL && InpShowEQHL && pivotL.currentLevel>0 && atr>0)
      {
         if(MathAbs(pivotL.currentLevel - low[pivotBar]) < InpEQHLThreshold*atr)
         {
            color c = (InpStyle==STYLE_MONOCHROME) ? clrSilver : InpSwingBullColor;
            string n = ObjName("SMC_EQ");
            ObjectCreate(0,n,OBJ_TREND,0,pivotL.barTime,pivotL.currentLevel,time[pivotBar],low[pivotBar]);
            ObjectSetInteger(0,n,OBJPROP_COLOR,c);
            ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_DOT);
            ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
            ObjectSetInteger(0,n,OBJPROP_BACK,true);
            datetime mt = (datetime)(((long)pivotL.barTime+(long)time[pivotBar])/2);
            DrawText(mt, low[pivotBar], "EQL", c, GetFS(InpEQHLLabelSize), false);
         }
      }

      pivotL.lastLevel    = pivotL.currentLevel;
      pivotL.currentLevel = low[pivotBar];
      pivotL.crossed      = false;
      pivotL.barTime      = time[pivotBar];
      pivotL.barIndex     = pivotBar;

      // Update swing low for TP (only major swings)
      if(!isEqualHL && !isInternal)
      {
         g_curSwingLow = pivotL.currentLevel;
         if(InpShowSwings)
         {
            string txt = (pivotL.currentLevel<pivotL.lastLevel && pivotL.lastLevel>0) ? "LL" : "HL";
            color c = (InpStyle==STYLE_MONOCHROME) ? clrSilver : InpSwingBullColor;
            DrawText(time[pivotBar], low[pivotBar], txt, c, 7, false);
         }
      }
   }
}



//+------------------------------------------------------------------+
//| PROCESS STRUCTURE (BOS / CHoCH detection)                         |
//| Outputs signal data for the EA buffers                            |
//+------------------------------------------------------------------+
void ProcessStructure(int bar, const double &close[], const double &high[],
                      const double &low[], const double &open[],
                      const datetime &time[],
                      PivotPoint &pivotH, PivotPoint &pivotL,
                      int &trendBias, bool isInternal,
                      double &outSignal, double &outTag,
                      double &outSeqLow, double &outSeqHigh)
{
   color bullC = (InpStyle==STYLE_MONOCHROME) ? clrSilver :
                 (isInternal ? InpInternalBullColor : InpSwingBullColor);
   color bearC = (InpStyle==STYLE_MONOCHROME) ? clrDimGray :
                 (isInternal ? InpInternalBearColor : InpSwingBearColor);
   ENUM_LINE_STYLE ls = isInternal ? STYLE_DASH : STYLE_SOLID;
   ENUM_LABEL_SIZE labelSz = isInternal ? InpInternalLabelSize : InpSwingLabelSize;

   // Confluence filter (internal only)
   bool cfBull=true, cfBear=true;
   if(InpConfluenceFilter && isInternal)
   {
      double upperWick = high[bar] - MathMax(close[bar], open[bar]);
      double lowerWick = MathMin(close[bar], open[bar]) - low[bar];
      cfBull = (upperWick > lowerWick);
      cfBear = (upperWick < lowerWick);
   }

   //--- BULLISH BREAK (close crosses above pivot high)
   bool extraBull = isInternal ? (pivotH.currentLevel != g_swingHigh.currentLevel && cfBull) : true;
   if(pivotH.currentLevel > 0 && !pivotH.crossed && extraBull)
   {
      if(bar > 0 && close[bar] > pivotH.currentLevel && close[bar-1] <= pivotH.currentLevel)
      {
         string tag = (trendBias == BEARISH) ? "CHoCH" : "BOS";
         pivotH.crossed = true;
         trendBias = BULLISH;

         // Drawing
         bool show = false;
         if(isInternal)
            show = InpShowInternals && (InpInternalBull==FILTER_ALL ||
                   (InpInternalBull==FILTER_BOS && tag=="BOS") ||
                   (InpInternalBull==FILTER_CHOCH && tag=="CHoCH"));
         else
            show = InpShowStructure && (InpSwingBull==FILTER_ALL ||
                   (InpSwingBull==FILTER_BOS && tag=="BOS") ||
                   (InpSwingBull==FILTER_CHOCH && tag=="CHoCH"));

         if(show)
         {
            DrawLine(pivotH.barTime, time[bar], pivotH.currentLevel, bullC, ls);
            datetime mt = (datetime)(((long)pivotH.barTime + (long)time[bar]) / 2);
            DrawText(mt, pivotH.currentLevel, tag, bullC, GetFS(labelSz), true);
         }

         // EA output: internal structure only
         if(isInternal)
         {
            outSignal = +1.0;
            outTag    = (tag=="CHoCH") ? 2.0 : 1.0;
            // Sequence low = lowest low from pivot bar to break bar
            double lo = low[pivotH.barIndex];
            for(int k = pivotH.barIndex; k <= bar; k++)
               if(low[k] < lo) lo = low[k];
            outSeqLow  = lo;
            outSeqHigh = high[pivotH.barIndex];
            for(int k = pivotH.barIndex; k <= bar; k++)
               if(high[k] > outSeqHigh) outSeqHigh = high[k];
         }
      }
   }

   //--- BEARISH BREAK (close crosses below pivot low)
   bool extraBear = isInternal ? (pivotL.currentLevel != g_swingLow.currentLevel && cfBear) : true;
   if(pivotL.currentLevel > 0 && !pivotL.crossed && extraBear)
   {
      if(bar > 0 && close[bar] < pivotL.currentLevel && close[bar-1] >= pivotL.currentLevel)
      {
         string tag = (trendBias == BULLISH) ? "CHoCH" : "BOS";
         pivotL.crossed = true;
         trendBias = BEARISH;

         // Drawing
         bool show = false;
         if(isInternal)
            show = InpShowInternals && (InpInternalBear==FILTER_ALL ||
                   (InpInternalBear==FILTER_BOS && tag=="BOS") ||
                   (InpInternalBear==FILTER_CHOCH && tag=="CHoCH"));
         else
            show = InpShowStructure && (InpSwingBear==FILTER_ALL ||
                   (InpSwingBear==FILTER_BOS && tag=="BOS") ||
                   (InpSwingBear==FILTER_CHOCH && tag=="CHoCH"));

         if(show)
         {
            DrawLine(pivotL.barTime, time[bar], pivotL.currentLevel, bearC, ls);
            datetime mt = (datetime)(((long)pivotL.barTime + (long)time[bar]) / 2);
            DrawText(mt, pivotL.currentLevel, tag, bearC, GetFS(labelSz), false);
         }

         // EA output: internal structure only
         if(isInternal)
         {
            outSignal = -1.0;
            outTag    = (tag=="CHoCH") ? 2.0 : 1.0;
            // Sequence high = highest high from pivot bar to break bar
            double hi = high[pivotL.barIndex];
            for(int k = pivotL.barIndex; k <= bar; k++)
               if(high[k] > hi) hi = high[k];
            outSeqHigh = hi;
            outSeqLow  = low[pivotL.barIndex];
            for(int k = pivotL.barIndex; k <= bar; k++)
               if(low[k] < outSeqLow) outSeqLow = low[k];
         }
      }
   }
}



//+------------------------------------------------------------------+
//| INDICATOR EVENT HANDLERS                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufSignal,    INDICATOR_DATA);
   SetIndexBuffer(1, BufTag,       INDICATOR_DATA);
   SetIndexBuffer(2, BufSeqLow,    INDICATOR_DATA);
   SetIndexBuffer(3, BufSeqHigh,   INDICATOR_DATA);
   SetIndexBuffer(4, BufSwingHigh, INDICATOR_DATA);
   SetIndexBuffer(5, BufSwingLow,  INDICATOR_DATA);

   // Set all plots to hidden (no visual drawing from buffers - we draw objects instead)
   // No indicator_plots so nothing renders from buffers visually

   InitPivot(g_swingHigh); InitPivot(g_swingLow);
   InitPivot(g_internalHigh); InitPivot(g_internalLow);
   InitPivot(g_equalHigh); InitPivot(g_equalLow);
   g_swingTrendBias = 0;
   g_internalTrendBias = 0;
   g_curSwingHigh = 0;
   g_curSwingLow = 0;
   g_objCount = 0;

   g_atrHandle = iATR(_Symbol, _Period, 200);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("SMC: ATR handle failed");
      return(INIT_FAILED);
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "SMC("+IntegerToString(InpInternalLength)+
                      ","+IntegerToString(InpSwingsLength)+")");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean all SMC objects
   int total = ObjectsTotal(0, 0, -1);
   for(int i=total-1; i>=0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, "SMC_") == 0)
         ObjectDelete(0, n);
   }
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
}

//+------------------------------------------------------------------+
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
   if(rates_total < InpSwingsLength + 10) return(0);

   ArraySetAsSeries(BufSignal,    false);
   ArraySetAsSeries(BufTag,       false);
   ArraySetAsSeries(BufSeqLow,    false);
   ArraySetAsSeries(BufSeqHigh,   false);
   ArraySetAsSeries(BufSwingHigh, false);
   ArraySetAsSeries(BufSwingLow,  false);

   int startBar = prev_calculated;
   if(startBar == 0)
   {
      // Clean objects on full recalc
      int total = ObjectsTotal(0, 0, -1);
      for(int i=total-1; i>=0; i--)
      {
         string n = ObjectName(0, i);
         if(StringFind(n, "SMC_") == 0) ObjectDelete(0, n);
      }

      InitPivot(g_swingHigh); InitPivot(g_swingLow);
      InitPivot(g_internalHigh); InitPivot(g_internalLow);
      InitPivot(g_equalHigh); InitPivot(g_equalLow);
      g_swingTrendBias = 0;
      g_internalTrendBias = 0;
      g_curSwingHigh = 0;
      g_curSwingLow = 0;
      g_objCount = 0;

      // Zero all buffers
      for(int i=0; i<rates_total; i++)
      {
         BufSignal[i]=0; BufTag[i]=0;
         BufSeqLow[i]=0; BufSeqHigh[i]=0;
         BufSwingHigh[i]=0; BufSwingLow[i]=0;
      }
      startBar = InpSwingsLength + 5;
   }
   else
   {
      startBar = MathMax(prev_calculated - 2, InpSwingsLength + 5);
   }

   // Copy ATR
   ArrayResize(g_atrBuffer, rates_total);
   ArraySetAsSeries(g_atrBuffer, false);
   if(CopyBuffer(g_atrHandle, 0, 0, rates_total, g_atrBuffer) <= 0) return(0);

   // Main calculation loop
   for(int bar = startBar; bar < rates_total; bar++)
   {
      double atr = g_atrBuffer[bar];

      // Detect major swing pivots (for TP targets)
      DetectSwings(bar, InpSwingsLength, high, low, time,
                   g_swingHigh, g_swingLow, false, false, atr);

      // Detect internal swing pivots (for BOS/CHoCH triggers)
      DetectSwings(bar, InpInternalLength, high, low, time,
                   g_internalHigh, g_internalLow, true, false, atr);

      // Equal Highs/Lows
      if(InpShowEQHL)
         DetectSwings(bar, InpEQHLLength, high, low, time,
                      g_equalHigh, g_equalLow, false, true, atr);

      // Process internal structure (BOS/CHoCH) - outputs to EA buffers
      double sig=0, tag=0, seqLo=0, seqHi=0;
      if(InpShowInternals)
         ProcessStructure(bar, close, high, low, open, time,
                          g_internalHigh, g_internalLow, g_internalTrendBias,
                          true, sig, tag, seqLo, seqHi);

      // Process swing structure (visual only, no EA output)
      double dS=0, dT=0, dL=0, dH=0;
      if(InpShowStructure || InpShowHighLowSwings)
         ProcessStructure(bar, close, high, low, open, time,
                          g_swingHigh, g_swingLow, g_swingTrendBias,
                          false, dS, dT, dL, dH);

      // Fill output buffers
      BufSignal[bar]    = sig;
      BufTag[bar]       = tag;
      BufSeqLow[bar]    = seqLo;
      BufSeqHigh[bar]   = seqHi;
      BufSwingHigh[bar] = g_curSwingHigh;
      BufSwingLow[bar]  = g_curSwingLow;
   }

   ChartRedraw(0);
   return(rates_total);
}
//+------------------------------------------------------------------+
