//+------------------------------------------------------------------+
//|                                               BracketBlitz.mq5   |
//|                         BracketBlitz Expert Advisor v1.00         |
//|                                                                  |
//|  Rapid-fire OCO bracket orders around live price.                |
//|  Buy Stop + Sell Stop with auto-refresh & trailing stop.         |
//|  One triggers → the other is instantly deleted.                  |
//+------------------------------------------------------------------+
#property copyright "BracketBlitz EA"
#property link      ""
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Input Parameters
input double LotSize          = 0.01;    // Trade lot size
input int    GapPips          = 50;      // Distance from price for pending orders (pips)
input int    StopLossPips     = 50;      // Stop loss distance (pips)
input int    TrailingStopPips = 20;      // Trailing stop distance (pips)
input int    OrderLifetimeSec = 30;      // Seconds before pending orders expire & refresh
input long   MagicNumber      = 123456;  // Unique EA identifier

//--- Global Objects & Variables
CTrade         g_trade;
CPositionInfo  g_position;
COrderInfo     g_order;

datetime g_pendingPlacedTime = 0;   // Time when pending orders were placed
ulong    g_buyTicket         = 0;   // Ticket of the Buy Stop order
ulong    g_sellTicket        = 0;   // Ticket of the Sell Stop order

//+------------------------------------------------------------------+
//| Return pip size adjusted for 3/5-digit brokers                   |
//+------------------------------------------------------------------+
double PipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
      return SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   else
      return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Count pending orders owned by this EA                            |
//+------------------------------------------------------------------+
int CountPendingOrders()
{
   int count = 0;
   int total = OrdersTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
      {
         ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count open positions owned by this EA                            |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if a specific ticket is still a pending order              |
//+------------------------------------------------------------------+
bool IsPendingOrder(ulong ticket)
{
   if(ticket == 0)
      return false;

   int total = OrdersTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      if(OrderGetTicket(i) == ticket)
      {
         ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if a pending order ticket has been filled (now a position) |
//+------------------------------------------------------------------+
bool IsFilledOrder(ulong ticket)
{
   if(ticket == 0)
      return false;

   // Check if the ticket now exists as an open position
   // In MT5, when a pending order fills, a position is created.
   // We check the deal history to see if our pending order triggered.
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         // Position exists from our EA — check if the pending order is gone
         // (meaning it was filled, not just deleted)
         if(!IsPendingOrder(ticket))
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Delete all pending orders owned by this EA                       |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   int total = OrdersTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
      {
         ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
         {
            if(!g_trade.OrderDelete(ticket))
               Print("Failed to delete order #", ticket, " Error: ", GetLastError());
         }
      }
   }
   g_buyTicket  = 0;
   g_sellTicket = 0;
}

//+------------------------------------------------------------------+
//| Delete a specific pending order by ticket                        |
//+------------------------------------------------------------------+
bool DeletePendingOrder(ulong ticket)
{
   if(ticket == 0)
      return false;

   if(IsPendingOrder(ticket))
   {
      if(g_trade.OrderDelete(ticket))
         return true;
      else
         Print("Failed to delete order #", ticket, " Error: ", GetLastError());
   }
   return false;
}

//+------------------------------------------------------------------+
//| Apply trailing stop to all open positions owned by this EA       |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   double trailDistance = TrailingStopPips * PipSize();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      if(posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSL = NormalizeDouble(bid - trailDistance, digits);

         // Only move SL up, never down
         if(newSL > currentSL && newSL > openPrice)
         {
            if(!g_trade.PositionModify(ticket, newSL, currentTP))
               Print("Trailing stop modify failed for #", ticket, " Error: ", GetLastError());
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL = NormalizeDouble(ask + trailDistance, digits);

         // Only move SL down (towards profit), never up
         if((newSL < currentSL || currentSL == 0) && newSL < openPrice)
         {
            if(!g_trade.PositionModify(ticket, newSL, currentTP))
               Print("Trailing stop modify failed for #", ticket, " Error: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Place Buy Stop and Sell Stop pending orders                      |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
   double pipSz      = PipSize();
   double gapDistance = GapPips * pipSz;
   double slDistance  = StopLossPips * pipSz;
   int    digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Buy Stop: above the current Ask
   double buyStopPrice = NormalizeDouble(ask + gapDistance, digits);
   double buySL        = NormalizeDouble(buyStopPrice - slDistance, digits);

   //--- Sell Stop: below the current Bid
   double sellStopPrice = NormalizeDouble(bid - gapDistance, digits);
   double sellSL        = NormalizeDouble(sellStopPrice + slDistance, digits);

   //--- Place Buy Stop
   if(g_trade.BuyStop(LotSize, buyStopPrice, _Symbol, buySL, 0, ORDER_TIME_GTC, 0, "OCO BuyStop"))
   {
      g_buyTicket = g_trade.ResultOrder();
      Print("Buy Stop placed at ", buyStopPrice, " SL: ", buySL, " Ticket #", g_buyTicket);
   }
   else
      Print("Buy Stop order failed. Error: ", GetLastError());

   //--- Place Sell Stop
   if(g_trade.SellStop(LotSize, sellStopPrice, _Symbol, sellSL, 0, ORDER_TIME_GTC, 0, "OCO SellStop"))
   {
      g_sellTicket = g_trade.ResultOrder();
      Print("Sell Stop placed at ", sellStopPrice, " SL: ", sellSL, " Ticket #", g_sellTicket);
   }
   else
      Print("Sell Stop order failed. Error: ", GetLastError());

   //--- Record placement time
   g_pendingPlacedTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Expiration check: March 28, 2026 (Real accounts only)
   datetime expirationDate = D'2026.03.28 00:00:00';
   ENUM_ACCOUNT_TRADE_MODE tradeMode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(tradeMode == ACCOUNT_TRADE_MODE_REAL && TimeCurrent() >= expirationDate)
   {
      string msg = "BracketBlitz EA has expired!\n\n"
                   + "Expiration Date: 2026.03.28\n\n"
                   + "To renew your license, please contact:\n"
                   + "Telegram: t.me/syariefazman\n\n"
                   + "The EA will now be removed from the chart.";
      MessageBox(msg, "BracketBlitz EA - License Expired", MB_OK | MB_ICONERROR);
      Print("BracketBlitz EA EXPIRED on real account. Contact Telegram: t.me/syariefazman");
      ExpertRemove();
      return INIT_FAILED;
   }

   //--- Configure CTrade object
   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetDeviationInPoints(3);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   Print("BracketBlitz EA (MT5) initialized.");
   Print("Gap: ", GapPips, " pips | SL: ", StopLossPips, " pips | Trail: ", TrailingStopPips, " pips | Lifetime: ", OrderLifetimeSec, " sec");

   // Place initial pending orders
   PlacePendingOrders();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up: delete all pending orders when EA is removed
   DeleteAllPendingOrders();
   Print("BracketBlitz EA (MT5) removed. All pending orders deleted.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //=================================================================
   // STEP 1: OCO Logic — Check if one side got filled
   //=================================================================

   // Detect fill: pending order disappeared AND a position exists
   bool buyStillPending  = IsPendingOrder(g_buyTicket);
   bool sellStillPending = IsPendingOrder(g_sellTicket);
   bool hasPosition      = (CountOpenPositions() > 0);

   // Buy Stop was filled (no longer pending, but we have a position)
   if(g_buyTicket > 0 && !buyStillPending && hasPosition && sellStillPending)
   {
      Print("Buy Stop #", g_buyTicket, " filled. Deleting Sell Stop #", g_sellTicket);
      DeletePendingOrder(g_sellTicket);
      g_sellTicket = 0;
      g_buyTicket  = 0;
      g_pendingPlacedTime = 0;
   }
   // Sell Stop was filled
   else if(g_sellTicket > 0 && !sellStillPending && hasPosition && buyStillPending)
   {
      Print("Sell Stop #", g_sellTicket, " filled. Deleting Buy Stop #", g_buyTicket);
      DeletePendingOrder(g_buyTicket);
      g_buyTicket  = 0;
      g_sellTicket = 0;
      g_pendingPlacedTime = 0;
   }

   //=================================================================
   // STEP 2: Trailing Stop on open positions
   //=================================================================
   if(CountOpenPositions() > 0)
   {
      ApplyTrailingStop();
   }

   //=================================================================
   // STEP 3: Check pending order expiry (timeout)
   //=================================================================
   if(g_pendingPlacedTime > 0 && CountPendingOrders() > 0)
   {
      int elapsed = (int)(TimeCurrent() - g_pendingPlacedTime);

      if(elapsed >= OrderLifetimeSec)
      {
         Print("Pending orders expired after ", elapsed, " seconds. Refreshing...");
         DeleteAllPendingOrders();
         g_pendingPlacedTime = 0;
      }
   }

   //=================================================================
   // STEP 4: Place new pending orders if none exist
   //=================================================================
   if(CountPendingOrders() == 0 && g_buyTicket == 0 && g_sellTicket == 0)
   {
      PlacePendingOrders();
   }
}
//+------------------------------------------------------------------+
