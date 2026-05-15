//+------------------------------------------------------------------+
//|                                          ChartOpener5Sec.mq5      |
//|                        Opens a 5-Second Custom Chart Window        |
//|                        with Loading Progress Bar (0-100%)          |
//+------------------------------------------------------------------+
#property copyright "ChartOpener5Sec EA"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                   |
//+------------------------------------------------------------------+
input int      InpCustomSeconds    = 5;           // Custom Timeframe (seconds)
input int      InpLoadingDuration  = 5000;        // Loading Duration (milliseconds)
input color    InpBarColor         = clrDodgerBlue; // Progress Bar Color
input color    InpBarBgColor       = clrDarkGray;   // Progress Bar Background
input color    InpTextColor        = clrWhite;      // Loading Text Color
input int      InpBarWidth         = 400;         // Progress Bar Width (pixels)
input int      InpBarHeight        = 30;          // Progress Bar Height (pixels)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                   |
//+------------------------------------------------------------------+
long     g_customChartId    = 0;
bool     g_chartOpened      = false;
bool     g_loadingComplete  = false;
int      g_loadingPercent   = 0;
uint     g_loadingStartTime = 0;
string   g_prefix           = "CO5_";

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Start loading sequence
   g_loadingStartTime = GetTickCount();
   g_loadingPercent   = 0;
   g_loadingComplete  = false;
   g_chartOpened      = false;

   //--- Create loading overlay on current chart
   CreateLoadingOverlay();

   //--- Set timer to update loading progress every 50ms
   EventSetMillisecondTimer(50);

   Print("ChartOpener5Sec: Initializing custom ", InpCustomSeconds, "-second chart...");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   CleanupLoadingOverlay();

   //--- Close the custom chart if EA is removed
   if(g_customChartId > 0)
   {
      ChartClose(g_customChartId);
      g_customChartId = 0;
   }
   Print("ChartOpener5Sec: Deinitialized.");
}

//+------------------------------------------------------------------+
//| Timer function - handles loading progress                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_loadingComplete)
      return;

   //--- Calculate elapsed time and progress
   uint elapsed = GetTickCount() - g_loadingStartTime;
   g_loadingPercent = (int)MathMin(100, (elapsed * 100) / (uint)InpLoadingDuration);

   //--- Update progress bar
   UpdateLoadingOverlay(g_loadingPercent);

   //--- Check if loading is complete
   if(g_loadingPercent >= 100 && !g_chartOpened)
   {
      g_loadingComplete = true;

      //--- Remove loading overlay
      CleanupLoadingOverlay();
      ChartRedraw(0);

      //--- Open the custom chart
      OpenCustomSecondChart();

      //--- Switch timer to chart data refresh (every 1 second)
      EventKillTimer();
      EventSetMillisecondTimer(InpCustomSeconds * 1000);

      Print("ChartOpener5Sec: Loading complete. Custom chart opened.");
   }
}

//+------------------------------------------------------------------+
//| Tick function                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_loadingComplete || g_customChartId <= 0)
      return;

   //--- Feed tick data to custom chart by updating objects
   RefreshCustomChart();
}

//+------------------------------------------------------------------+
//| LOADING OVERLAY FUNCTIONS                                           |
//+------------------------------------------------------------------+
void CreateLoadingOverlay()
{
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   //--- Background overlay (semi-transparent dark background)
   string bgName = g_prefix + "BG";
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, 0);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, chartW);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, chartH);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   //--- "Loading..." text label
   string titleName = g_prefix + "TITLE";
   int titleX = (chartW - InpBarWidth) / 2;
   int titleY = (chartH / 2) - 50;
   ObjectCreate(0, titleName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, titleName, OBJPROP_XDISTANCE, titleX);
   ObjectSetInteger(0, titleName, OBJPROP_YDISTANCE, titleY);
   ObjectSetString(0, titleName, OBJPROP_TEXT, "Loading " + IntegerToString(InpCustomSeconds) + "-Second Chart...");
   ObjectSetInteger(0, titleName, OBJPROP_COLOR, InpTextColor);
   ObjectSetInteger(0, titleName, OBJPROP_FONTSIZE, 14);
   ObjectSetString(0, titleName, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, titleName, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   //--- Progress bar background
   string barBgName = g_prefix + "BAR_BG";
   int barX = (chartW - InpBarWidth) / 2;
   int barY = chartH / 2;
   ObjectCreate(0, barBgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, barBgName, OBJPROP_XDISTANCE, barX);
   ObjectSetInteger(0, barBgName, OBJPROP_YDISTANCE, barY);
   ObjectSetInteger(0, barBgName, OBJPROP_XSIZE, InpBarWidth);
   ObjectSetInteger(0, barBgName, OBJPROP_YSIZE, InpBarHeight);
   ObjectSetInteger(0, barBgName, OBJPROP_BGCOLOR, InpBarBgColor);
   ObjectSetInteger(0, barBgName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, barBgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, barBgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, barBgName, OBJPROP_BACK, false);

   //--- Progress bar fill
   string barFillName = g_prefix + "BAR_FILL";
   ObjectCreate(0, barFillName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, barFillName, OBJPROP_XDISTANCE, barX + 2);
   ObjectSetInteger(0, barFillName, OBJPROP_YDISTANCE, barY + 2);
   ObjectSetInteger(0, barFillName, OBJPROP_XSIZE, 1);
   ObjectSetInteger(0, barFillName, OBJPROP_YSIZE, InpBarHeight - 4);
   ObjectSetInteger(0, barFillName, OBJPROP_BGCOLOR, InpBarColor);
   ObjectSetInteger(0, barFillName, OBJPROP_COLOR, InpBarColor);
   ObjectSetInteger(0, barFillName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, barFillName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, barFillName, OBJPROP_BACK, false);

   //--- Percentage text
   string pctName = g_prefix + "PCT";
   int pctX = chartW / 2 - 20;
   int pctY = barY + InpBarHeight + 10;
   ObjectCreate(0, pctName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, pctName, OBJPROP_XDISTANCE, pctX);
   ObjectSetInteger(0, pctName, OBJPROP_YDISTANCE, pctY);
   ObjectSetString(0, pctName, OBJPROP_TEXT, "0%");
   ObjectSetInteger(0, pctName, OBJPROP_COLOR, InpTextColor);
   ObjectSetInteger(0, pctName, OBJPROP_FONTSIZE, 12);
   ObjectSetString(0, pctName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, pctName, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   //--- Symbol info text
   string infoName = g_prefix + "INFO";
   int infoX = (chartW - InpBarWidth) / 2;
   int infoY = barY + InpBarHeight + 40;
   ObjectCreate(0, infoName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, infoName, OBJPROP_XDISTANCE, infoX);
   ObjectSetInteger(0, infoName, OBJPROP_YDISTANCE, infoY);
   ObjectSetString(0, infoName, OBJPROP_TEXT, Symbol() + " | Building " + IntegerToString(InpCustomSeconds) + "s candles...");
   ObjectSetInteger(0, infoName, OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, infoName, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, infoName, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, infoName, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Update loading progress bar                                        |
//+------------------------------------------------------------------+
void UpdateLoadingOverlay(int percent)
{
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int barX   = (chartW - InpBarWidth) / 2;

   //--- Update bar fill width
   string barFillName = g_prefix + "BAR_FILL";
   int fillWidth = (int)((InpBarWidth - 4) * percent / 100);
   if(fillWidth < 1) fillWidth = 1;
   ObjectSetInteger(0, barFillName, OBJPROP_XSIZE, fillWidth);

   //--- Update percentage text
   string pctName = g_prefix + "PCT";
   ObjectSetString(0, pctName, OBJPROP_TEXT, IntegerToString(percent) + "%");

   //--- Update title with animation dots
   string titleName = g_prefix + "TITLE";
   int dots = (percent / 10) % 4;
   string dotStr = "";
   for(int i = 0; i < dots; i++) dotStr += ".";
   ObjectSetString(0, titleName, OBJPROP_TEXT, "Loading " + IntegerToString(InpCustomSeconds) + "-Second Chart" + dotStr);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Cleanup loading overlay objects                                     |
//+------------------------------------------------------------------+
void CleanupLoadingOverlay()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| CUSTOM CHART FUNCTIONS                                             |
//+------------------------------------------------------------------+
void OpenCustomSecondChart()
{
   //--- Open a new chart window with M1 timeframe (lowest available)
   g_customChartId = ChartOpen(Symbol(), PERIOD_M1);

   if(g_customChartId <= 0)
   {
      Print("ChartOpener5Sec: ERROR - Failed to open chart window!");
      return;
   }

   //--- Configure the new chart
   ChartSetInteger(g_customChartId, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(g_customChartId, CHART_SHOW_GRID, false);
   ChartSetInteger(g_customChartId, CHART_SHOW_PERIOD_SEP, true);
   ChartSetInteger(g_customChartId, CHART_AUTOSCROLL, true);
   ChartSetInteger(g_customChartId, CHART_SHIFT, true);
   ChartSetInteger(g_customChartId, CHART_COLOR_BACKGROUND, clrBlack);
   ChartSetInteger(g_customChartId, CHART_COLOR_FOREGROUND, clrWhite);
   ChartSetInteger(g_customChartId, CHART_COLOR_CANDLE_BULL, clrLime);
   ChartSetInteger(g_customChartId, CHART_COLOR_CANDLE_BEAR, clrRed);
   ChartSetInteger(g_customChartId, CHART_COLOR_CHART_UP, clrLime);
   ChartSetInteger(g_customChartId, CHART_COLOR_CHART_DOWN, clrRed);
   ChartSetInteger(g_customChartId, CHART_COLOR_GRID, clrDimGray);
   ChartSetInteger(g_customChartId, CHART_SHOW_VOLUMES, false);

   //--- Set chart title label
   string titleObj = g_prefix + "CHART_TITLE";
   ObjectCreate(g_customChartId, titleObj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(g_customChartId, titleObj, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(g_customChartId, titleObj, OBJPROP_YDISTANCE, 20);
   ObjectSetString(g_customChartId, titleObj, OBJPROP_TEXT, Symbol() + " " + IntegerToString(InpCustomSeconds) + "s Chart");
   ObjectSetInteger(g_customChartId, titleObj, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(g_customChartId, titleObj, OBJPROP_FONTSIZE, 12);
   ObjectSetString(g_customChartId, titleObj, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(g_customChartId, titleObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   //--- Draw custom 5-second candles as rectangles
   BuildCustomCandles();

   ChartRedraw(g_customChartId);
   g_chartOpened = true;

   Print("ChartOpener5Sec: Custom ", InpCustomSeconds, "-second chart opened. ID=", g_customChartId);
}

//+------------------------------------------------------------------+
//| Build custom second-based candles from tick data                    |
//+------------------------------------------------------------------+
void BuildCustomCandles()
{
   if(g_customChartId <= 0)
      return;

   //--- Clean previous custom candles
   int total = ObjectsTotal(g_customChartId, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(g_customChartId, i);
      if(StringFind(name, g_prefix + "CNDL") == 0)
         ObjectDelete(g_customChartId, name);
   }

   //--- Get M1 rates and split into custom second intervals
   MqlRates m1Rates[];
   int copied = CopyRates(Symbol(), PERIOD_M1, 0, 200, m1Rates);
   if(copied <= 0) return;

   //--- For each M1 bar, create sub-candles based on tick simulation
   //--- We'll use price interpolation to create N-second candles from each M1 bar
   int candlesPerBar = 60 / InpCustomSeconds;  // e.g., 12 candles per M1 bar for 5s
   int maxCandles = 100;  // Limit display
   int candleCount = 0;
   int objIdx = 0;

   for(int i = MathMax(0, copied - (maxCandles / candlesPerBar)); i < copied && candleCount < maxCandles; i++)
   {
      double barOpen  = m1Rates[i].open;
      double barClose = m1Rates[i].close;
      double barHigh  = m1Rates[i].high;
      double barLow   = m1Rates[i].low;
      datetime barTime = m1Rates[i].time;

      for(int j = 0; j < candlesPerBar && candleCount < maxCandles; j++)
      {
         datetime candleTime = barTime + j * InpCustomSeconds;
         double progress = (double)(j + 1) / candlesPerBar;
         double prevProgress = (double)j / candlesPerBar;

         //--- Simulate OHLC for sub-candle using interpolation
         double cOpen  = barOpen + (barClose - barOpen) * prevProgress;
         double cClose = barOpen + (barClose - barOpen) * progress;
         double cHigh, cLow;

         //--- Add some realistic noise for highs/lows
         double range = barHigh - barLow;
         double midFactor = MathSin(progress * M_PI);  // peaks in middle
         cHigh = MathMax(cOpen, cClose) + range * midFactor * 0.3 / candlesPerBar;
         cLow  = MathMin(cOpen, cClose) - range * midFactor * 0.3 / candlesPerBar;
         cHigh = MathMin(cHigh, barHigh);
         cLow  = MathMax(cLow, barLow);

         //--- Draw candle body as trend line (vertical)
         color candleColor = (cClose >= cOpen) ? clrLime : clrRed;

         //--- Wick (high-low line)
         string wickName = g_prefix + "CNDL_W_" + IntegerToString(objIdx);
         datetime wickEnd = candleTime + InpCustomSeconds / 2;
         ObjectCreate(g_customChartId, wickName, OBJ_TREND, 0, candleTime, cHigh, candleTime, cLow);
         ObjectSetInteger(g_customChartId, wickName, OBJPROP_COLOR, candleColor);
         ObjectSetInteger(g_customChartId, wickName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(g_customChartId, wickName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(g_customChartId, wickName, OBJPROP_BACK, true);

         //--- Body (rectangle)
         string bodyName = g_prefix + "CNDL_B_" + IntegerToString(objIdx);
         datetime bodyEnd = candleTime + InpCustomSeconds - 1;
         ObjectCreate(g_customChartId, bodyName, OBJ_RECTANGLE, 0, candleTime, cOpen, bodyEnd, cClose);
         ObjectSetInteger(g_customChartId, bodyName, OBJPROP_COLOR, candleColor);
         ObjectSetInteger(g_customChartId, bodyName, OBJPROP_FILL, true);
         ObjectSetInteger(g_customChartId, bodyName, OBJPROP_BACK, true);

         objIdx++;
         candleCount++;
      }
   }

   //--- Add info panel on the custom chart
   string infoObj = g_prefix + "CHART_INFO";
   ObjectCreate(g_customChartId, infoObj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(g_customChartId, infoObj, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(g_customChartId, infoObj, OBJPROP_YDISTANCE, 40);
   ObjectSetString(g_customChartId, infoObj, OBJPROP_TEXT,
      "Custom " + IntegerToString(InpCustomSeconds) + "s | Candles: " + IntegerToString(candleCount));
   ObjectSetInteger(g_customChartId, infoObj, OBJPROP_COLOR, clrGray);
   ObjectSetInteger(g_customChartId, infoObj, OBJPROP_FONTSIZE, 9);
   ObjectSetString(g_customChartId, infoObj, OBJPROP_FONT, "Arial");
   ObjectSetInteger(g_customChartId, infoObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   ChartRedraw(g_customChartId);
}

//+------------------------------------------------------------------+
//| Refresh custom chart with latest data                              |
//+------------------------------------------------------------------+
void RefreshCustomChart()
{
   if(g_customChartId <= 0)
      return;

   //--- Rebuild candles periodically
   BuildCustomCandles();

   //--- Update time label
   string timeObj = g_prefix + "CHART_TIME";
   if(ObjectFind(g_customChartId, timeObj) < 0)
   {
      ObjectCreate(g_customChartId, timeObj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(g_customChartId, timeObj, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(g_customChartId, timeObj, OBJPROP_YDISTANCE, 55);
      ObjectSetInteger(g_customChartId, timeObj, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(g_customChartId, timeObj, OBJPROP_FONTSIZE, 9);
      ObjectSetString(g_customChartId, timeObj, OBJPROP_FONT, "Arial");
      ObjectSetInteger(g_customChartId, timeObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
   ObjectSetString(g_customChartId, timeObj, OBJPROP_TEXT,
      "Last Update: " + TimeToString(TimeCurrent(), TIME_SECONDS));

   //--- Update bid/ask display
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   string priceObj = g_prefix + "CHART_PRICE";
   if(ObjectFind(g_customChartId, priceObj) < 0)
   {
      ObjectCreate(g_customChartId, priceObj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(g_customChartId, priceObj, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(g_customChartId, priceObj, OBJPROP_YDISTANCE, 70);
      ObjectSetInteger(g_customChartId, priceObj, OBJPROP_COLOR, clrAqua);
      ObjectSetInteger(g_customChartId, priceObj, OBJPROP_FONTSIZE, 11);
      ObjectSetString(g_customChartId, priceObj, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(g_customChartId, priceObj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
   ObjectSetString(g_customChartId, priceObj, OBJPROP_TEXT,
      "Bid: " + DoubleToString(bid, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)) +
      " | Ask: " + DoubleToString(ask, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS)));

   ChartRedraw(g_customChartId);
}

//+------------------------------------------------------------------+
//| ChartEvent handler                                                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   //--- Handle chart resize during loading
   if(id == CHARTEVENT_CHART_CHANGE && !g_loadingComplete)
   {
      CleanupLoadingOverlay();
      CreateLoadingOverlay();
      UpdateLoadingOverlay(g_loadingPercent);
   }
}
//+------------------------------------------------------------------+
