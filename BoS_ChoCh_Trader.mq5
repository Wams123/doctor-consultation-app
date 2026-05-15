//+------------------------------------------------------------------+
//|                                          BoS_ChoCh_Trader.mq5    |
//|         SMC BOS/ChoCh Trader - 5 Second Entry EA                 |
//|         GUARANTEED EXECUTION VERSION                              |
//+------------------------------------------------------------------+
#property copyright   "SMC Trader EA"
#property version     "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs
input int      InpPivotLB     = 3;          // Pivot Left Bars
input int      InpPivotRB     = 3;          // Pivot Right Bars
input bool     InpTradeBOS    = true;       // Trade on BOS
input bool     InpTradeChoCh  = true;       // Trade on ChoCh
input double   InpRiskPercent = 1.0;        // Risk % per trade
input double   InpRR          = 2.0;        // Reward:Risk ratio (0=no TP)
input int      InpMaxTrades   = 3;          // Max open trades
input int      InpSeconds     = 5;          // Candle seconds
input int      InpMagic       = 55555;      // Magic Number
input color    InpBullColor   = clrLime;    // Bull color
input color    InpBearColor   = clrRed;     // Bear color

//--- Candle struct
struct Bar { datetime t; double o,h,l,c; };

//--- Globals
Bar      g_bars[];
int      g_count       = 0;
datetime g_barTime     = 0;
int      g_trend       = 0;
double   g_swingHi     = 0;
datetime g_swingHiTime = 0;
int      g_swingHiBar  = -1;
double   g_swingLo     = DBL_MAX;
datetime g_swingLoTime = 0;
int      g_swingLoBar  = -1;
datetime g_lastTrade   = 0;
int      g_objN        = 0;
CTrade   g_trade;

//+------------------------------------------------------------------+
int OnInit()
{
   g_count = 0; g_barTime = 0; g_trend = 0;
   g_swingHi = 0; g_swingHiBar = -1;
   g_swingLo = DBL_MAX; g_swingLoBar = -1;
   g_lastTrade = 0; g_objN = 0;
   ArrayResize(g_bars, 0);

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);

   EventSetMillisecondTimer(100);
   Print("=== BoS_ChoCh_Trader v2 STARTED === AutoTrade=",
         TerminalInfoInteger(TERMINAL_TRADE_ALLOWED),
         " MQL=", MQLInfoInteger(MQL_TRADE_ALLOWED));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r)
{
   EventKillTimer();
   ObjectsDeleteAll(0,"BST_");
}

//+------------------------------------------------------------------+
void OnTimer() { Run(); }
void OnTick()  { Run(); }

//+------------------------------------------------------------------+
void Run()
{
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   if(bid <= 0) return;

   datetime now = TimeCurrent();
   datetime bt  = now - (now % InpSeconds);

   //--- New candle
   if(bt != g_barTime)
   {
      g_barTime = bt;
      g_count++;
      ArrayResize(g_bars, g_count);
      g_bars[g_count-1].t = bt;
      g_bars[g_count-1].o = bid;
      g_bars[g_count-1].h = bid;
      g_bars[g_count-1].l = bid;
      g_bars[g_count-1].c = bid;

      if(g_count > 500) Trim();
      ScanPivot();
   }
   else if(g_count > 0)
   {
      int i = g_count - 1;
      g_bars[i].c = bid;
      if(bid > g_bars[i].h) g_bars[i].h = bid;
      if(bid < g_bars[i].l) g_bars[i].l = bid;
   }

   //--- Check break every tick
   if(g_count > 1) CheckBreak();
}

//+------------------------------------------------------------------+
void ScanPivot()
{
   int pb = g_count - 1 - InpPivotRB;
   if(pb < InpPivotLB) return;

   // Pivot High
   bool isHi = true;
   for(int j = pb - InpPivotLB; j <= pb + InpPivotRB; j++)
      if(j != pb && j >= 0 && j < g_count && g_bars[j].h >= g_bars[pb].h)
         { isHi = false; break; }
   if(isHi)
   {
      g_swingHi = g_bars[pb].h;
      g_swingHiTime = g_bars[pb].t;
      g_swingHiBar = pb;
   }

   // Pivot Low
   bool isLo = true;
   for(int j = pb - InpPivotLB; j <= pb + InpPivotRB; j++)
      if(j != pb && j >= 0 && j < g_count && g_bars[j].l <= g_bars[pb].l)
         { isLo = false; break; }
   if(isLo)
   {
      g_swingLo = g_bars[pb].l;
      g_swingLoTime = g_bars[pb].t;
      g_swingLoBar = pb;
   }
}

//+------------------------------------------------------------------+
void CheckBreak()
{
   int last = g_count - 1;
   double price = g_bars[last].c;
   datetime now = TimeCurrent();

   //--- Bullish break
   if(g_swingHiBar >= 0 && price > g_swingHi)
   {
      string lbl = (g_trend == -1) ? "ChoCh" : "BoS";
      bool ok = (g_trend == -1) ? InpTradeChoCh : InpTradeBOS;
      if(g_trend == 0) ok = true; // first signal always trade
      g_trend = 1;

      if(ok && (now - g_lastTrade) > InpSeconds)
      {
         g_lastTrade = now;
         double sl = (g_swingLo < DBL_MAX && g_swingLo > 0) ? g_swingLo : g_bars[g_swingHiBar].l;
         DoBuy(sl, lbl);
         DrawLine(g_swingHi, g_swingHiTime, g_bars[last].t, InpBullColor, lbl, true);
      }
      g_swingHiBar = -1; g_swingHi = 0;
   }

   //--- Bearish break
   if(g_swingLoBar >= 0 && price < g_swingLo)
   {
      string lbl = (g_trend == 1) ? "ChoCh" : "BoS";
      bool ok = (g_trend == 1) ? InpTradeChoCh : InpTradeBOS;
      if(g_trend == 0) ok = true;
      g_trend = -1;

      if(ok && (now - g_lastTrade) > InpSeconds)
      {
         g_lastTrade = now;
         double sl = (g_swingHi > 0) ? g_swingHi : g_bars[g_swingLoBar].h;
         DoSell(sl, lbl);
         DrawLine(g_swingLo, g_swingLoTime, g_bars[last].t, InpBearColor, lbl, false);
      }
      g_swingLoBar = -1; g_swingLo = DBL_MAX;
   }
}

//+------------------------------------------------------------------+
void DoBuy(double sl, string comment)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   { Print("[TRADER] AutoTrading is OFF!"); return; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   { Print("[TRADER] EA trading not allowed! Check Allow Algo Trading."); return; }
   if(CountTrades() >= InpMaxTrades)
   { Print("[TRADER] Max trades reached."); return; }

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   int dig = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

   if(sl >= ask) sl = ask - 100 * pt;
   double dist = ask - sl;
   if(dist <= 0) { Print("[TRADER] BUY skip: bad SL dist"); return; }

   double lots = CalcLots(dist);
   double tp = (InpRR > 0) ? NormalizeDouble(ask + dist * InpRR, dig) : 0;
   sl = NormalizeDouble(sl, dig);

   Print("[TRADER] >>> BUY ", comment, " lots=", lots, " ask=", ask, " sl=", sl, " tp=", tp);

   if(!g_trade.Buy(lots, Symbol(), ask, sl, tp, "SMC_" + comment))
      Print("[TRADER] BUY FAILED! code=", g_trade.ResultRetcode(),
            " desc=", g_trade.ResultRetcodeDescription());
   else
      Print("[TRADER] BUY OK! ticket=", g_trade.ResultOrder());
}

//+------------------------------------------------------------------+
void DoSell(double sl, string comment)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   { Print("[TRADER] AutoTrading is OFF!"); return; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   { Print("[TRADER] EA trading not allowed! Check Allow Algo Trading."); return; }
   if(CountTrades() >= InpMaxTrades)
   { Print("[TRADER] Max trades reached."); return; }

   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   int dig = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double pt = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

   if(sl <= bid) sl = bid + 100 * pt;
   double dist = sl - bid;
   if(dist <= 0) { Print("[TRADER] SELL skip: bad SL dist"); return; }

   double lots = CalcLots(dist);
   double tp = (InpRR > 0) ? NormalizeDouble(bid - dist * InpRR, dig) : 0;
   sl = NormalizeDouble(sl, dig);

   Print("[TRADER] >>> SELL ", comment, " lots=", lots, " bid=", bid, " sl=", sl, " tp=", tp);

   if(!g_trade.Sell(lots, Symbol(), bid, sl, tp, "SMC_" + comment))
      Print("[TRADER] SELL FAILED! code=", g_trade.ResultRetcode(),
            " desc=", g_trade.ResultRetcodeDescription());
   else
      Print("[TRADER] SELL OK! ticket=", g_trade.ResultOrder());
}

//+------------------------------------------------------------------+
double CalcLots(double slDist)
{
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = bal * InpRiskPercent / 100.0;
   double tv   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double ts   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double lmin = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double lmax = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double lstp = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   if(tv <= 0 || ts <= 0) return lmin;
   double lots = risk / ((slDist / ts) * tv);
   lots = MathFloor(lots / lstp) * lstp;
   if(lots < lmin) lots = lmin;
   if(lots > lmax) lots = lmax;

   //--- Check free margin before sending - cap lots to what we can afford
   double margin = 0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, Symbol(), lots, SymbolInfoDouble(Symbol(), SYMBOL_ASK), margin))
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * 0.8)  // Use max 80% of free margin
      {
         lots = lots * (freeMargin * 0.8) / margin;
         lots = MathFloor(lots / lstp) * lstp;
         if(lots < lmin) lots = lmin;
      }
   }

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
int CountTrades()
{
   int c = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
      if(PositionSelectByTicket(PositionGetTicket(i)))
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == Symbol())
            c++;
   return c;
}

//+------------------------------------------------------------------+
void Trim()
{
   int keep = 300, rm = g_count - keep;
   Bar tmp[]; ArrayResize(tmp, keep);
   for(int i=0;i<keep;i++) tmp[i] = g_bars[rm+i];
   ArrayResize(g_bars, keep);
   for(int i=0;i<keep;i++) g_bars[i] = tmp[i];
   g_count = keep;
   if(g_swingHiBar >= 0) { g_swingHiBar -= rm; if(g_swingHiBar < 0) { g_swingHiBar=-1; g_swingHi=0; } }
   if(g_swingLoBar >= 0) { g_swingLoBar -= rm; if(g_swingLoBar < 0) { g_swingLoBar=-1; g_swingLo=DBL_MAX; } }
}

//+------------------------------------------------------------------+
void DrawLine(double price, datetime t1, datetime t2, color col, string lbl, bool above)
{
   g_objN++;
   string n1 = "BST_L"+IntegerToString(g_objN);
   string n2 = "BST_T"+IntegerToString(g_objN);
   ObjectCreate(0,n1,OBJ_TREND,0,t1,price,t2,price);
   ObjectSetInteger(0,n1,OBJPROP_COLOR,col);
   ObjectSetInteger(0,n1,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,n1,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,n1,OBJPROP_BACK,true);
   datetime mt=(datetime)(((long)t1+(long)t2)/2);
   ObjectCreate(0,n2,OBJ_TEXT,0,mt,price);
   ObjectSetString(0,n2,OBJPROP_TEXT,lbl);
   ObjectSetInteger(0,n2,OBJPROP_COLOR,col);
   ObjectSetInteger(0,n2,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,n2,OBJPROP_ANCHOR,above?ANCHOR_LOWER:ANCHOR_UPPER);
}
//+------------------------------------------------------------------+
