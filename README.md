# Digital System Final Project

DE2-115（Cyclone IV E EP4CE115F29C7）智慧交通號誌專題。Quartus II 專案 revision 與 Verilog 頂層 module 均為 `digital_system_final_project`。

## 目錄

```text
DigitalLab/
├─ README.md
├─ PROJECT_PLAN.md
└─ digital_system_final_project/
   ├─ digital_system_final_project.v    # 頂層設計
   ├─ clock_divider.v
   ├─ button_conditioner.v
   ├─ traffic_controller.v
   ├─ countdown_display.v
   ├─ seven_seg_decoder.v
   ├─ lcd_controller.v               # LCD 初始化、時序與兩行狀態顯示
   ├─ digital_system_final_project.qpf  # Quartus 專案
   ├─ digital_system_final_project.qsf  # FPGA、來源檔與腳位設定入口
   ├─ digital_system_final_project.sdc  # 時序限制
   ├─ digital_system_final_project.tcl  # DE2-115 腳位設定
   ├─ build.ps1                         # Quartus 完整編譯
   ├─ download.ps1                      # USB-Blaster 下載
   └─ tests/
      ├─ run_tests.sh
      ├─ run_tests.ps1
      ├─ traffic_controller_tb.v
      ├─ night_mode_tb.v
      ├─ fault_mode_tb.v
      ├─ countdown_display_tb.v
      └─ lcd_controller_tb.v
```

LCD 第一行顯示東西向燈號及目前階段倒數，第二行顯示南北向燈號及
行人狀態（`STOP`、`WAIT` 或 `GO`）。控制器使用 8-bit 寫入模式，會在
上電後自動初始化並持續刷新，不需要讀取 busy flag。

將 `SW[3]` 撥至 ON 可啟用夜間閃燈模式：東西向主幹道閃黃燈、南北向
支線閃紅燈，LCD 顯示 `NIGHT MODE`，雙向七段倒數顯示 `--`。撥回 OFF
後，系統先維持一個完整的全紅安全間隔，再從東西向綠燈重新開始循環。

將 `SW[4]` 撥至 ON 可模擬系統故障。故障模式具有最高優先權，東西向與
南北向皆閃紅燈，LCD 顯示 `SYSTEM FAULT`，雙向七段倒數顯示 `--`。
故障解除後，系統先維持一個完整的全紅安全間隔；若夜間模式仍啟用則轉入
夜間模式，否則從東西向綠燈重新開始循環。

`db/`、`incremental_db/`、`output_files/`、`simulation/` 都是可重建的 Quartus 生成物，不納入 Git。

## 驗證

在 repository 根目錄執行：

macOS／Linux（需先安裝 Icarus Verilog）：

```sh
./digital_system_final_project/tests/run_tests.sh
```

Windows PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\digital_system_final_project\tests\run_tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\digital_system_final_project\build.ps1
```

Build 成功後，`digital_system_final_project/output_files/digital_system_final_project.sof` 可用下列指令下載：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\digital_system_final_project\download.ps1
```
