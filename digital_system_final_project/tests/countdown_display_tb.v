`timescale 1ns/1ps

module countdown_display_tb;

    localparam [3:0] ST_EW_GREEN  = 4'd0;
    localparam [3:0] ST_EW_YELLOW = 4'd1;
    localparam [3:0] ST_ALL_RED_1 = 4'd2;
    localparam [3:0] ST_NS_GREEN  = 4'd3;
    localparam [3:0] ST_NS_YELLOW = 4'd4;
    localparam [3:0] ST_ALL_RED_2 = 4'd5;
    localparam [3:0] ST_PED_GO    = 4'd6;
    localparam [3:0] ST_PED_CLEAR = 4'd7;
    localparam [3:0] ST_NIGHT     = 4'd8;

    reg  [3:0]  state;
    reg  [15:0] remaining_seconds;
    reg         ped_pending;
    reg  [2:0]  ped_return_state;
    wire [6:0]  ew_seconds;
    wire [6:0]  ns_seconds;
    wire        show_dashes;
    wire [6:0]  ew_tens_segments;
    wire [6:0]  ew_ones_segments;
    wire [6:0]  ns_tens_segments;
    wire [6:0]  ns_ones_segments;
    wire [3:0]  ew_tens = show_dashes ? 4'd10 : ew_seconds / 10;
    wire [3:0]  ew_ones = show_dashes ? 4'd10 : ew_seconds % 10;
    wire [3:0]  ns_tens = show_dashes ? 4'd10 : ns_seconds / 10;
    wire [3:0]  ns_ones = show_dashes ? 4'd10 : ns_seconds % 10;
    integer     errors;

    countdown_display dut (
        .state             (state),
        .remaining_seconds (remaining_seconds),
        .ped_pending       (ped_pending),
        .ped_return_state  (ped_return_state),
        .ew_seconds        (ew_seconds),
        .ns_seconds        (ns_seconds),
        .show_dashes       (show_dashes)
    );

    seven_seg_decoder ew_tens_decoder (
        .value(ew_tens), .segments(ew_tens_segments));
    seven_seg_decoder ew_ones_decoder (
        .value(ew_ones), .segments(ew_ones_segments));
    seven_seg_decoder ns_tens_decoder (
        .value(ns_tens), .segments(ns_tens_segments));
    seven_seg_decoder ns_ones_decoder (
        .value(ns_ones), .segments(ns_ones_segments));

    function [6:0] expected_segments;
        input [3:0] value;
        begin
            case (value)
                4'd0:  expected_segments = 7'b1000000;
                4'd1:  expected_segments = 7'b1111001;
                4'd2:  expected_segments = 7'b0100100;
                4'd3:  expected_segments = 7'b0110000;
                4'd4:  expected_segments = 7'b0011001;
                4'd5:  expected_segments = 7'b0010010;
                4'd6:  expected_segments = 7'b0000010;
                4'd7:  expected_segments = 7'b1111000;
                4'd8:  expected_segments = 7'b0000000;
                4'd9:  expected_segments = 7'b0010000;
                4'd10: expected_segments = 7'b0111111;
                default: expected_segments = 7'b1111111;
            endcase
        end
    endfunction

    task check_countdown;
        input [3:0]  test_state;
        input [15:0] test_remaining;
        input        test_pending;
        input [2:0]  test_return_state;
        input [6:0]  expected_ew;
        input [6:0]  expected_ns;
        input        expected_dashes;
        reg   [3:0]  expected_ew_tens;
        reg   [3:0]  expected_ew_ones;
        reg   [3:0]  expected_ns_tens;
        reg   [3:0]  expected_ns_ones;
        begin
            state             = test_state;
            remaining_seconds = test_remaining;
            ped_pending       = test_pending;
            ped_return_state  = test_return_state;
            #1;

            if ((ew_seconds !== expected_ew) ||
                (ns_seconds !== expected_ns) ||
                (show_dashes !== expected_dashes)) begin
                $display("FAIL: state %0d rem %0d expected EW=%0d NS=%0d dash=%0b, got EW=%0d NS=%0d dash=%0b",
                         test_state, test_remaining, expected_ew, expected_ns,
                         expected_dashes, ew_seconds, ns_seconds, show_dashes);
                errors = errors + 1;
            end

            if (expected_dashes) begin
                expected_ew_tens = 4'd10;
                expected_ew_ones = 4'd10;
                expected_ns_tens = 4'd10;
                expected_ns_ones = 4'd10;
            end else begin
                expected_ew_tens = expected_ew / 10;
                expected_ew_ones = expected_ew % 10;
                expected_ns_tens = expected_ns / 10;
                expected_ns_ones = expected_ns % 10;
            end

            if ((ew_tens_segments !== expected_segments(expected_ew_tens)) ||
                (ew_ones_segments !== expected_segments(expected_ew_ones)) ||
                (ns_tens_segments !== expected_segments(expected_ns_tens)) ||
                (ns_ones_segments !== expected_segments(expected_ns_ones))) begin
                $display("FAIL: active-low segment encoding mismatch for state %0d", test_state);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        errors = 0;

        check_countdown(ST_EW_GREEN,  10, 1'b0, ST_NS_GREEN, 10, 14, 1'b0);
        check_countdown(ST_EW_GREEN,   5, 1'b1, ST_NS_GREEN,  5, 15, 1'b0);
        check_countdown(ST_EW_YELLOW,  3, 1'b1, ST_NS_GREEN,  3, 10, 1'b0);
        check_countdown(ST_ALL_RED_1,  1, 1'b1, ST_NS_GREEN, 21,  7, 1'b0);
        check_countdown(ST_NS_GREEN,  10, 1'b0, ST_EW_GREEN, 14, 10, 1'b0);
        check_countdown(ST_NS_YELLOW,  3, 1'b1, ST_EW_GREEN, 10,  3, 1'b0);
        check_countdown(ST_ALL_RED_2,  1, 1'b0, ST_EW_GREEN,  1, 15, 1'b0);
        check_countdown(ST_PED_GO,     5, 1'b1, ST_NS_GREEN, 20,  6, 1'b0);
        check_countdown(ST_PED_CLEAR,  1, 1'b0, ST_NS_GREEN, 15,  1, 1'b0);
        check_countdown(ST_PED_GO,     5, 1'b1, ST_EW_GREEN,  6, 20, 1'b0);
        check_countdown(ST_PED_CLEAR,  1, 1'b0, ST_EW_GREEN,  1, 15, 1'b0);

        // Values above the display range must saturate instead of wrapping.
        check_countdown(ST_EW_GREEN, 120, 1'b0, ST_NS_GREEN, 99, 99, 1'b0);

        // Unsupported future modes use two minus signs for each direction.
        check_countdown(ST_NIGHT, 0, 1'b0, ST_EW_GREEN, 0, 0, 1'b1);

        if (errors == 0)
            $display("PASS: dual countdown arithmetic, pedestrian phases, saturation and active-low segment encoding passed");
        else
            $display("FAIL: %0d countdown display checks failed", errors);

        $finish;
    end

endmodule
