# Computer Architecture

本課程主要探討現代微處理器的設計原理，從基礎的運算單元、管線化設計、超純量架構、亂序執行到記憶體階層設計。所有實作皆使用 Verilog 硬體描述語言進行開發，並通過嚴謹的單元測試與效能評估。

## 開發環境與工具

* **語言:** Verilog HDL
* **模擬工具:** Icarus Verilog (iverilog) / Synopsys VCS
* **波形觀察:** GTKWave
* **建置系統:** Makefile / Python scripts

## 實驗內容詳細說明

### Lab 1: Integer Multiply/Divide Unit

本實驗目標為設計並實作一個基於 Val/Rdy 介面協定的迭代式整數乘法與除法單元，將兩個 32 位元運算元處理後產生 64 位元結果。

**實作重點:**
* **迭代式乘除法:** 採用 Radix-4 Booth 演算法大幅縮減乘法部分積數量，除法部分則實踐 Non-restoring division。
* **介面協定:** 嚴格遵守對 Latency-insensitive 的 Val/Rdy 握手協定，並將資料路徑與控制邏輯解耦。

### Lab 2: Pipelined RISC-V Processor

本實驗將基礎的單週期處理器擴展為 5-stage Pipeline 架構，涵蓋 RV32I 基本指令與部分的 M-extension。

**實作重點:**
* **危險處理與資料前遞:** 建構完整的 Data Forwarding 網路來繞過 RAW 衝突，大幅減少硬體 Stall 並提升系統的 IPC。
* **CSR 暫存器:** 實作基礎的控制與狀態暫存器讀寫，以支援後續的系統測試與診斷功能。

### Lab 3: Superscalar RISC-V Processor

本實驗目標為設計一個 Two-wide 的循序執行超純量處理器，使其能在單一週期內發射並執行兩道指令。

**實作重點:**
* **雙指令分派:** 實作雙指令提取單元，並透過 Steering Logic 動態分配任務給主管線或次管線。
* **Scoreboard:** 導入計分板技術進行全局的暫存器監控與危險攔截，確保資源不衝突且資料相依性正確。

### Lab 4: Out-of-Order RISC-V Processor

本實驗將處理器升級為支援 Out-of-Order Execution 的架構，允許底層單元不按程式順序執行指令以最大化效能。

**實作重點:**
* **ROB:** 開發 ROB 機制，允許指令提前執行但必須 In-order Commit，以保證 Precise Exception。
* **暫存器更名與回復:** 透過 Renaming 避開假性相依，並處理分支預測錯誤時的 Rollback。

### Lab 5: Cache Implementation

本實驗為處理器加入指令快取 (I-Cache) 與資料快取 (D-Cache)，以降低記憶體存取延遲並提升整體系統效能。

**實作重點:**
* **Cache Controller:** 透過複雜的 FSM 管理 Hit, Miss, Refill 與 Evict 流程，並實踐 Write-back 搭配 Write-allocate 原則。
* **Victim Cache:** 額外掛載 Victim Cache 降低 Conflict miss，並支援 Direct-mapped 或 Set-associative 的配置彈性。

## 專案結構

```text
Computer-Architecture/
├── Lab1/           # Integer Multiply/Divide Unit
├── Lab2/           # Pipelined RISC-V Processor
├── Lab3/           # Superscalar RISC-V Processor
├── Lab4/           # Out-of-Order RISC-V Processor (ROB)
└── Lab5/           # Cache Implementation

