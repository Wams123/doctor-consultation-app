//+------------------------------------------------------------------+
//|                                          BoS_ChoCh_Trader.mq5    |
//|         SMC Break of Structure & Change of Character TRADER       |
//|  Takes trades on every BOS/ChoCh signal on 5-second candles      |
//|  SL at the high/low of the structure swing point                 |
//|  Lot size based on % risk of account balance                     |
//+------------------------------------------------------------------+
#property copyright   "SMC Trader EA"
#property version     "1.00"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                   |
//+------------------------------------------------------------------+
input string   sep0           = "=== Structure Settings ===";
input int      InpPivotLB     = 2;          // Pivot Left Bars
input int      InpPivotRB     = 2;          // Pivot Right Bars
input bool     InpTradeBOS    = true;       // Trade on BOS
input bool     InpTradeChoCh  = true;       // Trade on ChoCh

input string   sep1           = "=== Risk Management ===";
input double   InpRiskPercent = 1.0;        // Risk % per trade
input double   InpRR          = 2.0;        // Reward:Risk ratio (0=no TP)
input int      InpMaxTrades   = 3;          // Max simultaneous trades
input int      InpSlippage    = 10;         // Slippage (points)

input string   sep2           = "=== Timeframe ===";
input int      InpSeconds     = 5;          // Candle size (seconds) for entries
input bool     InpUseSeconds  = true;       // Use seconds chart (false=use chart TF)

input string   sep3           = "=== Visual ===";
input bool     InpDrawSignals = true;       // Draw BOS/ChoCh lines on chart
input color    InpBullColor   = clrLime;    // Bullish signal color
input color    InpBearColor   = clrRed;     // Bearish signal color
input int      InpMagic       = 55555;      // Magic Number

//+------------------------------------------------------------------+
//| CANDLE STRUCTURE                                                   |
//+------------------------------------------------------------------+
struct SCandle
{
   datetime openTime;
   double   open;
   double   high;
   double   low;
   double   close;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                   |
//+------------------------------------------------------------------+
SCandle  g_candles[];
int      g_candleCount    = 0;
datetime g_currentBarTime = 0;
int      g_trend          = 0;        // 1=bull, -1=bear, 0=unknown
double   g_lastHighPrice  = 0;
datetime g_lastHighTime   = 0;
int      g_lastHighBar    = -1;
double   g_lastLowPrice   = DBL_MAX;
datetime g_lastLowTime    = 0;
int      g_lastLowBar     = -1;
int      g_objIdx         = 0;
int      g_lastSignalBar  = -1;       // Prevent duplicate trades on same bar

//+------------------------------------------------------------------+
//| Expert initialization                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(g_candles, 0);
   g_candleCount    = 0;
   g_currentBarTime = 0;
   g_trend          = 0;
   g_lastHighPrice  = 0;
   g_lastHighBar    = -1;
   g_lastLowPrice   = DBL_MAX;
   g_lastLowBar     = -1;
   g_objIdx         = 0;
   g_lastSignalBar  = -1;

   if(InpUseSeconds)
      EventSetMillisecondTimer(100);  // Check every 100ms for real-time detection

   Print("[BoS_ChoCh_Trader] Initialized. Risk=", InpRiskPercent, "% | ",
         InpSeconds, "s candles | Magic=", InpMagic);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(reason == REASON_REMOVE || reason == REASON_PROGRAM)
      ObjectsDeleteAll(0, "BST_");
   ArrayFree(g_candles);
}

//+------------------------------------------------------------------+
//| Timer - for seconds-based candle building                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!InpUseSeconds) return;
   ProcessTick();
}

//+------------------------------------------------------------------+
//| Tick handler                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   if(InpUseSeconds)
   {
      ProcessTick();
   }
   else
   {
      //--- Use chart timeframe bars directly
      ProcessChartBars();
   }
}

//+------------------------------------------------------------------+
//| Process tick - build second candles and check signals               |
//+------------------------------------------------------------------+
void ProcessTick()
{
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   if(bid <= 0) return;

   datetime now = TimeCurrent();
   datetime barTime = now - (now % InpSeconds);

   if(barTime != g_currentBarTime)
   {
      //--- Start new candle
      g_currentBarTime = barTime;
      g_candleCount++;
      ArrayResize(g_candles, g_candleCount);
      g_candles[g_candleCount-1].openTime = barTime;
      g_candles[g_candleCount-1].open     = bid;
      g_candles[g_candleCount-1].high     = bid;
      g_candles[g_candleCount-1].low      = bid;
      g_candles[g_candleCount-1].close    = bid;

      //--- Keep max 500 candles in memory
      if(g_candleCount > 500)
         TrimCandles();

      //--- On every new candle, scan for new pivots that just confirmed
      ScanForNewPivots();
   }
   else if(g_candleCount > 0)
   {
      //--- Update current candle
      int idx = g_candleCount - 1;
      g_candles[idx].close = bid;
      if(bid > g_candles[idx].high) g_candles[idx].high = bid;
      if(bid < g_candles[idx].low)  g_candles[idx].low  = bid;
   }

   //--- Check for break on EVERY tick (real-time detection)
   if(g_candleCount > 0)
      CheckBreak();
}

//+------------------------------------------------------------------+
//| Process chart bars (non-seconds mode)                              |
//+------------------------------------------------------------------+
void ProcessChartBars()
{
   static datetime lastBarTime = 0;
   datetime currentBar = iTime(Symbol(), PERIOD_CURRENT, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;

   //--- Load bars into candle array
   int barsNeeded = InpPivotLB + InpPivotRB + 50;
   MqlRates rates[];
   int copied = CopyRates(Symbol(), PERIOD_CURRENT, 1, barsNeeded, rates);
   if(copied < InpPivotLB + InpPivotRB + 5) return;

   ArrayResize(g_candles, copied);
   g_candleCount = copied;
   for(int i = 0; i < copied; i++)
   {
      g_candles[i].openTime = rates[i].time;
      g_candles[i].open     = rates[i].open;
      g_candles[i].high     = rates[i].high;
      g_candles[i].low      = rates[i].low;
      g_candles[i].close    = rates[i].close;
   }

   //--- Reset structure tracking and recalculate
   g_trend         = 0;
   g_lastHighPrice = 0;
   g_lastHighBar   = -1;
   g_lastLowPrice  = DBL_MAX;
   g_lastLowBar    = -1;

   CheckStructureFull();
}

//+------------------------------------------------------------------+
//| Scan for newly confirmed pivots                                    |
//+------------------------------------------------------------------+
void ScanForNewPivots()
{
   //--- A pivot is confirmed when we have InpPivotRB candles after it
   //--- The pivot bar is at index: g_candleCount - 1 - InpPivotRB
   int pivotBar = g_candleCount - 1 - InpPivotRB;
   if(pivotBar < InpPivotLB) return;

   //--- Check if this bar is a pivot high
   if(IsPivotHigh(pivotBar))
   {
      g_lastHighPrice = g_candles[pivotBar].high;
      g_lastHighTime  = g_candles[pivotBar].openTime;
      g_lastHighBar   = pivotBar;
      Print("[BoS_ChoCh_Trader] New Pivot HIGH confirmed at ", g_lastHighPrice,
            " bar=", pivotBar);
   }

   //--- Check if this bar is a pivot low
   if(IsPivotLow(pivotBar))
   {
      g_lastLowPrice = g_candles[pivotBar].low;
      g_lastLowTime  = g_candles[pivotBar].openTime;
      g_lastLowBar   = pivotBar;
      Print("[BoS_ChoCh_Trader] New Pivot LOW confirmed at ", g_lastLowPrice,
            " bar=", pivotBar);
   }
}

//+------------------------------------------------------------------+
//| Check for break of structure on current price (every tick)         |
//+------------------------------------------------------------------+
void CheckBreak()
{
   int lastBar = g_candleCount - 1;
   if(lastBar < 1) return;

   double currentClose = g_candles[lastBar].close;

   //--- Check bullish break (close above last swing high)
   if(g_lastHighBar >= 0 && lastBar > g_lastHighBar && currentClose > g_lastHighPrice)
   {
      string lbl = (g_trend == -1) ? "ChoCh" : "BoS";
      bool canTrade = (g_trend == -1) ? InpTradeChoCh : InpTradeBOS;
      g_trend = 1;

      if(canTrade && lastBar != g_lastSignalBar)
      {
         g_lastSignalBar = lastBar;

         //--- SL = low of the swing structure (the last pivot low)
         double slPrice = g_lastLowPrice;
         if(slPrice >= DBL_MAX || slPrice <= 0)
            slPrice = g_candles[g_lastHighBar].low;

         Print("[BoS_ChoCh_Trader] BULLISH ", lbl, " detected! Price=", currentClose,
               " broke above ", g_lastHighPrice, " | SL=", slPrice);
         ExecuteBuy(slPrice, lbl);

         if(InpDrawSignals)
            DrawSignal(g_lastHighPrice, g_lastHighTime,
                      g_candles[lastBar].openTime, InpBullColor, true, lbl);
      }

      g_lastHighBar   = -1;
      g_lastHighPrice = 0;
   }

   //--- Check bearish break (close below last swing low)
   if(g_lastLowBar >= 0 && lastBar > g_lastLowBar && currentClose < g_lastLowPrice)
   {
      string lbl = (g_trend == 1) ? "ChoCh" : "BoS";
      bool canTrade = (g_trend == 1) ? InpTradeChoCh : InpTradeBOS;
      g_trend = -1;

      if(canTrade && lastBar != g_lastSignalBar)
      {
         g_lastSignalBar = lastBar;

         //--- SL = high of the swing structure (the last pivot high)
         double slPrice = g_lastHighPrice;
         if(slPrice <= 0)
            slPrice = g_candles[g_lastLowBar].high;

         Print("[BoS_ChoCh_Trader] BEARISH ", lbl, " detected! Price=", currentClose,
               " broke below ", g_lastLowPrice, " | SL=", slPrice);
         ExecuteSell(slPrice, lbl);

         if(InpDrawSignals)
            DrawSignal(g_lastLowPrice, g_lastLowTime,
                      g_candles[lastBar].openTime, InpBearColor, false, lbl);
      }

      g_lastLowBar   = -1;
      g_lastLowPrice = DBL_MAX;
   }
}

//+------------------------------------------------------------------+
//| Check structure on the last closed candle (seconds mode) - LEGACY  |
//+------------------------------------------------------------------+
void CheckStructure()
{
   // Now handled by ScanForNewPivots() + CheckBreak()
   return;
}

//+------------------------------------------------------------------+
//| Full recalculation for chart-bar mode (find latest signal)         |
//+------------------------------------------------------------------+
void CheckStructureFull()
{
   if(g_candleCount < InpPivotLB + InpPivotRB + 5) return;

   int limit = g_candleCount - InpPivotRB;

   for(int i = InpPivotLB; i < limit; i++)
   {
      if(IsPivotHigh(i))
      {
         g_lastHighPrice = g_candles[i].high;
         g_lastHighTime  = g_candles[i].openTime;
         g_lastHighBar   = i;
      }

      if(IsPivotLow(i))
      {
         g_lastLowPrice = g_candles[i].low;
         g_lastLowTime  = g_candles[i].openTime;
         g_lastLowBar   = i;
      }

      //--- Bullish break
      if(g_lastHighBar >= 0 && i > g_lastHighBar && g_candles[i].close > g_lastHighPrice)
      {
         string lbl = (g_trend == -1) ? "ChoCh" : "BoS";
         g_trend = 1;
         g_lastHighBar = -1;
         g_lastHighPrice = 0;
      }

      //--- Bearish break
      if(g_lastLowBar >= 0 && i > g_lastLowBar && g_candles[i].close < g_lastLowPrice)
      {
         string lbl = (g_trend == 1) ? "ChoCh" : "BoS";
         g_trend = -1;
         g_lastLowBar = -1;
         g_lastLowPrice = DBL_MAX;
      }
   }

   //--- Now check the very last bar for a live signal
   int lastBar = g_candleCount - 1;

   if(g_lastHighBar >= 0 && g_candles[lastBar].close > g_lastHighPrice)
   {
      string lbl = (g_trend == -1) ? "ChoCh" : "BoS";
      bool canTrade = (g_trend == -1) ? InpTradeChoCh : InpTradeBOS;
      g_trend = 1;

      if(canTrade && lastBar != g_lastSignalBar)
      {
         g_lastSignalBar = lastBar;
         double slPrice = g_lastLowPrice;
         if(slPrice >= DBL_MAX || slPrice <= 0)
            slPrice = g_candles[g_lastHighBar].low;
         ExecuteBuy(slPrice, lbl);
      }
      g_lastHighBar = -1;
      g_lastHighPrice = 0;
   }

   if(g_lastLowBar >= 0 && g_candles[lastBar].close < g_lastLowPrice)
   {
      string lbl = (g_trend == 1) ? "ChoCh" : "BoS";
      bool canTrade = (g_trend == 1) ? InpTradeChoCh : InpTradeBOS;
      g_trend = -1;

      if(canTrade && lastBar != g_lastSignalBar)
      {
         g_lastSignalBar = lastBar;
         double slPrice = g_lastHighPrice;
         if(slPrice <= 0)
            slPrice = g_candles[g_lastLowBar].high;
         ExecuteSell(slPrice, lbl);
      }
      g_lastLowBar = -1;
      g_lastLowPrice = DBL_MAX;
   }
}

//+------------------------------------------------------------------+
//| PIVOT DETECTION                                                    |
//+------------------------------------------------------------------+
bool IsPivotHigh(int bar)
{
   if(bar - InpPivotLB < 0 || bar + InpPivotRB >= g_candleCount) return false;
   for(int j = bar - InpPivotLB; j <= bar + InpPivotRB; j++)
      if(j != bar && g_candles[j].high >= g_candles[bar].high) return false;
   return true;
}

bool IsPivotLow(int bar)
{
   if(bar - InpPivotLB < 0 || bar + InpPivotRB >= g_candleCount) return false;
   for(int j = bar - InpPivotLB; j <= bar + InpPivotRB; j++)
      if(j != bar && g_candles[j].low <= g_candles[bar].low) return false;
   return true;
}

//+------------------------------------------------------------------+
//| EXECUTE BUY                                                        |
//+------------------------------------------------------------------+
void ExecuteBuy(double slPrice, string comment)
{
   if(CountOpenTrades() >= InpMaxTrades)
   {
      Print("[BoS_ChoCh_Trader] Max trades reached. Skipping BUY.");
      return;
   }

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

   //--- SL must be below entry
   if(slPrice >= ask)
      slPrice = ask - 50 * point;  // Fallback: 50 points SL

   double slDistance = ask - slPrice;
   if(slDistance <= 0) return;

   //--- Calculate lot size based on risk %
   double lots = CalculateLotSize(slDistance);
   if(lots <= 0) return;

   //--- TP based on R:R
   double tp = 0;
   if(InpRR > 0)
      tp = NormalizeDouble(ask + slDistance * InpRR, digits);

   double sl = NormalizeDouble(slPrice, digits);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = Symbol();
   request.volume    = lots;
   request.type      = ORDER_TYPE_BUY;
   request.price     = NormalizeDouble(ask, digits);
   request.sl        = sl;
   request.tp        = tp;
   request.deviation = InpSlippage;
   request.magic     = InpMagic;
   request.comment   = "SMC_" + comment;

   if(OrderSend(request, result))
      Print("[BoS_ChoCh_Trader] BUY ", comment, " | Lots=", lots,
            " | Entry=", ask, " | SL=", sl, " | TP=", tp);
   else
      Print("[BoS_ChoCh_Trader] BUY FAILED! Error=", GetLastError(),
            " RetCode=", result.retcode);
}

//+------------------------------------------------------------------+
//| EXECUTE SELL                                                       |
//+------------------------------------------------------------------+
void ExecuteSell(double slPrice, string comment)
{
   if(CountOpenTrades() >= InpMaxTrades)
   {
      Print("[BoS_ChoCh_Trader] Max trades reached. Skipping SELL.");
      return;
   }

   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

   //--- SL must be above entry
   if(slPrice <= bid)
      slPrice = bid + 50 * point;  // Fallback: 50 points SL

   double slDistance = slPrice - bid;
   if(slDistance <= 0) return;

   //--- Calculate lot size based on risk %
   double lots = CalculateLotSize(slDistance);
   if(lots <= 0) return;

   //--- TP based on R:R
   double tp = 0;
   if(InpRR > 0)
      tp = NormalizeDouble(bid - slDistance * InpRR, digits);

   double sl = NormalizeDouble(slPrice, digits);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = Symbol();
   request.volume    = lots;
   request.type      = ORDER_TYPE_SELL;
   request.price     = NormalizeDouble(bid, digits);
   request.sl        = sl;
   request.tp        = tp;
   request.deviation = InpSlippage;
   request.magic     = InpMagic;
   request.comment   = "SMC_" + comment;

   if(OrderSend(request, result))
      Print("[BoS_ChoCh_Trader] SELL ", comment, " | Lots=", lots,
            " | Entry=", bid, " | SL=", sl, " | TP=", tp);
   else
      Print("[BoS_ChoCh_Trader] SELL FAILED! Error=", GetLastError(),
            " RetCode=", result.retcode);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk %                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney  = balance * (InpRiskPercent / 100.0);
   double tickValue  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double lotMin     = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double lotMax     = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double lotStep    = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   if(tickValue <= 0 || tickSize <= 0 || slDistancePrice <= 0)
      return lotMin;

   //--- Risk money / (SL in ticks * tick value)
   double slTicks = slDistancePrice / tickSize;
   double lots    = riskMoney / (slTicks * tickValue);

   //--- Round to lot step
   lots = MathFloor(lots / lotStep) * lotStep;

   //--- Clamp
   if(lots < lotMin) lots = lotMin;
   if(lots > lotMax) lots = lotMax;

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Count open trades with our magic number                            |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(PositionGetTicket(i)))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
            PositionGetString(POSITION_SYMBOL) == Symbol())
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Trim candle array to keep memory clean                             |
//+------------------------------------------------------------------+
void TrimCandles()
{
   int keep = 300;
   int remove = g_candleCount - keep;
   if(remove <= 0) return;

   SCandle temp[];
   ArrayResize(temp, keep);
   for(int i = 0; i < keep; i++)
      temp[i] = g_candles[remove + i];

   ArrayResize(g_candles, keep);
   for(int i = 0; i < keep; i++)
      g_candles[i] = temp[i];

   g_candleCount = keep;
   ArrayFree(temp);

   //--- Adjust bar indices
   if(g_lastHighBar >= 0) g_lastHighBar -= remove;
   if(g_lastLowBar >= 0)  g_lastLowBar  -= remove;
   if(g_lastHighBar < 0)  { g_lastHighBar = -1; g_lastHighPrice = 0; }
   if(g_lastLowBar < 0)   { g_lastLowBar = -1; g_lastLowPrice = DBL_MAX; }
   g_lastSignalBar -= remove;
}

//+------------------------------------------------------------------+
//| Draw signal line on chart                                          |
//+------------------------------------------------------------------+
void DrawSignal(double price, datetime t1, datetime t2,
                color col, bool isHigh, string label)
{
   g_objIdx++;
   string lnName  = "BST_L" + IntegerToString(g_objIdx);
   string txtName = "BST_T" + IntegerToString(g_objIdx);

   ObjectDelete(0, lnName);
   if(ObjectCreate(0, lnName, OBJ_TREND, 0, t1, price, t2, price))
   {
      ObjectSetInteger(0, lnName, OBJPROP_COLOR, col);
      ObjectSetInteger(0, lnName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, lnName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, lnName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, lnName, OBJPROP_BACK, true);
      ObjectSetInteger(0, lnName, OBJPROP_SELECTABLE, false);
   }

   ObjectDelete(0, txtName);
   datetime midT = (datetime)(((long)t1 + (long)t2) / 2);
   if(ObjectCreate(0, txtName, OBJ_TEXT, 0, midT, price))
   {
      ObjectSetString(0, txtName, OBJPROP_TEXT, label);
      ObjectSetInteger(0, txtName, OBJPROP_COLOR, col);
      ObjectSetInteger(0, txtName, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, txtName, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, txtName, OBJPROP_ANCHOR, isHigh ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, txtName, OBJPROP_SELECTABLE, false);
   }

   ChartRedraw(0);
}
//+------------------------------------------------------------------+
