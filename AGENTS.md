# AGENTS.md

本工作區的 FPGA 專案位於 `digital_system_final_project/`，目標板為 DE2-115，FPGA 為 Cyclone IV E `EP4CE115F29C7`，使用 Quartus II 13.1。

## 專案結構

- Quartus 專案：`digital_system_final_project/digital_system_final_project.qpf`
- 頂層 module：`digital_system_final_project`
- 必要 Verilog：專案目錄根層的 6 個 `.v` 檔
- Testbench：`digital_system_final_project/tests/`
- 腳位：`digital_system_final_project/digital_system_final_project.tcl`
- 時序限制：`digital_system_final_project/digital_system_final_project.sdc`
- Quartus 生成物：`db/`、`incremental_db/`、`output_files/`、`simulation/`，均由 `.gitignore` 排除

## 驗證規則

修改 Verilog 後，先從專案目錄執行 iVerilog 測試：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run_tests.ps1
```

測試必須同時檢查 iVerilog/vvp 結束碼、`PASS:` 結果，且不得出現 `FAIL:`。不要將 `.vvp` 或波形檔加入專案。

接著執行 Quartus 完整編譯：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

Build 成功時會產生 `output_files/digital_system_final_project.sof`。iVerilog 不能取代 Quartus synthesis、fitter、TimeQuest 與腳位檢查。

實板連接 USB-Blaster 後才能執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\download.ps1
```

可用 `-QuartusBin` 指定 Quartus 工具目錄；多條 USB-Blaster 同時連接時以 `-Cable` 指定。JTAG 載入的 `.sof` 斷電後會消失。
