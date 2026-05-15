//+------------------------------------------------------------------+
//|                                           SecondsChartEA.mq5      |
//|                     Custom Seconds Chart with Loading Animation    |
//|                     Opens a new window with N-second candles       |
//+------------------------------------------------------------------+
#property copyright "SecondsChartEA"
#property link      ""
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                   |
//+------------------------------------------------------------------+
input int      InpSeconds          = 5;             // Chart Seconds Timeframe
input int      InpLoadTimeMs       = 5500;          // Loading Time (ms) 5-6 sec
input int      InpMaxCandles       = 150;           // Max Candles to Display
input color    InpProgressColor    = clrDeepSkyBlue;// Progress Bar Fill Color
input color    InpProgressBgColor  = clrSlateGray;  // Progress Bar Background
input color    InpLoadTextColor    = clrWhite;      // Loading Text Color
input color    InpBullCandle       = clrLime;       // Bullish Candle Color
input color    InpBearCandle       = clrOrangeRed;  // Bearish Candle Color
input color    InpChartBgColor     = C'20,20,30';   // Chart Background Color
input bool     InpShowSpread       = true;          // Show Spread on Chart
input bool     InpShowTickCounter  = true;          // Show Tick Counter

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                   |
//+------------------------------------------------------------------+
string   PREFIX           = "SEC_";
long     g_chartId        = 0;
bool     g_isLoading      = true;
bool     g_chartReady     = false;
int      g_progress       = 0;
uint     g_startTick      = 0;
int      g_tickCount      = 0;
int      g_candleObjCount = 0;

// Custom candle data storage
struct SecondCandle
{
   datetime openTime;
   double   open;
   double   high;
   double   low;
   double   close;
   long     volume;
};

SecondCandle g_candles[];
datetime     g_lastCandleTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   g_startTick    = GetTickCount();
   g_isLoading    = true;
   g_chartReady   = false;
   g_progress     = 0;
   g_chartId      = 0;
   g_tickCount    = 0;
   g_candleObjCount = 0;
   g_lastCandleTime = 0;
   ArrayResize(g_candles, 0);

   //--- Draw loading screen
   DrawLoadingScreen();

   //--- Timer at 50ms for smooth loading animation
   EventSetMillisecondTimer(50);

   Print("[SecondsChartEA] Starting... Will open ", InpSeconds, "s chart in ~",
         InpLoadTimeMs/1000, " seconds.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   RemoveAllObjects(0);

   if(g_chartId > 0)
   {
      RemoveAllObjects(g_chartId);
      ChartClose(g_chartId);
      g_chartId = 0;
   }

   ArrayFree(g_candles);
   Print("[SecondsChartEA] Removed.");
}



//+------------------------------------------------------------------+
//| Timer handler - loading animation + candle refresh                 |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_isLoading)
   {
      uint elapsed = GetTickCount() - g_startTick;
      g_progress = (int)MathMin(100, (elapsed * 100) / (uint)InpLoadTimeMs);

      UpdateLoadingBar(g_progress);

      if(g_progress >= 100)
      {
         g_isLoading = false;
         RemoveAllObjects(0);
         ChartRedraw(0);

         //--- Open custom seconds chart
         OpenSecondsChart();

         //--- Switch to candle-building timer
         EventKillTimer();
         EventSetMillisecondTimer(InpSeconds * 1000);

         Print("[SecondsChartEA] Loading complete! Chart opened.");
      }
   }
   else
   {
      //--- Periodic refresh of custom chart
      if(g_chartReady && g_chartId > 0)
         RedrawCandlesOnChart();
   }
}

//+------------------------------------------------------------------+
//| Tick handler - builds real-time second candles                     |
//+------------------------------------------------------------------+
void OnTick()
{
   g_tickCount++;

   if(g_isLoading || !g_chartReady || g_chartId <= 0)
      return;

   //--- Get current price
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   if(bid <= 0) return;

   datetime now = TimeCurrent();
   datetime candleStart = now - (now % InpSeconds);

   int size = ArraySize(g_candles);

   //--- Check if we need a new candle or update existing
   if(size == 0 || g_candles[size-1].openTime != candleStart)
   {
      //--- New candle
      ArrayResize(g_candles, size + 1);
      g_candles[size].openTime = candleStart;
      g_candles[size].open     = bid;
      g_candles[size].high     = bid;
      g_candles[size].low      = bid;
      g_candles[size].close    = bid;
      g_candles[size].volume   = 1;

      //--- Trim to max candles
      if(ArraySize(g_candles) > InpMaxCandles)
      {
         SecondCandle temp[];
         int newSize = InpMaxCandles;
         ArrayResize(temp, newSize);
         for(int i = 0; i < newSize; i++)
            temp[i] = g_candles[ArraySize(g_candles) - newSize + i];
         ArrayResize(g_candles, newSize);
         for(int i = 0; i < newSize; i++)
            g_candles[i] = temp[i];
         ArrayFree(temp);
      }
   }
   else
   {
      //--- Update current candle
      int idx = size - 1;
      g_candles[idx].close = bid;
      if(bid > g_candles[idx].high) g_candles[idx].high = bid;
      if(bid < g_candles[idx].low)  g_candles[idx].low  = bid;
      g_candles[idx].volume++;
   }

   //--- Update live info on chart
   UpdateLiveInfo();
}



//+------------------------------------------------------------------+
//| LOADING SCREEN FUNCTIONS                                           |
//+------------------------------------------------------------------+
void DrawLoadingScreen()
{
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   //--- Full black overlay
   string bg = PREFIX + "LOAD_BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, 0);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, 0);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'15,15,25');
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'15,15,25');
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   //--- Title
   string title = PREFIX + "LOAD_TITLE";
   ObjectCreate(0, title, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, title, OBJPROP_XDISTANCE, w/2 - 150);
   ObjectSetInteger(0, title, OBJPROP_YDISTANCE, h/2 - 60);
   ObjectSetString(0, title, OBJPROP_TEXT, Symbol() + " | " + IntegerToString(InpSeconds) + " Second Chart");
   ObjectSetInteger(0, title, OBJPROP_COLOR, InpLoadTextColor);
   ObjectSetInteger(0, title, OBJPROP_FONTSIZE, 16);
   ObjectSetString(0, title, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, title, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   //--- Progress bar background
   int barW = 360;
   int barH = 24;
   int barX = w/2 - barW/2;
   int barY = h/2 - barH/2;

   string barBg = PREFIX + "LOAD_BARBG";
   ObjectCreate(0, barBg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, barBg, OBJPROP_XDISTANCE, barX);
   ObjectSetInteger(0, barBg, OBJPROP_YDISTANCE, barY);
   ObjectSetInteger(0, barBg, OBJPROP_XSIZE, barW);
   ObjectSetInteger(0, barBg, OBJPROP_YSIZE, barH);
   ObjectSetInteger(0, barBg, OBJPROP_BGCOLOR, InpProgressBgColor);
   ObjectSetInteger(0, barBg, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, barBg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, barBg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, barBg, OBJPROP_BACK, false);

   //--- Progress bar fill
   string barFill = PREFIX + "LOAD_BARFILL";
   ObjectCreate(0, barFill, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, barFill, OBJPROP_XDISTANCE, barX + 2);
   ObjectSetInteger(0, barFill, OBJPROP_YDISTANCE, barY + 2);
   ObjectSetInteger(0, barFill, OBJPROP_XSIZE, 1);
   ObjectSetInteger(0, barFill, OBJPROP_YSIZE, barH - 4);
   ObjectSetInteger(0, barFill, OBJPROP_BGCOLOR, InpProgressColor);
   ObjectSetInteger(0, barFill, OBJPROP_COLOR, InpProgressColor);
   ObjectSetInteger(0, barFill, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, barFill, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, barFill, OBJPROP_BACK, false);

   //--- Percent label
   string pct = PREFIX + "LOAD_PCT";
   ObjectCreate(0, pct, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, pct, OBJPROP_XDISTANCE, w/2 - 15);
   ObjectSetInteger(0, pct, OBJPROP_YDISTANCE, barY + barH + 12);
   ObjectSetString(0, pct, OBJPROP_TEXT, "0%");
   ObjectSetInteger(0, pct, OBJPROP_COLOR, InpLoadTextColor);
   ObjectSetInteger(0, pct, OBJPROP_FONTSIZE, 12);
   ObjectSetString(0, pct, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, pct, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   //--- Status text
   string status = PREFIX + "LOAD_STATUS";
   ObjectCreate(0, status, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, status, OBJPROP_XDISTANCE, w/2 - 120);
   ObjectSetInteger(0, status, OBJPROP_YDISTANCE, barY + barH + 40);
   ObjectSetString(0, status, OBJPROP_TEXT, "Preparing tick aggregation engine...");
   ObjectSetInteger(0, status, OBJPROP_COLOR, clrDarkGray);
   ObjectSetInteger(0, status, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, status, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, status, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Update progress bar                                                |
//+------------------------------------------------------------------+
void UpdateLoadingBar(int percent)
{
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int barW = 360;
   int barX = w/2 - barW/2;

   //--- Fill bar
   string barFill = PREFIX + "LOAD_BARFILL";
   int fillW = (int)((barW - 4) * percent / 100);
   if(fillW < 1) fillW = 1;
   ObjectSetInteger(0, barFill, OBJPROP_XSIZE, fillW);

   //--- Percent text
   string pct = PREFIX + "LOAD_PCT";
   ObjectSetString(0, pct, OBJPROP_TEXT, IntegerToString(percent) + "%");

   //--- Status text changes as loading progresses
   string status = PREFIX + "LOAD_STATUS";
   if(percent < 20)
      ObjectSetString(0, status, OBJPROP_TEXT, "Initializing tick collector...");
   else if(percent < 40)
      ObjectSetString(0, status, OBJPROP_TEXT, "Loading historical data...");
   else if(percent < 60)
      ObjectSetString(0, status, OBJPROP_TEXT, "Building " + IntegerToString(InpSeconds) + "s candle structure...");
   else if(percent < 80)
      ObjectSetString(0, status, OBJPROP_TEXT, "Preparing chart renderer...");
   else
      ObjectSetString(0, status, OBJPROP_TEXT, "Finalizing... Opening chart window");

   ChartRedraw(0);
}



//+------------------------------------------------------------------+
//| CHART OPEN & CONFIGURATION                                         |
//+------------------------------------------------------------------+
void OpenSecondsChart()
{
   g_chartId = ChartOpen(Symbol(), PERIOD_M1);

   if(g_chartId <= 0)
   {
      Print("[SecondsChartEA] ERROR: Could not open chart!");
      return;
   }

   //--- Configure chart appearance
   ChartSetInteger(g_chartId, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(g_chartId, CHART_SHOW_GRID, false);
   ChartSetInteger(g_chartId, CHART_SHOW_PERIOD_SEP, false);
   ChartSetInteger(g_chartId, CHART_AUTOSCROLL, true);
   ChartSetInteger(g_chartId, CHART_SHIFT, true);
   ChartSetInteger(g_chartId, CHART_COLOR_BACKGROUND, InpChartBgColor);
   ChartSetInteger(g_chartId, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(g_chartId, CHART_COLOR_CANDLE_BULL, InpBullCandle);
   ChartSetInteger(g_chartId, CHART_COLOR_CANDLE_BEAR, InpBearCandle);
   ChartSetInteger(g_chartId, CHART_COLOR_CHART_UP, InpBullCandle);
   ChartSetInteger(g_chartId, CHART_COLOR_CHART_DOWN, InpBearCandle);
   ChartSetInteger(g_chartId, CHART_COLOR_GRID, C'40,40,50');
   ChartSetInteger(g_chartId, CHART_SHOW_VOLUMES, false);
   ChartSetInteger(g_chartId, CHART_SHOW_OHLC, false);

   //--- Header label
   string hdr = PREFIX + "HDR";
   ObjectCreate(g_chartId, hdr, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(g_chartId, hdr, OBJPROP_XDISTANCE, 15);
   ObjectSetInteger(g_chartId, hdr, OBJPROP_YDISTANCE, 15);
   ObjectSetString(g_chartId, hdr, OBJPROP_TEXT,
      Symbol() + "  " + IntegerToString(InpSeconds) + " SECONDS");
   ObjectSetInteger(g_chartId, hdr, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(g_chartId, hdr, OBJPROP_FONTSIZE, 14);
   ObjectSetString(g_chartId, hdr, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(g_chartId, hdr, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   //--- Pre-load candles from M1 data
   PreloadCandles();

   //--- Draw initial candles
   RedrawCandlesOnChart();

   g_chartReady = true;
   ChartRedraw(g_chartId);
}

//+------------------------------------------------------------------+
//| Preload historical candles from M1 data                            |
//+------------------------------------------------------------------+
void PreloadCandles()
{
   MqlRates rates[];
   int copied = CopyRates(Symbol(), PERIOD_M1, 0, 100, rates);
   if(copied <= 0) return;

   int candlesPerM1 = 60 / InpSeconds;
   ArrayResize(g_candles, 0);

   for(int i = 0; i < copied; i++)
   {
      double o = rates[i].open;
      double c = rates[i].close;
      double h = rates[i].high;
      double l = rates[i].low;
      double range = h - l;

      for(int j = 0; j < candlesPerM1; j++)
      {
         int sz = ArraySize(g_candles);
         if(sz >= InpMaxCandles) break;

         ArrayResize(g_candles, sz + 1);

         double pctStart = (double)j / candlesPerM1;
         double pctEnd   = (double)(j+1) / candlesPerM1;

         g_candles[sz].openTime = rates[i].time + j * InpSeconds;
         g_candles[sz].open     = o + (c - o) * pctStart;
         g_candles[sz].close    = o + (c - o) * pctEnd;

         //--- Simulate high/low with variation
         double mid = (g_candles[sz].open + g_candles[sz].close) / 2.0;
         double subRange = range / candlesPerM1;
         double noise = MathSin((j + 1.0) * M_PI / candlesPerM1) * subRange * 0.5;
         g_candles[sz].high = MathMax(g_candles[sz].open, g_candles[sz].close) + MathAbs(noise);
         g_candles[sz].low  = MathMin(g_candles[sz].open, g_candles[sz].close) - MathAbs(noise);

         //--- Clamp within M1 bar
         if(g_candles[sz].high > h) g_candles[sz].high = h;
         if(g_candles[sz].low  < l) g_candles[sz].low  = l;

         g_candles[sz].volume = rates[i].tick_volume / candlesPerM1;
      }
   }

   //--- Trim to max
   if(ArraySize(g_candles) > InpMaxCandles)
   {
      int excess = ArraySize(g_candles) - InpMaxCandles;
      SecondCandle temp[];
      ArrayResize(temp, InpMaxCandles);
      for(int i = 0; i < InpMaxCandles; i++)
         temp[i] = g_candles[excess + i];
      ArrayResize(g_candles, InpMaxCandles);
      for(int i = 0; i < InpMaxCandles; i++)
         g_candles[i] = temp[i];
      ArrayFree(temp);
   }
}



//+------------------------------------------------------------------+
//| Draw all candles on the custom chart                                |
//+------------------------------------------------------------------+
void RedrawCandlesOnChart()
{
   if(g_chartId <= 0) return;

   //--- Remove old candle objects
   int total = ObjectsTotal(g_chartId, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(g_chartId, i);
      if(StringFind(name, PREFIX + "C_") == 0)
         ObjectDelete(g_chartId, name);
   }

   int size = ArraySize(g_candles);
   if(size == 0) return;

   g_candleObjCount = 0;

   for(int i = 0; i < size; i++)
   {
      color clr = (g_candles[i].close >= g_candles[i].open) ? InpBullCandle : InpBearCandle;
      datetime t1 = g_candles[i].openTime;
      datetime t2 = t1 + InpSeconds - 1;

      //--- Wick line (high to low)
      string wName = PREFIX + "C_W" + IntegerToString(g_candleObjCount);
      ObjectCreate(g_chartId, wName, OBJ_TREND, 0, t1, g_candles[i].high, t1, g_candles[i].low);
      ObjectSetInteger(g_chartId, wName, OBJPROP_COLOR, clr);
      ObjectSetInteger(g_chartId, wName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(g_chartId, wName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(g_chartId, wName, OBJPROP_BACK, true);
      ObjectSetInteger(g_chartId, wName, OBJPROP_SELECTABLE, false);

      //--- Body rectangle (open to close)
      string bName = PREFIX + "C_B" + IntegerToString(g_candleObjCount);
      ObjectCreate(g_chartId, bName, OBJ_RECTANGLE, 0, t1, g_candles[i].open, t2, g_candles[i].close);
      ObjectSetInteger(g_chartId, bName, OBJPROP_COLOR, clr);
      ObjectSetInteger(g_chartId, bName, OBJPROP_FILL, true);
      ObjectSetInteger(g_chartId, bName, OBJPROP_BACK, true);
      ObjectSetInteger(g_chartId, bName, OBJPROP_SELECTABLE, false);

      g_candleObjCount++;
   }

   ChartRedraw(g_chartId);
}

//+------------------------------------------------------------------+
//| Update live information panel on chart                              |
//+------------------------------------------------------------------+
void UpdateLiveInfo()
{
   if(g_chartId <= 0) return;

   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double spread = (ask - bid) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);

   //--- Price label
   string priceLabel = PREFIX + "PRICE";
   if(ObjectFind(g_chartId, priceLabel) < 0)
   {
      ObjectCreate(g_chartId, priceLabel, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(g_chartId, priceLabel, OBJPROP_XDISTANCE, 15);
      ObjectSetInteger(g_chartId, priceLabel, OBJPROP_YDISTANCE, 40);
      ObjectSetInteger(g_chartId, priceLabel, OBJPROP_FONTSIZE, 11);
      ObjectSetString(g_chartId, priceLabel, OBJPROP_FONT, "Segoe UI");
      ObjectSetInteger(g_chartId, priceLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
   color priceClr = (bid >= ask) ? InpBullCandle : InpBearCandle;
   ObjectSetInteger(g_chartId, priceLabel, OBJPROP_COLOR, priceClr);
   ObjectSetString(g_chartId, priceLabel, OBJPROP_TEXT,
      "Bid: " + DoubleToString(bid, digits) + "  Ask: " + DoubleToString(ask, digits));

   //--- Spread
   if(InpShowSpread)
   {
      string spreadLabel = PREFIX + "SPREAD";
      if(ObjectFind(g_chartId, spreadLabel) < 0)
      {
         ObjectCreate(g_chartId, spreadLabel, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(g_chartId, spreadLabel, OBJPROP_XDISTANCE, 15);
         ObjectSetInteger(g_chartId, spreadLabel, OBJPROP_YDISTANCE, 58);
         ObjectSetInteger(g_chartId, spreadLabel, OBJPROP_FONTSIZE, 9);
         ObjectSetString(g_chartId, spreadLabel, OBJPROP_FONT, "Segoe UI");
         ObjectSetInteger(g_chartId, spreadLabel, OBJPROP_COLOR, clrGray);
         ObjectSetInteger(g_chartId, spreadLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      }
      ObjectSetString(g_chartId, spreadLabel, OBJPROP_TEXT,
         "Spread: " + DoubleToString(spread, 1) + " pts | Candles: " + IntegerToString(ArraySize(g_candles)));
   }

   //--- Tick counter
   if(InpShowTickCounter)
   {
      string tickLabel = PREFIX + "TICKS";
      if(ObjectFind(g_chartId, tickLabel) < 0)
      {
         ObjectCreate(g_chartId, tickLabel, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(g_chartId, tickLabel, OBJPROP_XDISTANCE, 15);
         ObjectSetInteger(g_chartId, tickLabel, OBJPROP_YDISTANCE, 74);
         ObjectSetInteger(g_chartId, tickLabel, OBJPROP_FONTSIZE, 9);
         ObjectSetString(g_chartId, tickLabel, OBJPROP_FONT, "Segoe UI");
         ObjectSetInteger(g_chartId, tickLabel, OBJPROP_COLOR, clrYellow);
         ObjectSetInteger(g_chartId, tickLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      }
      ObjectSetString(g_chartId, tickLabel, OBJPROP_TEXT,
         "Ticks: " + IntegerToString(g_tickCount) + " | " + TimeToString(TimeCurrent(), TIME_SECONDS));
   }

   ChartRedraw(g_chartId);
}

//+------------------------------------------------------------------+
//| Remove all objects with our prefix from a chart                    |
//+------------------------------------------------------------------+
void RemoveAllObjects(long chartId)
{
   int total = ObjectsTotal(chartId, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(chartId, i);
      if(StringFind(name, PREFIX) == 0)
         ObjectDelete(chartId, name);
   }
}

//+------------------------------------------------------------------+
//| Chart event handler                                                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE && g_isLoading)
   {
      RemoveAllObjects(0);
      DrawLoadingScreen();
      UpdateLoadingBar(g_progress);
   }
}
//+------------------------------------------------------------------+
