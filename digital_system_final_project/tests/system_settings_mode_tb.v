`timescale 1ns/1ps

module system_settings_mode_tb;

    localparam [3:0] ST_EW_GREEN     = 4'd0;
    localparam [3:0] ST_EW_YELLOW    = 4'd1;
    localparam [3:0] ST_NS_GREEN     = 4'd3;
    localparam [3:0] ST_NS_YELLOW    = 4'd4;
    localparam [3:0] ST_ALL_RED_2    = 4'd5;
    localparam [3:0] ST_NIGHT        = 4'd8;
    localparam [3:0] ST_NIGHT_CLEAR  = 4'd9;
    localparam [3:0] ST_FAULT        = 4'd10;
    localparam [3:0] ST_FAULT_CLEAR  = 4'd11;
    localparam [3:0] ST_CONFIG_ENTER = 4'd12;
    localparam [3:0] ST_CONFIG       = 4'd13;
    localparam [3:0] ST_CONFIG_EXIT  = 4'd14;

    reg clk;
    reg [3:0] KEY;
    reg [17:0] SW;
    wire [17:0] LEDR;
    wire [8:0] LEDG;
    wire [6:0] HEX4;
    wire [6:0] HEX5;
    wire [6:0] HEX6;
    wire [6:0] HEX7;
    integer errors;
    integer timeout_count;

    digital_system_final_project #(
        .CLOCK_HZ(8),
        .BUTTON_DEBOUNCE_CYCLES(1),
        .MIN_RED_SECONDS(14),
        .GREEN_SECONDS(6),
        .MIN_GREEN_SECONDS(2),
        .YELLOW_SECONDS(2),
        .ALL_RED_SECONDS(2),
        .PED_SECONDS(3),
        .FLASH_SECONDS(1)
    ) dut (
        .CLOCK_50(clk), .KEY(KEY), .SW(SW),
        .LEDR(LEDR), .LEDG(LEDG),
        .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7)
    );

    always #5 clk = ~clk;

    task wait_for_state;
        input [3:0] expected_state;
        begin
            timeout_count = 0;
            while ((dut.traffic_state !== expected_state) &&
                   (timeout_count < 200)) begin
                @(posedge clk); #1;
                timeout_count = timeout_count + 1;
            end
            if (dut.traffic_state !== expected_state) begin
                $display("FAIL: timed out waiting for state %0d", expected_state);
                errors = errors + 1;
            end
        end
    endtask

    task wait_tick;
        begin
            @(posedge dut.tick_1s);
            @(posedge clk); #1;
        end
    endtask

    task press_key;
        input integer key_index;
        begin
            KEY[key_index] = 1'b0;
            repeat (5) @(posedge clk);
            #1 KEY[key_index] = 1'b1;
            repeat (5) @(posedge clk);
            #1;
        end
    endtask

    task check_all_red_dashed;
        begin
            if ({LEDR[1:0], LEDG[1:0]} !== 4'b11_00) begin
                $display("FAIL: settings-related state is not vehicle all-red");
                errors = errors + 1;
            end
            if ({HEX5, HEX4, HEX7, HEX6} !== {4{7'b0111111}}) begin
                $display("FAIL: settings-related state does not show dashed countdowns");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        KEY = 4'b1110;
        SW = 18'd0;
        errors = 0;

        repeat (2) @(posedge clk);
        #1 KEY[0] = 1'b1;
        wait_for_state(ST_EW_GREEN);

        // A request from green must perform yellow and then a full all-red
        // entry interval before exposing the menu.
        SW[17] = 1'b1;
        wait_for_state(ST_EW_YELLOW);
        wait_tick;
        wait_tick;
        wait_for_state(ST_CONFIG_ENTER);
        check_all_red_dashed;
        wait_tick;
        wait_tick;
        wait_for_state(ST_CONFIG);
        check_all_red_dashed;

        // KEY0 is SELECT here, not reset. Change GREEN TIME from 06 to 07.
        press_key(0);
        press_key(2);
        press_key(0);
        press_key(1);
        press_key(0);
        if (dut.configured_green_seconds !== 16'd7) begin
            $display("FAIL: confirmed GREEN TIME was not stored");
            errors = errors + 1;
        end

        // Fault must immediately preempt settings. With SW17 still active,
        // clearing it must complete fault clearance and re-enter settings.
        SW[4] = 1'b1;
        wait_for_state(ST_FAULT);
        SW[4] = 1'b0;
        wait_for_state(ST_FAULT_CLEAR);
        wait_tick;
        wait_tick;
        wait_for_state(ST_CONFIG_ENTER);
        wait_tick;
        wait_tick;
        wait_for_state(ST_CONFIG);
        if (dut.configured_green_seconds !== 16'd7) begin
            $display("FAIL: settings were lost across fault preemption");
            errors = errors + 1;
        end

        // Settings outrank a simultaneous night request. Releasing SW17 still
        // inserts a full all-red exit interval before night mode may start.
        SW[3] = 1'b1;
        repeat (5) @(posedge clk);
        #1;
        if (dut.traffic_state !== ST_CONFIG) begin
            $display("FAIL: night mode preempted the higher-priority settings mode");
            errors = errors + 1;
        end
        SW[17] = 1'b0;
        wait_for_state(ST_CONFIG_EXIT);
        check_all_red_dashed;
        wait_tick;
        if (dut.traffic_state !== ST_CONFIG_EXIT) begin
            $display("FAIL: settings exit all-red interval ended too early");
            errors = errors + 1;
        end
        wait_tick;
        wait_for_state(ST_NIGHT);
        SW[3] = 1'b0;
        wait_for_state(ST_NIGHT_CLEAR);
        wait_tick;
        wait_tick;
        wait_for_state(ST_EW_GREEN);
        if (dut.remaining_seconds !== 16'd7) begin
            $display("FAIL: confirmed GREEN TIME was not applied after exit");
            errors = errors + 1;
        end

        // After NS receives green, EW must remain red for at least 14 seconds.
        // The ordinary 7+2+2 sequence is too short, so ST_ALL_RED_2 extends.
        repeat (7) wait_tick;
        if (dut.traffic_state !== ST_EW_YELLOW)
            errors = errors + 1;
        repeat (2) wait_tick;
        wait_for_state(ST_NS_GREEN);
        repeat (7) wait_tick;
        if (dut.traffic_state !== ST_NS_YELLOW)
            errors = errors + 1;
        repeat (2) wait_tick;
        wait_for_state(ST_ALL_RED_2);
        repeat (2) wait_tick;
        if ((dut.traffic_state !== ST_ALL_RED_2) ||
            (dut.remaining_seconds == 16'd0)) begin
            $display("FAIL: minimum-red setting did not extend all-red hold");
            errors = errors + 1;
        end
        wait_for_state(ST_EW_GREEN);

        if (errors == 0)
            $display("PASS: safe settings entry/exit, key roles, fault priority, value application, and minimum red passed");
        else
            $display("FAIL: %0d system-settings integration checks failed", errors);
        $finish;
    end

endmodule
