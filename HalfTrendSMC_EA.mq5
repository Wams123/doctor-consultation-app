//+------------------------------------------------------------------+
//|                                            HalfTrendSMC_EA.mq5   |
//|                                                                   |
//|  STRATEGY:                                                        |
//|   1. HalfTrend flips to NEW trend (bull or bear)                  |
//|   2. Price touches/wicks through the HalfTrend line               |
//|      (even 1 pip/tick below line = touch in uptrend)              |
//|   3. After touch: wait for internal BOS or CHoCH PRO-TREND        |
//|   4. Entry at market on close of BOS/CHoCH bar                    |
//|   5. SL = sequence low (BUY) / sequence high (SELL)               |
//|   6. TP = swing high (BUY) / swing low (SELL)                     |
//|   7. ONE trade per HalfTrend flip only                            |
//|   8. Lot size = 1% account risk based on SL distance              |
//|   9. Time filter for session control                              |
//|                                                                   |
//|  REQUIREMENTS:                                                    |
//|   - Place HalfTrend.mq5 in MQL5/Indicators/                      |
//|   - Place SmartMoneyConcepts.mq5 in MQL5/Indicators/              |
//|   - Both indicators will be visible on chart during backtest      |
//+------------------------------------------------------------------+
#property copyright "HalfTrend + SMC EA"
#property version   "1.00"
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
input bool   InpOneTradeAtATime  = true;    // Only one trade at a time

input group "═══════════ HALFTREND ═══════════"
input int    InpHT_Amplitude     = 2;       // HalfTrend Amplitude
input int    InpHT_ChannelDev    = 2;       // HalfTrend Channel Deviation
input bool   InpHT_ShowArrows    = true;    // Show HT Arrows on chart
input bool   InpHT_ShowChannels  = true;    // Show HT Channels on chart

input group "═══════════ SMC ═══════════"
input int    InpSMC_Style        = 0;       // SMC Style (0=Colored, 1=Mono)
input int    InpSMC_InternalLen  = 5;       // Internal Swing Length
input int    InpSMC_SwingLen     = 50;      // Major Swing Length (TP source)

input group "═══════════ SETUP ═══════════"
input int    InpTouchExpiry      = 20;      // Bars before touch expires
input double InpMinRR            = 1.0;     // Minimum Risk:Reward (0=off)
input int    InpSLBufferPts      = 30;      // SL buffer below/above (points)

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
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade      g_trade;
int         g_htHandle    = INVALID_HANDLE;
int         g_smcHandle   = INVALID_HANDLE;
datetime    g_lastBarTime = 0;

//--- State Machine
enum ENUM_EA_STATE
{
   STATE_WAIT_FLIP,       // Waiting for new HalfTrend flip
   STATE_WAIT_TOUCH,      // HT flipped, waiting for price to touch HT line
   STATE_WAIT_BOS,        // Touched, waiting for pro-trend BOS/CHoCH
   STATE_DONE             // Trade taken for this flip, wait for next flip
};

ENUM_EA_STATE g_state       = STATE_WAIT_FLIP;
int           g_htTrend     = -1;     // current HT trend: 0=bull, 1=bear
int           g_prevHTTrend = -1;     // previous HT trend (to detect flip)
int           g_touchBarsAgo= -1;     // bars since the touch happened
bool          g_tradeTaken  = false;  // flag: trade taken for current flip

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_FOK);

   //--- Create HalfTrend indicator handle
   // Input order: InpAmplitude, InpChannelDeviation, InpShowArrows, InpShowChannels
   g_htHandle = iCustom(_Symbol, _Period, "HalfTrend",
                        InpHT_Amplitude,
                        InpHT_ChannelDev,
                        InpHT_ShowArrows,
                        InpHT_ShowChannels);
   if(g_htHandle == INVALID_HANDLE)
   {
      PrintFormat("EA ERROR: Failed to load HalfTrend indicator. Error: %d", GetLastError());
      return(INIT_FAILED);
   }

   //--- Create SMC indicator handle
   // Input order matches SmartMoneyConcepts.mq5:
   //   InpStyle, InpShowInternals, InpInternalBull, InpInternalBullColor,
   //   InpInternalBear, InpInternalBearColor, InpConfluenceFilter,
   //   InpInternalLabelSize, InpInternalLength,
   //   InpShowStructure, InpSwingBull, InpSwingBullColor,
   //   InpSwingBear, InpSwingBearColor, InpSwingLabelSize,
   //   InpShowSwings, InpSwingsLength, InpShowHighLowSwings,
   //   InpShowEQHL, InpEQHLLength, InpEQHLThreshold, InpEQHLLabelSize
   g_smcHandle = iCustom(_Symbol, _Period, "SmartMoneyConcepts",
                         InpSMC_Style,        // Style
                         true,                // ShowInternals
                         0,                   // InternalBull = ALL
                         clrGreen,            // InternalBullColor
                         0,                   // InternalBear = ALL
                         clrRed,              // InternalBearColor
                         false,               // ConfluenceFilter
                         0,                   // InternalLabelSize = TINY
                         InpSMC_InternalLen,  // InternalLength
                         true,                // ShowStructure
                         0,                   // SwingBull = ALL
                         clrGreen,            // SwingBullColor
                         0,                   // SwingBear = ALL
                         clrRed,              // SwingBearColor
                         1,                   // SwingLabelSize = SMALL
                         true,                // ShowSwings
                         InpSMC_SwingLen,     // SwingsLength
                         true,                // ShowHighLowSwings
                         true,                // ShowEQHL
                         3,                   // EQHLLength
                         0.1,                 // EQHLThreshold
                         0                    // EQHLLabelSize = TINY
                         );
   if(g_smcHandle == INVALID_HANDLE)
   {
      PrintFormat("EA ERROR: Failed to load SmartMoneyConcepts indicator. Error: %d", GetLastError());
      return(INIT_FAILED);
   }

   g_state       = STATE_WAIT_FLIP;
   g_htTrend     = -1;
   g_prevHTTrend = -1;
   g_touchBarsAgo= -1;
   g_tradeTaken  = false;
   g_lastBarTime = 0;

   Print("EA Initialized: HalfTrend + SMC Strategy");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_htHandle  != INVALID_HANDLE) IndicatorRelease(g_htHandle);
   if(g_smcHandle != INVALID_HANDLE) IndicatorRelease(g_smcHandle);
   Print("EA Deinitialized");
}



//+------------------------------------------------------------------+
//| UTILITY: Read single buffer value at given shift                 |
//+------------------------------------------------------------------+
bool ReadBuf(int handle, int bufIdx, int shift, double &val)
{
   double tmp[];
   ArraySetAsSeries(tmp, true);
   if(CopyBuffer(handle, bufIdx, shift, 1, tmp) <= 0) return false;
   val = tmp[0];
   return true;
}

//+------------------------------------------------------------------+
//| UTILITY: Check if we have an open position                       |
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
//| UTILITY: Calculate lot size based on 1% risk                     |
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

   double slTicks  = slDistance / tickSize;
   double riskPerLot = slTicks * tickValue;
   if(riskPerLot <= 0) return minLot;

   double lots = riskAmount / riskPerLot;

   // Round to lot step
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| UTILITY: Time filter check                                       |
//+------------------------------------------------------------------+
bool IsWithinTradingTime()
{
   if(!InpUseTimeFilter) return true;

   MqlDateTime dt;
   TimeCurrent(dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   int startMinutes   = InpStartHour * 60 + InpStartMinute;
   int endMinutes     = InpEndHour * 60 + InpEndMinute;

   if(startMinutes < endMinutes)
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   else // overnight session (e.g., 22:00 - 06:00)
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
}

//+------------------------------------------------------------------+
//| CORE: Update HalfTrend state and detect flip/touch               |
//+------------------------------------------------------------------+
void UpdateHalfTrendState()
{
   double trend = 0;
   if(!ReadBuf(g_htHandle, 6, 1, trend)) return;

   int currentTrend = (int)MathRound(trend);

   // Detect FLIP
   if(g_prevHTTrend >= 0 && currentTrend != g_prevHTTrend)
   {
      // NEW HalfTrend flip!
      g_state        = STATE_WAIT_TOUCH;
      g_touchBarsAgo = -1;
      g_tradeTaken   = false;
      PrintFormat("EA: HalfTrend FLIP detected -> %s", currentTrend==0 ? "BULLISH" : "BEARISH");
   }

   g_prevHTTrend = g_htTrend;
   g_htTrend     = currentTrend;
}

//+------------------------------------------------------------------+
//| CORE: Check if price touched the HalfTrend line                  |
//+------------------------------------------------------------------+
void CheckForTouch()
{
   if(g_state != STATE_WAIT_TOUCH) return;
   if(g_tradeTaken) return;

   double htLine = 0;
   if(!ReadBuf(g_htHandle, 0, 1, htLine)) return;
   if(htLine <= 0) return;

   double barHigh = iHigh(_Symbol, _Period, 1);
   double barLow  = iLow(_Symbol, _Period, 1);

   bool touched = false;

   if(g_htTrend == 0) // Bullish trend -> touch = low reaches or goes below HT line
   {
      // Even 1 tick below counts
      touched = (barLow <= htLine);
   }
   else if(g_htTrend == 1) // Bearish trend -> touch = high reaches or goes above HT line
   {
      touched = (barHigh >= htLine);
   }

   if(touched)
   {
      g_state        = STATE_WAIT_BOS;
      g_touchBarsAgo = 0;
      PrintFormat("EA: TOUCH detected! HT line=%.5f, barLow=%.5f, barHigh=%.5f",
                  htLine, barLow, barHigh);
   }
}

//+------------------------------------------------------------------+
//| CORE: Check for pro-trend BOS/CHoCH after touch                  |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(g_state != STATE_WAIT_BOS) return;
   if(g_tradeTaken) return;

   // Increment touch age
   g_touchBarsAgo++;

   // Expire touch if too old
   if(g_touchBarsAgo > InpTouchExpiry)
   {
      g_state = STATE_WAIT_TOUCH;  // go back to waiting for another touch
      g_touchBarsAgo = -1;
      Print("EA: Touch expired, going back to STATE_WAIT_TOUCH");
      return;
   }

   // Check if one trade limit reached
   if(InpOneTradeAtATime && HasOpenPosition()) return;

   // Time filter
   if(!IsWithinTradingTime()) return;

   // Spread filter
   if(InpMaxSpreadPts > 0)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPts) return;
   }

   // Read SMC buffers at shift=1 (just-closed bar)
   double smcSignal=0, smcTag=0, seqLow=0, seqHigh=0, swingHigh=0, swingLow=0;
   if(!ReadBuf(g_smcHandle, 0, 1, smcSignal)) return;
   if(!ReadBuf(g_smcHandle, 1, 1, smcTag))    return;
   if(!ReadBuf(g_smcHandle, 2, 1, seqLow))    return;
   if(!ReadBuf(g_smcHandle, 3, 1, seqHigh))   return;
   if(!ReadBuf(g_smcHandle, 4, 1, swingHigh)) return;
   if(!ReadBuf(g_smcHandle, 5, 1, swingLow))  return;

   // No signal on this bar
   if(smcSignal == 0) return;

   // Check pro-trend alignment
   bool bullEntry = (g_htTrend == 0) && (smcSignal > 0.5);   // HT bull + bull BOS/CHoCH
   bool bearEntry = (g_htTrend == 1) && (smcSignal < -0.5);  // HT bear + bear BOS/CHoCH

   if(!bullEntry && !bearEntry) return;

   // Validate levels
   double pt     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double buffer = InpSLBufferPts * pt;

   double sl=0, tp=0, entry=0;

   if(bullEntry)
   {
      entry = ask;
      sl    = seqLow - buffer;    // SL below lowest low of sequence + buffer
      tp    = swingHigh;           // TP at swing high

      if(sl <= 0 || tp <= 0 || tp <= entry || sl >= entry) return;
   }
   else // bearEntry
   {
      entry = bid;
      sl    = seqHigh + buffer;   // SL above highest high of sequence + buffer
      tp    = swingLow;            // TP at swing low

      if(sl <= 0 || tp <= 0 || tp >= entry || sl <= entry) return;
   }

   // Risk:Reward check
   double risk   = MathAbs(entry - sl);
   double reward = MathAbs(tp - entry);
   if(risk <= 0) return;
   if(InpMinRR > 0 && (reward / risk) < InpMinRR) return;

   // Stops level check
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist  = stopsLevel * pt;
   if(MathAbs(entry - sl) < minDist) return;
   if(MathAbs(tp - entry) < minDist) return;

   // Normalize
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Calculate lot size (1% risk)
   double lots = CalcLotSize(risk);
   if(lots <= 0) return;

   // Execute trade
   bool ok = false;
   string comment = StringFormat("HT+SMC %s | RR=%.1f", bullEntry?"BUY":"SELL", reward/risk);

   if(bullEntry)
      ok = g_trade.Buy(lots, _Symbol, entry, sl, tp, comment);
   else
      ok = g_trade.Sell(lots, _Symbol, entry, sl, tp, comment);

   if(ok)
   {
      PrintFormat("EA: %s OPENED | Lots=%.2f | Entry=%.5f | SL=%.5f | TP=%.5f | RR=%.2f | Tag=%s",
                  bullEntry ? "BUY" : "SELL",
                  lots, entry, sl, tp, reward/risk,
                  ((int)MathRound(smcTag)==2) ? "CHoCH" : "BOS");

      g_tradeTaken = true;
      g_state      = STATE_DONE;
   }
   else
   {
      PrintFormat("EA: Order FAILED | Retcode=%d | %s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
}



//+------------------------------------------------------------------+
//| TRADE MANAGEMENT: Breakeven + HT Trail                           |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   double htLine = 0;
   ReadBuf(g_htHandle, 0, 0, htLine);  // current bar HT line (for trailing)

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

      //--- Breakeven: move SL to entry after +1R profit
      if(InpMoveToBreakeven && curSL != 0)
      {
         double oneR = MathAbs(openPr - curSL);
         if(posType == POSITION_TYPE_BUY)
         {
            if(bid - openPr >= oneR && curSL < openPr)
               newSL = openPr + 1*pt;  // +1 point to ensure BE isn't exact
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            if(openPr - ask >= oneR && curSL > openPr)
               newSL = openPr - 1*pt;
         }
      }

      //--- Trail with HalfTrend line
      if(InpTrailWithHT && htLine > 0)
      {
         if(posType == POSITION_TYPE_BUY)
         {
            // Only move SL up, never down
            if(htLine > newSL && htLine < bid)
               newSL = htLine;
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            // Only move SL down, never up
            if(htLine < newSL && htLine > ask)
               newSL = htLine;
         }
      }

      // Apply modification if changed
      newSL = NormalizeDouble(newSL, digits);
      if(newSL != NormalizeDouble(curSL, digits) && newSL > 0)
      {
         if(g_trade.PositionModify(ticket, newSL, curTP))
            PrintFormat("EA: SL modified to %.5f (was %.5f)", newSL, curSL);
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick: Main event handler                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Manage positions on every tick (breakeven/trail)
   ManageOpenPositions();

   //--- Only process logic on new bar
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0) return;
   if(t0 == g_lastBarTime) return;
   g_lastBarTime = t0;

   //--- State machine on new bar (analyzing closed bar at shift=1)
   UpdateHalfTrendState();

   switch(g_state)
   {
      case STATE_WAIT_FLIP:
         // Do nothing, waiting for HT flip (handled in UpdateHalfTrendState)
         break;

      case STATE_WAIT_TOUCH:
         CheckForTouch();
         break;

      case STATE_WAIT_BOS:
         CheckForEntry();
         break;

      case STATE_DONE:
         // Trade already taken for this flip. Only reset on next flip.
         break;
   }
}

//+------------------------------------------------------------------+
//| OnTrade: Log trade events                                        |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Optional: can add trade logging here
}
//+------------------------------------------------------------------+
