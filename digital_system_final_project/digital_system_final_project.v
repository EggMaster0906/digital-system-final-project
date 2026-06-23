`timescale 1ns/1ps

// Top-level module for the DE2-115 traffic-light project.
module digital_system_final_project #(
    parameter integer CLOCK_HZ         = 50_000_000,
    parameter integer BUTTON_DEBOUNCE_CYCLES = 1_000_000,
    parameter [15:0]  GREEN_SECONDS    = 16'd10,
    parameter [15:0]  MIN_GREEN_SECONDS = 16'd5,
    parameter [15:0]  MAX_GREEN_SECONDS = 16'd15,
    parameter [15:0]  EXTENSION_RELEASE_SECONDS = 16'd3,
    parameter [15:0]  YELLOW_SECONDS   = 16'd3,
    parameter [15:0]  ALL_RED_SECONDS  = 16'd1,
    parameter [15:0]  PED_SECONDS      = 16'd5
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
    wire [2:0]  traffic_state;
    wire [15:0] remaining_seconds;
    wire        ew_red;
    wire        ew_green;
    wire        ns_red;
    wire        ns_green;
    wire        ped_request;
    wire        ped_pending;
    wire        ped_stop;
    wire        ped_go;
    wire [2:0]  ped_return_state;
    wire [6:0]  ew_countdown;
    wire [6:0]  ns_countdown;
    wire        countdown_dashes;
    wire        traffic_extended;
    reg         blink_visible;
    reg  [31:0] blink_count;
    reg  [2:0]  sensor_meta;
    reg  [2:0]  sensor_sync;
    wire [3:0]  ew_tens;
    wire [3:0]  ew_ones;
    wire [3:0]  ns_tens;
    wire [3:0]  ns_ones;
    wire [6:0]  ew_tens_value;
    wire [6:0]  ew_ones_value;
    wire [6:0]  ns_tens_value;
    wire [6:0]  ns_ones_value;

    // KEY[0] is active-low on the DE2-115 board.
    wire reset_n = KEY[0];
    localparam integer BLINK_HALF_CYCLES =
        (CLOCK_HZ < 2) ? 1 : ((CLOCK_HZ + 1) / 2);

    // SW[0]=EW vehicle, SW[1]=NS vehicle, SW[2]=smart traffic mode.
    // Synchronize the board switches before they enter the state machine.
    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n) begin
            sensor_meta <= 3'b000;
            sensor_sync <= 3'b000;
        end else begin
            sensor_meta <= SW[2:0];
            sensor_sync <= sensor_meta;
        end
    end

    // A full blink cycle is one second: 0.5 s visible and 0.5 s blank. Start
    // each extension with the dashes visible for deterministic feedback.
    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n) begin
            blink_count   <= 32'd0;
            blink_visible <= 1'b1;
        end else if (!traffic_extended) begin
            blink_count   <= 32'd0;
            blink_visible <= 1'b1;
        end else if (blink_count >= BLINK_HALF_CYCLES - 1) begin
            blink_count   <= 32'd0;
            blink_visible <= ~blink_visible;
        end else begin
            blink_count <= blink_count + 1'b1;
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

    traffic_controller #(
        .GREEN_SECONDS   (GREEN_SECONDS),
        .MIN_GREEN_SECONDS(MIN_GREEN_SECONDS),
        .MAX_GREEN_SECONDS(MAX_GREEN_SECONDS),
        .EXTENSION_RELEASE_SECONDS(EXTENSION_RELEASE_SECONDS),
        .YELLOW_SECONDS  (YELLOW_SECONDS),
        .ALL_RED_SECONDS (ALL_RED_SECONDS),
        .PED_SECONDS     (PED_SECONDS)
    ) traffic_controller_inst (
        .clk               (CLOCK_50),
        .reset_n           (reset_n),
        .tick_1s           (tick_1s),
        .ped_request       (ped_request),
        .smart_mode        (sensor_sync[2]),
        .ew_vehicle        (sensor_sync[0]),
        .ns_vehicle        (sensor_sync[1]),
        .state             (traffic_state),
        .remaining_seconds (remaining_seconds),
        .ped_pending       (ped_pending),
        .ped_return_state  (ped_return_state),
        .ew_red            (ew_red),
        .ew_green          (ew_green),
        .ns_red            (ns_red),
        .ns_green          (ns_green),
        .ped_stop          (ped_stop),
        .ped_go            (ped_go),
        .traffic_extended  (traffic_extended)
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
        .ew_seconds        (ew_countdown),
        .ns_seconds        (ns_countdown),
        .show_dashes       (countdown_dashes)
    );

    assign ew_tens_value = ew_countdown / 7'd10;
    assign ew_ones_value = ew_countdown % 7'd10;
    assign ns_tens_value = ns_countdown / 7'd10;
    assign ns_ones_value = ns_countdown % 7'd10;
    assign ew_tens = countdown_dashes ? 4'd10 :
                     traffic_extended ? (blink_visible ? 4'd10 : 4'd15) :
                     ew_tens_value[3:0];
    assign ew_ones = countdown_dashes ? 4'd10 :
                     traffic_extended ? (blink_visible ? 4'd10 : 4'd15) :
                     ew_ones_value[3:0];
    assign ns_tens = countdown_dashes ? 4'd10 :
                     traffic_extended ? (blink_visible ? 4'd10 : 4'd15) :
                     ns_tens_value[3:0];
    assign ns_ones = countdown_dashes ? 4'd10 :
                     traffic_extended ? (blink_visible ? 4'd10 : 4'd15) :
                     ns_ones_value[3:0];

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
        .traffic_extended  (traffic_extended),
        .blink_visible     (blink_visible),
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

endmodule
