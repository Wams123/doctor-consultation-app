//+------------------------------------------------------------------+
//|                                              HalfTrendSMC_EA.mq5 |
//|                                                                   |
//|  Strategy:                                                        |
//|   1. HalfTrend defines trend direction                            |
//|   2. Wait until price TOUCHES the HalfTrend line                  |
//|   3. After a touch, wait for internal BOS/CHoCH in trend direction|
//|   4. Entry = market at the close of the BOS/CHoCH bar             |
//|   5. SL   = low of BOS/CHoCH sequence (for BUY)                   |
//|             high of BOS/CHoCH sequence (for SELL)                 |
//|   6. TP   = current (unbroken) swing high for BUY                 |
//|             current (unbroken) swing low for SELL                 |
//+------------------------------------------------------------------+
#property copyright "Kiro"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== General ==="
input double InpLots             = 0.10;    // Lot size
input int    InpMagic            = 990011;  // Magic number
input int    InpSlippage         = 20;      // Slippage (points)
input int    InpMaxSpreadPts     = 100;     // Max allowed spread (points, 0=off)

input group "=== HalfTrend ==="
input int    InpHT_Amplitude     = 2;       // HalfTrend Amplitude
input int    InpHT_ChanDev       = 2;       // HalfTrend Channel Deviation

input group "=== Smart Money Concepts ==="
input int    InpSMC_SwingLen     = 50;      // Swing length (TP source)
input int    InpSMC_IntLen       = 5;       // Internal length (entry trigger)

input group "=== Setup / Filters ==="
input int    InpTouchLookback    = 10;      // Bars after touch before signal expires
input bool   InpRequireCHoCH     = false;   // Require CHoCH (not just BOS)
input double InpMinRRR           = 1.0;     // Skip trades below this RR; 0 = off
input bool   InpOneTradeAtATime  = true;    // Only one open trade per symbol

input group "=== Risk Management ==="
input bool   InpUseBreakeven     = true;    // Move SL to BE after +1R
input bool   InpUseTrailHT       = false;   // Trail SL along HalfTrend line

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade      g_trade;
int         g_htHandle  = INVALID_HANDLE;
int         g_smcHandle = INVALID_HANDLE;
datetime    g_lastBarTime = 0;

// Touch tracking
int         g_touchTrend    = 0;   // 0=bull, 1=bear, -1=none
int         g_touchBarsAgo  = -1;  // bars since touch; -1 = no active touch

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_htHandle = iCustom(_Symbol, _Period, "HalfTrend",
                        InpHT_Amplitude,
                        InpHT_ChanDev,
                        true,   // show arrows
                        true);  // show channels
   if(g_htHandle == INVALID_HANDLE)
   {
      Print("EA: iCustom(HalfTrend) failed: ", GetLastError());
      return(INIT_FAILED);
   }

   // SMC inputs (must match order of input parameters in SMC indicator):
   //  InpStyle, InpShowTrend,
   //  InpShowInternals, InpInternalBull, InpInternalBullColor,
   //  InpInternalBear, InpInternalBearColor, InpConfluenceFilter,
   //  InpInternalLabelSize, InpInternalLength,
   //  InpShowStructure, InpSwingBull, InpSwingBullColor,
   //  InpSwingBear, InpSwingBearColor, InpSwingLabelSize,
   //  InpShowSwings, InpSwingsLength, InpShowHighLowSwings,
   //  ... (order block, EQHL, FVG inputs use defaults)
   g_smcHandle = iCustom(_Symbol, _Period, "SmartMoneyConcepts",
                         0,           // InpStyle (COLORED)
                         false,       // InpShowTrend
                         true,        // InpShowInternals
                         0,           // InpInternalBull (ALL)
                         clrGreen,    // InpInternalBullColor
                         0,           // InpInternalBear (ALL)
                         clrRed,      // InpInternalBearColor
                         false,       // InpConfluenceFilter
                         0,           // InpInternalLabelSize
                         InpSMC_IntLen,   // InpInternalLength
                         true,        // InpShowStructure
                         0,           // InpSwingBull
                         clrGreen,    // InpSwingBullColor
                         0,           // InpSwingBear
                         clrRed,      // InpSwingBearColor
                         1,           // InpSwingLabelSize
                         false,       // InpShowSwings
                         InpSMC_SwingLen, // InpSwingsLength
                         true         // InpShowHighLowSwings
                         );
   if(g_smcHandle == INVALID_HANDLE)
   {
      Print("EA: iCustom(SmartMoneyConcepts) failed: ", GetLastError());
      return(INIT_FAILED);
   }

   g_lastBarTime    = 0;
   g_touchTrend     = -1;
   g_touchBarsAgo   = -1;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_htHandle  != INVALID_HANDLE) IndicatorRelease(g_htHandle);
   if(g_smcHandle != INVALID_HANDLE) IndicatorRelease(g_smcHandle);
}

//+------------------------------------------------------------------+
//| Utility: read one buffer value at shift                          |
//+------------------------------------------------------------------+
bool ReadBuf(int handle, int bufIdx, int shift, double &outVal)
{
   double tmp[];
   if(CopyBuffer(handle, bufIdx, shift, 1, tmp) <= 0) return false;
   outVal = tmp[0];
   return true;
}

//+------------------------------------------------------------------+
//| Check if we already have an open trade for this EA/symbol        |
//+------------------------------------------------------------------+
bool HasOpenTrade()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Update touch state using the just-closed bar (shift=1)           |
//+------------------------------------------------------------------+
void UpdateTouchState()
{
   double ht=0, trend=0;
   if(!ReadBuf(g_htHandle, 0, 1, ht))    return;
   if(!ReadBuf(g_htHandle, 6, 1, trend)) return;

   if(ht <= 0) return;

   double h = iHigh(_Symbol, _Period, 1);
   double l = iLow (_Symbol, _Period, 1);

   int trendInt = (int)MathRound(trend);

   // touch = the HT line sits inside the bar's range
   bool touched = (l <= ht && h >= ht);

   if(touched)
   {
      g_touchTrend   = trendInt;
      g_touchBarsAgo = 0;
   }
   else if(g_touchBarsAgo >= 0)
   {
      g_touchBarsAgo++;
      // expire
      if(g_touchBarsAgo > InpTouchLookback)
      {
         g_touchBarsAgo = -1;
         g_touchTrend   = -1;
      }
      // invalidate if trend flipped since touch
      if(trendInt != g_touchTrend)
      {
         g_touchBarsAgo = -1;
         g_touchTrend   = -1;
      }
   }
}

//+------------------------------------------------------------------+
//| Try to open a trade based on the just-closed bar (shift=1)       |
//+------------------------------------------------------------------+
void TryEnterOnClosedBar()
{
   if(InpOneTradeAtATime && HasOpenTrade()) return;
   if(g_touchBarsAgo < 0) return;   // no armed touch

   double smcSig=0, smcTag=0, seqLo=0, seqHi=0, swH=0, swL=0;
   if(!ReadBuf(g_smcHandle, 0, 1, smcSig)) return;
   if(!ReadBuf(g_smcHandle, 1, 1, smcTag)) return;
   if(!ReadBuf(g_smcHandle, 2, 1, seqLo))  return;
   if(!ReadBuf(g_smcHandle, 3, 1, seqHi))  return;
   if(!ReadBuf(g_smcHandle, 4, 1, swH))    return;
   if(!ReadBuf(g_smcHandle, 5, 1, swL))    return;

   if(smcSig == 0) return;

   // pro-trend filter
   bool bullSetup = (g_touchTrend == 0) && (smcSig > 0.5);
   bool bearSetup = (g_touchTrend == 1) && (smcSig < -0.5);
   if(!bullSetup && !bearSetup) return;

   // optional CHoCH-only filter (tag: 1=BOS, 2=CHoCH)
   if(InpRequireCHoCH && (int)MathRound(smcTag) != 2) return;

   // spread filter
   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPts > 0 && spreadPts > InpMaxSpreadPts) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pt  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   digits = (long)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLvl * pt;

   double sl=0, tp=0, entry=0;

   if(bullSetup)
   {
      entry = ask;
      sl    = seqLo;
      tp    = (swH > 0) ? swH : 0;
      if(sl <= 0 || tp <= 0) return;
      if(entry - sl < minDist) sl = entry - minDist;
      if(tp - entry < minDist) tp = entry + minDist;
      if(tp <= entry || sl >= entry) return;
   }
   else // bearSetup
   {
      entry = bid;
      sl    = seqHi;
      tp    = (swL > 0) ? swL : 0;
      if(sl <= 0 || tp <= 0) return;
      if(sl - entry < minDist) sl = entry + minDist;
      if(entry - tp < minDist) tp = entry - minDist;
      if(tp >= entry || sl <= entry) return;
   }

   sl = NormalizeDouble(sl, (int)digits);
   tp = NormalizeDouble(tp, (int)digits);

   // RR filter
   if(InpMinRRR > 0)
   {
      double risk   = MathAbs(entry - sl);
      double reward = MathAbs(tp - entry);
      if(risk <= 0) return;
      if(reward / risk < InpMinRRR) return;
   }

   bool ok = false;
   if(bullSetup)
      ok = g_trade.Buy (InpLots, _Symbol, entry, sl, tp, "HT+SMC BUY");
   else
      ok = g_trade.Sell(InpLots, _Symbol, entry, sl, tp, "HT+SMC SELL");

   if(ok)
   {
      PrintFormat("EA: %s opened  entry=%.*f sl=%.*f tp=%.*f  tag=%s",
                  bullSetup?"BUY":"SELL",
                  (int)digits, entry, (int)digits, sl, (int)digits, tp,
                  ((int)MathRound(smcTag)==2)?"CHoCH":"BOS");
      // consume the touch so we don't re-trigger on the same arm
      g_touchBarsAgo = -1;
      g_touchTrend   = -1;
   }
   else
   {
      PrintFormat("EA: order failed: %d / %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Manage open positions: breakeven + optional HT trail             |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double htNow=0;
   if(!ReadBuf(g_htHandle, 0, 1, htNow)) htNow = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   type    = PositionGetInteger(POSITION_TYPE);
      double openPr  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL   = PositionGetDouble(POSITION_SL);
      double curTP   = PositionGetDouble(POSITION_TP);
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      long   digits  = (long)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

      double newSL = curSL;

      if(InpUseBreakeven && curSL != 0)
      {
         double oneR = MathAbs(openPr - curSL);
         if(type == POSITION_TYPE_BUY && (bid - openPr) >= oneR && curSL < openPr)
            newSL = openPr;
         if(type == POSITION_TYPE_SELL && (openPr - ask) >= oneR && curSL > openPr)
            newSL = openPr;
      }

      if(InpUseTrailHT && htNow > 0)
      {
         if(type == POSITION_TYPE_BUY && htNow > newSL && htNow < bid)
            newSL = htNow;
         if(type == POSITION_TYPE_SELL && (htNow < newSL || newSL == 0) && htNow > ask)
            newSL = htNow;
      }

      newSL = NormalizeDouble(newSL, (int)digits);
      if(newSL != curSL && newSL != 0)
         g_trade.PositionModify(ticket, newSL, curTP);
   }
}

//+------------------------------------------------------------------+
//| OnTick: act only on new closed bar                               |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 == 0) return;

   // manage on every tick (cheap)
   ManagePositions();

   if(t0 == g_lastBarTime) return;   // not a new bar yet
   g_lastBarTime = t0;

   // new bar just opened -> bar index 1 is the just-closed bar
   UpdateTouchState();
   TryEnterOnClosedBar();
}
//+------------------------------------------------------------------+
