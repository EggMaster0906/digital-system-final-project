`timescale 1ns/1ps

module fault_mode_tb;

    localparam integer TEST_CLOCK_HZ        = 8;
    localparam integer TEST_GREEN_SECONDS   = 4;
    localparam integer TEST_ALL_RED_SECONDS = 2;

    localparam [3:0] ST_EW_GREEN    = 4'd0;
    localparam [3:0] ST_NIGHT       = 4'd8;
    localparam [3:0] ST_FAULT       = 4'd10;
    localparam [3:0] ST_FAULT_CLEAR = 4'd11;

    reg         clk;
    reg  [3:0]  KEY;
    reg  [17:0] SW;
    wire [17:0] LEDR;
    wire [8:0]  LEDG;
    wire [6:0]  HEX0;
    wire [6:0]  HEX1;
    wire [6:0]  HEX2;
    wire [6:0]  HEX3;
    wire [6:0]  HEX4;
    wire [6:0]  HEX5;
    wire [6:0]  HEX6;
    wire [6:0]  HEX7;
    integer     errors;
    integer     timeout_count;

    digital_system_final_project #(
        .CLOCK_HZ              (TEST_CLOCK_HZ),
        .BUTTON_DEBOUNCE_CYCLES(1),
        .MIN_RED_SECONDS       (1),
        .GREEN_SECONDS         (TEST_GREEN_SECONDS),
        .MIN_GREEN_SECONDS     (2),
        .YELLOW_SECONDS        (2),
        .ALL_RED_SECONDS       (TEST_ALL_RED_SECONDS),
        .PED_SECONDS           (3),
        .FLASH_SECONDS         (1)
    ) dut (
        .CLOCK_50 (clk),
        .KEY      (KEY),
        .SW       (SW),
        .LEDR     (LEDR),
        .LEDG     (LEDG),
        .HEX0     (HEX0),
        .HEX1     (HEX1),
        .HEX2     (HEX2),
        .HEX3     (HEX3),
        .HEX4     (HEX4),
        .HEX5     (HEX5),
        .HEX6     (HEX6),
        .HEX7     (HEX7)
    );

    always #5 clk = ~clk;

    task wait_for_state;
        input [3:0] expected_state;
        begin
            timeout_count = 0;
            while ((dut.traffic_state !== expected_state) &&
                   (timeout_count < 30)) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end
            if (dut.traffic_state !== expected_state) begin
                $display("FAIL: timed out waiting for state %0d", expected_state);
                errors = errors + 1;
            end
        end
    endtask

    task wait_controller_tick;
        begin
            @(posedge dut.tick_1s);
            @(posedge clk);
            #1;
        end
    endtask

    task check_lights;
        input [5:0] expected_lights;
        begin
            if ({LEDR[2:0], LEDG[2:0]} !== expected_lights) begin
                $display("FAIL: expected lights %06b, got %06b at time %0t",
                         expected_lights, {LEDR[2:0], LEDG[2:0]}, $time);
                errors = errors + 1;
            end
        end
    endtask

    task check_dashed_countdowns;
        begin
            if ({HEX5, HEX4, HEX7, HEX6} !== {4{7'b0111111}}) begin
                $display("FAIL: fault-related state does not show -- for both countdowns");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk    = 1'b0;
        KEY    = 4'b1110;
        SW     = 18'd0;
        errors = 0;

        repeat (2) @(posedge clk);
        #1;
        KEY[0] = 1'b1;
        wait_for_state(ST_EW_GREEN);

        // Simultaneous night and fault requests must enter fault because it
        // has the higher priority. Both directions flash red, never green.
        SW[3] = 1'b1;
        SW[4] = 1'b1;
        wait_for_state(ST_FAULT);
        check_lights(6'b111_000);
        check_dashed_countdowns;

        wait_controller_tick;
        if (dut.traffic_state !== ST_FAULT) begin
            $display("FAIL: controller left fault while SW[4] remained active");
            errors = errors + 1;
        end
        check_lights(6'b100_000);

        wait_controller_tick;
        check_lights(6'b111_000);

        // Clearing the fault cannot jump directly into the requested night
        // mode. A complete all-red interval must occur first.
        SW[4] = 1'b0;
        wait_for_state(ST_FAULT_CLEAR);
        check_lights(6'b111_000);
        check_dashed_countdowns;
        if (dut.remaining_seconds !== TEST_ALL_RED_SECONDS) begin
            $display("FAIL: fault exit did not start a full all-red interval");
            errors = errors + 1;
        end

        wait_controller_tick;
        if ((dut.traffic_state !== ST_FAULT_CLEAR) ||
            (dut.remaining_seconds !== TEST_ALL_RED_SECONDS - 1)) begin
            $display("FAIL: fault-clearance duration is incorrect");
            errors = errors + 1;
        end
        check_lights(6'b111_000);

        wait_controller_tick;
        if (dut.traffic_state !== ST_NIGHT) begin
            $display("FAIL: active night request was not honored after clearance");
            errors = errors + 1;
        end

        // A new fault must immediately preempt night mode. Clearing both mode
        // switches then restarts the normal cycle only after another clearance.
        SW[4] = 1'b1;
        wait_for_state(ST_FAULT);
        check_lights(6'b111_000);

        SW[3] = 1'b0;
        SW[4] = 1'b0;
        wait_for_state(ST_FAULT_CLEAR);
        check_lights(6'b111_000);

        wait_controller_tick;
        if (dut.traffic_state !== ST_FAULT_CLEAR) begin
            $display("FAIL: second fault clearance ended too early");
            errors = errors + 1;
        end
        wait_controller_tick;
        if ((dut.traffic_state !== ST_EW_GREEN) ||
            (dut.remaining_seconds !== TEST_GREEN_SECONDS)) begin
            $display("FAIL: normal cycle did not restart from a full EW green phase");
            errors = errors + 1;
        end
        check_lights(6'b110_001);

        if (errors == 0)
            $display("PASS: fault priority, synchronized input, flashing red, dashed countdowns, and safe recovery passed");
        else
            $display("FAIL: %0d fault-mode checks failed", errors);

        $finish;
    end

endmodule
