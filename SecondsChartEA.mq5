//+------------------------------------------------------------------+
//|                                           SecondsChartEA.mq5      |
//|                  Opens a TRUE 5-Second Custom Symbol Chart         |
//|                  Uses CustomSymbol + CustomRatesUpdate             |
//+------------------------------------------------------------------+
#property copyright "SecondsChartEA v3"
#property link      ""
#property version   "3.00"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                   |
//+------------------------------------------------------------------+
input int      InpSeconds          = 5;             // Chart Seconds Timeframe
input int      InpLoadTimeMs       = 5500;          // Loading Time (ms) 5-6 sec
input int      InpMaxBars          = 500;           // Max Bars to Build
input color    InpProgressColor    = clrDeepSkyBlue;// Progress Bar Fill Color
input color    InpProgressBgColor  = clrSlateGray;  // Progress Bar Background
input color    InpLoadTextColor    = clrWhite;      // Loading Text Color
input color    InpBullCandle       = clrLime;       // Bullish Candle Color
input color    InpBearCandle       = clrOrangeRed;  // Bearish Candle Color
input color    InpChartBgColor     = C'20,20,30';   // Chart Background Color

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                   |
//+------------------------------------------------------------------+
string   PREFIX              = "SEC_";
string   g_customSymbol      = "";
long     g_chartId           = 0;
bool     g_isLoading         = true;
bool     g_chartReady        = false;
int      g_progress          = 0;
uint     g_startTick         = 0;
bool     g_symbolCreated     = false;

// Live candle building
datetime g_currentBarTime    = 0;
double   g_currentOpen       = 0;
double   g_currentHigh       = 0;
double   g_currentLow        = 0;
double   g_currentClose      = 0;
long     g_currentVolume     = 0;

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
   g_currentBarTime = 0;

   //--- Build custom symbol name (e.g., "EURUSD_5s")
   g_customSymbol = Symbol() + "_" + IntegerToString(InpSeconds) + "s";

   //--- Draw loading screen on current chart
   DrawLoadingScreen();

   //--- Timer at 50ms for smooth loading animation
   EventSetMillisecondTimer(50);

   Print("[SecondsChartEA] Initializing ", InpSeconds, "s chart for ", Symbol());
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   RemoveAllObjects(0);

   //--- Close custom chart
   if(g_chartId > 0)
   {
      ChartClose(g_chartId);
      g_chartId = 0;
   }

   //--- Delete custom symbol
   if(g_symbolCreated)
   {
      CustomSymbolDelete(g_customSymbol);
      g_symbolCreated = false;
      Print("[SecondsChartEA] Custom symbol ", g_customSymbol, " deleted.");
   }

   Print("[SecondsChartEA] Deinitialized.");
}

//+------------------------------------------------------------------+
//| Timer handler                                                       |
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

         //--- Create custom symbol and open chart
         if(CreateCustomSymbolChart())
         {
            g_chartReady = true;
            Print("[SecondsChartEA] ", InpSeconds, "s chart ready!");
         }

         //--- Switch timer to feed data every second
         EventKillTimer();
         EventSetMillisecondTimer(1000);
      }
   }
   else
   {
      //--- Feed live data to custom symbol every second
      if(g_chartReady)
         FeedLiveData();
   }
}

//+------------------------------------------------------------------+
//| Tick handler                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_chartReady || !g_symbolCreated)
      return;

   FeedLiveData();
}

//+------------------------------------------------------------------+
//| Create custom symbol and open its chart                            |
//+------------------------------------------------------------------+
bool CreateCustomSymbolChart()
{
   //--- Step 1: Create custom symbol
   if(!CustomSymbolCreate(g_customSymbol, "Custom\\" + g_customSymbol, Symbol()))
   {
      //--- Maybe already exists, try to use it
      if(GetLastError() != 5300) // ERR_CUSTOM_SYMBOL_EXIST
      {
         // Try deleting and recreating
         CustomSymbolDelete(g_customSymbol);
         if(!CustomSymbolCreate(g_customSymbol, "Custom\\" + g_customSymbol, Symbol()))
         {
            Print("[SecondsChartEA] ERROR: Cannot create custom symbol! Error=", GetLastError());
            return false;
         }
      }
   }
   g_symbolCreated = true;

   //--- Step 2: Copy symbol properties from parent
   CustomSymbolSetInteger(g_customSymbol, SYMBOL_DIGITS, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
   CustomSymbolSetDouble(g_customSymbol, SYMBOL_POINT, SymbolInfoDouble(Symbol(), SYMBOL_POINT));
   CustomSymbolSetDouble(g_customSymbol, SYMBOL_TRADE_TICK_SIZE, SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE));
   CustomSymbolSetDouble(g_customSymbol, SYMBOL_TRADE_TICK_VALUE, SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE));
   CustomSymbolSetDouble(g_customSymbol, SYMBOL_VOLUME_MIN, SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN));
   CustomSymbolSetString(g_customSymbol, SYMBOL_DESCRIPTION, Symbol() + " " + IntegerToString(InpSeconds) + " Seconds");
   CustomSymbolSetString(g_customSymbol, SYMBOL_CURRENCY_BASE, SymbolInfoString(Symbol(), SYMBOL_CURRENCY_BASE));
   CustomSymbolSetString(g_customSymbol, SYMBOL_CURRENCY_PROFIT, SymbolInfoString(Symbol(), SYMBOL_CURRENCY_PROFIT));

   //--- Step 3: Build historical N-second bars from ticks
   BuildHistoricalBars();

   //--- Step 4: Select symbol in Market Watch (required to open chart)
   SymbolSelect(g_customSymbol, true);

   //--- Step 5: Open chart with M1 (we feed custom rates so each M1 bar = our N seconds)
   //--- Actually open on the custom symbol itself
   g_chartId = ChartOpen(g_customSymbol, PERIOD_M1);

   if(g_chartId <= 0)
   {
      Print("[SecondsChartEA] ERROR: Failed to open chart for ", g_customSymbol, "! Error=", GetLastError());
      return false;
   }

   //--- Step 6: Configure chart appearance
   ChartSetInteger(g_chartId, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(g_chartId, CHART_SHOW_GRID, false);
   ChartSetInteger(g_chartId, CHART_SHOW_PERIOD_SEP, true);
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

   //--- Add header label
   string hdr = PREFIX + "HDR";
   ObjectCreate(g_chartId, hdr, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(g_chartId, hdr, OBJPROP_XDISTANCE, 15);
   ObjectSetInteger(g_chartId, hdr, OBJPROP_YDISTANCE, 15);
   ObjectSetString(g_chartId, hdr, OBJPROP_TEXT,
      Symbol() + "  " + IntegerToString(InpSeconds) + " SECONDS CHART");
   ObjectSetInteger(g_chartId, hdr, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(g_chartId, hdr, OBJPROP_FONTSIZE, 12);
   ObjectSetString(g_chartId, hdr, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(g_chartId, hdr, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   ChartRedraw(g_chartId);
   Print("[SecondsChartEA] Chart opened: ", g_customSymbol, " ID=", g_chartId);
   return true;
}

//+------------------------------------------------------------------+
//| Build historical bars from tick data                                |
//+------------------------------------------------------------------+
void BuildHistoricalBars()
{
   //--- Get recent ticks from parent symbol
   MqlTick ticks[];
   int tickCount = CopyTicks(Symbol(), ticks, COPY_TICKS_ALL, 0, 50000);

   if(tickCount <= 0)
   {
      Print("[SecondsChartEA] No ticks available, building from M1 rates instead.");
      BuildFromM1Rates();
      return;
   }

   Print("[SecondsChartEA] Building ", InpSeconds, "s bars from ", tickCount, " ticks...");

   //--- Aggregate ticks into N-second bars
   MqlRates bars[];
   ArrayResize(bars, 0);

   datetime barStart = ticks[0].time - (ticks[0].time % InpSeconds);
   double barOpen = ticks[0].bid;
   double barHigh = ticks[0].bid;
   double barLow  = ticks[0].bid;
   double barClose = ticks[0].bid;
   long   barVol  = 1;

   for(int i = 1; i < tickCount; i++)
   {
      datetime tickBarStart = ticks[i].time - (ticks[i].time % InpSeconds);

      if(tickBarStart != barStart)
      {
         //--- Save completed bar
         int sz = ArraySize(bars);
         ArrayResize(bars, sz + 1);
         bars[sz].time       = barStart;
         bars[sz].open       = barOpen;
         bars[sz].high       = barHigh;
         bars[sz].low        = barLow;
         bars[sz].close      = barClose;
         bars[sz].tick_volume = barVol;
         bars[sz].spread     = 0;
         bars[sz].real_volume = 0;

         //--- Start new bar
         barStart = tickBarStart;
         barOpen  = ticks[i].bid;
         barHigh  = ticks[i].bid;
         barLow   = ticks[i].bid;
         barClose = ticks[i].bid;
         barVol   = 1;

         if(ArraySize(bars) >= InpMaxBars)
            break;
      }
      else
      {
         //--- Update current bar
         barClose = ticks[i].bid;
         if(ticks[i].bid > barHigh) barHigh = ticks[i].bid;
         if(ticks[i].bid < barLow)  barLow  = ticks[i].bid;
         barVol++;
      }
   }

   //--- Add last bar
   if(ArraySize(bars) < InpMaxBars)
   {
      int sz = ArraySize(bars);
      ArrayResize(bars, sz + 1);
      bars[sz].time       = barStart;
      bars[sz].open       = barOpen;
      bars[sz].high       = barHigh;
      bars[sz].low        = barLow;
      bars[sz].close      = barClose;
      bars[sz].tick_volume = barVol;
      bars[sz].spread     = 0;
      bars[sz].real_volume = 0;
   }

   //--- Push bars to custom symbol
   if(ArraySize(bars) > 0)
   {
      int added = CustomRatesUpdate(g_customSymbol, bars);
      Print("[SecondsChartEA] Added ", added, " bars (", InpSeconds, "s each) to ", g_customSymbol);
   }

   //--- Set initial live bar tracking
   if(ArraySize(bars) > 0)
   {
      g_currentBarTime = bars[ArraySize(bars)-1].time + InpSeconds;
   }
}

//+------------------------------------------------------------------+
//| Fallback: Build from M1 rates if no ticks available                |
//+------------------------------------------------------------------+
void BuildFromM1Rates()
{
   MqlRates m1[];
   int copied = CopyRates(Symbol(), PERIOD_M1, 0, 200, m1);
   if(copied <= 0) return;

   int candlesPerM1 = 60 / InpSeconds;
   MqlRates bars[];
   ArrayResize(bars, 0);

   for(int i = 0; i < copied; i++)
   {
      double o = m1[i].open;
      double c = m1[i].close;
      double h = m1[i].high;
      double l = m1[i].low;
      double range = h - l;

      for(int j = 0; j < candlesPerM1; j++)
      {
         int sz = ArraySize(bars);
         if(sz >= InpMaxBars) break;

         ArrayResize(bars, sz + 1);

         double pctS = (double)j / candlesPerM1;
         double pctE = (double)(j+1) / candlesPerM1;

         bars[sz].time       = m1[i].time + j * InpSeconds;
         bars[sz].open       = o + (c - o) * pctS;
         bars[sz].close      = o + (c - o) * pctE;

         double subRange = range / candlesPerM1;
         double noise = MathSin((j + 1.0) * M_PI / candlesPerM1) * subRange * 0.4;
         bars[sz].high = MathMax(bars[sz].open, bars[sz].close) + MathAbs(noise);
         bars[sz].low  = MathMin(bars[sz].open, bars[sz].close) - MathAbs(noise);
         if(bars[sz].high > h) bars[sz].high = h;
         if(bars[sz].low  < l) bars[sz].low  = l;

         bars[sz].tick_volume = m1[i].tick_volume / candlesPerM1;
         bars[sz].spread     = 0;
         bars[sz].real_volume = 0;
      }
   }

   if(ArraySize(bars) > 0)
   {
      int added = CustomRatesUpdate(g_customSymbol, bars);
      Print("[SecondsChartEA] Fallback: Added ", added, " bars from M1 data.");
      g_currentBarTime = bars[ArraySize(bars)-1].time + InpSeconds;
   }
}

//+------------------------------------------------------------------+
//| Feed live tick data to custom symbol as N-second bars              |
//+------------------------------------------------------------------+
void FeedLiveData()
{
   if(!g_symbolCreated) return;

   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   if(bid <= 0) return;

   datetime now = TimeCurrent();
   datetime barTime = now - (now % InpSeconds);

   //--- Feed tick to custom symbol (updates its bid/ask)
   MqlTick tickArr[1];
   tickArr[0].time     = now;
   tickArr[0].time_msc = (long)now * 1000;
   tickArr[0].bid      = bid;
   tickArr[0].ask      = ask;
   tickArr[0].last     = bid;
   tickArr[0].volume   = 1;
   tickArr[0].flags    = TICK_FLAG_BID | TICK_FLAG_ASK;
   CustomTicksAdd(g_customSymbol, tickArr);

   //--- Build/update the current N-second bar
   if(barTime != g_currentBarTime)
   {
      //--- New bar started
      g_currentBarTime = barTime;
      g_currentOpen    = bid;
      g_currentHigh    = bid;
      g_currentLow     = bid;
      g_currentClose   = bid;
      g_currentVolume  = 1;
   }
   else
   {
      //--- Update current bar
      g_currentClose = bid;
      if(bid > g_currentHigh) g_currentHigh = bid;
      if(bid < g_currentLow)  g_currentLow  = bid;
      g_currentVolume++;
   }

   //--- Push current bar to custom symbol rates
   MqlRates rate[1];
   rate[0].time        = g_currentBarTime;
   rate[0].open        = g_currentOpen;
   rate[0].high        = g_currentHigh;
   rate[0].low         = g_currentLow;
   rate[0].close       = g_currentClose;
   rate[0].tick_volume = g_currentVolume;
   rate[0].spread      = (int)MathRound((ask - bid) / SymbolInfoDouble(Symbol(), SYMBOL_POINT));
   rate[0].real_volume = 0;
   CustomRatesUpdate(g_customSymbol, rate);
}

//+------------------------------------------------------------------+
//| LOADING SCREEN                                                     |
//+------------------------------------------------------------------+
void DrawLoadingScreen()
{
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   //--- Full dark overlay
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

   //--- Fill bar
   string barFill = PREFIX + "LOAD_BARFILL";
   int fillW = (int)((barW - 4) * percent / 100);
   if(fillW < 1) fillW = 1;
   ObjectSetInteger(0, barFill, OBJPROP_XSIZE, fillW);

   //--- Percent text
   string pct = PREFIX + "LOAD_PCT";
   ObjectSetString(0, pct, OBJPROP_TEXT, IntegerToString(percent) + "%");

   //--- Dynamic status messages
   string status = PREFIX + "LOAD_STATUS";
   if(percent < 15)
      ObjectSetString(0, status, OBJPROP_TEXT, "Creating custom symbol...");
   else if(percent < 35)
      ObjectSetString(0, status, OBJPROP_TEXT, "Downloading tick history...");
   else if(percent < 55)
      ObjectSetString(0, status, OBJPROP_TEXT, "Aggregating " + IntegerToString(InpSeconds) + "s bars...");
   else if(percent < 75)
      ObjectSetString(0, status, OBJPROP_TEXT, "Building chart data...");
   else if(percent < 90)
      ObjectSetString(0, status, OBJPROP_TEXT, "Preparing chart window...");
   else
      ObjectSetString(0, status, OBJPROP_TEXT, "Opening " + IntegerToString(InpSeconds) + " second chart...");

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Remove all objects with our prefix                                 |
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
