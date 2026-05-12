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

//--- Plot 1: HalfTrend line (colored)
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
input int    InpAmplitude        = 2;     // Amplitude
input int    InpChannelDeviation = 2;     // Channel Deviation
input bool   InpShowArrows       = true;  // Show Arrows
input bool   InpShowChannels     = true;  // Show Channels

//+------------------------------------------------------------------+
//| Buffer Layout for EA (via iCustom):                              |
//|  Buffer 0: HalfTrend line value (price)                          |
//|  Buffer 1: Color index (0=Blue/Bull, 1=Red/Bear)                 |
//|  Buffer 2: ATR High channel                                      |
//|  Buffer 3: ATR Low channel                                       |
//|  Buffer 4: Buy arrow price (!=EMPTY_VALUE -> buy signal)         |
//|  Buffer 5: Sell arrow price (!=EMPTY_VALUE -> sell signal)       |
//|  Buffer 6: Trend (0=Bullish, 1=Bearish)                          |
//|  Buffer 7: Signal (+1=NewBuy, -1=NewSell, 0=None)                |
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

   PlotIndexSetInteger(3, PLOT_ARROW, 233);   // up arrow
   PlotIndexSetInteger(4, PLOT_ARROW, 234);   // down arrow

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);

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

   //--- State variables (persistent across bars via static)
   static double s_maxLowPrice, s_minHighPrice, s_up, s_down;
   static int    s_nextTrend;

   int start;
   if(prev_calculated == 0)
   {
      start = minBars;
      for(int i=0; i<start; i++)
      {
         HtLineBuffer[i]    = EMPTY_VALUE;
         HtColorBuffer[i]   = 0;
         AtrHighBuffer[i]   = EMPTY_VALUE;
         AtrLowBuffer[i]    = EMPTY_VALUE;
         BuyArrowBuffer[i]  = EMPTY_VALUE;
         SellArrowBuffer[i] = EMPTY_VALUE;
         TrendBuffer[i]     = 0;
         SignalBuffer[i]    = 0;
      }
      // Seed
      TrendBuffer[start-1]  = 0;
      HtLineBuffer[start-1] = low[start-1];
      HtColorBuffer[start-1]= 0;
      s_nextTrend   = 0;
      s_maxLowPrice = low[start-1];
      s_minHighPrice= high[start-1];
      s_up          = low[start-1];
      s_down        = high[start-1];
   }
   else
   {
      start = prev_calculated - 1;
   }

   for(int i = start; i < rates_total; i++)
   {
      BuyArrowBuffer[i]  = EMPTY_VALUE;
      SellArrowBuffer[i] = EMPTY_VALUE;
      SignalBuffer[i]    = 0;

      double atr2 = (atrData[i] > 0) ? atrData[i] / 2.0 : 0.0;
      double dev  = InpChannelDeviation * atr2;

      // Highest high / lowest low over amplitude
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

      // SMA of high/low over amplitude
      double highma=0, lowma=0;
      int cnt=0;
      for(int j=0; j<InpAmplitude; j++)
      {
         if(i-j >= 0) { highma += high[i-j]; lowma += low[i-j]; cnt++; }
      }
      if(cnt>0) { highma/=cnt; lowma/=cnt; }

      double prevTrend = (i>0) ? TrendBuffer[i-1] : 0;
      double prevLow1  = (i>0) ? low[i-1]  : low[i];
      double prevHigh1 = (i>0) ? high[i-1] : high[i];

      int    trend    = (int)prevTrend;
      int    nextTrend= s_nextTrend;
      double maxLow   = s_maxLowPrice;
      double minHigh  = s_minHighPrice;
      double up       = s_up;
      double down     = s_down;

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
            up       = down;
            arrowUp  = up - atr2;
         }
         else
            up = MathMax(maxLow, up);
      }
      else
      {
         if((int)prevTrend != 1 && i>0)
         {
            down      = up;
            arrowDown = down + atr2;
         }
         else
            down = MathMin(minHigh, down);
      }

      double ht      = (trend==0) ? up : down;
      double atrHigh = ht + dev;
      double atrLow  = ht - dev;

      // Save state
      s_nextTrend   = nextTrend;
      s_maxLowPrice = maxLow;
      s_minHighPrice= minHigh;
      s_up          = up;
      s_down        = down;

      // Fill buffers
      HtLineBuffer[i]  = ht;
      HtColorBuffer[i] = (trend==0) ? 0.0 : 1.0;
      TrendBuffer[i]   = (double)trend;

      if(InpShowChannels) { AtrHighBuffer[i]=atrHigh; AtrLowBuffer[i]=atrLow; }
      else                { AtrHighBuffer[i]=EMPTY_VALUE; AtrLowBuffer[i]=EMPTY_VALUE; }

      // Signals (trend flip)
      bool buySignal  = (arrowUp!=0)  && (trend==0) && ((int)prevTrend==1);
      bool sellSignal = (arrowDown!=0)&& (trend==1) && ((int)prevTrend==0);

      if(buySignal)
      {
         BuyArrowBuffer[i] = InpShowArrows ? atrLow : EMPTY_VALUE;
         SignalBuffer[i]   = 1.0;
      }
      if(sellSignal)
      {
         SellArrowBuffer[i] = InpShowArrows ? atrHigh : EMPTY_VALUE;
         SignalBuffer[i]    = -1.0;
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
