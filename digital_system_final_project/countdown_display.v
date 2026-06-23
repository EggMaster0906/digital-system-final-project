`timescale 1ns/1ps

// Calculates the displayed time for both vehicle directions. Red-light
// countdowns include every already-scheduled phase before the next green.
module countdown_display #(
    parameter [15:0] GREEN_SECONDS   = 16'd10,
    parameter [15:0] YELLOW_SECONDS  = 16'd3,
    parameter [15:0] ALL_RED_SECONDS = 16'd1,
    parameter [15:0] PED_SECONDS     = 16'd5
)(
    input  wire [3:0]  state,
    input  wire [15:0] remaining_seconds,
    input  wire        ped_pending,
    input  wire [2:0]  ped_return_state,
    output reg  [6:0]  ew_seconds,
    output reg  [6:0]  ns_seconds,
    output reg         show_dashes
);

    localparam [3:0] ST_EW_GREEN  = 4'd0;
    localparam [3:0] ST_EW_YELLOW = 4'd1;
    localparam [3:0] ST_ALL_RED_1 = 4'd2;
    localparam [3:0] ST_NS_GREEN  = 4'd3;
    localparam [3:0] ST_NS_YELLOW = 4'd4;
    localparam [3:0] ST_ALL_RED_2 = 4'd5;
    localparam [3:0] ST_PED_GO    = 4'd6;
    localparam [3:0] ST_PED_CLEAR = 4'd7;

    reg [31:0] ew_value;
    reg [31:0] ns_value;

    function [6:0] clamp_99;
        input [31:0] value;
        begin
            if (value > 32'd99)
                clamp_99 = 7'd99;
            else
                clamp_99 = value[6:0];
        end
    endfunction

    always @(*) begin
        ew_value    = 32'd0;
        ns_value    = 32'd0;
        show_dashes = 1'b0;

        case (state)
            ST_EW_GREEN: begin
                ew_value = {16'd0, remaining_seconds};
                ns_value = {16'd0, remaining_seconds} +
                           YELLOW_SECONDS + ALL_RED_SECONDS;
                if (ped_pending)
                    ns_value = ns_value + PED_SECONDS + ALL_RED_SECONDS;
            end
            ST_EW_YELLOW: begin
                ew_value = {16'd0, remaining_seconds};
                ns_value = {16'd0, remaining_seconds} + ALL_RED_SECONDS;
                if (ped_pending)
                    ns_value = ns_value + PED_SECONDS + ALL_RED_SECONDS;
            end
            ST_ALL_RED_1: begin
                ns_value = {16'd0, remaining_seconds};
                if (ped_pending)
                    ns_value = ns_value + PED_SECONDS + ALL_RED_SECONDS;
                ew_value = ns_value + GREEN_SECONDS +
                           YELLOW_SECONDS + ALL_RED_SECONDS;
            end
            ST_NS_GREEN: begin
                ns_value = {16'd0, remaining_seconds};
                ew_value = {16'd0, remaining_seconds} +
                           YELLOW_SECONDS + ALL_RED_SECONDS;
                if (ped_pending)
                    ew_value = ew_value + PED_SECONDS + ALL_RED_SECONDS;
            end
            ST_NS_YELLOW: begin
                ns_value = {16'd0, remaining_seconds};
                ew_value = {16'd0, remaining_seconds} + ALL_RED_SECONDS;
                if (ped_pending)
                    ew_value = ew_value + PED_SECONDS + ALL_RED_SECONDS;
            end
            ST_ALL_RED_2: begin
                ew_value = {16'd0, remaining_seconds};
                if (ped_pending)
                    ew_value = ew_value + PED_SECONDS + ALL_RED_SECONDS;
                ns_value = ew_value + GREEN_SECONDS +
                           YELLOW_SECONDS + ALL_RED_SECONDS;
            end
            ST_PED_GO: begin
                if (ped_return_state == ST_EW_GREEN) begin
                    ew_value = {16'd0, remaining_seconds} + ALL_RED_SECONDS;
                    ns_value = ew_value + GREEN_SECONDS +
                               YELLOW_SECONDS + ALL_RED_SECONDS;
                end else begin
                    ns_value = {16'd0, remaining_seconds} + ALL_RED_SECONDS;
                    ew_value = ns_value + GREEN_SECONDS +
                               YELLOW_SECONDS + ALL_RED_SECONDS;
                end
            end
            ST_PED_CLEAR: begin
                if (ped_return_state == ST_EW_GREEN) begin
                    ew_value = {16'd0, remaining_seconds};
                    ns_value = ew_value + GREEN_SECONDS +
                               YELLOW_SECONDS + ALL_RED_SECONDS;
                end else begin
                    ns_value = {16'd0, remaining_seconds};
                    ew_value = ns_value + GREEN_SECONDS +
                               YELLOW_SECONDS + ALL_RED_SECONDS;
                end
            end
            default: begin
                show_dashes = 1'b1;
            end
        endcase

        ew_seconds = clamp_99(ew_value);
        ns_seconds = clamp_99(ns_value);
    end

endmodule
