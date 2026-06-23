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
    input  wire [3:0]  traffic_state,
    input  wire [15:0] remaining_seconds,
    input  wire        ped_pending,
    input  wire [1:0]  config_page,
    input  wire [2:0]  config_item,
    input  wire [15:0] config_value,
    input  wire [15:0] config_min_red,
    input  wire [15:0] config_green,
    input  wire [15:0] config_yellow,
    input  wire [15:0] config_ped,
    output wire        LCD_ON,
    output wire        LCD_BLON,
    output reg  [7:0]  LCD_DATA,
    output reg         LCD_RS,
    output wire        LCD_RW,
    output reg         LCD_EN
);

    localparam [3:0] ST_EW_GREEN  = 4'd0;
    localparam [3:0] ST_EW_YELLOW = 4'd1;
    localparam [3:0] ST_ALL_RED_1 = 4'd2;
    localparam [3:0] ST_NS_GREEN  = 4'd3;
    localparam [3:0] ST_NS_YELLOW = 4'd4;
    localparam [3:0] ST_ALL_RED_2 = 4'd5;
    localparam [3:0] ST_PED_GO    = 4'd6;
    localparam [3:0] ST_NIGHT     = 4'd8;
    localparam [3:0] ST_FAULT     = 4'd10;
    localparam [3:0] ST_CONFIG_ENTER = 4'd12;
    localparam [3:0] ST_CONFIG       = 4'd13;
    localparam [3:0] ST_CONFIG_EXIT  = 4'd14;

    localparam [1:0] PAGE_HOME = 2'd0;
    localparam [1:0] PAGE_MENU = 2'd1;
    localparam [1:0] PAGE_EDIT = 2'd2;

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
    reg [3:0]  frame_state;
    reg [6:0]  frame_seconds;
    reg        frame_ped_pending;
    reg [1:0]  frame_config_page;
    reg [2:0]  frame_config_item;
    reg [15:0] frame_config_value;
    reg [15:0] frame_config_min_red;
    reg [15:0] frame_config_green;
    reg [15:0] frame_config_yellow;
    reg [15:0] frame_config_ped;

    wire [6:0] shown_seconds =
        (remaining_seconds > 16'd99) ? 7'd99 : remaining_seconds[6:0];
    // Snapshot the raw value before decimal formatting.  The division then
    // sits entirely in the LCD controller's 20 us multicycle path instead of
    // extending the single-cycle traffic-controller-to-frame path.
    wire [6:0] frame_tens_value = frame_seconds / 7'd10;
    wire [6:0] frame_ones_value = frame_seconds % 7'd10;
    wire [3:0] frame_tens = frame_tens_value[3:0];
    wire [3:0] frame_ones = frame_ones_value[3:0];

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

    function [7:0] setting_label_char;
        input [2:0] item;
        input [3:0] position;
        begin
            setting_label_char = " ";
            case (item)
                3'd0: begin // MIN RED
                    case (position)
                        4'd0: setting_label_char = "M";
                        4'd1: setting_label_char = "I";
                        4'd2: setting_label_char = "N";
                        4'd3: setting_label_char = " ";
                        4'd4: setting_label_char = "R";
                        4'd5: setting_label_char = "E";
                        4'd6: setting_label_char = "D";
                        default: setting_label_char = " ";
                    endcase
                end
                3'd1: begin // GREEN TIME
                    case (position)
                        4'd0: setting_label_char = "G";
                        4'd1: setting_label_char = "R";
                        4'd2: setting_label_char = "E";
                        4'd3: setting_label_char = "E";
                        4'd4: setting_label_char = "N";
                        4'd5: setting_label_char = " ";
                        4'd6: setting_label_char = "T";
                        4'd7: setting_label_char = "I";
                        4'd8: setting_label_char = "M";
                        4'd9: setting_label_char = "E";
                        default: setting_label_char = " ";
                    endcase
                end
                3'd2: begin // YELLOW TIME
                    case (position)
                        4'd0: setting_label_char = "Y";
                        4'd1: setting_label_char = "E";
                        4'd2: setting_label_char = "L";
                        4'd3: setting_label_char = "L";
                        4'd4: setting_label_char = "O";
                        4'd5: setting_label_char = "W";
                        4'd6: setting_label_char = " ";
                        4'd7: setting_label_char = "T";
                        4'd8: setting_label_char = "I";
                        4'd9: setting_label_char = "M";
                        4'd10: setting_label_char = "E";
                        default: setting_label_char = " ";
                    endcase
                end
                3'd3: begin // PED TIME
                    case (position)
                        4'd0: setting_label_char = "P";
                        4'd1: setting_label_char = "E";
                        4'd2: setting_label_char = "D";
                        4'd3: setting_label_char = " ";
                        4'd4: setting_label_char = "T";
                        4'd5: setting_label_char = "I";
                        4'd6: setting_label_char = "M";
                        4'd7: setting_label_char = "E";
                        default: setting_label_char = " ";
                    endcase
                end
                default: begin // RESTORE DEFAULT
                    case (position)
                        4'd0: setting_label_char = "R";
                        4'd1: setting_label_char = "E";
                        4'd2: setting_label_char = "S";
                        4'd3: setting_label_char = "T";
                        4'd4: setting_label_char = "O";
                        4'd5: setting_label_char = "R";
                        4'd6: setting_label_char = "E";
                        4'd7: setting_label_char = " ";
                        4'd8: setting_label_char = "D";
                        4'd9: setting_label_char = "E";
                        4'd10: setting_label_char = "F";
                        4'd11: setting_label_char = "A";
                        4'd12: setting_label_char = "U";
                        4'd13: setting_label_char = "L";
                        default: setting_label_char = "T";
                    endcase
                end
            endcase
        end
    endfunction

    function [15:0] setting_minimum;
        input [2:0] item;
        begin
            case (item)
                3'd0: setting_minimum = 16'd8;
                3'd1: setting_minimum = 16'd5;
                3'd2: setting_minimum = 16'd2;
                default: setting_minimum = 16'd3;
            endcase
        end
    endfunction

    function [15:0] setting_maximum;
        input [2:0] item;
        begin
            case (item)
                3'd0: setting_maximum = 16'd40;
                3'd1: setting_maximum = 16'd30;
                3'd2: setting_maximum = 16'd5;
                default: setting_maximum = 16'd15;
            endcase
        end
    endfunction

    function [7:0] screen_char;
        input       line_number;
        input [4:0] character_column;
        input [3:0] current_state;
        input [3:0] time_tens;
        input [3:0] time_ones;
        input       request_pending;
        input [1:0] settings_page;
        input [2:0] settings_item;
        input [15:0] settings_value;
        input [15:0] settings_min_red;
        input [15:0] settings_green;
        input [15:0] settings_yellow;
        input [15:0] settings_ped;
        reg   [1:0] ew_signal;
        reg   [1:0] ns_signal;
        reg   [1:0] ped_status;
        reg   [2:0] line_item;
        reg  [15:0] line_value;
        reg  [15:0] range_value;
        begin
            ew_signal  = 2'd0;
            ns_signal  = 2'd0;
            ped_status = request_pending ? 2'd1 : 2'd0;
            line_item  = settings_item;
            line_value = settings_value;
            range_value = 16'd0;

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

            if (current_state == ST_FAULT) begin
                if (!line_number) begin
                    case (character_column)
                        5'd0:  screen_char = "S";
                        5'd1:  screen_char = "Y";
                        5'd2:  screen_char = "S";
                        5'd3:  screen_char = "T";
                        5'd4:  screen_char = "E";
                        5'd5:  screen_char = "M";
                        5'd6:  screen_char = " ";
                        5'd7:  screen_char = "F";
                        5'd8:  screen_char = "A";
                        5'd9:  screen_char = "U";
                        5'd10: screen_char = "L";
                        5'd11: screen_char = "T";
                        default: screen_char = " ";
                    endcase
                end else begin
                    case (character_column)
                        5'd0:  screen_char = "F";
                        5'd1:  screen_char = "L";
                        5'd2:  screen_char = "A";
                        5'd3:  screen_char = "S";
                        5'd4:  screen_char = "H";
                        5'd5:  screen_char = "I";
                        5'd6:  screen_char = "N";
                        5'd7:  screen_char = "G";
                        5'd8:  screen_char = " ";
                        5'd9:  screen_char = "R";
                        5'd10: screen_char = "E";
                        5'd11: screen_char = "D";
                        default: screen_char = " ";
                    endcase
                end
            end else if (current_state == ST_CONFIG) begin
                if (settings_page == PAGE_HOME) begin
                    if (!line_number) begin
                        case (character_column)
                            5'd0: screen_char = "S";
                            5'd1: screen_char = "Y";
                            5'd2: screen_char = "S";
                            5'd3: screen_char = "T";
                            5'd4: screen_char = "E";
                            5'd5: screen_char = "M";
                            5'd6: screen_char = " ";
                            5'd7: screen_char = "S";
                            5'd8: screen_char = "E";
                            5'd9: screen_char = "T";
                            5'd10: screen_char = "T";
                            5'd11: screen_char = "I";
                            5'd12: screen_char = "N";
                            5'd13: screen_char = "G";
                            5'd14: screen_char = "S";
                            default: screen_char = " ";
                        endcase
                    end else begin
                        case (character_column)
                            5'd0: screen_char = "K";
                            5'd1: screen_char = "E";
                            5'd2: screen_char = "Y";
                            5'd3: screen_char = "0";
                            5'd4: screen_char = ":";
                            5'd5: screen_char = "E";
                            5'd6: screen_char = "N";
                            5'd7: screen_char = "T";
                            5'd8: screen_char = "E";
                            5'd9: screen_char = "R";
                            default: screen_char = " ";
                        endcase
                    end
                end else if (settings_page == PAGE_MENU) begin
                    if (line_number) begin
                        if (settings_item == 3'd4)
                            line_item = 3'd0;
                        else
                            line_item = settings_item + 1'b1;
                    end

                    case (line_item)
                        3'd0: line_value = settings_min_red;
                        3'd1: line_value = settings_green;
                        3'd2: line_value = settings_yellow;
                        3'd3: line_value = settings_ped;
                        default: line_value = 16'd0;
                    endcase

                    if (character_column == 5'd0)
                        screen_char = line_number ? " " : ">";
                    else if ((line_item != 3'd4) &&
                             (character_column == 5'd13))
                        screen_char = "0" + ((line_value / 16'd10) % 16'd10);
                    else if ((line_item != 3'd4) &&
                             (character_column == 5'd14))
                        screen_char = "0" + (line_value % 16'd10);
                    else if ((line_item != 3'd4) &&
                             (character_column == 5'd15))
                        screen_char = "s";
                    else
                        screen_char = setting_label_char(
                            line_item, character_column - 1'b1);
                end else begin
                    if (!line_number) begin
                        if (character_column == 5'd0)
                            screen_char = "E";
                        else if (character_column == 5'd1)
                            screen_char = "D";
                        else if (character_column == 5'd2)
                            screen_char = "I";
                        else if (character_column == 5'd3)
                            screen_char = "T";
                        else if (character_column == 5'd4)
                            screen_char = " ";
                        else
                            screen_char = setting_label_char(
                                settings_item, character_column - 5'd5);
                    end else begin
                        if (character_column == 5'd0)
                            screen_char = "0" +
                                ((settings_value / 16'd10) % 16'd10);
                        else if (character_column == 5'd1)
                            screen_char = "0" + (settings_value % 16'd10);
                        else if (character_column == 5'd2)
                            screen_char = "s";
                        else if (character_column == 5'd3)
                            screen_char = " ";
                        else if (character_column == 5'd4)
                            screen_char = "R";
                        else if (character_column == 5'd5)
                            screen_char = "A";
                        else if (character_column == 5'd6)
                            screen_char = "N";
                        else if (character_column == 5'd7)
                            screen_char = "G";
                        else if (character_column == 5'd8)
                            screen_char = "E";
                        else if (character_column == 5'd9)
                            screen_char = " ";
                        else if (character_column == 5'd10) begin
                            range_value = setting_minimum(settings_item);
                            screen_char = "0" +
                                ((range_value / 16'd10) % 16'd10);
                        end else if (character_column == 5'd11) begin
                            range_value = setting_minimum(settings_item);
                            screen_char = "0" + (range_value % 16'd10);
                        end else if (character_column == 5'd12)
                            screen_char = "-";
                        else if (character_column == 5'd13) begin
                            range_value = setting_maximum(settings_item);
                            screen_char = "0" +
                                ((range_value / 16'd10) % 16'd10);
                        end else if (character_column == 5'd14) begin
                            range_value = setting_maximum(settings_item);
                            screen_char = "0" + (range_value % 16'd10);
                        end else
                            screen_char = " ";
                    end
                end
            end else if ((current_state == ST_CONFIG_ENTER) ||
                         (current_state == ST_CONFIG_EXIT)) begin
                if (!line_number) begin
                    case (character_column)
                        5'd0: screen_char = "S";
                        5'd1: screen_char = "Y";
                        5'd2: screen_char = "S";
                        5'd3: screen_char = "T";
                        5'd4: screen_char = "E";
                        5'd5: screen_char = "M";
                        5'd6: screen_char = " ";
                        5'd7: screen_char = "S";
                        5'd8: screen_char = "E";
                        5'd9: screen_char = "T";
                        5'd10: screen_char = "T";
                        5'd11: screen_char = "I";
                        5'd12: screen_char = "N";
                        5'd13: screen_char = "G";
                        5'd14: screen_char = "S";
                        default: screen_char = " ";
                    endcase
                end else if (current_state == ST_CONFIG_ENTER) begin
                    case (character_column)
                        5'd0: screen_char = "E";
                        5'd1: screen_char = "N";
                        5'd2: screen_char = "T";
                        5'd3: screen_char = "E";
                        5'd4: screen_char = "R";
                        5'd5: screen_char = " ";
                        5'd6: screen_char = "A";
                        5'd7: screen_char = "L";
                        5'd8: screen_char = "L";
                        5'd9: screen_char = "-";
                        5'd10: screen_char = "R";
                        5'd11: screen_char = "E";
                        5'd12: screen_char = "D";
                        default: screen_char = " ";
                    endcase
                end else begin
                    case (character_column)
                        5'd0: screen_char = "E";
                        5'd1: screen_char = "X";
                        5'd2: screen_char = "I";
                        5'd3: screen_char = "T";
                        5'd4: screen_char = " ";
                        5'd5: screen_char = "A";
                        5'd6: screen_char = "L";
                        5'd7: screen_char = "L";
                        5'd8: screen_char = "-";
                        5'd9: screen_char = "R";
                        5'd10: screen_char = "E";
                        5'd11: screen_char = "D";
                        default: screen_char = " ";
                    endcase
                end
            end else if (current_state == ST_NIGHT) begin
                if (!line_number) begin
                    case (character_column)
                        5'd0: screen_char = "N";
                        5'd1: screen_char = "I";
                        5'd2: screen_char = "G";
                        5'd3: screen_char = "H";
                        5'd4: screen_char = "T";
                        5'd5: screen_char = " ";
                        5'd6: screen_char = "M";
                        5'd7: screen_char = "O";
                        5'd8: screen_char = "D";
                        5'd9: screen_char = "E";
                        default: screen_char = " ";
                    endcase
                end else begin
                    case (character_column)
                        5'd0:  screen_char = "E";
                        5'd1:  screen_char = "W";
                        5'd2:  screen_char = ":";
                        5'd3:  screen_char = "Y";
                        5'd4:  screen_char = "E";
                        5'd5:  screen_char = "L";
                        5'd6:  screen_char = "L";
                        5'd7:  screen_char = "O";
                        5'd8:  screen_char = "W";
                        5'd9:  screen_char = " ";
                        5'd10: screen_char = "N";
                        5'd11: screen_char = "S";
                        5'd12: screen_char = ":";
                        5'd13: screen_char = "R";
                        5'd14: screen_char = "E";
                        default: screen_char = "D";
                    endcase
                end
            end else if (!line_number) begin
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
                    5'd12: screen_char = "0" + time_tens;
                    5'd13: screen_char = "0" + time_ones;
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
            frame_seconds <= 7'd0;
            frame_ped_pending <= 1'b0;
            frame_config_page <= PAGE_HOME;
            frame_config_item <= 3'd0;
            frame_config_value <= 16'd0;
            frame_config_min_red <= 16'd0;
            frame_config_green <= 16'd0;
            frame_config_yellow <= 16'd0;
            frame_config_ped <= 16'd0;
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
                            frame_seconds     <= shown_seconds;
                            frame_ped_pending <= ped_pending;
                            frame_config_page <= config_page;
                            frame_config_item <= config_item;
                            frame_config_value <= config_value;
                            frame_config_min_red <= config_min_red;
                            frame_config_green <= config_green;
                            frame_config_yellow <= config_yellow;
                            frame_config_ped <= config_ped;
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
                                frame_config_page,
                                frame_config_item,
                                frame_config_value,
                                frame_config_min_red,
                                frame_config_green,
                                frame_config_yellow,
                                frame_config_ped);
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
