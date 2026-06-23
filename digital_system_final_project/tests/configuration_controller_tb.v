`timescale 1ns/1ps

module configuration_controller_tb;

    reg clk;
    reg reset_n;
    reg config_active;
    reg key_select;
    reg key_up;
    reg key_down;
    reg key_back;
    wire [1:0] page;
    wire [2:0] selected_item;
    wire [15:0] display_value;
    wire [15:0] min_red_seconds;
    wire [15:0] green_seconds;
    wire [15:0] yellow_seconds;
    wire [15:0] ped_seconds;
    integer errors;
    integer index;

    configuration_controller dut (
        .clk(clk),
        .reset_n(reset_n),
        .config_active(config_active),
        .key_select(key_select),
        .key_up(key_up),
        .key_down(key_down),
        .key_back(key_back),
        .page(page),
        .selected_item(selected_item),
        .display_value(display_value),
        .min_red_seconds(min_red_seconds),
        .green_seconds(green_seconds),
        .yellow_seconds(yellow_seconds),
        .ped_seconds(ped_seconds)
    );

    always #5 clk = ~clk;

    task pulse_select;
        begin
            key_select = 1'b1; @(posedge clk); #1; key_select = 1'b0;
        end
    endtask

    task pulse_up;
        begin
            key_up = 1'b1; @(posedge clk); #1; key_up = 1'b0;
        end
    endtask

    task pulse_down;
        begin
            key_down = 1'b1; @(posedge clk); #1; key_down = 1'b0;
        end
    endtask

    task pulse_back;
        begin
            key_back = 1'b1; @(posedge clk); #1; key_back = 1'b0;
        end
    endtask

    task expect_value;
        input [15:0] actual;
        input [15:0] expected;
        input [8*32-1:0] label;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s expected %0d, got %0d", label, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset_n = 1'b0;
        config_active = 1'b0;
        key_select = 1'b0;
        key_up = 1'b0;
        key_down = 1'b0;
        key_back = 1'b0;
        errors = 0;

        repeat (2) @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk); #1;
        expect_value(min_red_seconds, 14, "default minimum red");
        expect_value(green_seconds, 10, "default green");
        expect_value(yellow_seconds, 3, "default yellow");
        expect_value(ped_seconds, 5, "default pedestrian");

        config_active = 1'b1;
        pulse_select; // Home -> menu.
        pulse_down;   // GREEN TIME.
        pulse_select; // Edit.
        pulse_up;
        expect_value(display_value, 11, "green edit value");
        pulse_back;   // Cancel must discard 11.
        expect_value(green_seconds, 10, "cancelled green");

        pulse_select;
        pulse_up;
        pulse_select; // Confirm 11.
        expect_value(green_seconds, 11, "confirmed green");

        // Clamp GREEN TIME at its documented upper bound.
        pulse_select;
        for (index = 0; index < 30; index = index + 1)
            pulse_up;
        expect_value(display_value, 30, "green upper clamp");
        pulse_select;
        expect_value(green_seconds, 30, "committed upper clamp");

        // Move to RESTORE DEFAULT and restore every committed register.
        pulse_down; // YELLOW
        pulse_down; // PED
        pulse_down; // RESTORE
        if (selected_item !== 3'd4) begin
            $display("FAIL: menu navigation did not reach RESTORE DEFAULT");
            errors = errors + 1;
        end
        pulse_select;
        expect_value(min_red_seconds, 14, "restored minimum red");
        expect_value(green_seconds, 10, "restored green");
        expect_value(yellow_seconds, 3, "restored yellow");
        expect_value(ped_seconds, 5, "restored pedestrian");

        pulse_back; // Menu -> home.
        if (page !== 2'd0) begin
            $display("FAIL: KEY3 did not return from menu to home");
            errors = errors + 1;
        end

        config_active = 1'b0;
        @(posedge clk); #1;
        if ((page !== 2'd0) || (selected_item !== 3'd0)) begin
            $display("FAIL: leaving settings did not reset UI navigation");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: settings navigation, edit/confirm/cancel, bounds, and restore defaults passed");
        else
            $display("FAIL: %0d configuration-controller checks failed", errors);
        $finish;
    end

endmodule
