# ⚡ BracketBlitz EA

**Rapid-fire OCO bracket orders that chase the market — Buy Stop + Sell Stop, auto-refreshed every 30 seconds.**

[![Platform MT4](https://img.shields.io/badge/Platform-MetaTrader%204-blue)](#) [![Platform MT5](https://img.shields.io/badge/Platform-MetaTrader%205-green)](#) [![Version](https://img.shields.io/badge/Version-1.00-orange)](#) [![License](https://img.shields.io/badge/License-MIT-yellow)](#-license)

BracketBlitz is a MetaTrader Expert Advisor (available for both **MT4** and **MT5**) that continuously places bracket pending orders around the live price. When one side triggers, the other is instantly cancelled (**One-Cancels-Other**). If neither triggers within the configurable time window, both are deleted and re-placed at the current price — keeping your entries razor-close to the action.

---

## 📑 Table of Contents

- [Features](#-features)
- [How It Works](#-how-it-works)
- [Strategy Explained](#-strategy-explained)
- [Configuration](#%EF%B8%8F-configuration)
- [Installation](#-installation)
- [Backtesting Guide](#-backtesting-guide)
- [Code Architecture](#-code-architecture)
- [Function Reference](#-function-reference)
- [Troubleshooting](#-troubleshooting)
- [FAQ](#-faq)
- [Project Structure](#-project-structure)
- [Changelog](#-changelog)
- [Risk Disclaimer](#%EF%B8%8F-risk-disclaimer)
- [License](#-license)
- [Author](#-author)

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔀 **OCO Bracket Orders** | Simultaneously places a Buy Stop above and a Sell Stop below the current price. When one triggers, the other is instantly deleted. |
| ⏱️ **Auto-Refresh Timer** | Pending orders auto-cancel & re-place every 30 seconds (configurable) so your entries never go stale. |
| 🎯 **Smart Trailing Stop** | Automatically trails the stop loss as price moves in your favour. Only moves SL in the profitable direction — never against you. |
| ⚙️ **Fully Configurable** | Gap distance, stop loss, trailing distance, lot size, refresh timer, and magic number — all adjustable from the EA inputs dialog at runtime. |
| 🧹 **Clean Lifecycle Management** | All pending orders belonging to this EA are automatically deleted when the EA is removed from the chart, ensuring no orphaned orders. |
| 🔢 **Magic Number Isolation** | Each instance uses a unique magic number so it never interferes with your other EAs, manual trades, or other BracketBlitz instances. |
| 📊 **Universal Broker Support** | Automatically detects and adjusts pip calculations for all broker configurations — 4-digit, 5-digit, 3-digit (JPY pairs), and 2-digit. |
| 🔄 **Dual Platform** | Full native implementations for both MetaTrader 4 (MQL4) and MetaTrader 5 (MQL5). Not a compatibility wrapper — each is written for its platform's native API. |

---

## 📐 How It Works

```
                    ┌───────────────────────┐
                    │   EA Starts (OnInit)  │
                    └───────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
                    │  Place Buy Stop       │
                    │  + Sell Stop           │
                    │  (± GapPips from       │
                    │   current price)       │
                    └───────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
               ┌────┤    OnTick Loop        ├────┐
               │    └───────────────────────┘    │
               │                                  │
          ┌────▼──────┐                   ┌───────▼───────┐
          │ One side   │                   │ Timer expired │
          │ triggers   │                   │ (≥30 seconds) │
          └────┬──────┘                   └───────┬───────┘
               │                                  │
          ┌────▼─────────────┐          ┌─────────▼─────────┐
          │ Delete opposite  │          │ Delete BOTH        │
          │ pending order    │          │ pending orders     │
          │ (OCO cancel)     │          │ (stale refresh)    │
          └────┬─────────────┘          └─────────┬─────────┘
               │                                  │
          ┌────▼─────────────┐          ┌─────────▼─────────┐
          │ Trail SL on      │          │ Re-place at new    │
          │ open position    │          │ current price      │
          └──────────────────┘          └───────────────────┘
```

### Tick-by-Tick Lifecycle

Every tick, the EA runs through **4 sequential steps**:

1. **OCO Check** — Did one of our pending orders get filled? If yes → immediately delete the opposite pending order.
2. **Trailing Stop** — For any open position owned by this EA, adjust the stop loss to trail behind the current price.
3. **Expiry Check** — Have the pending orders been alive longer than `OrderLifetimeSec`? If yes → delete both and flag for re-placement.
4. **Re-placement** — If no pending orders exist and no tickets are tracked, place a fresh pair of Buy Stop + Sell Stop at the current price.

---

## 📖 Strategy Explained

BracketBlitz implements a **breakout-capture** strategy designed for volatile market conditions:

### 1. Bracket Placement
Two pending orders straddle the current price:
- **Buy Stop** at `Ask + GapPips` — catches upward breakouts
- **Sell Stop** at `Bid − GapPips` — catches downward breakouts

### 2. OCO Execution
The moment price breaks through one level and triggers an order, the opposite side is **immediately deleted**. This prevents the EA from opening conflicting positions and keeps your exposure directional.

### 3. Fresh Entries
If neither order triggers within 30 seconds (configurable), both are deleted and re-placed at the **new current price**. This keeps the bracket tight around the latest price action rather than leaving stale orders behind during range-bound markets.

### 4. Trailing Protection
Once in a trade, the stop loss automatically follows price movement:
- **Buy positions**: SL moves up as `Bid` rises, but never moves back down
- **Sell positions**: SL moves down as `Ask` falls, but never moves back up

This locks in profits as the breakout extends while giving the trade room to breathe.

### When Does It Work Best?

| Market Condition | Performance |
|---|---|
| **High-volatility breakouts** (news events, session opens) | ✅ Excellent — captures sharp moves |
| **Trending markets** | ✅ Good — rides momentum with trailing stop |
| **Range-bound / choppy markets** | ⚠️ Caution — frequent SL hits possible |
| **Low-liquidity periods** | ⚠️ Caution — wider spreads may cause slippage |

---

## ⚙️ Configuration

All parameters are adjustable from the EA input dialog when attaching to a chart:

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `LotSize` | `double` | `0.01` | 0.01 – broker max | Trade volume per order. Keep small for testing. |
| `GapPips` | `int` | `50` | 1 – 500 | Distance (in pips) from current price where pending orders are placed. Smaller = more fills, larger = stronger breakouts only. |
| `StopLossPips` | `int` | `50` | 1 – 500 | Stop loss distance (in pips) from the entry price. Sets initial risk per trade. |
| `TrailingStopPips` | `int` | `20` | 1 – 500 | Trailing stop distance (in pips). Once in profit, SL trails this far behind current price. Smaller = tighter trail, locks profit faster but may exit early. |
| `OrderLifetimeSec` | `int` | `30` | 5 – 3600 | Seconds before unfilled pending orders are cancelled & refreshed. Shorter = tighter brackets, more order churn. |
| `MagicNumber` | `int`/`long` | `123456` | Any unique value | Unique identifier for this EA's orders. **Change this if running multiple instances** on different charts. |

### Tuning Tips

- **Scalping (M1/M5)**: Try `GapPips=10`, `StopLossPips=15`, `TrailingStopPips=8`, `OrderLifetimeSec=15`
- **Swing (H1/H4)**: Try `GapPips=100`, `StopLossPips=80`, `TrailingStopPips=40`, `OrderLifetimeSec=120`
- **News Trading**: Try `GapPips=30`, `StopLossPips=50`, `TrailingStopPips=20`, `OrderLifetimeSec=10`

---

## 🚀 Installation

### Prerequisites

- **MetaTrader 4** and/or **MetaTrader 5** (any broker)
- **MetaEditor** (comes bundled with MT4/MT5)
- **Allow Algo Trading** must be enabled in MT4/MT5 settings

### For MetaTrader 4

1. **Locate your data folder**
   - In MT4, go to **File → Open Data Folder**

2. **Copy the EA file**
   ```
   Copy  BracketBlitz.mq4  →  [Data Folder]/MQL4/Experts/
   ```

3. **Compile in MetaEditor**
   - Open `BracketBlitz.mq4` in **MetaEditor**
   - Press **F7** (Compile)
   - Verify the output: **0 errors, 0 warnings**

4. **Enable Auto Trading**
   - In MT4, click the **AutoTrading** button in the toolbar (should show green)
   - Go to **Tools → Options → Expert Advisors** and check:
     - ☑ Allow automated trading
     - ☑ Allow DLL imports (not required, but good practice)

5. **Attach to a chart**
   - Open a chart (e.g., EURUSD M1)
   - In the **Navigator** panel, expand **Expert Advisors**
   - Drag **BracketBlitz** onto the chart
   - In the dialog, go to the **Inputs** tab and configure parameters
   - Click **OK**

### For MetaTrader 5

1. **Locate your data folder**
   - In MT5, go to **File → Open Data Folder**

2. **Copy the EA file**
   ```
   Copy  BracketBlitz.mq5  →  [Data Folder]/MQL5/Experts/
   ```

3. **Compile in MetaEditor**
   - Open `BracketBlitz.mq5` in **MetaEditor**
   - Press **F7** (Compile)
   - Verify the output: **0 errors, 0 warnings**

4. **Enable Algo Trading**
   - In MT5, click the **Algo Trading** button in the toolbar (should show green)
   - Go to **Tools → Options → Expert Advisors** and check:
     - ☑ Allow Algo Trading

5. **Attach to a chart**
   - Open a chart (e.g., EURUSD M1)
   - In the **Navigator** panel, expand **Expert Advisors**
   - Drag **BracketBlitz** onto the chart
   - Check **"Allow Algo Trading"** in the dialog
   - Go to the **Inputs** tab and configure parameters
   - Click **OK**

### Verify It's Running

- A **smiley face** (😊) should appear in the top-right corner of the chart
- Check the **Experts** tab (bottom panel) for log messages:
  ```
  BracketBlitz EA initialized.
  Gap: 50 pips | SL: 50 pips | Trail: 20 pips | Lifetime: 30 sec
  Buy Stop placed at 1.08550 SL: 1.08050 Ticket #12345
  Sell Stop placed at 1.07550 SL: 1.08050 Ticket #12346
  ```
- If you see a **sad face** (☹️), check that Algo/Auto Trading is enabled

---

## 🧪 Backtesting Guide

Always backtest before going live. Here's how:

### MetaTrader 4

1. Go to **View → Strategy Tester** (or press **Ctrl+R**)
2. Select **BracketBlitz** from the Expert Advisor dropdown
3. Choose your symbol (e.g., EURUSD) and timeframe (e.g., M1)
4. Set the date range and modelling mode:
   - Use **"Every tick"** for the most accurate results
5. Set initial deposit and configure inputs
6. Check **Visual mode** to watch the EA in real-time
7. Click **Start**

### MetaTrader 5

1. Go to **View → Strategy Tester** (or press **Ctrl+R**)
2. Select **BracketBlitz** from the Expert Advisor dropdown
3. Choose your symbol and timeframe
4. Set the execution mode to **"Every tick based on real ticks"** for best accuracy
5. Configure inputs and set the date range
6. Enable **Visualization** to watch live
7. Click **Start**

### What to Look For

- ✅ Two pending orders appear on the chart at startup
- ✅ Orders refresh (delete + re-place) every 30 seconds if untriggered
- ✅ When one order triggers, the other disappears immediately (OCO)
- ✅ The trailing stop moves the SL line as price advances
- ✅ When the EA is removed, all pending orders are deleted
- ✅ No orphaned orders remain after EA removal

---

## 🏗️ Code Architecture

### MT4 Version (`BracketBlitz.mq4`)

Uses MQL4's classic order management system where pending orders and open positions share a **unified order pool**. Key characteristics:

- `OrderSend()` / `OrderModify()` / `OrderDelete()` for all trade operations
- `OrderSelect()` with `SELECT_BY_POS` or `SELECT_BY_TICKET` to access order data
- Ticket tracked as `int` (signed integer, `-1` = no order)
- When a pending order fills, it stays in the same pool with a changed `OrderType()` (e.g., `OP_BUYSTOP` → `OP_BUY`)

### MT5 Version (`BracketBlitz.mq5`)

Uses MQL5's modern trade architecture with **separate pools** for orders and positions:

- `CTrade` class (from `<Trade\Trade.mqh>`) for sending/modifying/deleting orders
- `OrdersTotal()` / `OrderGetTicket()` — accesses the **pending order** pool
- `PositionsTotal()` / `PositionGetTicket()` — accesses the **open position** pool
- Ticket tracked as `ulong` (unsigned long, `0` = no order)
- When a pending order fills, it moves from the **order pool** to the **position pool** — detection requires checking both pools

### Shared Logic Flow

Both versions implement identical trading logic:

```
OnInit()
  └─ PlacePendingOrders()

OnTick()
  ├─ Step 1: OCO check (IsFilledOrder → DeletePendingOrder)
  ├─ Step 2: Trailing stop (ApplyTrailingStop)
  ├─ Step 3: Expiry check (TimeCurrent - placedTime ≥ lifetime)
  └─ Step 4: Re-place if no pending orders exist

OnDeinit()
  └─ DeleteAllPendingOrders()
```

---

## 📚 Function Reference

### Core Functions

| Function | Returns | Description |
|---|---|---|
| `PipSize()` | `double` | Returns the pip value adjusted for the broker's digit configuration. Returns `Point*10` for 3/5-digit brokers, `Point` otherwise. |
| `PlacePendingOrders()` | `void` | Calculates Buy Stop and Sell Stop prices from the current market price, places both orders, and stores their tickets + placement time. |
| `ApplyTrailingStop()` | `void` | Iterates all open positions owned by this EA and moves the SL to trail behind the current price. Never moves SL against the trade. |

### Order Management

| Function | Returns | Description |
|---|---|---|
| `CountPendingOrders()` | `int` | Counts how many pending orders (Buy Stop / Sell Stop) belong to this EA on this symbol. |
| `CountOpenPositions()` | `int` | Counts how many open market positions (Buy / Sell) belong to this EA on this symbol. |
| `IsPendingOrder(ticket)` | `bool` | Checks if a given ticket number is still a live pending order. |
| `IsFilledOrder(ticket)` | `bool` | Checks if a pending order ticket has been triggered and is now an open position. |
| `DeletePendingOrder(ticket)` | `bool` | Deletes a specific pending order by its ticket number. Returns `true` on success. |
| `DeleteAllPendingOrders()` | `void` | Deletes ALL pending orders belonging to this EA on this symbol. Resets stored tickets. |

### Event Handlers

| Function | Called When | Purpose |
|---|---|---|
| `OnInit()` | EA attached to chart | Initializes the EA, prints config, places first pair of pending orders. |
| `OnTick()` | Every new tick | Main loop: OCO check → trailing stop → expiry check → re-placement. |
| `OnDeinit()` | EA removed from chart | Cleanup: deletes all pending orders to prevent orphans. |

---

## 🔧 Troubleshooting

### Common Issues

| Problem | Cause | Solution |
|---|---|---|
| **Sad face on chart** | Algo Trading is disabled | Enable the AutoTrading / Algo Trading button in the MT toolbar |
| **"OrderSend Error 130"** | Invalid stops — too close to price | Increase `GapPips` or `StopLossPips`. Some brokers have a minimum stop distance. |
| **"OrderSend Error 131"** | Invalid lot size | Check your broker's minimum lot size. Adjust `LotSize` accordingly. |
| **"OrderSend Error 134"** | Not enough free margin | Reduce `LotSize` or deposit more funds. |
| **"OrderSend Error 148"** | Too many pending orders | Some brokers limit pending orders. Close some existing orders. |
| **Orders not refreshing** | Timer relies on server time | Ensure your broker's server is responsive. `TimeCurrent()` only updates on new ticks. |
| **Both orders triggered** | Extreme volatility / gap | This is rare but possible during gaps. The OCO check runs tick-by-tick, so both can fill between ticks. |
| **No trades on backtest** | Spread too wide for gap | In Strategy Tester, set a realistic spread. If spread > `GapPips`, orders may fail. |

### Logging

All EA activities are logged to the **Experts** tab. Key log messages:

```
BracketBlitz EA initialized.
Buy Stop placed at 1.08550 SL: 1.08050 Ticket #12345
Sell Stop placed at 1.07550 SL: 1.08050 Ticket #12346
Buy Stop #12345 filled. Deleting Sell Stop #12346
Pending orders expired after 30 seconds. Refreshing...
BracketBlitz EA removed. All pending orders deleted.
```

---

## ❓ FAQ

**Q: Can I run BracketBlitz on multiple charts?**
> Yes! Just give each instance a **different `MagicNumber`** so they don't interfere with each other.

**Q: Does it work on all currency pairs?**
> Yes. It works on any instrument available in MetaTrader — forex pairs, gold (XAUUSD), indices, crypto CFDs, etc. The pip calculation auto-adjusts for each symbol's digit configuration.

**Q: Can I use it alongside manual trading?**
> Absolutely. The EA only manages orders with its own `MagicNumber`. It will never touch your manual trades or orders from other EAs.

**Q: Why 30 seconds for the refresh timer?**
> 30 seconds is a balance between keeping entries fresh and avoiding excessive order churn. You can adjust this from 5 seconds (aggressive) to 3600 seconds (passive) via the `OrderLifetimeSec` input.

**Q: Does it set a Take Profit?**
> No. The strategy relies on the **trailing stop** to lock in profit and exit. This allows the trade to ride extended breakouts without a hard exit cap. If you want a TP, you can manually set one on the position after it opens.

**Q: What happens during high-impact news?**
> BracketBlitz is designed for breakout-capture, making it well-suited for news events. However, be aware of:
> - **Wider spreads** during news (may affect order placement)
> - **Slippage** on the fill price
> - **Both orders filling** in a gap scenario (rare but possible)

**Q: MT4 or MT5 — which should I use?**
> Both versions have identical logic. Choose based on your broker:
> - **MT4** — most retail forex brokers, simpler interface
> - **MT5** — newer brokers, more asset classes, faster backtesting

---

## 📁 Project Structure

```
BracketBlitz/
├── BracketBlitz.ex4     # Compiled EA — MetaTrader 4
├── BracketBlitz.ex5     # Compiled EA — MetaTrader 5
├── .gitignore           # Excludes source .mq4/.mq5 files to protect IP
└── README.md            # This documentation
```

> **Note:** Source code files (`.mq4`/`.mq5`) are excluded from the repository via `.gitignore` to protect intellectual property. Only compiled `.ex4`/`.ex5` files are distributed.

---

## 📋 Changelog

### v1.00 — Initial Release
- OCO bracket order placement (Buy Stop + Sell Stop)
- Configurable gap, stop loss, trailing stop, and refresh timer
- Auto-refresh pending orders on timeout
- Smart trailing stop (only moves in profitable direction)
- Clean lifecycle management (auto-cleanup on EA removal)
- Magic number isolation for multi-instance support
- 4/5-digit and 3-digit (JPY) broker auto-detection
- Full MetaTrader 4 (MQL4) implementation
- Full MetaTrader 5 (MQL5) implementation
- Source code protection via .gitignore (only compiled files distributed)

---

## ⚠️ Risk Disclaimer

> **Trading forex and CFDs involves substantial risk of loss and is not suitable for all investors.** The high degree of leverage can work against you as well as for you. Before deciding to trade, you should carefully consider your investment objectives, level of experience, and risk appetite.
>
> **There is no guarantee of profit.** Past performance is not indicative of future results. This Expert Advisor is provided as-is with no warranty of any kind. The authors are not responsible for any financial losses incurred through the use of this software.
>
> **Always test on a demo account first.** Never risk capital you cannot afford to lose. It is your responsibility to validate the EA's behaviour in a risk-free environment before deploying it on a live account.

---

## 📄 License

This project is licensed under the **MIT License** — you are free to use, modify, and distribute it for personal or commercial purposes. See below:

```
MIT License

Copyright (c) 2025 BracketBlitz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 👤 Author

Built with ⚡ by **BracketBlitz Team**

---

*If you find BracketBlitz useful, give it a ⭐ on GitHub!*
