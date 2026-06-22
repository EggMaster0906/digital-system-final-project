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
   ├─ digital_system_final_project.qpf  # Quartus 專案
   ├─ digital_system_final_project.qsf  # FPGA、來源檔與腳位設定入口
   ├─ digital_system_final_project.sdc  # 時序限制
   ├─ digital_system_final_project.tcl  # DE2-115 腳位設定
   ├─ build.ps1                         # Quartus 完整編譯
   ├─ download.ps1                      # USB-Blaster 下載
   └─ tests/
      ├─ run_tests.ps1
      ├─ traffic_controller_tb.v
      └─ countdown_display_tb.v
```

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
