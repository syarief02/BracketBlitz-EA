//+------------------------------------------------------------------+
//|                                               BracketBlitz.mq4   |
//|                         BracketBlitz Expert Advisor v1.00         |
//|                                                                  |
//|  Rapid-fire OCO bracket orders around live price.                |
//|  Buy Stop + Sell Stop with auto-refresh & trailing stop.         |
//|  One triggers → the other is instantly deleted.                  |
//+------------------------------------------------------------------+
#property copyright "BracketBlitz EA"
#property link      ""
#property version   "1.00"
#property strict

//--- Input Parameters
input double LotSize         = 0.01;    // Trade lot size
input int    GapPips         = 50;      // Distance from price for pending orders (pips)
input int    StopLossPips    = 50;      // Stop loss distance (pips)
input int    TrailingStopPips = 20;     // Trailing stop distance (pips)
input int    OrderLifetimeSec = 30;     // Seconds before pending orders expire & refresh
input int    MagicNumber     = 123456;  // Unique EA identifier

//--- Global Variables
datetime g_pendingPlacedTime = 0;       // Time when pending orders were placed
int      g_buyTicket         = -1;      // Ticket of the Buy Stop order
int      g_sellTicket        = -1;      // Ticket of the Sell Stop order

//+------------------------------------------------------------------+
//| Return pip size adjusted for 4/5-digit brokers                   |
//+------------------------------------------------------------------+
double PipSize()
{
   if(Digits == 3 || Digits == 5)
      return Point * 10;
   else
      return Point;
}

//+------------------------------------------------------------------+
//| Count pending orders owned by this EA                            |
//+------------------------------------------------------------------+
int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol())
         {
            if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
               count++;
         }
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
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol())
         {
            if(OrderType() == OP_BUY || OrderType() == OP_SELL)
               count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if a specific ticket is still a pending order              |
//+------------------------------------------------------------------+
bool IsPendingOrder(int ticket)
{
   if(ticket < 0)
      return false;

   if(OrderSelect(ticket, SELECT_BY_TICKET))
   {
      // Order is still pending if type is BUYSTOP/SELLSTOP and not closed
      if((OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP) && OrderCloseTime() == 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if a specific ticket has been filled (is now a position)   |
//+------------------------------------------------------------------+
bool IsFilledOrder(int ticket)
{
   if(ticket < 0)
      return false;

   if(OrderSelect(ticket, SELECT_BY_TICKET))
   {
      // A pending order that got triggered becomes OP_BUY or OP_SELL
      if((OrderType() == OP_BUY || OrderType() == OP_SELL) && OrderCloseTime() == 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Delete all pending orders owned by this EA                       |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol())
         {
            if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
            {
               if(!OrderDelete(OrderTicket()))
                  Print("Failed to delete order #", OrderTicket(), " Error: ", GetLastError());
            }
         }
      }
   }
   g_buyTicket  = -1;
   g_sellTicket = -1;
}

//+------------------------------------------------------------------+
//| Delete a specific pending order by ticket                        |
//+------------------------------------------------------------------+
bool DeletePendingOrder(int ticket)
{
   if(ticket < 0)
      return false;

   if(OrderSelect(ticket, SELECT_BY_TICKET))
   {
      if((OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP) && OrderCloseTime() == 0)
      {
         if(OrderDelete(ticket))
            return true;
         else
            Print("Failed to delete order #", ticket, " Error: ", GetLastError());
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Apply trailing stop to all open positions owned by this EA       |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   double trailDistance = TrailingStopPips * PipSize();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
            continue;

         if(OrderType() == OP_BUY)
         {
            double newSL = Bid - trailDistance;
            newSL = NormalizeDouble(newSL, Digits);

            // Only move SL up, never down
            if(newSL > OrderStopLoss() && newSL > OrderOpenPrice())
            {
               if(!OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrGreen))
                  Print("Trailing stop modify failed for #", OrderTicket(), " Error: ", GetLastError());
            }
         }
         else if(OrderType() == OP_SELL)
         {
            double newSL = Ask + trailDistance;
            newSL = NormalizeDouble(newSL, Digits);

            // Only move SL down (towards profit), never up
            if((newSL < OrderStopLoss() || OrderStopLoss() == 0) && newSL < OrderOpenPrice())
            {
               if(!OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrRed))
                  Print("Trailing stop modify failed for #", OrderTicket(), " Error: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Place Buy Stop and Sell Stop pending orders                      |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
   double pipSz       = PipSize();
   double gapDistance  = GapPips * pipSz;
   double slDistance   = StopLossPips * pipSz;

   //--- Buy Stop: above the current Ask
   double buyStopPrice = NormalizeDouble(Ask + gapDistance, Digits);
   double buySL        = NormalizeDouble(buyStopPrice - slDistance, Digits);

   //--- Sell Stop: below the current Bid
   double sellStopPrice = NormalizeDouble(Bid - gapDistance, Digits);
   double sellSL        = NormalizeDouble(sellStopPrice + slDistance, Digits);

   //--- Place Buy Stop
   g_buyTicket = OrderSend(
      Symbol(),           // symbol
      OP_BUYSTOP,         // order type
      LotSize,            // lot size
      buyStopPrice,       // price
      3,                  // slippage
      buySL,              // stop loss
      0,                  // take profit (none)
      "OCO BuyStop",      // comment
      MagicNumber,        // magic number
      0,                  // expiration (0 = no server-side expiry)
      clrBlue             // color
   );

   if(g_buyTicket < 0)
      Print("Buy Stop order failed. Error: ", GetLastError());
   else
      Print("Buy Stop placed at ", buyStopPrice, " SL: ", buySL, " Ticket #", g_buyTicket);

   //--- Place Sell Stop
   g_sellTicket = OrderSend(
      Symbol(),           // symbol
      OP_SELLSTOP,        // order type
      LotSize,            // lot size
      sellStopPrice,      // price
      3,                  // slippage
      sellSL,             // stop loss
      0,                  // take profit (none)
      "OCO SellStop",     // comment
      MagicNumber,        // magic number
      0,                  // expiration (0 = no server-side expiry)
      clrRed              // color
   );

   if(g_sellTicket < 0)
      Print("Sell Stop order failed. Error: ", GetLastError());
   else
      Print("Sell Stop placed at ", sellStopPrice, " SL: ", sellSL, " Ticket #", g_sellTicket);

   //--- Record placement time
   g_pendingPlacedTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("BracketBlitz EA initialized.");
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
   Print("BracketBlitz EA removed. All pending orders deleted.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //=================================================================
   // STEP 1: OCO Logic — Check if one side got filled
   //=================================================================
   bool buyFilled  = IsFilledOrder(g_buyTicket);
   bool sellFilled = IsFilledOrder(g_sellTicket);

   if(buyFilled)
   {
      // Buy side triggered → delete the Sell Stop
      Print("Buy Stop #", g_buyTicket, " filled. Deleting Sell Stop #", g_sellTicket);
      DeletePendingOrder(g_sellTicket);
      g_sellTicket = -1;
      g_buyTicket  = -1;  // Reset — it's now a position, not a pending order
      g_pendingPlacedTime = 0;
   }
   else if(sellFilled)
   {
      // Sell side triggered → delete the Buy Stop
      Print("Sell Stop #", g_sellTicket, " filled. Deleting Buy Stop #", g_buyTicket);
      DeletePendingOrder(g_buyTicket);
      g_buyTicket  = -1;
      g_sellTicket = -1;  // Reset
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
   if(CountPendingOrders() == 0 && g_buyTicket < 0 && g_sellTicket < 0)
   {
      // Small delay check: don't re-place while we have open positions
      // (new orders placed only when no pending AND no open managed positions,
      //  OR after the position is closed — this keeps it clean)
      // However, per the spec, new orders should be placed "immediately"
      // after timeout even if a position is open. So we place them regardless.
      PlacePendingOrders();
   }
}
//+------------------------------------------------------------------+
