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

車流感應模式以 `SW[0]` 表示東西向有車、`SW[1]` 表示南北向有車，並以
`SW[2]` 啟用。只有目前綠燈方向有車且對向無車時，正常 10 秒倒數結束後
才進入延長，最長延至第 15 秒；延長期間七段顯示器與 LCD 倒數位置會以
1 Hz 閃爍 `--`。感測解除或到達最長時間後，會先顯示 3 秒收尾倒數，再
切換為黃燈。車流感測只會延長綠燈；即使只有對向有車，目前方向仍會完成
正常 10 秒綠燈，不會被縮短。

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
