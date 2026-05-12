//+------------------------------------------------------------------+
//|                                                   HalfTrend.mq5  |
//|           Ported from Pine Script (Alex Orekhov / everget)        |
//|           MT5 Indicator with EA-consumable buffers                |
//+------------------------------------------------------------------+
#property copyright "Ported from everget HalfTrend"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   5

//--- Plot 1: HalfTrend line
#property indicator_label1  "HalfTrend"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue,clrCrimson
#property indicator_width1  2

//--- Plot 2: ATR High channel
#property indicator_label2  "ATR High"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrCrimson
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- Plot 3: ATR Low channel
#property indicator_label3  "ATR Low"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

//--- Plot 4: Buy arrow
#property indicator_label4  "Buy Signal"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrDodgerBlue
#property indicator_width4  2

//--- Plot 5: Sell arrow
#property indicator_label5  "Sell Signal"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrCrimson
#property indicator_width5  2

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Calculation ==="
input int    InpAmplitude        = 2;     // Amplitude
input int    InpChannelDeviation = 2;     // Channel Deviation

input group "=== Visuals ==="
input bool   InpShowArrows       = true;  // Show Arrows
input bool   InpShowChannels     = true;  // Show Channels

//+------------------------------------------------------------------+
//| Buffer indices (for EA consumption via iCustom)                  |
//|                                                                   |
//|  Buffer 0: HalfTrend line value (price level)                    |
//|  Buffer 1: HalfTrend color index (0=Bull, 1=Bear)                |
//|  Buffer 2: ATR High channel value                                |
//|  Buffer 3: ATR Low channel value                                 |
//|  Buffer 4: Buy arrow price (!=0 -> buy signal on this bar)       |
//|  Buffer 5: Sell arrow price (!=0 -> sell signal on this bar)     |
//|  Buffer 6: Trend direction (0=Bull, 1=Bear)   <- FOR EA          |
//|  Buffer 7: Signal flag (+1=Buy, -1=Sell, 0=None)   <- FOR EA     |
//+------------------------------------------------------------------+
double HtLineBuffer[];
double HtColorBuffer[];
double AtrHighBuffer[];
double AtrLowBuffer[];
double BuyArrowBuffer[];
double SellArrowBuffer[];
double TrendBuffer[];
double SignalBuffer[];

int g_atrHandle;

//--- persistent HalfTrend state (carried across bars)
double g_maxLowPrice  = 0;
double g_minHighPrice = 0;
int    g_nextTrend    = 0;
double g_up           = 0;
double g_down         = 0;
int    g_lastCalcBar  = -1;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpAmplitude < 1)
   {
      Print("HalfTrend: Amplitude must be >= 1");
      return(INIT_PARAMETERS_INCORRECT);
   }

   SetIndexBuffer(0, HtLineBuffer,    INDICATOR_DATA);
   SetIndexBuffer(1, HtColorBuffer,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, AtrHighBuffer,   INDICATOR_DATA);
   SetIndexBuffer(3, AtrLowBuffer,    INDICATOR_DATA);
   SetIndexBuffer(4, BuyArrowBuffer,  INDICATOR_DATA);
   SetIndexBuffer(5, SellArrowBuffer, INDICATOR_DATA);
   SetIndexBuffer(6, TrendBuffer,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, SignalBuffer,    INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(3, PLOT_ARROW, 233);
   PlotIndexSetInteger(4, PLOT_ARROW, 234);

   for(int p=0; p<=5; p++) PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, 0.0);

   g_atrHandle = iATR(_Symbol, _Period, 100);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("HalfTrend: Failed to create ATR handle");
      return(INIT_FAILED);
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "HalfTrend("+
                      IntegerToString(InpAmplitude)+","+
                      IntegerToString(InpChannelDeviation)+")");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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
   int minBars = MathMax(100, InpAmplitude) + 2;
   if(rates_total < minBars) return(0);

   double atrData[];
   ArraySetAsSeries(atrData, false);
   if(CopyBuffer(g_atrHandle, 0, 0, rates_total, atrData) <= 0) return(0);

   ArraySetAsSeries(HtLineBuffer,    false);
   ArraySetAsSeries(HtColorBuffer,   false);
   ArraySetAsSeries(AtrHighBuffer,   false);
   ArraySetAsSeries(AtrLowBuffer,    false);
   ArraySetAsSeries(BuyArrowBuffer,  false);
   ArraySetAsSeries(SellArrowBuffer, false);
   ArraySetAsSeries(TrendBuffer,     false);
   ArraySetAsSeries(SignalBuffer,    false);

   int start;
   if(prev_calculated == 0)
   {
      start = minBars;
      for(int i=0; i<start; i++)
      {
         HtLineBuffer[i]=0; HtColorBuffer[i]=0;
         AtrHighBuffer[i]=0; AtrLowBuffer[i]=0;
         BuyArrowBuffer[i]=0; SellArrowBuffer[i]=0;
         TrendBuffer[i]=0; SignalBuffer[i]=0;
      }
      TrendBuffer[start-1]  = 0;
      HtLineBuffer[start-1] = low[start-1];
      HtColorBuffer[start-1]= 0;

      g_nextTrend    = 0;
      g_maxLowPrice  = low[start-1];
      g_minHighPrice = high[start-1];
      g_up           = low[start-1];
      g_down         = high[start-1];
      g_lastCalcBar  = start-1;
   }
   else
   {
      start = prev_calculated - 1;
   }

   for(int i=start; i<rates_total; i++)
   {
      BuyArrowBuffer[i]=0; SellArrowBuffer[i]=0; SignalBuffer[i]=0;

      double atr2 = (atrData[i]>0) ? atrData[i]/2.0 : 0.0;
      double dev  = InpChannelDeviation * atr2;

      double highPrice = high[i];
      double lowPrice  = low[i];
      for(int j=1; j<InpAmplitude; j++)
      {
         if(i-j >= 0)
         {
            if(high[i-j] > highPrice) highPrice = high[i-j];
            if(low[i-j]  < lowPrice)  lowPrice  = low[i-j];
         }
      }

      double highma=0, lowma=0;
      int cnt=0;
      for(int j=0; j<InpAmplitude; j++)
      {
         if(i-j>=0)
         {
            highma += high[i-j];
            lowma  += low[i-j];
            cnt++;
         }
      }
      if(cnt>0) { highma/=cnt; lowma/=cnt; }

      double prevTrend  = (i>0) ? TrendBuffer[i-1]   : 0;
      double prevLow1   = (i>0) ? low[i-1]           : low[i];
      double prevHigh1  = (i>0) ? high[i-1]          : high[i];

      int    trend     = (int)prevTrend;
      int    nextTrend = g_nextTrend;
      double maxLow    = g_maxLowPrice;
      double minHigh   = g_minHighPrice;
      double up        = g_up;
      double down      = g_down;

      if(nextTrend == 1)
      {
         maxLow = MathMax(lowPrice, maxLow);
         if(highma < maxLow && close[i] < prevLow1)
         {
            trend     = 1;
            nextTrend = 0;
            minHigh   = highPrice;
         }
      }
      else
      {
         minHigh = MathMin(highPrice, minHigh);
         if(lowma > minHigh && close[i] > prevHigh1)
         {
            trend     = 0;
            nextTrend = 1;
            maxLow    = lowPrice;
         }
      }

      double arrowUp=0, arrowDown=0;
      if(trend == 0)
      {
         if((int)prevTrend != 0 && i>0)
         {
            up      = down;
            arrowUp = up - atr2;
         }
         else
         {
            up = MathMax(maxLow, up);
         }
      }
      else
      {
         if((int)prevTrend != 1 && i>0)
         {
            down      = up;
            arrowDown = down + atr2;
         }
         else
         {
            down = MathMin(minHigh, down);
         }
      }

      double ht      = (trend==0) ? up : down;
      double atrHigh = ht + dev;
      double atrLow  = ht - dev;

      g_nextTrend    = nextTrend;
      g_maxLowPrice  = maxLow;
      g_minHighPrice = minHigh;
      g_up           = up;
      g_down         = down;

      HtLineBuffer[i]  = ht;
      HtColorBuffer[i] = (trend==0) ? 0.0 : 1.0;
      TrendBuffer[i]   = (double)trend;

      if(InpShowChannels) { AtrHighBuffer[i]=atrHigh; AtrLowBuffer[i]=atrLow; }
      else                { AtrHighBuffer[i]=0; AtrLowBuffer[i]=0; }

      bool buySignal  = (arrowUp  != 0) && (trend==0) && ((int)prevTrend==1);
      bool sellSignal = (arrowDown!= 0) && (trend==1) && ((int)prevTrend==0);

      if(buySignal)
      {
         BuyArrowBuffer[i] = InpShowArrows ? atrLow : 0;
         SignalBuffer[i]   = 1.0;
      }
      if(sellSignal)
      {
         SellArrowBuffer[i] = InpShowArrows ? atrHigh : 0;
         SignalBuffer[i]    = -1.0;
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
