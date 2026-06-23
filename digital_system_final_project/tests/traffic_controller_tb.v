`timescale 1ns/1ps

module traffic_controller_tb;

    localparam integer TEST_CLOCK_HZ        = 20;
    localparam integer TEST_DEBOUNCE_CYCLES = 1;
    localparam integer TEST_GREEN_SECONDS   = 4;
    localparam integer TEST_MIN_GREEN       = 2;
    localparam integer TEST_MAX_GREEN       = 7;
    localparam integer TEST_YELLOW_SECONDS  = 2;
    localparam integer TEST_ALL_RED_SECONDS = 1;
    localparam integer TEST_PED_SECONDS     = 3;

    localparam [2:0] ST_EW_GREEN  = 3'd0;
    localparam [2:0] ST_EW_YELLOW = 3'd1;
    localparam [2:0] ST_ALL_RED_1 = 3'd2;
    localparam [2:0] ST_NS_GREEN  = 3'd3;
    localparam [2:0] ST_NS_YELLOW = 3'd4;
    localparam [2:0] ST_ALL_RED_2 = 3'd5;
    localparam [2:0] ST_PED_GO    = 3'd6;
    localparam [2:0] ST_PED_CLEAR = 3'd7;

    reg         clk;
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
    reg  [3:0]  KEY;
    reg  [17:0] SW;
    integer     errors;

    digital_system_final_project #(
        .CLOCK_HZ              (TEST_CLOCK_HZ),
        .BUTTON_DEBOUNCE_CYCLES(TEST_DEBOUNCE_CYCLES),
        .GREEN_SECONDS         (TEST_GREEN_SECONDS),
        .MIN_GREEN_SECONDS     (TEST_MIN_GREEN),
        .MAX_GREEN_SECONDS     (TEST_MAX_GREEN),
        .YELLOW_SECONDS        (TEST_YELLOW_SECONDS),
        .ALL_RED_SECONDS       (TEST_ALL_RED_SECONDS),
        .PED_SECONDS           (TEST_PED_SECONDS)
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

    task wait_controller_tick;
        begin
            // The divider raises tick_1s with a nonblocking assignment. The
            // controller consumes that pulse on the following clock edge.
            @(posedge dut.tick_1s);
            @(posedge clk);
            #1;
        end
    endtask

    task check_state;
        input [2:0]  expected_state;
        input [15:0] expected_remaining;
        input        expected_pending;
        begin
            if (dut.traffic_state !== expected_state) begin
                $display("FAIL: expected state %0d, got %0d at time %0t",
                         expected_state, dut.traffic_state, $time);
                errors = errors + 1;
            end

            if (dut.remaining_seconds !== expected_remaining) begin
                $display("FAIL: state %0d expected remaining %0d, got %0d at time %0t",
                         expected_state, expected_remaining,
                         dut.remaining_seconds, $time);
                errors = errors + 1;
            end

            if (dut.ped_pending !== expected_pending) begin
                $display("FAIL: expected ped_pending %0b, got %0b at time %0t",
                         expected_pending, dut.ped_pending, $time);
                errors = errors + 1;
            end

            if (LEDG[0] && LEDG[1]) begin
                $display("FAIL: both vehicle directions green at time %0t", $time);
                errors = errors + 1;
            end

            if (LEDG[2] && (LEDG[0] || LEDG[1])) begin
                $display("FAIL: pedestrian and vehicle GO overlap at time %0t", $time);
                errors = errors + 1;
            end

            if ((HEX0 !== 7'b1111111) || (HEX1 !== 7'b1111111) ||
                (HEX2 !== 7'b1111111) || (HEX3 !== 7'b1111111)) begin
                $display("FAIL: unused HEX3..HEX0 displays are not blank at time %0t", $time);
                errors = errors + 1;
            end

            case (expected_state)
                ST_EW_GREEN:
                    if ({LEDR[2:0], LEDG[2:0]} !== 6'b110_001)
                        errors = errors + 1;
                ST_EW_YELLOW:
                    if ({LEDR[2:0], LEDG[2:0]} !== 6'b111_001)
                        errors = errors + 1;
                ST_ALL_RED_1, ST_ALL_RED_2, ST_PED_CLEAR:
                    if ({LEDR[2:0], LEDG[2:0]} !== 6'b111_000)
                        errors = errors + 1;
                ST_NS_GREEN:
                    if ({LEDR[2:0], LEDG[2:0]} !== 6'b101_010)
                        errors = errors + 1;
                ST_NS_YELLOW:
                    if ({LEDR[2:0], LEDG[2:0]} !== 6'b111_010)
                        errors = errors + 1;
                ST_PED_GO:
                    if ({LEDR[2:0], LEDG[2:0]} !== 6'b011_100)
                        errors = errors + 1;
                default: errors = errors + 1;
            endcase
        end
    endtask

    initial begin
        clk    = 1'b0;
        KEY    = 4'b1110;
        SW     = 18'd0;
        errors = 0;

        repeat (2) @(posedge clk);
        #1;
        check_state(ST_EW_GREEN, TEST_GREEN_SECONDS, 1'b0);
        if ({HEX5, HEX4, HEX7, HEX6} !==
            {7'b1000000, 7'b0011001, 7'b1000000, 7'b1111000}) begin
            $display("FAIL: top-level initial countdown is not EW=04 NS=07");
            errors = errors + 1;
        end
        KEY[0] = 1'b1;

        // Let one safe green second elapse before requesting a crossing.
        wait_controller_tick;
        check_state(ST_EW_GREEN, TEST_GREEN_SECONDS - 1, 1'b0);

        // A held active-low KEY[1] must produce one remembered request.
        KEY[1] = 1'b0;
        repeat (6) @(posedge clk);
        #1;
        check_state(ST_EW_GREEN, TEST_MIN_GREEN - 1, 1'b1);

        // At the minimum green time, safely run yellow and all-red first.
        wait_controller_tick;
        check_state(ST_EW_YELLOW, TEST_YELLOW_SECONDS, 1'b1);
        wait_controller_tick;
        check_state(ST_EW_YELLOW, TEST_YELLOW_SECONDS - 1, 1'b1);
        wait_controller_tick;
        check_state(ST_ALL_RED_1, TEST_ALL_RED_SECONDS, 1'b1);
        wait_controller_tick;
        check_state(ST_PED_GO, TEST_PED_SECONDS, 1'b1);
        wait_controller_tick;
        check_state(ST_PED_GO, TEST_PED_SECONDS - 1, 1'b1);
        wait_controller_tick;
        check_state(ST_PED_GO, TEST_PED_SECONDS - 2, 1'b1);
        wait_controller_tick;
        check_state(ST_PED_CLEAR, TEST_ALL_RED_SECONDS, 1'b0);
        wait_controller_tick;
        check_state(ST_NS_GREEN, TEST_GREEN_SECONDS, 1'b0);

        // Keep KEY[1] held throughout another complete direction change. It
        // must not create a second request or another pedestrian phase.
        wait_controller_tick;
        check_state(ST_NS_GREEN, 3, 1'b0);
        wait_controller_tick;
        check_state(ST_NS_GREEN, 2, 1'b0);
        wait_controller_tick;
        check_state(ST_NS_GREEN, 1, 1'b0);
        wait_controller_tick;
        check_state(ST_NS_YELLOW, 2, 1'b0);
        wait_controller_tick;
        check_state(ST_NS_YELLOW, 1, 1'b0);
        wait_controller_tick;
        check_state(ST_ALL_RED_2, 1, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 4, 1'b0);

        // Release and debounce the button, then reach NS green normally.
        KEY[1] = 1'b1;
        repeat (6) @(posedge clk);
        wait_controller_tick;
        wait_controller_tick;
        wait_controller_tick;
        wait_controller_tick;
        check_state(ST_EW_YELLOW, 2, 1'b0);
        wait_controller_tick;
        wait_controller_tick;
        wait_controller_tick;
        check_state(ST_NS_GREEN, 4, 1'b0);

        // Request from the opposite direction to verify the pedestrian phase
        // returns to EW green after ST_ALL_RED_2.
        KEY[1] = 1'b0;
        repeat (6) @(posedge clk);
        #1;
        check_state(ST_NS_GREEN, TEST_MIN_GREEN, 1'b1);
        wait_controller_tick;
        check_state(ST_NS_GREEN, TEST_MIN_GREEN - 1, 1'b1);
        wait_controller_tick;
        check_state(ST_NS_YELLOW, TEST_YELLOW_SECONDS, 1'b1);
        wait_controller_tick;
        wait_controller_tick;
        check_state(ST_ALL_RED_2, TEST_ALL_RED_SECONDS, 1'b1);
        wait_controller_tick;
        check_state(ST_PED_GO, TEST_PED_SECONDS, 1'b1);
        wait_controller_tick;
        wait_controller_tick;
        wait_controller_tick;
        check_state(ST_PED_CLEAR, TEST_ALL_RED_SECONDS, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_GREEN, TEST_GREEN_SECONDS, 1'b0);

        // Reset immediately restores STOP and clears any remembered request.
        KEY[0] = 1'b0;
        #1;
        check_state(ST_EW_GREEN, TEST_GREEN_SECONDS, 1'b0);

        // Smart mode must finish the ordinary four-second countdown without
        // jumping to the maximum value, then flash "--" during extension.
        KEY[1] = 1'b1;
        SW     = 18'd0;
        SW[2:0] = 3'b101;
        repeat (2) @(posedge clk);
        KEY[0] = 1'b1;
        repeat (3) @(posedge clk);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 3, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 2, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 1, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 0, 1'b0);
        if (!dut.traffic_extended ||
            ({HEX5, HEX4, HEX7, HEX6} !== {4{7'b0111111}})) begin
            $display("FAIL: smart extension did not begin with visible dashes");
            errors = errors + 1;
        end

        repeat (10) @(posedge clk);
        #1;
        if ({HEX5, HEX4, HEX7, HEX6} !== {4{7'b1111111}}) begin
            $display("FAIL: extended countdown did not blank after half a second");
            errors = errors + 1;
        end

        repeat (10) @(posedge clk);
        #1;
        check_state(ST_EW_GREEN, 0, 1'b0);
        if ({HEX5, HEX4, HEX7, HEX6} !== {4{7'b0111111}}) begin
            $display("FAIL: extended countdown did not return after one second");
            errors = errors + 1;
        end

        // Releasing the active-direction sensor ends the unknown display and
        // starts a stable three-second green countdown before yellow.
        SW[0] = 1'b0;
        repeat (3) @(posedge clk);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 3, 1'b0);
        if (dut.traffic_extended) begin
            $display("FAIL: dashes continued after active vehicle demand ended");
            errors = errors + 1;
        end
        wait_controller_tick;
        check_state(ST_EW_GREEN, 2, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 1, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_YELLOW, TEST_YELLOW_SECONDS, 1'b0);

        // If demand remains asserted, the unknown extension ends at the
        // configured maximum and enters the same three-second release phase.
        KEY[0] = 1'b0;
        SW[2:0] = 3'b101;
        repeat (2) @(posedge clk);
        KEY[0] = 1'b1;
        repeat (3) @(posedge clk);
        wait_controller_tick;
        wait_controller_tick;
        wait_controller_tick;
        wait_controller_tick;
        check_state(ST_EW_GREEN, 0, 1'b0);
        wait_controller_tick;
        wait_controller_tick;
        wait_controller_tick;
        check_state(ST_EW_GREEN, 3, 1'b0);
        if (dut.traffic_extended) begin
            $display("FAIL: extension exceeded the configured maximum");
            errors = errors + 1;
        end

        // Reproduce the board-level bug: keep EW sensing asserted throughout
        // its extension and verify the following NS green is not shortened.
        wait_controller_tick;
        check_state(ST_EW_GREEN, 2, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 1, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_YELLOW, TEST_YELLOW_SECONDS, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_YELLOW, TEST_YELLOW_SECONDS - 1, 1'b0);
        wait_controller_tick;
        check_state(ST_ALL_RED_1, TEST_ALL_RED_SECONDS, 1'b0);
        wait_controller_tick;
        check_state(ST_NS_GREEN, TEST_GREEN_SECONDS, 1'b0);
        wait_controller_tick;
        check_state(ST_NS_GREEN, TEST_GREEN_SECONDS - 1, 1'b0);
        wait_controller_tick;
        check_state(ST_NS_GREEN, TEST_GREEN_SECONDS - 2, 1'b0);
        wait_controller_tick;
        check_state(ST_NS_GREEN, TEST_GREEN_SECONDS - 3, 1'b0);
        wait_controller_tick;
        check_state(ST_NS_YELLOW, TEST_YELLOW_SECONDS, 1'b0);

        // Opposing-only demand must not shorten the active green. Vehicle
        // sensing is extension-only; this direction still gets four seconds.
        KEY[0] = 1'b0;
        SW[2:0] = 3'b110;
        repeat (2) @(posedge clk);
        KEY[0] = 1'b1;
        repeat (3) @(posedge clk);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 3, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 2, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_GREEN, 1, 1'b0);
        wait_controller_tick;
        check_state(ST_EW_YELLOW, TEST_YELLOW_SECONDS, 1'b0);

        if (errors == 0)
            $display("PASS: extension-only smart mode, release phase, limits, flashing, and pedestrian handling passed");
        else
            $display("FAIL: %0d pedestrian traffic-light checks failed", errors);

        $finish;
    end

endmodule
