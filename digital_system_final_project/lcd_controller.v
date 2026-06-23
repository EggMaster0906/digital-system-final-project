`timescale 1ns/1ps

// Write-only controller for the DE2-115 16x2 character LCD.  The interface
// follows the board document's 8-bit timing: RS/data are established before
// E rises, held while E is high, and retained after E falls.
module lcd_controller #(
    parameter integer CLOCK_HZ = 50_000_000,
    parameter integer STEP_CYCLES = (CLOCK_HZ + 49_999) / 50_000
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire [2:0]  traffic_state,
    input  wire [15:0] remaining_seconds,
    input  wire        ped_pending,
    input  wire        traffic_extended,
    input  wire        blink_visible,
    output wire        LCD_ON,
    output wire        LCD_BLON,
    output reg  [7:0]  LCD_DATA,
    output reg         LCD_RS,
    output wire        LCD_RW,
    output reg         LCD_EN
);

    localparam [2:0] ST_EW_GREEN  = 3'd0;
    localparam [2:0] ST_EW_YELLOW = 3'd1;
    localparam [2:0] ST_ALL_RED_1 = 3'd2;
    localparam [2:0] ST_NS_GREEN  = 3'd3;
    localparam [2:0] ST_NS_YELLOW = 3'd4;
    localparam [2:0] ST_ALL_RED_2 = 3'd5;
    localparam [2:0] ST_PED_GO    = 3'd6;

    localparam [3:0] OP_FUNCTION_1  = 4'd0;
    localparam [3:0] OP_FUNCTION_2  = 4'd1;
    localparam [3:0] OP_FUNCTION_3  = 4'd2;
    localparam [3:0] OP_DISPLAY_OFF = 4'd3;
    localparam [3:0] OP_CLEAR       = 4'd4;
    localparam [3:0] OP_ENTRY_MODE  = 4'd5;
    localparam [3:0] OP_DISPLAY_ON  = 4'd6;
    localparam [3:0] OP_LINE1_ADDR  = 4'd7;
    localparam [3:0] OP_LINE1_DATA  = 4'd8;
    localparam [3:0] OP_LINE2_ADDR  = 4'd9;
    localparam [3:0] OP_LINE2_DATA  = 4'd10;

    // One interface step is approximately 20 us.  Three steps form a write
    // cycle, comfortably exceeding the document's 1 us cycle / 450 ns E-high
    // minima and the controller's normal 40 us instruction execution time.
    localparam integer SAFE_STEP_CYCLES = (STEP_CYCLES < 1) ? 1 : STEP_CYCLES;
    localparam [15:0] POWER_WAIT_STEPS   = 16'd1000; // 20 ms
    localparam [15:0] FIRST_WAIT_STEPS   = 16'd250;  // 5 ms
    localparam [15:0] SHORT_WAIT_STEPS   = 16'd10;   // 200 us
    localparam [15:0] CLEAR_WAIT_STEPS   = 16'd100;  // 2 ms

    reg [31:0] step_count;
    reg [15:0] wait_steps;
    reg [3:0]  operation;
    reg [1:0]  write_phase;
    reg [4:0]  column;
    reg [2:0]  frame_state;
    reg [3:0]  frame_tens;
    reg [3:0]  frame_ones;
    reg        frame_ped_pending;
    reg        frame_traffic_extended;
    reg        frame_blink_visible;

    wire [6:0] shown_seconds =
        (remaining_seconds > 16'd99) ? 7'd99 : remaining_seconds[6:0];
    wire [6:0] shown_tens_value = shown_seconds / 7'd10;
    wire [6:0] shown_ones_value = shown_seconds % 7'd10;
    wire [3:0] shown_tens = shown_tens_value[3:0];
    wire [3:0] shown_ones = shown_ones_value[3:0];

    assign LCD_ON   = 1'b1;
    assign LCD_BLON = 1'b1;
    assign LCD_RW   = 1'b0;

    function [7:0] signal_char;
        input [1:0] signal_kind;
        input [2:0] position;
        begin
            case (signal_kind)
                2'd0: begin // RED, padded to six characters.
                    case (position)
                        3'd0: signal_char = "R";
                        3'd1: signal_char = "E";
                        3'd2: signal_char = "D";
                        default: signal_char = " ";
                    endcase
                end
                2'd1: begin // GREEN, padded to six characters.
                    case (position)
                        3'd0: signal_char = "G";
                        3'd1: signal_char = "R";
                        3'd2: signal_char = "E";
                        3'd3: signal_char = "E";
                        3'd4: signal_char = "N";
                        default: signal_char = " ";
                    endcase
                end
                default: begin // YELLOW is exactly six characters.
                    case (position)
                        3'd0: signal_char = "Y";
                        3'd1: signal_char = "E";
                        3'd2: signal_char = "L";
                        3'd3: signal_char = "L";
                        3'd4: signal_char = "O";
                        default: signal_char = "W";
                    endcase
                end
            endcase
        end
    endfunction

    function [7:0] status_char;
        input [1:0] status_kind;
        input [1:0] position;
        begin
            case (status_kind)
                2'd0: begin // STOP
                    case (position)
                        2'd0: status_char = "S";
                        2'd1: status_char = "T";
                        2'd2: status_char = "O";
                        default: status_char = "P";
                    endcase
                end
                2'd1: begin // WAIT
                    case (position)
                        2'd0: status_char = "W";
                        2'd1: status_char = "A";
                        2'd2: status_char = "I";
                        default: status_char = "T";
                    endcase
                end
                default: begin // GO, padded to four characters.
                    case (position)
                        2'd0: status_char = "G";
                        2'd1: status_char = "O";
                        default: status_char = " ";
                    endcase
                end
            endcase
        end
    endfunction

    function [7:0] screen_char;
        input       line_number;
        input [4:0] character_column;
        input [2:0] current_state;
        input [3:0] time_tens;
        input [3:0] time_ones;
        input       request_pending;
        input       extended_countdown;
        input       dashes_visible;
        reg   [1:0] ew_signal;
        reg   [1:0] ns_signal;
        reg   [1:0] ped_status;
        begin
            ew_signal = 2'd0;
            ns_signal = 2'd0;
            ped_status = request_pending ? 2'd1 : 2'd0;

            case (current_state)
                ST_EW_GREEN:  ew_signal = 2'd1;
                ST_EW_YELLOW: ew_signal = 2'd2;
                ST_NS_GREEN:  ns_signal = 2'd1;
                ST_NS_YELLOW: ns_signal = 2'd2;
                ST_PED_GO:    ped_status = 2'd2;
                default: begin
                    ew_signal = 2'd0;
                    ns_signal = 2'd0;
                end
            endcase

            if (!line_number) begin
                case (character_column)
                    5'd0:  screen_char = "E";
                    5'd1:  screen_char = "W";
                    5'd2:  screen_char = ":";
                    5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8:
                        screen_char = signal_char(ew_signal,
                                                  character_column - 5'd3);
                    5'd9:  screen_char = " ";
                    5'd10: screen_char = "T";
                    5'd11: screen_char = ":";
                    5'd12: begin
                        if (extended_countdown)
                            screen_char = dashes_visible ? "-" : " ";
                        else
                            screen_char = "0" + time_tens;
                    end
                    5'd13: begin
                        if (extended_countdown)
                            screen_char = dashes_visible ? "-" : " ";
                        else
                            screen_char = "0" + time_ones;
                    end
                    default: screen_char = " ";
                endcase
            end else begin
                case (character_column)
                    5'd0:  screen_char = "N";
                    5'd1:  screen_char = "S";
                    5'd2:  screen_char = ":";
                    5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8:
                        screen_char = signal_char(ns_signal,
                                                  character_column - 5'd3);
                    5'd9:  screen_char = " ";
                    5'd10: screen_char = "P";
                    5'd11: screen_char = ":";
                    5'd12, 5'd13, 5'd14, 5'd15:
                        screen_char = status_char(ped_status,
                                                  character_column - 5'd12);
                    default: screen_char = " ";
                endcase
            end
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            step_count  <= 32'd0;
            wait_steps  <= POWER_WAIT_STEPS;
            operation   <= OP_FUNCTION_1;
            write_phase <= 2'd0;
            column      <= 5'd0;
            LCD_DATA    <= 8'd0;
            LCD_RS      <= 1'b0;
            LCD_EN      <= 1'b0;
            frame_state <= ST_EW_GREEN;
            frame_tens  <= 4'd0;
            frame_ones  <= 4'd0;
            frame_ped_pending <= 1'b0;
            frame_traffic_extended <= 1'b0;
            frame_blink_visible <= 1'b1;
        end else if (step_count >= SAFE_STEP_CYCLES - 1) begin
            step_count <= 32'd0;

            if (wait_steps != 16'd0) begin
                wait_steps <= wait_steps - 1'b1;
                LCD_EN     <= 1'b0;
            end else begin
                case (write_phase)
                    2'd0: begin
                        LCD_EN <= 1'b0;
                        if (operation == OP_LINE1_ADDR) begin
                            frame_state       <= traffic_state;
                            frame_tens        <= shown_tens;
                            frame_ones        <= shown_ones;
                            frame_ped_pending <= ped_pending;
                            frame_traffic_extended <= traffic_extended;
                            frame_blink_visible <= blink_visible;
                        end
                        if ((operation == OP_LINE1_DATA) ||
                            (operation == OP_LINE2_DATA)) begin
                            LCD_RS <= 1'b1;
                            LCD_DATA <= screen_char(
                                operation == OP_LINE2_DATA,
                                column,
                                frame_state,
                                frame_tens,
                                frame_ones,
                                frame_ped_pending,
                                frame_traffic_extended,
                                frame_blink_visible);
                        end else begin
                            LCD_RS <= 1'b0;
                            case (operation)
                                OP_FUNCTION_1,
                                OP_FUNCTION_2,
                                OP_FUNCTION_3: LCD_DATA <= 8'h38;
                                OP_DISPLAY_OFF: LCD_DATA <= 8'h08;
                                OP_CLEAR:       LCD_DATA <= 8'h01;
                                OP_ENTRY_MODE:  LCD_DATA <= 8'h06;
                                OP_DISPLAY_ON:  LCD_DATA <= 8'h0C;
                                OP_LINE1_ADDR:  LCD_DATA <= 8'h80;
                                OP_LINE2_ADDR:  LCD_DATA <= 8'hC0;
                                default:        LCD_DATA <= 8'h80;
                            endcase
                        end
                        write_phase <= 2'd1;
                    end
                    2'd1: begin
                        LCD_EN      <= 1'b1;
                        write_phase <= 2'd2;
                    end
                    default: begin
                        LCD_EN      <= 1'b0;
                        write_phase <= 2'd0;

                        case (operation)
                            OP_FUNCTION_1: begin
                                operation  <= OP_FUNCTION_2;
                                wait_steps <= FIRST_WAIT_STEPS;
                            end
                            OP_FUNCTION_2: begin
                                operation  <= OP_FUNCTION_3;
                                wait_steps <= SHORT_WAIT_STEPS;
                            end
                            OP_FUNCTION_3:
                                operation <= OP_DISPLAY_OFF;
                            OP_DISPLAY_OFF:
                                operation <= OP_CLEAR;
                            OP_CLEAR: begin
                                operation  <= OP_ENTRY_MODE;
                                wait_steps <= CLEAR_WAIT_STEPS;
                            end
                            OP_ENTRY_MODE:
                                operation <= OP_DISPLAY_ON;
                            OP_DISPLAY_ON:
                                operation <= OP_LINE1_ADDR;
                            OP_LINE1_ADDR: begin
                                operation <= OP_LINE1_DATA;
                                column    <= 5'd0;
                            end
                            OP_LINE1_DATA: begin
                                if (column == 5'd15) begin
                                    operation <= OP_LINE2_ADDR;
                                    column    <= 5'd0;
                                end else begin
                                    column <= column + 1'b1;
                                end
                            end
                            OP_LINE2_ADDR: begin
                                operation <= OP_LINE2_DATA;
                                column    <= 5'd0;
                            end
                            OP_LINE2_DATA: begin
                                if (column == 5'd15) begin
                                    operation <= OP_LINE1_ADDR;
                                    column    <= 5'd0;
                                end else begin
                                    column <= column + 1'b1;
                                end
                            end
                            default:
                                operation <= OP_FUNCTION_1;
                        endcase
                    end
                endcase
            end
        end else begin
            step_count <= step_count + 1'b1;
        end
    end

endmodule
