//+------------------------------------------------------------------+
//|                                            HalfTrendSMC_EA.mq5   |
//|  SELF-CONTAINED EA - No external indicators needed!               |
//|                                                                   |
//|  STRATEGY:                                                        |
//|   1. HalfTrend flips to NEW trend (bull or bear)                  |
//|   2. Price touches/wicks through the HalfTrend line               |
//|      (even 1 tick below/above = touch)                            |
//|   3. After touch: wait for internal BOS or CHoCH PRO-TREND        |
//|   4. Entry at market on close of BOS/CHoCH bar                    |
//|   5. SL = sequence low (BUY) / sequence high (SELL)               |
//|   6. TP = swing high (BUY) / swing low (SELL)                     |
//|   7. ONE trade per HalfTrend flip only                            |
//|   8. Lot size = 1% account risk based on SL distance              |
//|   9. Time filter for session control                              |
//|  10. Draws HalfTrend + BOS/CHoCH on chart (visible in backtest)  |
//+------------------------------------------------------------------+
#property copyright "HalfTrend + SMC EA"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "═══════════ GENERAL ═══════════"
input double InpRiskPercent      = 1.0;     // Risk % per trade
input int    InpMagic            = 887766;  // Magic Number
input int    InpSlippage         = 30;      // Slippage (points)
input int    InpMaxSpreadPts     = 50;      // Max Spread (points, 0=off)

input group "═══════════ HALFTREND ═══════════"
input int    InpHT_Amplitude     = 2;       // HalfTrend Amplitude
input int    InpHT_ChannelDev    = 2;       // HalfTrend Channel Deviation

input group "═══════════ SMC ═══════════"
input int    InpSMC_InternalLen  = 5;       // Internal Swing Length (BOS/CHoCH)
input int    InpSMC_SwingLen     = 50;      // Major Swing Length (TP source)

input group "═══════════ SETUP ═══════════"
input int    InpTouchExpiry      = 20;      // Bars before touch expires
input double InpMinRR            = 1.0;     // Minimum Risk:Reward (0=off)
input int    InpSLBufferPts      = 30;      // SL buffer (points)

input group "═══════════ TIME FILTER ═══════════"
input bool   InpUseTimeFilter    = true;    // Enable Time Filter
input int    InpStartHour        = 2;       // Start Hour (server time)
input int    InpStartMinute      = 0;       // Start Minute
input int    InpEndHour          = 22;      // End Hour (server time)
input int    InpEndMinute        = 0;       // End Minute

input group "═══════════ TRADE MANAGEMENT ═══════════"
input bool   InpMoveToBreakeven  = true;    // Move SL to Breakeven at +1R
input bool   InpTrailWithHT      = false;   // Trail SL with HalfTrend line

//+------------------------------------------------------------------+
//| STRUCTURES                                                        |
//+------------------------------------------------------------------+
struct PivotPoint
{
   double   level;
   double   lastLevel;
   bool     crossed;
   int      barIdx;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade      g_trade;
int         g_atrHandle = INVALID_HANDLE;
datetime    g_lastBarTime = 0;

//--- HalfTrend state
double g_htLine[];        // HT line values (ring buffer not needed, use array)
int    g_htTrend;         // 0=bull, 1=bear
int    g_htPrevTrend;     // previous bar trend
double g_ht_maxLow, g_ht_minHigh, g_ht_up, g_ht_down;
int    g_ht_nextTrend;

//--- SMC state
PivotPoint g_intHigh, g_intLow;     // internal pivots
PivotPoint g_swHigh, g_swLow;       // swing pivots
int g_intTrendBias;                  // internal trend bias
int g_swTrendBias;                   // swing trend bias
double g_swingHigh, g_swingLow;     // current swing H/L for TP

//--- EA State Machine
enum ENUM_EA_STATE { STATE_WAIT_FLIP, STATE_WAIT_TOUCH, STATE_WAIT_BOS, STATE_DONE };
ENUM_EA_STATE g_state;
int    g_touchBarsAgo;
bool   g_tradeTaken;
double g_lastHTLine;      // HT line value on last closed bar

//--- Drawing
int g_objCount = 0;



//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+
string MakeObjName(string prefix)
{
   g_objCount++;
   return "HTSMC_"+prefix+"_"+IntegerToString(g_objCount);
}

void InitPivot(PivotPoint &p)
{
   p.level=0; p.lastLevel=0; p.crossed=false; p.barIdx=0;
}

//+------------------------------------------------------------------+
//| DRAWING (visible in backtest)                                     |
//+------------------------------------------------------------------+
void DrawHTLine(datetime t1, datetime t2, double price, color clr)
{
   string n = MakeObjName("HTL");
   ObjectCreate(0, n, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
}

void DrawStructureLine(datetime t1, datetime t2, double price, color clr, bool dashed)
{
   string n = MakeObjName("SL");
   ObjectCreate(0, n, OBJ_TREND, 0, t1, price, t2, price);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_STYLE, dashed ? STYLE_DASH : STYLE_SOLID);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
}

void DrawLabel(datetime t, double price, string text, color clr, bool above)
{
   string n = MakeObjName("LB");
   ObjectCreate(0, n, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
}

void DrawArrow(datetime t, double price, color clr, int code)
{
   string n = MakeObjName("AR");
   ObjectCreate(0, n, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, n, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
//| UTILITY: Lot size based on % risk                                |
//+------------------------------------------------------------------+
double CalcLotSize(double slDistance)
{
   if(slDistance <= 0) return 0;
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(tickValue <= 0 || tickSize <= 0) return minLot;
   double slTicks    = slDistance / tickSize;
   double riskPerLot = slTicks * tickValue;
   if(riskPerLot <= 0) return minLot;
   double lots = riskAmount / riskPerLot;
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| UTILITY: Time filter                                             |
//+------------------------------------------------------------------+
bool IsWithinTradingTime()
{
   if(!InpUseTimeFilter) return true;
   MqlDateTime dt;
   TimeCurrent(dt);
   int cur   = dt.hour * 60 + dt.min;
   int start = InpStartHour * 60 + InpStartMinute;
   int end   = InpEndHour * 60 + InpEndMinute;
   if(start < end)
      return (cur >= start && cur < end);
   else
      return (cur >= start || cur < end);
}

//+------------------------------------------------------------------+
//| UTILITY: Has open position                                       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return true;
   }
   return false;
}



//+------------------------------------------------------------------+
//| HALFTREND CALCULATION (built-in, no external indicator)          |
//| Returns: HT line value for bar at shift                          |
//| Updates: g_htTrend, g_ht_* state variables                      |
//+------------------------------------------------------------------+
double CalcHalfTrend(int shift, double atrVal)
{
   double atr2 = (atrVal > 0) ? atrVal / 2.0 : 0;

   // Highest high / lowest low over amplitude
   double highPrice = iHigh(_Symbol, _Period, shift);
   double lowPrice  = iLow(_Symbol, _Period, shift);
   for(int j = 1; j < InpHT_Amplitude; j++)
   {
      double h = iHigh(_Symbol, _Period, shift + j);
      double l = iLow(_Symbol, _Period, shift + j);
      if(h > highPrice) highPrice = h;
      if(l < lowPrice)  lowPrice  = l;
   }

   // SMA of high/low
   double highma = 0, lowma = 0;
   for(int j = 0; j < InpHT_Amplitude; j++)
   {
      highma += iHigh(_Symbol, _Period, shift + j);
      lowma  += iLow(_Symbol, _Period, shift + j);
   }
   highma /= InpHT_Amplitude;
   lowma  /= InpHT_Amplitude;

   double prevLow  = iLow(_Symbol, _Period, shift + 1);
   double prevHigh = iHigh(_Symbol, _Period, shift + 1);
   double closeNow = iClose(_Symbol, _Period, shift);

   int trend     = g_htTrend;
   int nextTrend = g_ht_nextTrend;
   double maxLow = g_ht_maxLow;
   double minHigh= g_ht_minHigh;
   double up     = g_ht_up;
   double down   = g_ht_down;

   if(nextTrend == 1)
   {
      maxLow = MathMax(lowPrice, maxLow);
      if(highma < maxLow && closeNow < prevLow)
      {
         trend     = 1;
         nextTrend = 0;
         minHigh   = highPrice;
      }
   }
   else
   {
      minHigh = MathMin(highPrice, minHigh);
      if(lowma > minHigh && closeNow > prevHigh)
      {
         trend     = 0;
         nextTrend = 1;
         maxLow    = lowPrice;
      }
   }

   if(trend == 0)
   {
      if(g_htTrend != 0)
         up = down;
      else
         up = MathMax(maxLow, up);
   }
   else
   {
      if(g_htTrend != 1)
         down = up;
      else
         down = MathMin(minHigh, down);
   }

   double ht = (trend == 0) ? up : down;

   // Save state
   g_htPrevTrend  = g_htTrend;
   g_htTrend      = trend;
   g_ht_nextTrend = nextTrend;
   g_ht_maxLow    = maxLow;
   g_ht_minHigh   = minHigh;
   g_ht_up        = up;
   g_ht_down      = down;

   return ht;
}

//+------------------------------------------------------------------+
//| SMC: Detect pivot highs/lows                                     |
//+------------------------------------------------------------------+
bool IsPivotHigh(int shift, int size)
{
   double pivotVal = iHigh(_Symbol, _Period, shift);
   for(int i = 1; i <= size; i++)
   {
      if(iHigh(_Symbol, _Period, shift + i) > pivotVal) return false;
      if(iHigh(_Symbol, _Period, shift - i) > pivotVal) return false;
   }
   return true;
}

bool IsPivotLow(int shift, int size)
{
   double pivotVal = iLow(_Symbol, _Period, shift);
   for(int i = 1; i <= size; i++)
   {
      if(iLow(_Symbol, _Period, shift + i) < pivotVal) return false;
      if(iLow(_Symbol, _Period, shift - i) < pivotVal) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| SMC: Update internal pivots                                      |
//+------------------------------------------------------------------+
void UpdateInternalPivots(int confirmedShift)
{
   // Check for pivot at confirmedShift (needs InpSMC_InternalLen bars on each side)
   int pivotShift = confirmedShift + InpSMC_InternalLen;

   if(IsPivotHigh(pivotShift, InpSMC_InternalLen))
   {
      double val = iHigh(_Symbol, _Period, pivotShift);
      if(val != g_intHigh.level)
      {
         g_intHigh.lastLevel = g_intHigh.level;
         g_intHigh.level     = val;
         g_intHigh.crossed   = false;
         g_intHigh.barIdx    = pivotShift;
      }
   }

   if(IsPivotLow(pivotShift, InpSMC_InternalLen))
   {
      double val = iLow(_Symbol, _Period, pivotShift);
      if(val != g_intLow.level)
      {
         g_intLow.lastLevel = g_intLow.level;
         g_intLow.level     = val;
         g_intLow.crossed   = false;
         g_intLow.barIdx    = pivotShift;
      }
   }
}

//+------------------------------------------------------------------+
//| SMC: Update swing pivots (major - for TP)                        |
//+------------------------------------------------------------------+
void UpdateSwingPivots(int confirmedShift)
{
   int pivotShift = confirmedShift + InpSMC_SwingLen;

   if(IsPivotHigh(pivotShift, InpSMC_SwingLen))
   {
      double val = iHigh(_Symbol, _Period, pivotShift);
      if(val != g_swHigh.level)
      {
         g_swHigh.lastLevel = g_swHigh.level;
         g_swHigh.level     = val;
         g_swHigh.crossed   = false;
         g_swHigh.barIdx    = pivotShift;
         g_swingHigh        = val;
      }
   }

   if(IsPivotLow(pivotShift, InpSMC_SwingLen))
   {
      double val = iLow(_Symbol, _Period, pivotShift);
      if(val != g_swLow.level)
      {
         g_swLow.lastLevel = g_swLow.level;
         g_swLow.level     = val;
         g_swLow.crossed   = false;
         g_swLow.barIdx    = pivotShift;
         g_swingLow        = val;
      }
   }
}



//+------------------------------------------------------------------+
//| SMC: Check for BOS/CHoCH on just-closed bar (shift=1)            |
//| Returns: +1 bullish break, -1 bearish break, 0 none              |
//| Outputs: tag (1=BOS,2=CHoCH), seqLow, seqHigh                   |
//+------------------------------------------------------------------+
int CheckInternalBreak(double &seqLow, double &seqHigh, int &tag)
{
   double closeNow  = iClose(_Symbol, _Period, 1);
   double closePrev = iClose(_Symbol, _Period, 2);

   // Bullish break: close crosses above internal high pivot
   if(g_intHigh.level > 0 && !g_intHigh.crossed)
   {
      if(closeNow > g_intHigh.level && closePrev <= g_intHigh.level)
      {
         g_intHigh.crossed = true;
         tag = (g_intTrendBias == -1) ? 2 : 1;  // CHoCH or BOS
         g_intTrendBias = +1;

         // Sequence low = lowest low from pivot bar to current bar
         double lo = iLow(_Symbol, _Period, 1);
         for(int k = 1; k <= g_intHigh.barIdx; k++)
         {
            double l = iLow(_Symbol, _Period, k);
            if(l < lo) lo = l;
         }
         seqLow = lo;

         // Sequence high
         double hi = iHigh(_Symbol, _Period, 1);
         for(int k = 1; k <= g_intHigh.barIdx; k++)
         {
            double h = iHigh(_Symbol, _Period, k);
            if(h > hi) hi = h;
         }
         seqHigh = hi;

         // Draw on chart
         datetime t1 = iTime(_Symbol, _Period, g_intHigh.barIdx);
         datetime t2 = iTime(_Symbol, _Period, 1);
         DrawStructureLine(t1, t2, g_intHigh.level, clrGreen, true);
         datetime mt = (datetime)(((long)t1 + (long)t2) / 2);
         DrawLabel(mt, g_intHigh.level, (tag==2)?"CHoCH":"BOS", clrGreen, true);

         return +1;
      }
   }

   // Bearish break: close crosses below internal low pivot
   if(g_intLow.level > 0 && !g_intLow.crossed)
   {
      if(closeNow < g_intLow.level && closePrev >= g_intLow.level)
      {
         g_intLow.crossed = true;
         tag = (g_intTrendBias == +1) ? 2 : 1;  // CHoCH or BOS
         g_intTrendBias = -1;

         // Sequence high = highest high from pivot bar to current bar
         double hi = iHigh(_Symbol, _Period, 1);
         for(int k = 1; k <= g_intLow.barIdx; k++)
         {
            double h = iHigh(_Symbol, _Period, k);
            if(h > hi) hi = h;
         }
         seqHigh = hi;

         // Sequence low
         double lo = iLow(_Symbol, _Period, 1);
         for(int k = 1; k <= g_intLow.barIdx; k++)
         {
            double l = iLow(_Symbol, _Period, k);
            if(l < lo) lo = l;
         }
         seqLow = lo;

         // Draw on chart
         datetime t1 = iTime(_Symbol, _Period, g_intLow.barIdx);
         datetime t2 = iTime(_Symbol, _Period, 1);
         DrawStructureLine(t1, t2, g_intLow.level, clrRed, true);
         datetime mt = (datetime)(((long)t1 + (long)t2) / 2);
         DrawLabel(mt, g_intLow.level, (tag==2)?"CHoCH":"BOS", clrRed, false);

         return -1;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT                                                  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   posType = PositionGetInteger(POSITION_TYPE);
      double openPr  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL   = PositionGetDouble(POSITION_SL);
      double curTP   = PositionGetDouble(POSITION_TP);
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double pt      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      double newSL = curSL;

      // Breakeven at +1R
      if(InpMoveToBreakeven && curSL != 0)
      {
         double oneR = MathAbs(openPr - curSL);
         if(posType == POSITION_TYPE_BUY && bid - openPr >= oneR && curSL < openPr)
            newSL = openPr + pt;
         if(posType == POSITION_TYPE_SELL && openPr - ask >= oneR && curSL > openPr)
            newSL = openPr - pt;
      }

      // Trail with HT line
      if(InpTrailWithHT && g_lastHTLine > 0)
      {
         if(posType == POSITION_TYPE_BUY && g_lastHTLine > newSL && g_lastHTLine < bid)
            newSL = g_lastHTLine;
         if(posType == POSITION_TYPE_SELL && g_lastHTLine < newSL && g_lastHTLine > ask)
            newSL = g_lastHTLine;
      }

      newSL = NormalizeDouble(newSL, digits);
      if(newSL != NormalizeDouble(curSL, digits) && newSL > 0)
         g_trade.PositionModify(ticket, newSL, curTP);
   }
}



//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_atrHandle = iATR(_Symbol, _Period, 100);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("EA: Failed to create ATR handle");
      return(INIT_FAILED);
   }

   // Init HT state
   g_htTrend      = 0;
   g_htPrevTrend  = 0;
   g_ht_nextTrend = 0;
   g_ht_maxLow    = 0;
   g_ht_minHigh   = 99999;
   g_ht_up        = 0;
   g_ht_down      = 99999;
   g_lastHTLine   = 0;

   // Init SMC state
   InitPivot(g_intHigh); InitPivot(g_intLow);
   InitPivot(g_swHigh);  InitPivot(g_swLow);
   g_intTrendBias = 0;
   g_swTrendBias  = 0;
   g_swingHigh    = 0;
   g_swingLow     = 0;

   // Init EA state
   g_state        = STATE_WAIT_FLIP;
   g_touchBarsAgo = -1;
   g_tradeTaken   = false;
   g_lastBarTime  = 0;
   g_objCount     = 0;

   Print("EA Initialized: HalfTrend + SMC (Self-Contained)");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   // Clean up chart objects
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total-1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, "HTSMC_") == 0)
         ObjectDelete(0, n);
   }
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Manage positions every tick
   ManageOpenPositions();

   // Only process on new bar
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0) return;
   if(t0 == g_lastBarTime) return;
   g_lastBarTime = t0;

   // Need enough bars
   int barsNeeded = MathMax(InpSMC_SwingLen * 2 + 5, 200);
   if(Bars(_Symbol, _Period) < barsNeeded) return;

   //=== GET ATR ===
   double atrBuf[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) <= 0) return;
   double atr = atrBuf[0];

   //=== CALCULATE HALFTREND for bar[1] (just closed) ===
   double htLine = CalcHalfTrend(1, atr);
   g_lastHTLine = htLine;

   // Draw HT line segment
   if(htLine > 0)
   {
      datetime t1 = iTime(_Symbol, _Period, 2);
      datetime t2 = iTime(_Symbol, _Period, 1);
      color htColor = (g_htTrend == 0) ? clrDodgerBlue : clrCrimson;
      DrawHTLine(t1, t2, htLine, htColor);
   }

   // Detect HT FLIP
   bool htFlipped = (g_htPrevTrend >= 0 && g_htTrend != g_htPrevTrend);

   if(htFlipped)
   {
      g_state        = STATE_WAIT_TOUCH;
      g_touchBarsAgo = -1;
      g_tradeTaken   = false;

      // Draw flip arrow
      datetime at = iTime(_Symbol, _Period, 1);
      if(g_htTrend == 0)
         DrawArrow(at, iLow(_Symbol, _Period, 1) - atr*0.3, clrDodgerBlue, 233);
      else
         DrawArrow(at, iHigh(_Symbol, _Period, 1) + atr*0.3, clrCrimson, 234);

      PrintFormat("EA: HT FLIP -> %s", g_htTrend==0 ? "BULL" : "BEAR");
   }

   //=== UPDATE SMC PIVOTS ===
   // Internal pivots (confirmed at shift = InpSMC_InternalLen)
   if(Bars(_Symbol, _Period) > InpSMC_InternalLen * 2 + 2)
      UpdateInternalPivots(1);

   // Swing pivots (confirmed at shift = InpSMC_SwingLen)
   if(Bars(_Symbol, _Period) > InpSMC_SwingLen * 2 + 2)
      UpdateSwingPivots(1);

   //=== STATE MACHINE ===
   switch(g_state)
   {
      case STATE_WAIT_FLIP:
         // waiting, handled above
         break;

      case STATE_WAIT_TOUCH:
         CheckTouch();
         break;

      case STATE_WAIT_BOS:
         CheckEntry(atr);
         break;

      case STATE_DONE:
         break;
   }
}

//+------------------------------------------------------------------+
//| Check if price touched HT line                                   |
//+------------------------------------------------------------------+
void CheckTouch()
{
   if(g_tradeTaken) return;
   if(g_lastHTLine <= 0) return;

   double barHigh = iHigh(_Symbol, _Period, 1);
   double barLow  = iLow(_Symbol, _Period, 1);

   bool touched = false;
   if(g_htTrend == 0)  // Bull: low touches or goes below HT line
      touched = (barLow <= g_lastHTLine);
   else                // Bear: high touches or goes above HT line
      touched = (barHigh >= g_lastHTLine);

   if(touched)
   {
      g_state        = STATE_WAIT_BOS;
      g_touchBarsAgo = 0;
      PrintFormat("EA: TOUCH! HT=%.5f Low=%.5f High=%.5f", g_lastHTLine, barLow, barHigh);
   }
}

//+------------------------------------------------------------------+
//| Check for pro-trend BOS/CHoCH entry                              |
//+------------------------------------------------------------------+
void CheckEntry(double atr)
{
   if(g_tradeTaken) return;

   g_touchBarsAgo++;
   if(g_touchBarsAgo > InpTouchExpiry)
   {
      g_state = STATE_WAIT_TOUCH;
      g_touchBarsAgo = -1;
      Print("EA: Touch expired");
      return;
   }

   if(HasOpenPosition()) return;
   if(!IsWithinTradingTime()) return;

   // Spread filter
   if(InpMaxSpreadPts > 0)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPts) return;
   }

   // Check for internal BOS/CHoCH
   double seqLow = 0, seqHigh = 0;
   int tag = 0;
   int signal = CheckInternalBreak(seqLow, seqHigh, tag);

   if(signal == 0) return;

   // Pro-trend filter
   bool bullEntry = (g_htTrend == 0) && (signal > 0);
   bool bearEntry = (g_htTrend == 1) && (signal < 0);
   if(!bullEntry && !bearEntry) return;

   // Calculate SL/TP/Entry
   double pt     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = InpSLBufferPts * pt;

   double sl = 0, tp = 0, entry = 0;

   if(bullEntry)
   {
      entry = ask;
      sl    = seqLow - buffer;
      tp    = g_swingHigh;
      if(sl <= 0 || tp <= 0 || tp <= entry || sl >= entry) return;
   }
   else
   {
      entry = bid;
      sl    = seqHigh + buffer;
      tp    = g_swingLow;
      if(sl <= 0 || tp <= 0 || tp >= entry || sl <= entry) return;
   }

   // RR check
   double risk   = MathAbs(entry - sl);
   double reward = MathAbs(tp - entry);
   if(risk <= 0) return;
   if(InpMinRR > 0 && (reward / risk) < InpMinRR) return;

   // Stops level
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist  = stopsLevel * pt;
   if(risk < minDist || reward < minDist) return;

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Lot size
   double lots = CalcLotSize(risk);
   if(lots <= 0) return;

   // Execute
   string comment = StringFormat("HT+SMC %s RR=%.1f", bullEntry?"BUY":"SELL", reward/risk);
   bool ok = false;
   if(bullEntry)
      ok = g_trade.Buy(lots, _Symbol, entry, sl, tp, comment);
   else
      ok = g_trade.Sell(lots, _Symbol, entry, sl, tp, comment);

   if(ok)
   {
      PrintFormat("EA: %s | Lots=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f | RR=%.2f | %s",
                  bullEntry?"BUY":"SELL", lots, entry, sl, tp, reward/risk,
                  (tag==2)?"CHoCH":"BOS");
      g_tradeTaken = true;
      g_state      = STATE_DONE;

      // Draw entry marker
      datetime at = iTime(_Symbol, _Period, 1);
      DrawArrow(at, entry, bullEntry?clrLime:clrOrangeRed, bullEntry?233:234);
   }
   else
   {
      PrintFormat("EA: FAILED | %d | %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
}
//+------------------------------------------------------------------+
