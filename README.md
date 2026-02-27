# ⚡ BracketBlitz EA

> Rapid-fire OCO bracket orders that chase the market — **Buy Stop + Sell Stop**, auto-refreshed every 30 seconds.

BracketBlitz is a MetaTrader 4 Expert Advisor that continuously places bracket pending orders around the live price. When one side triggers, the other is instantly cancelled (**One-Cancels-Other**). If neither triggers within the configurable time window, both are deleted and re-placed at the current price — keeping your entries razor-close to the action.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔀 **OCO Bracket Orders** | Simultaneously places a Buy Stop above and a Sell Stop below the current price |
| ⏱️ **Auto-Refresh** | Pending orders auto-cancel & re-place every 30 seconds (configurable) |
| 🎯 **Trailing Stop** | Automatically trails the stop loss as price moves in your favour |
| ⚙️ **Fully Configurable** | Gap, stop loss, trailing distance, lot size, and timer — all adjustable from the EA inputs |
| 🧹 **Clean Lifecycle** | All pending orders are automatically deleted when the EA is removed |
| 🔢 **Magic Number Isolation** | Uses a unique magic number so it never interferes with your other EAs or manual trades |
| 📊 **4/5-Digit Broker Support** | Automatically detects and adjusts pip calculations for all broker digit configurations |

---

## 📐 How It Works

```
              ┌─────────────────────┐
              │  EA Starts (OnInit) │
              └─────────┬───────────┘
                        │
              ┌─────────▼───────────┐
              │  Place Buy Stop     │
              │  + Sell Stop        │
              │  (± GapPips from    │
              │   current price)    │
              └─────────┬───────────┘
                        │
              ┌─────────▼───────────┐
         ┌────│  OnTick Loop        │────┐
         │    └─────────────────────┘    │
         │                               │
    ┌────▼─────┐                  ┌──────▼──────┐
    │ One side │                  │ 30s elapsed │
    │ triggers │                  │ (no fill)   │
    └────┬─────┘                  └──────┬──────┘
         │                               │
    ┌────▼──────────┐            ┌───────▼───────┐
    │ Delete other  │            │ Delete both   │
    │ (OCO cancel)  │            │ pending orders│
    └────┬──────────┘            └───────┬───────┘
         │                               │
    ┌────▼──────────┐            ┌───────▼───────┐
    │ Trail SL on   │            │ Re-place at   │
    │ open position │            │ current price │
    └───────────────┘            └───────────────┘
```

---

## ⚙️ Configuration

All parameters are adjustable from the EA input dialog when attaching to a chart:

| Parameter | Default | Description |
|---|---|---|
| `LotSize` | `0.01` | Trade volume per order |
| `GapPips` | `50` | Distance (in pips) from current price for pending orders |
| `StopLossPips` | `50` | Stop loss distance (in pips) from entry price |
| `TrailingStopPips` | `20` | Trailing stop distance (in pips) — SL follows price |
| `OrderLifetimeSec` | `30` | Seconds before unfilled pending orders are cancelled & refreshed |
| `MagicNumber` | `123456` | Unique identifier for this EA's orders (change if running multiple instances) |

---

## 🚀 Installation

### Prerequisites

- **MetaTrader 4** (any broker)
- **MetaEditor** (comes bundled with MT4)

### Steps

1. **Copy the file**
   ```
   Copy BracketBlitz.mq4 → [MT4 Data Folder]/MQL4/Experts/
   ```
   > 💡 To find your MT4 data folder: In MT4, go to **File → Open Data Folder**

2. **Compile**
   - Open `BracketBlitz.mq4` in **MetaEditor**
   - Press **F7** (Compile)
   - Verify: **0 errors, 0 warnings**

3. **Attach to chart**
   - In MT4, open a chart (e.g., EURUSD M1)
   - Drag **BracketBlitz** from the Navigator panel onto the chart
   - Configure input parameters in the dialog
   - Click **OK**

4. **Verify it's running**
   - You should see a smiley face (😊) in the top-right corner of the chart
   - Check the **Experts** tab for log messages like:
     ```
     BracketBlitz EA initialized.
     Buy Stop placed at 1.08550 SL: 1.08050 Ticket #12345
     Sell Stop placed at 1.07550 SL: 1.08050 Ticket #12346
     ```

---

## 📖 Strategy Explained

BracketBlitz implements a **breakout-capture** strategy:

1. **Bracket placement** — Two pending orders straddle the current price, ready to catch a breakout in either direction.

2. **OCO execution** — The moment price breaks through one level and triggers an order, the opposite side is deleted to avoid opening conflicting positions.

3. **Fresh entries** — If neither order triggers within 30 seconds, both are deleted and re-placed at the new current price. This keeps the bracket tight around the latest price action rather than leaving stale orders behind.

4. **Trailing protection** — Once in a trade, the stop loss automatically follows price movement, locking in profits as the breakout extends.

---

## ⚠️ Risk Disclaimer

> **Trading forex involves substantial risk of loss and is not suitable for all investors.**
> Past performance is not indicative of future results. This EA is provided as-is with no guarantee of profitability. Always test on a demo account first, and never risk capital you cannot afford to lose.

---

## 📁 Project Structure

```
BracketBlitz/
├── BracketBlitz.mq4    # Expert Advisor source code
└── README.md           # This file
```

---

## 📄 License

This project is provided for educational and personal use. Use at your own risk.

---

## 👤 Author

Built with ⚡ by BracketBlitz Team
