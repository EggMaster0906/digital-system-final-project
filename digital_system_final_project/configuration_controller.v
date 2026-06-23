`timescale 1ns/1ps

// Three-level settings menu used while the traffic controller is safely
// stopped. Values are volatile and return to their parameter defaults after
// reset or power-up.
module configuration_controller #(
    parameter [15:0] DEFAULT_MIN_RED_SECONDS = 16'd14,
    parameter [15:0] DEFAULT_GREEN_SECONDS   = 16'd10,
    parameter [15:0] DEFAULT_YELLOW_SECONDS  = 16'd3,
    parameter [15:0] DEFAULT_PED_SECONDS     = 16'd5
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        config_active,
    input  wire        key_select,
    input  wire        key_up,
    input  wire        key_down,
    input  wire        key_back,
    output reg  [1:0]  page,
    output reg  [2:0]  selected_item,
    output reg  [15:0] display_value,
    output reg  [15:0] min_red_seconds,
    output reg  [15:0] green_seconds,
    output reg  [15:0] yellow_seconds,
    output reg  [15:0] ped_seconds
);

    localparam [1:0] PAGE_HOME = 2'd0;
    localparam [1:0] PAGE_MENU = 2'd1;
    localparam [1:0] PAGE_EDIT = 2'd2;

    localparam [2:0] ITEM_MIN_RED = 3'd0;
    localparam [2:0] ITEM_GREEN   = 3'd1;
    localparam [2:0] ITEM_YELLOW  = 3'd2;
    localparam [2:0] ITEM_PED     = 3'd3;
    localparam [2:0] ITEM_RESTORE = 3'd4;

    reg [15:0] edit_value;

    function [15:0] item_value;
        input [2:0] item;
        begin
            case (item)
                ITEM_MIN_RED: item_value = min_red_seconds;
                ITEM_GREEN:   item_value = green_seconds;
                ITEM_YELLOW:  item_value = yellow_seconds;
                ITEM_PED:     item_value = ped_seconds;
                default:      item_value = 16'd0;
            endcase
        end
    endfunction

    function [15:0] item_minimum;
        input [2:0] item;
        begin
            case (item)
                ITEM_MIN_RED: item_minimum = 16'd8;
                ITEM_GREEN:   item_minimum = 16'd5;
                ITEM_YELLOW:  item_minimum = 16'd2;
                ITEM_PED:     item_minimum = 16'd3;
                default:      item_minimum = 16'd0;
            endcase
        end
    endfunction

    function [15:0] item_maximum;
        input [2:0] item;
        begin
            case (item)
                ITEM_MIN_RED: item_maximum = 16'd40;
                ITEM_GREEN:   item_maximum = 16'd30;
                ITEM_YELLOW:  item_maximum = 16'd5;
                ITEM_PED:     item_maximum = 16'd15;
                default:      item_maximum = 16'd0;
            endcase
        end
    endfunction

    always @(*) begin
        if (page == PAGE_EDIT)
            display_value = edit_value;
        else
            display_value = item_value(selected_item);
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            page             <= PAGE_HOME;
            selected_item    <= ITEM_MIN_RED;
            edit_value       <= DEFAULT_MIN_RED_SECONDS;
            min_red_seconds  <= DEFAULT_MIN_RED_SECONDS;
            green_seconds    <= DEFAULT_GREEN_SECONDS;
            yellow_seconds   <= DEFAULT_YELLOW_SECONDS;
            ped_seconds      <= DEFAULT_PED_SECONDS;
        end else if (!config_active) begin
            // Every settings session starts from the documented home page.
            page          <= PAGE_HOME;
            selected_item <= ITEM_MIN_RED;
            edit_value    <= min_red_seconds;
        end else begin
            case (page)
                PAGE_HOME: begin
                    if (key_select)
                        page <= PAGE_MENU;
                end
                PAGE_MENU: begin
                    if (key_back) begin
                        page <= PAGE_HOME;
                    end else if (key_up) begin
                        if (selected_item == ITEM_MIN_RED)
                            selected_item <= ITEM_RESTORE;
                        else
                            selected_item <= selected_item - 1'b1;
                    end else if (key_down) begin
                        if (selected_item == ITEM_RESTORE)
                            selected_item <= ITEM_MIN_RED;
                        else
                            selected_item <= selected_item + 1'b1;
                    end else if (key_select) begin
                        if (selected_item == ITEM_RESTORE) begin
                            min_red_seconds <= DEFAULT_MIN_RED_SECONDS;
                            green_seconds   <= DEFAULT_GREEN_SECONDS;
                            yellow_seconds  <= DEFAULT_YELLOW_SECONDS;
                            ped_seconds     <= DEFAULT_PED_SECONDS;
                        end else begin
                            edit_value <= item_value(selected_item);
                            page       <= PAGE_EDIT;
                        end
                    end
                end
                PAGE_EDIT: begin
                    if (key_back) begin
                        // Discard the working value and keep the committed one.
                        edit_value <= item_value(selected_item);
                        page       <= PAGE_MENU;
                    end else if (key_up) begin
                        if (edit_value < item_minimum(selected_item))
                            edit_value <= item_minimum(selected_item);
                        else if (edit_value < item_maximum(selected_item))
                            edit_value <= edit_value + 1'b1;
                    end else if (key_down) begin
                        if (edit_value > item_maximum(selected_item))
                            edit_value <= item_maximum(selected_item);
                        else if (edit_value > item_minimum(selected_item))
                            edit_value <= edit_value - 1'b1;
                    end else if (key_select) begin
                        case (selected_item)
                            ITEM_MIN_RED: min_red_seconds <= edit_value;
                            ITEM_GREEN:   green_seconds   <= edit_value;
                            ITEM_YELLOW:  yellow_seconds  <= edit_value;
                            ITEM_PED:     ped_seconds     <= edit_value;
                            default: begin end
                        endcase
                        page <= PAGE_MENU;
                    end
                end
                default: page <= PAGE_HOME;
            endcase
        end
    end

endmodule
