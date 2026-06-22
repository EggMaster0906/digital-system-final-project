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
      ├─ run_tests.ps1
      ├─ traffic_controller_tb.v
      ├─ countdown_display_tb.v
      └─ lcd_controller_tb.v
```

LCD 第一行顯示東西向燈號及目前階段倒數，第二行顯示南北向燈號及
行人狀態（`STOP`、`WAIT` 或 `GO`）。控制器使用 8-bit 寫入模式，會在
上電後自動初始化並持續刷新，不需要讀取 busy flag。

`db/`、`incremental_db/`、`output_files/`、`simulation/` 都是可重建的 Quartus 生成物，不納入 Git。

## 驗證

在 repository 根目錄執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\digital_system_final_project\tests\run_tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\digital_system_final_project\build.ps1
```

Build 成功後，`digital_system_final_project/output_files/digital_system_final_project.sof` 可用下列指令下載：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\digital_system_final_project\download.ps1
```
