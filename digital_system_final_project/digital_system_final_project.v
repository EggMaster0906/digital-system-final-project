`timescale 1ns/1ps

// Top-level module for the DE2-115 traffic-light project.
module digital_system_final_project #(
    parameter integer CLOCK_HZ         = 50_000_000,
    parameter integer BUTTON_DEBOUNCE_CYCLES = 1_000_000,
    parameter [15:0]  MIN_RED_SECONDS  = 16'd14,
    parameter [15:0]  GREEN_SECONDS    = 16'd10,
    parameter [15:0]  MIN_GREEN_SECONDS = 16'd5,
    parameter [15:0]  YELLOW_SECONDS   = 16'd3,
    parameter [15:0]  ALL_RED_SECONDS  = 16'd1,
    parameter [15:0]  PED_SECONDS      = 16'd5,
    parameter [15:0]  FLASH_SECONDS    = 16'd1
)(
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [17:0] SW,
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    output wire [6:0]  HEX6,
    output wire [6:0]  HEX7,
    output wire        LCD_ON,
    output wire        LCD_BLON,
    output wire [7:0]  LCD_DATA,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_EN
);

    wire        tick_1s;
    wire [3:0]  traffic_state;
    wire [15:0] remaining_seconds;
    wire        ew_red;
    wire        ew_green;
    wire        ns_red;
    wire        ns_green;
    wire        ped_request;
    wire        key_select;
    wire        key_down;
    wire        key_back;
    wire        ped_pending;
    wire        ped_stop;
    wire        ped_go;
    wire [2:0]  ped_return_state;
    wire [6:0]  ew_countdown;
    wire [6:0]  ns_countdown;
    wire        countdown_dashes;
    wire [3:0]  ew_tens;
    wire [3:0]  ew_ones;
    wire [3:0]  ns_tens;
    wire [3:0]  ns_ones;
    wire [6:0]  ew_tens_value;
    wire [6:0]  ew_ones_value;
    wire [6:0]  ns_tens_value;
    wire [6:0]  ns_ones_value;
    reg  [1:0]  night_mode_sync;
    reg  [1:0]  fault_mode_sync;
    reg  [1:0]  config_mode_sync;
    wire        night_mode = night_mode_sync[1];
    wire        fault_mode = fault_mode_sync[1];
    wire        config_mode = config_mode_sync[1];
    wire        config_active = (traffic_state == 4'd13);
    wire        config_related = (traffic_state >= 4'd12);
    wire [1:0]  config_page;
    wire [2:0]  config_item;
    wire [15:0] config_display_value;
    wire [15:0] configured_min_red_seconds;
    wire [15:0] configured_green_seconds;
    wire [15:0] configured_yellow_seconds;
    wire [15:0] configured_ped_seconds;

    // KEY[0] is masked from reset only while the menu itself is active. The
    // function defaults safely to reset mode even if state is unknown during
    // power-up, and fault preemption restores KEY[0]'s reset role.
    function is_config_state;
        input [3:0] current_state;
        begin
            case (current_state)
                4'd13: is_config_state = 1'b1;
                default: is_config_state = 1'b0;
            endcase
        end
    endfunction

    wire key0_is_select = is_config_state(traffic_state);
    wire reset_n = KEY[0] | key0_is_select;

    // Synchronize asynchronous mode switches before they control the FSM.
    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n) begin
            night_mode_sync <= 2'b00;
            fault_mode_sync <= 2'b00;
            config_mode_sync <= 2'b00;
        end else begin
            night_mode_sync <= {night_mode_sync[0], SW[3]};
            fault_mode_sync <= {fault_mode_sync[0], SW[4]};
            config_mode_sync <= {config_mode_sync[0], SW[17]};
        end
    end

    clock_divider #(
        .CLOCK_HZ(CLOCK_HZ)
    ) clock_divider_inst (
        .clk     (CLOCK_50),
        .reset_n (reset_n),
        .tick_1s (tick_1s)
    );

    // KEY[1] is the active-low pedestrian request button. The conditioner
    // converts a physical press, including a long hold, into one clock pulse.
    button_conditioner #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)
    ) pedestrian_button_inst (
        .clk         (CLOCK_50),
        .reset_n     (reset_n),
        .button_n    (KEY[1]),
        .press_pulse (ped_request)
    );

    button_conditioner #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)
    ) select_button_inst (
        .clk         (CLOCK_50),
        .reset_n     (reset_n),
        .button_n    (KEY[0]),
        .press_pulse (key_select)
    );

    button_conditioner #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)
    ) down_button_inst (
        .clk         (CLOCK_50),
        .reset_n     (reset_n),
        .button_n    (KEY[2]),
        .press_pulse (key_down)
    );

    button_conditioner #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)
    ) back_button_inst (
        .clk         (CLOCK_50),
        .reset_n     (reset_n),
        .button_n    (KEY[3]),
        .press_pulse (key_back)
    );

    configuration_controller #(
        .DEFAULT_MIN_RED_SECONDS(MIN_RED_SECONDS),
        .DEFAULT_GREEN_SECONDS  (GREEN_SECONDS),
        .DEFAULT_YELLOW_SECONDS (YELLOW_SECONDS),
        .DEFAULT_PED_SECONDS    (PED_SECONDS)
    ) configuration_controller_inst (
        .clk             (CLOCK_50),
        .reset_n         (reset_n),
        .config_active   (config_active),
        .key_select      (key_select),
        .key_up          (ped_request),
        .key_down        (key_down),
        .key_back        (key_back),
        .page            (config_page),
        .selected_item   (config_item),
        .display_value   (config_display_value),
        .min_red_seconds (configured_min_red_seconds),
        .green_seconds   (configured_green_seconds),
        .yellow_seconds  (configured_yellow_seconds),
        .ped_seconds     (configured_ped_seconds)
    );

    traffic_controller #(
        .GREEN_SECONDS   (GREEN_SECONDS),
        .MIN_GREEN_SECONDS(MIN_GREEN_SECONDS),
        .YELLOW_SECONDS  (YELLOW_SECONDS),
        .ALL_RED_SECONDS (ALL_RED_SECONDS),
        .PED_SECONDS     (PED_SECONDS),
        .FLASH_SECONDS   (FLASH_SECONDS)
    ) traffic_controller_inst (
        .clk               (CLOCK_50),
        .reset_n           (reset_n),
        .tick_1s           (tick_1s),
        .ped_request       (ped_request & !config_mode & !config_related),
        .night_mode        (night_mode),
        .fault_mode        (fault_mode),
        .config_mode       (config_mode),
        .min_red_seconds   (configured_min_red_seconds),
        .green_seconds     (configured_green_seconds),
        .yellow_seconds    (configured_yellow_seconds),
        .ped_seconds       (configured_ped_seconds),
        .state             (traffic_state),
        .remaining_seconds (remaining_seconds),
        .ped_pending       (ped_pending),
        .ped_return_state  (ped_return_state),
        .ew_red            (ew_red),
        .ew_green          (ew_green),
        .ns_red            (ns_red),
        .ns_green          (ns_green),
        .ped_stop          (ped_stop),
        .ped_go            (ped_go)
    );

    countdown_display #(
        .GREEN_SECONDS   (GREEN_SECONDS),
        .YELLOW_SECONDS  (YELLOW_SECONDS),
        .ALL_RED_SECONDS (ALL_RED_SECONDS),
        .PED_SECONDS     (PED_SECONDS)
    ) countdown_display_inst (
        .state             (traffic_state),
        .remaining_seconds (remaining_seconds),
        .ped_pending       (ped_pending),
        .ped_return_state  (ped_return_state),
        .green_seconds     (configured_green_seconds),
        .yellow_seconds    (configured_yellow_seconds),
        .all_red_seconds   (ALL_RED_SECONDS),
        .ped_seconds       (configured_ped_seconds),
        .ew_seconds        (ew_countdown),
        .ns_seconds        (ns_countdown),
        .show_dashes       (countdown_dashes)
    );

    assign ew_tens_value = ew_countdown / 7'd10;
    assign ew_ones_value = ew_countdown % 7'd10;
    assign ns_tens_value = ns_countdown / 7'd10;
    assign ns_ones_value = ns_countdown % 7'd10;
    assign ew_tens = countdown_dashes ? 4'd10 : ew_tens_value[3:0];
    assign ew_ones = countdown_dashes ? 4'd10 : ew_ones_value[3:0];
    assign ns_tens = countdown_dashes ? 4'd10 : ns_tens_value[3:0];
    assign ns_ones = countdown_dashes ? 4'd10 : ns_ones_value[3:0];

    seven_seg_decoder hex4_decoder (.value(ew_ones), .segments(HEX4));
    seven_seg_decoder hex5_decoder (.value(ew_tens), .segments(HEX5));
    seven_seg_decoder hex6_decoder (.value(ns_ones), .segments(HEX6));
    seven_seg_decoder hex7_decoder (.value(ns_tens), .segments(HEX7));

    lcd_controller #(
        .CLOCK_HZ(CLOCK_HZ)
    ) lcd_controller_inst (
        .clk               (CLOCK_50),
        .reset_n           (reset_n),
        .traffic_state     (traffic_state),
        .remaining_seconds (remaining_seconds),
        .ped_pending       (ped_pending),
        .config_page       (config_page),
        .config_item       (config_item),
        .config_value      (config_display_value),
        .config_min_red    (configured_min_red_seconds),
        .config_green      (configured_green_seconds),
        .config_yellow     (configured_yellow_seconds),
        .config_ped        (configured_ped_seconds),
        .LCD_ON            (LCD_ON),
        .LCD_BLON          (LCD_BLON),
        .LCD_DATA          (LCD_DATA),
        .LCD_RS            (LCD_RS),
        .LCD_RW            (LCD_RW),
        .LCD_EN            (LCD_EN)
    );

    // A yellow indication uses the red and green LEDs together.
    assign LEDR = {15'b0, ped_stop, ns_red, ew_red};
    assign LEDG = {6'b0, ped_go, ns_green, ew_green};

    // Unused displays are active-low and therefore blank when all bits are 1.
    assign HEX0 = 7'b1111111;
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;

    // SW[3] selects night mode, SW[4] simulates a system fault, and SW[17]
    // requests the safely interlocked system-settings mode.

endmodule
