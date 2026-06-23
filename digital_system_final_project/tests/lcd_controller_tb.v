`timescale 1ns/1ps

module lcd_controller_tb;

    localparam [3:0] ST_EW_GREEN  = 4'd0;
    localparam [3:0] ST_NS_YELLOW = 4'd4;
    localparam [3:0] ST_NIGHT     = 4'd8;
    localparam [3:0] ST_FAULT     = 4'd10;
    localparam [3:0] ST_CONFIG    = 4'd13;

    reg         clk;
    reg         reset_n;
    reg  [3:0]  traffic_state;
    reg  [15:0] remaining_seconds;
    reg         ped_pending;
    reg  [1:0]  config_page;
    reg  [2:0]  config_item;
    reg  [15:0] config_value;
    reg  [15:0] config_min_red;
    reg  [15:0] config_green;
    reg  [15:0] config_yellow;
    reg  [15:0] config_ped;
    wire        LCD_ON;
    wire        LCD_BLON;
    wire [7:0]  LCD_DATA;
    wire        LCD_RS;
    wire        LCD_RW;
    wire        LCD_EN;

    reg  [7:0] captured_data [0:511];
    reg        captured_rs   [0:511];
    reg  [7:0] expected_line1[0:15];
    reg  [7:0] expected_line2[0:15];
    integer    write_count;
    integer    errors;
    integer    timeout_count;
    integer    index;

    lcd_controller #(
        .CLOCK_HZ   (50_000),
        .STEP_CYCLES(1)
    ) dut (
        .clk               (clk),
        .reset_n           (reset_n),
        .traffic_state     (traffic_state),
        .remaining_seconds (remaining_seconds),
        .ped_pending       (ped_pending),
        .config_page       (config_page),
        .config_item       (config_item),
        .config_value      (config_value),
        .config_min_red    (config_min_red),
        .config_green      (config_green),
        .config_yellow     (config_yellow),
        .config_ped        (config_ped),
        .LCD_ON            (LCD_ON),
        .LCD_BLON          (LCD_BLON),
        .LCD_DATA          (LCD_DATA),
        .LCD_RS            (LCD_RS),
        .LCD_RW            (LCD_RW),
        .LCD_EN            (LCD_EN)
    );

    always #5 clk = ~clk;

    always @(negedge LCD_EN) begin
        if (reset_n && (write_count < 512)) begin
            captured_data[write_count] = LCD_DATA;
            captured_rs[write_count]   = LCD_RS;
            write_count = write_count + 1;
        end
    end

    task wait_for_writes;
        input integer target;
        begin
            timeout_count = 0;
            while ((write_count < target) && (timeout_count < 10000)) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            if (write_count < target) begin
                $display("FAIL: LCD timed out waiting for %0d writes", target);
                errors = errors + 1;
            end
        end
    endtask

    task check_write;
        input integer test_index;
        input         expected_rs;
        input [7:0]   expected_data;
        begin
            if ((captured_rs[test_index] !== expected_rs) ||
                (captured_data[test_index] !== expected_data)) begin
                $display("FAIL: write %0d expected RS=%0b data=%02h, got RS=%0b data=%02h",
                         test_index, expected_rs, expected_data,
                         captured_rs[test_index], captured_data[test_index]);
                errors = errors + 1;
            end
        end
    endtask

    task load_ew_green_lines;
        begin
            expected_line1[0]  = "E"; expected_line1[1]  = "W";
            expected_line1[2]  = ":"; expected_line1[3]  = "G";
            expected_line1[4]  = "R"; expected_line1[5]  = "E";
            expected_line1[6]  = "E"; expected_line1[7]  = "N";
            expected_line1[8]  = " "; expected_line1[9]  = " ";
            expected_line1[10] = "T"; expected_line1[11] = ":";
            expected_line1[12] = "0"; expected_line1[13] = "8";
            expected_line1[14] = " "; expected_line1[15] = " ";

            expected_line2[0]  = "N"; expected_line2[1]  = "S";
            expected_line2[2]  = ":"; expected_line2[3]  = "R";
            expected_line2[4]  = "E"; expected_line2[5]  = "D";
            expected_line2[6]  = " "; expected_line2[7]  = " ";
            expected_line2[8]  = " "; expected_line2[9]  = " ";
            expected_line2[10] = "P"; expected_line2[11] = ":";
            expected_line2[12] = "S"; expected_line2[13] = "T";
            expected_line2[14] = "O"; expected_line2[15] = "P";
        end
    endtask

    task load_ns_yellow_lines;
        begin
            expected_line1[0]  = "E"; expected_line1[1]  = "W";
            expected_line1[2]  = ":"; expected_line1[3]  = "R";
            expected_line1[4]  = "E"; expected_line1[5]  = "D";
            expected_line1[6]  = " "; expected_line1[7]  = " ";
            expected_line1[8]  = " "; expected_line1[9]  = " ";
            expected_line1[10] = "T"; expected_line1[11] = ":";
            expected_line1[12] = "0"; expected_line1[13] = "3";
            expected_line1[14] = " "; expected_line1[15] = " ";

            expected_line2[0]  = "N"; expected_line2[1]  = "S";
            expected_line2[2]  = ":"; expected_line2[3]  = "Y";
            expected_line2[4]  = "E"; expected_line2[5]  = "L";
            expected_line2[6]  = "L"; expected_line2[7]  = "O";
            expected_line2[8]  = "W"; expected_line2[9]  = " ";
            expected_line2[10] = "P"; expected_line2[11] = ":";
            expected_line2[12] = "W"; expected_line2[13] = "A";
            expected_line2[14] = "I"; expected_line2[15] = "T";
        end
    endtask

    task load_night_lines;
        begin
            expected_line1[0]  = "N"; expected_line1[1]  = "I";
            expected_line1[2]  = "G"; expected_line1[3]  = "H";
            expected_line1[4]  = "T"; expected_line1[5]  = " ";
            expected_line1[6]  = "M"; expected_line1[7]  = "O";
            expected_line1[8]  = "D"; expected_line1[9]  = "E";
            expected_line1[10] = " "; expected_line1[11] = " ";
            expected_line1[12] = " "; expected_line1[13] = " ";
            expected_line1[14] = " "; expected_line1[15] = " ";

            expected_line2[0]  = "E"; expected_line2[1]  = "W";
            expected_line2[2]  = ":"; expected_line2[3]  = "Y";
            expected_line2[4]  = "E"; expected_line2[5]  = "L";
            expected_line2[6]  = "L"; expected_line2[7]  = "O";
            expected_line2[8]  = "W"; expected_line2[9]  = " ";
            expected_line2[10] = "N"; expected_line2[11] = "S";
            expected_line2[12] = ":"; expected_line2[13] = "R";
            expected_line2[14] = "E"; expected_line2[15] = "D";
        end
    endtask

    task load_fault_lines;
        begin
            expected_line1[0]  = "S"; expected_line1[1]  = "Y";
            expected_line1[2]  = "S"; expected_line1[3]  = "T";
            expected_line1[4]  = "E"; expected_line1[5]  = "M";
            expected_line1[6]  = " "; expected_line1[7]  = "F";
            expected_line1[8]  = "A"; expected_line1[9]  = "U";
            expected_line1[10] = "L"; expected_line1[11] = "T";
            expected_line1[12] = " "; expected_line1[13] = " ";
            expected_line1[14] = " "; expected_line1[15] = " ";

            expected_line2[0]  = "F"; expected_line2[1]  = "L";
            expected_line2[2]  = "A"; expected_line2[3]  = "S";
            expected_line2[4]  = "H"; expected_line2[5]  = "I";
            expected_line2[6]  = "N"; expected_line2[7]  = "G";
            expected_line2[8]  = " "; expected_line2[9]  = "R";
            expected_line2[10] = "E"; expected_line2[11] = "D";
            expected_line2[12] = " "; expected_line2[13] = " ";
            expected_line2[14] = " "; expected_line2[15] = " ";
        end
    endtask

    task load_config_home_lines;
        begin
            expected_line1[0]  = "S"; expected_line1[1]  = "Y";
            expected_line1[2]  = "S"; expected_line1[3]  = "T";
            expected_line1[4]  = "E"; expected_line1[5]  = "M";
            expected_line1[6]  = " "; expected_line1[7]  = "S";
            expected_line1[8]  = "E"; expected_line1[9]  = "T";
            expected_line1[10] = "T"; expected_line1[11] = "I";
            expected_line1[12] = "N"; expected_line1[13] = "G";
            expected_line1[14] = "S"; expected_line1[15] = " ";

            expected_line2[0]  = "K"; expected_line2[1]  = "E";
            expected_line2[2]  = "Y"; expected_line2[3]  = "0";
            expected_line2[4]  = ":"; expected_line2[5]  = "E";
            expected_line2[6]  = "N"; expected_line2[7]  = "T";
            expected_line2[8]  = "E"; expected_line2[9]  = "R";
            expected_line2[10] = " "; expected_line2[11] = " ";
            expected_line2[12] = " "; expected_line2[13] = " ";
            expected_line2[14] = " "; expected_line2[15] = " ";
        end
    endtask

    task load_config_menu_lines;
        begin
            expected_line1[0]  = ">"; expected_line1[1]  = "G";
            expected_line1[2]  = "R"; expected_line1[3]  = "E";
            expected_line1[4]  = "E"; expected_line1[5]  = "N";
            expected_line1[6]  = " "; expected_line1[7]  = "T";
            expected_line1[8]  = "I"; expected_line1[9]  = "M";
            expected_line1[10] = "E"; expected_line1[11] = " ";
            expected_line1[12] = " "; expected_line1[13] = "1";
            expected_line1[14] = "0"; expected_line1[15] = "s";

            expected_line2[0]  = " "; expected_line2[1]  = "Y";
            expected_line2[2]  = "E"; expected_line2[3]  = "L";
            expected_line2[4]  = "L"; expected_line2[5]  = "O";
            expected_line2[6]  = "W"; expected_line2[7]  = " ";
            expected_line2[8]  = "T"; expected_line2[9]  = "I";
            expected_line2[10] = "M"; expected_line2[11] = "E";
            expected_line2[12] = " "; expected_line2[13] = "0";
            expected_line2[14] = "3"; expected_line2[15] = "s";
        end
    endtask

    task load_config_edit_lines;
        begin
            expected_line1[0]  = "E"; expected_line1[1]  = "D";
            expected_line1[2]  = "I"; expected_line1[3]  = "T";
            expected_line1[4]  = " "; expected_line1[5]  = "G";
            expected_line1[6]  = "R"; expected_line1[7]  = "E";
            expected_line1[8]  = "E"; expected_line1[9]  = "N";
            expected_line1[10] = " "; expected_line1[11] = "T";
            expected_line1[12] = "I"; expected_line1[13] = "M";
            expected_line1[14] = "E"; expected_line1[15] = " ";

            expected_line2[0]  = "1"; expected_line2[1]  = "2";
            expected_line2[2]  = "s"; expected_line2[3]  = " ";
            expected_line2[4]  = "R"; expected_line2[5]  = "A";
            expected_line2[6]  = "N"; expected_line2[7]  = "G";
            expected_line2[8]  = "E"; expected_line2[9]  = " ";
            expected_line2[10] = "0"; expected_line2[11] = "5";
            expected_line2[12] = "-"; expected_line2[13] = "3";
            expected_line2[14] = "0"; expected_line2[15] = " ";
        end
    endtask

    initial begin
        clk               = 1'b0;
        reset_n           = 1'b0;
        traffic_state     = ST_EW_GREEN;
        remaining_seconds = 16'd8;
        ped_pending       = 1'b0;
        config_page       = 2'd0;
        config_item       = 3'd0;
        config_value      = 16'd14;
        config_min_red    = 16'd14;
        config_green      = 16'd10;
        config_yellow     = 16'd3;
        config_ped        = 16'd5;
        write_count       = 0;
        errors            = 0;

        repeat (2) @(posedge clk);
        reset_n = 1'b1;

        wait_for_writes(41);

        if ((LCD_ON !== 1'b1) || (LCD_BLON !== 1'b1) ||
            (LCD_RW !== 1'b0)) begin
            $display("FAIL: LCD power, backlight, or write-only control is incorrect");
            errors = errors + 1;
        end

        check_write(0, 1'b0, 8'h38);
        check_write(1, 1'b0, 8'h38);
        check_write(2, 1'b0, 8'h38);
        check_write(3, 1'b0, 8'h08);
        check_write(4, 1'b0, 8'h01);
        check_write(5, 1'b0, 8'h06);
        check_write(6, 1'b0, 8'h0C);
        check_write(7, 1'b0, 8'h80);
        check_write(24, 1'b0, 8'hC0);

        load_ew_green_lines;
        for (index = 0; index < 16; index = index + 1) begin
            check_write(8 + index, 1'b1, expected_line1[index]);
            check_write(25 + index, 1'b1, expected_line2[index]);
        end

        // Verify that the next refresh reflects a changed traffic state,
        // remaining time, and pending pedestrian request without re-clearing.
        traffic_state     = ST_NS_YELLOW;
        remaining_seconds = 16'd3;
        ped_pending       = 1'b1;
        // The controller snapshots a frame when it writes 0x80.  Waiting one
        // additional refresh avoids a testbench race at the prior frame edge.
        wait_for_writes(109);
        check_write(75, 1'b0, 8'h80);
        check_write(92, 1'b0, 8'hC0);

        load_ns_yellow_lines;
        for (index = 0; index < 16; index = index + 1) begin
            check_write(76 + index, 1'b1, expected_line1[index]);
            check_write(93 + index, 1'b1, expected_line2[index]);
        end

        // Night mode replaces the normal countdown frame with an explicit
        // mode label and the two flashing signal meanings.
        traffic_state = ST_NIGHT;
        wait_for_writes(177);
        check_write(143, 1'b0, 8'h80);
        check_write(160, 1'b0, 8'hC0);

        load_night_lines;
        for (index = 0; index < 16; index = index + 1) begin
            check_write(144 + index, 1'b1, expected_line1[index]);
            check_write(161 + index, 1'b1, expected_line2[index]);
        end

        // Fault mode replaces every normal field with an unambiguous alarm.
        traffic_state = ST_FAULT;
        wait_for_writes(245);
        check_write(211, 1'b0, 8'h80);
        check_write(228, 1'b0, 8'hC0);

        load_fault_lines;
        for (index = 0; index < 16; index = index + 1) begin
            check_write(212 + index, 1'b1, expected_line1[index]);
            check_write(229 + index, 1'b1, expected_line2[index]);
        end

        // Settings home, scrolling menu, and editor each occupy a complete
        // stable LCD frame with the documented labels, values, and range.
        traffic_state = ST_CONFIG;
        config_page = 2'd0;
        wait_for_writes(313);
        load_config_home_lines;
        for (index = 0; index < 16; index = index + 1) begin
            check_write(280 + index, 1'b1, expected_line1[index]);
            check_write(297 + index, 1'b1, expected_line2[index]);
        end

        config_page = 2'd1;
        config_item = 3'd1;
        wait_for_writes(381);
        load_config_menu_lines;
        for (index = 0; index < 16; index = index + 1) begin
            check_write(348 + index, 1'b1, expected_line1[index]);
            check_write(365 + index, 1'b1, expected_line2[index]);
        end

        config_page = 2'd2;
        config_value = 16'd12;
        wait_for_writes(449);
        load_config_edit_lines;
        for (index = 0; index < 16; index = index + 1) begin
            check_write(416 + index, 1'b1, expected_line1[index]);
            check_write(433 + index, 1'b1, expected_line2[index]);
        end

        if (errors == 0)
            $display("PASS: LCD initialization, operating modes, and all settings pages passed");
        else
            $display("FAIL: %0d LCD controller checks failed", errors);

        $finish;
    end

endmodule
