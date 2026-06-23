`timescale 1ns/1ps

module night_mode_tb;

    localparam integer TEST_CLOCK_HZ       = 8;
    localparam integer TEST_GREEN_SECONDS  = 4;
    localparam integer TEST_ALL_RED_SECONDS = 2;

    localparam [3:0] ST_EW_GREEN    = 4'd0;
    localparam [3:0] ST_NIGHT       = 4'd8;
    localparam [3:0] ST_NIGHT_CLEAR = 4'd9;

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
        .CLOCK_HZ             (TEST_CLOCK_HZ),
        .BUTTON_DEBOUNCE_CYCLES(1),
        .GREEN_SECONDS        (TEST_GREEN_SECONDS),
        .MIN_GREEN_SECONDS    (2),
        .YELLOW_SECONDS       (2),
        .ALL_RED_SECONDS      (TEST_ALL_RED_SECONDS),
        .PED_SECONDS          (3),
        .FLASH_SECONDS        (1)
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
                   (timeout_count < 20)) begin
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

    task check_vehicle_lights;
        input [5:0] expected_lights;
        begin
            if ({LEDR[2:0], LEDG[2:0]} !== expected_lights) begin
                $display("FAIL: expected vehicle/pedestrian lights %06b, got %06b at time %0t",
                         expected_lights, {LEDR[2:0], LEDG[2:0]}, $time);
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

        // SW[3] is synchronized before it can preempt the normal FSM.
        SW[3] = 1'b1;
        wait_for_state(ST_NIGHT);
        check_vehicle_lights(6'b111_001); // EW yellow, NS red, pedestrian STOP.

        if ({HEX5, HEX4, HEX7, HEX6} !== {4{7'b0111111}}) begin
            $display("FAIL: night mode does not show -- for both countdowns");
            errors = errors + 1;
        end

        // With a one-second flash parameter, every tick toggles the lamps.
        wait_controller_tick;
        if (dut.traffic_state !== ST_NIGHT)
            errors = errors + 1;
        check_vehicle_lights(6'b100_000);

        wait_controller_tick;
        if (dut.traffic_state !== ST_NIGHT)
            errors = errors + 1;
        check_vehicle_lights(6'b111_001);

        // The switch release must enter an all-red clearance state before any
        // normal vehicle green can return.
        SW[3] = 1'b0;
        wait_for_state(ST_NIGHT_CLEAR);
        check_vehicle_lights(6'b111_000);
        if (dut.remaining_seconds !== TEST_ALL_RED_SECONDS) begin
            $display("FAIL: night-mode exit did not start a full all-red interval");
            errors = errors + 1;
        end
        if ({HEX5, HEX4, HEX7, HEX6} !== {4{7'b0111111}}) begin
            $display("FAIL: night-mode clearance does not keep countdowns dashed");
            errors = errors + 1;
        end

        wait_controller_tick;
        if ((dut.traffic_state !== ST_NIGHT_CLEAR) ||
            (dut.remaining_seconds !== TEST_ALL_RED_SECONDS - 1)) begin
            $display("FAIL: all-red clearance duration is incorrect");
            errors = errors + 1;
        end
        check_vehicle_lights(6'b111_000);

        wait_controller_tick;
        if ((dut.traffic_state !== ST_EW_GREEN) ||
            (dut.remaining_seconds !== TEST_GREEN_SECONDS)) begin
            $display("FAIL: normal cycle did not restart from a full EW green phase");
            errors = errors + 1;
        end
        check_vehicle_lights(6'b110_001);

        if (errors == 0)
            $display("PASS: synchronized night mode, flashing lamps, dashed countdowns, and all-red exit passed");
        else
            $display("FAIL: %0d night-mode checks failed", errors);

        $finish;
    end

endmodule
