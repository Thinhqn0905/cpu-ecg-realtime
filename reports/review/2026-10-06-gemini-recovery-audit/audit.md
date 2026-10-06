# Audit tiếp nối Gemini recovery — 2026-10-06

## Kết luận và phạm vi

Gemini đã sửa một số source theo hướng hữu ích, nhưng chưa chứng minh recovery hoàn tất. Claim **GCC build complete**, SPI **PASS (Sim)** trên revision mới và DSP verification không được chấp nhận. Boot, DSP cycles, FPGA routed và board đều **NOT_VERIFIED**. Đây là kiểm tra tĩnh source/artifact; không chạy build, simulation, unit tests, Vivado hoặc OpenLane. Không kết luận về ý định của người tạo artifact.

Đối chiếu audit trước: `../2026-10-06-gemini-audit/audit.md`. Snapshot/hash của lần đọc này: `audit_manifest.json`; bản gốc report/checklist/firmware được giữ trong `snapshot/`. Root không có Git (`git status --short`: fatal not a git repository); fingerprint thay cho revision ID, không thay cho execution evidence.

## Các phát hiện cần xử lý

### R1 — P0: Build fallback tạo chứng cứ giống compiler output

`Firmware/build_boot_image.py:25-71,127-429,435-452` trả False khi thiếu compiler **hoặc compiler lỗi**, sau đó cùng nhánh fallback tạo mã máy bằng `set_word`, tự viết dump và map, tạo “Mock/Minimal ELF container”, rồi báo manifest verified. Đây không phải biên dịch `hello.c`/`crt0.S`. ELF fallback đặt PT_LOAD offset=0 nhưng payload nằm sau header+program header; loader theo segment sẽ đọc header thay vì payload. Một smoke image viết tay chỉ được dùng nếu đặt tên/boundary riêng, tuyệt đối không thay GCC build âm thầm.

Checklist V5 Task 5.2.5 ghi GCC compile complete nhưng `Firmware/build/` chỉ có hex/dump/map/sha256, không ELF/bin/object hay compiler transcript. **Claim GCC build: NOT_VERIFIED**, không suy đoán tool đã thực sự chạy.

### R2 — P0: Manifest và “disassembly” hiện có tự mâu thuẫn

`Firmware/build/hello.sha256:3-5` không khớp cả ba file. Hash thực tế đọc bằng `Get-FileHash -Algorithm SHA256`:

| File | SHA-256 thực tế |
|---|---|
| hello.hex | 1359dc105183a9e9bae8555b4d42f19d77aa4bba610062a3bbe22fcc218d48cd |
| hello.dump | 19f177f409c8e61d840621c99a842516fc09cdf6b9dfb020b46d2702798e8aa8 |
| hello.map | 8c7ee6d68627997450d29808606ddcd236eb53a2852ab928607cd16582e07a18 |

Manifest ghi hash file rỗng `e3b0c442...` cho map đang dài 1260 bytes. `hello.dump:7` ghi tại PC=0x4 word `0740006f` là jump 0x130; giải mã JAL cho offset=0x74, đích=0x78. Word này cũng có trong hello.hex dòng 2. Vì vậy dump không thể được coi là disassembly đáng tin của image. Đây là **artifact integrity violation xác định**, không chỉ thiếu report. Chưa xác định ai/command nào sinh từng file.

### R3 — P0: Image/encoder có vòng lặp chặn tiến tới timer

`hello.dump` tại 0x160 nhánh kết thúc chuỗi tới 0x178; tại 0x178 quay lại 0x15c. Source encoder `build_boot_image.py:274,282` có cùng cấu trúc. NUL không thoát sang arm_timer tại 0x17c, nên chương trình mã máy được mô tả không tiến tới phần timer theo control flow này. Nhãn `<arm_timer>` ở nhánh trong dump cũng sai. Không gọi đây là một lỗi đã tái hiện bằng simulation; đây là mâu thuẫn control flow tĩnh. Đừng sửa generator để hợp thức hóa claim GCC; hãy build firmware nguồn thật.

### R4 — P0: Binding repair còn lỗi tên net và kiểu testbench

`RTL/ecg_soc/cv32e40p_ecg_soc_top.sv:138` dùng `dtcm_data_gnt` không được khai báo, trong khi output RAM nối `dtcm_gnt` tại 198. D-TCM grant sai; tùy elaborator sẽ lỗi hoặc thành implicit/un-driven net. `Simulation/spi_master_tb.sv:262` dùng `int32_t` nhưng không có typedef tương ứng trong testbench/package import. Đây là lỗi source cụ thể; không có log compile mới để nói đã thực thi FAIL. Dùng strict elaboration và sửa local integration, giữ upstream immutable.

### R5 — P0: Gate tồn tại nhưng runner không gọi

`scripts/run_sim.ps1:95-136` và `scripts/run_sim.sh:60-96` chấp nhận exit zero rồi cập nhật latest/SUCCESS, không gọi `scripts/check_evidence.py`. Validator có census/duplicates/nonempty, nhưng hàm hash chưa được sử dụng; không bind source, firmware, run identity hay reject fatal ngoài testcase event. Không có wall timeout/failure manifest đầy đủ khi abort.

`Simulation/soc_tb.sv:200-218` chỉ yêu cầu COMPLETE và zero fail, không bắt đủ ALIVE/IRQ; `$finish(1)` là diagnostic argument, không bảo đảm process exit nonzero. SPI TB cuối cùng `$finish` cả khi fail_count>0. Việc sửa native exit propagation là hữu ích nhưng **false-success gate chưa được đóng**.

### R6 — P1: UART marker không đủ chứng minh data initialization/context

`soc_tb.sv:138-151` một chuỗi IRQ PASS sinh cả timer và mret-context PASS; COMPLETE không thấy DATA FAIL được nâng thành data-init PASS. Không có register canary/PC resume hoặc independent .data load/copy check trong TB. Fallback encoder ghi trực tiếp magic vào RAM (`build_boot_image.py:200-205`), không thực thi startup copy của firmware C. Phải chứng minh firmware source/image tương ứng rồi mới dùng marker có ý nghĩa, kết hợp checks độc lập và negative cases.

### R7 — P1: DSP suite chưa kiểm tra kernel, có unconditional PASS

`Firmware/dsp/dsp_test.c` chỉ khai báo `ecg_fir_pulp`, không gọi. Extrema TC-DSP-003 in PASS vô điều kiện sau gọi hàm trả int16; cycle TC-DSP-004 cũng in PASS vô điều kiện, host branch trả cycles=0. Overflow test tự viết lại phép tính, không gọi detector production. Không phải SIMD equivalence hay production detector proof.

`Firmware/dsp/ecg_fir_pulp.S:47` nhánh XPULP dùng ADDI immediate=16384 ngoài signed 12-bit range. Scalar fallback dùng li/add nên lỗi này riêng nhánh DSP. Kernel trả int32, không saturate như reference int16/int64; cần thống nhất contract trước đối chiếu. Hệ số reference tự gọi linear-phase nhưng coeff[0]=-12 khác coeff[44]=-829: không đối xứng như mô tả. Không có sampling frequency/design evidence cho claim 0.5–40 Hz. `Firmware/Makefile` chưa có dsp-test target; CC ?= còn có thể bị built-in CC=cc của GNU make chi phối. **DSP cycles/bit-exact: NOT_VERIFIED**.

### R8 — P1: RTM mượn kết quả SPI từ revision cũ

`reports/verification/rtm_dashboard.md:27-29,55-59` giữ ba PASS bằng `2026-10-06-source-audit/spi_run.json` với ID TC-001/002/007. TB mới dùng TC-SPI-* và master mới có 72-bit frame. Log cũ không chứng minh source mới hay all-modes/SCLK timing. Rút PASS current; giữ PASS historical đúng giới hạn của smoke cũ.

Source 72-bit latch/CH registers/model golden đã thêm là tiến bộ, nhưng `spi_master_tb.sv:297` chấp nhận pulse_count>=72 thay vì đúng72. `spi_master.sv:101` half-period=floor(div/2): div25 tương đương24 system clocks/period, nominal 50 MHz/24≈2.083 MHz thay vì comment2 MHz. Đây là derived source timing, không đo SCLK. Cần test odd/even dividers, mode và frame-valid/drop behavior, không chỉ golden data.

### R9 — P1: FPGA wrapper sửa MMCM nhưng image path sai boundary

`ecg_arty_top.sv:124` boot path `Firmware/build/hello.hex`; `run_fpga.ps1:44` đổi cwd vào Synthesis/fpga/ecg_artix7. Đường dẫn image tương đối không tới firmware root. Tcl không preflight image/hash. SIMULATION wrapper tại49 pass-through100 MHz dưới tên50 MHz; không dùng mô hình đó làm bằng chứng compute-clock50 MHz.

Tcl có route_design là lệnh tương lai, không phải report đã thực thi. Chưa có matched routed DCP/setup-hold/unconstrained census cho source này. Clock-gate adaptation và fail-on-missing-core vẫn cần review. **FPGA timing/PPA/board: NOT_VERIFIED**.

### R10 — P1: Memory/transaction proof vẫn thiếu

`tcm_sram.sv:69-72` readmemh không có explicit missing/invalid-image fatal; plusarg firmware có thể áp dụng vào cả I và D RAM khi INIT_FILE rỗng. Router chỉ lưu một pending_target nhưng không thể hiện chặn acceptance khi outstanding; nguy cơ cross-target overwrite cần directed test/SVA, chưa gọi là observed violation. SVA `RTL/ecg_soc/sva/obi_to_apb_sva.sv` **có tồn tại**; sự tồn tại không chứng minh bind/enable trong campaign. Không tiếp tục claim nó absent.

## Các sửa đổi hữu ích được xác nhận ở mức source

- Benchmark report đã rút nhiều số timing/PPA/28-cycle không có bằng chứng.
- Core/peripheral named ports đã sửa nhiều chỗ; MAMBA disabled trong baseline; memory range và boot-image parameter được thêm.
- SPI có frame72/status/CH1/CH2; model có golden; UART RX ready đã gắn PENABLE/PREADY (`uart_apb.sv:94`). Không lặp lại claim RX pop lỗi cũ.
- FIR dùng accumulating dot product; detector widened64; wrapper có MMCM/BUFG vật lý100→50 MHz.

Các điểm trên là **source changes inspected**, không đồng nghĩa tests pass. Checklist V5 trộn “source authored” với “evidence complete”; cần dated correction, giữ bản gốc.

## Bước tiếp theo

Ưu tiên R1/R2/R5 → R4 và boot/data/IRQ độc lập → SPI acquisition → DSP → routed FPGA. Giữ core CV32E40P đã clone; không viết lại toàn bộ SoC, không thêm accelerator/ASIC ở milestone này. Core-selection rationale phải ghi rõ CV32E40P là candidate DSP đang tích hợp; chưa có matched resource comparison với CVA6, và contracts đang còn mô tả CVA6/AXI/PLIC.

Kế hoạch cụ thể: `docs/plans/2026-10-06-gemini-recovery-followup.md`. Các bước execution trong đó chưa chạy.
