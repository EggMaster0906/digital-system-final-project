`timescale 1ns/1ps

// Traffic-light controller for a two-direction intersection. In smart mode,
// vehicle demand may extend a green after its normal countdown, followed by a
// deterministic release countdown before yellow. Vehicle sensing never
// shortens the ordinary green interval.
module traffic_controller #(
    parameter [15:0] GREEN_SECONDS    = 16'd10,
    parameter [15:0] MIN_GREEN_SECONDS = 16'd5,
    parameter [15:0] MAX_GREEN_SECONDS = 16'd15,
    parameter [15:0] EXTENSION_RELEASE_SECONDS = 16'd3,
    parameter [15:0] YELLOW_SECONDS   = 16'd3,
    parameter [15:0] ALL_RED_SECONDS  = 16'd1,
    parameter [15:0] PED_SECONDS      = 16'd5
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        tick_1s,
    input  wire        ped_request,
    input  wire        smart_mode,
    input  wire        ew_vehicle,
    input  wire        ns_vehicle,
    output reg  [2:0]  state,
    output reg  [15:0] remaining_seconds,
    output reg         ped_pending,
    output reg  [2:0]  ped_return_state,
    output reg         ew_red,
    output reg         ew_green,
    output reg         ns_red,
    output reg         ns_green,
    output reg         ped_stop,
    output reg         ped_go,
    output wire        traffic_extended
);

    localparam [2:0] ST_EW_GREEN  = 3'd0;
    localparam [2:0] ST_EW_YELLOW = 3'd1;
    localparam [2:0] ST_ALL_RED_1 = 3'd2;
    localparam [2:0] ST_NS_GREEN  = 3'd3;
    localparam [2:0] ST_NS_YELLOW = 3'd4;
    localparam [2:0] ST_ALL_RED_2 = 3'd5;
    localparam [2:0] ST_PED_GO    = 3'd6;
    localparam [2:0] ST_PED_CLEAR = 3'd7;

    localparam [1:0] EXT_NORMAL  = 2'd0;
    localparam [1:0] EXT_HOLD    = 2'd1;
    localparam [1:0] EXT_RELEASE = 2'd2;
    localparam [15:0] EXTENSION_WINDOW_SECONDS =
        (MAX_GREEN_SECONDS > GREEN_SECONDS) ?
        (MAX_GREEN_SECONDS - GREEN_SECONDS) : 16'd0;

    reg [15:0] elapsed_seconds;
    reg [15:0] extension_elapsed;
    reg [15:0] release_remaining;
    reg [1:0]  extension_phase;
    reg [15:0] state_duration;
    reg [2:0]  next_state;
    reg        transition_due;
    wire       ped_request_active = ped_pending | ped_request;
    wire       vehicle_green =
        (state == ST_EW_GREEN) || (state == ST_NS_GREEN);
    wire       extension_demand = smart_mode &&
        (((state == ST_EW_GREEN) && ew_vehicle && !ns_vehicle) ||
         ((state == ST_NS_GREEN) && ns_vehicle && !ew_vehicle));

    // Only EXT_HOLD is indeterminate. EXT_RELEASE has a known three-second
    // countdown and therefore returns to normal numeric display.
    assign traffic_extended = vehicle_green &&
                              (extension_phase == EXT_HOLD);

    always @(*) begin
        case (state)
            ST_EW_GREEN: begin
                state_duration = GREEN_SECONDS;
                next_state     = ST_EW_YELLOW;
            end
            ST_EW_YELLOW: begin
                state_duration = YELLOW_SECONDS;
                next_state     = ST_ALL_RED_1;
            end
            ST_ALL_RED_1: begin
                state_duration = ALL_RED_SECONDS;
                if (ped_request_active)
                    next_state = ST_PED_GO;
                else
                    next_state = ST_NS_GREEN;
            end
            ST_NS_GREEN: begin
                state_duration = GREEN_SECONDS;
                next_state     = ST_NS_YELLOW;
            end
            ST_NS_YELLOW: begin
                state_duration = YELLOW_SECONDS;
                next_state     = ST_ALL_RED_2;
            end
            ST_ALL_RED_2: begin
                state_duration = ALL_RED_SECONDS;
                if (ped_request_active)
                    next_state = ST_PED_GO;
                else
                    next_state = ST_EW_GREEN;
            end
            ST_PED_GO: begin
                state_duration = PED_SECONDS;
                next_state     = ST_PED_CLEAR;
            end
            ST_PED_CLEAR: begin
                // Keep vehicles all-red and return the pedestrian signal to
                // STOP before releasing the next vehicle direction.
                state_duration = ALL_RED_SECONDS;
                next_state     = ped_return_state;
            end
            default: begin
                state_duration = ALL_RED_SECONDS;
                next_state     = ST_EW_GREEN;
            end
        endcase


        transition_due = (elapsed_seconds + 1'b1 >= state_duration);

        if (vehicle_green) begin
            case (extension_phase)
                EXT_NORMAL: begin
                    // A pedestrian request may shorten green, but never below
                    // the configured safe minimum.
                    if (ped_request_active &&
                        (elapsed_seconds + 1'b1 >= MIN_GREEN_SECONDS))
                        transition_due = 1'b1;
                    // At the normal deadline, enter the unknown extension
                    // instead of changing the displayed countdown beforehand.
                    else if ((elapsed_seconds + 1'b1 >= GREEN_SECONDS) &&
                             extension_demand &&
                             (EXTENSION_WINDOW_SECONDS != 16'd0))
                        transition_due = 1'b0;
                end
                EXT_HOLD: begin
                    // A pedestrian request retains priority over traffic
                    // sensing and starts the safe yellow transition promptly.
                    transition_due = ped_request_active;
                end
                EXT_RELEASE: begin
                    transition_due = ped_request_active ||
                                     (release_remaining <= 16'd1);
                end
                default: transition_due = 1'b1;
            endcase
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= ST_EW_GREEN;
            elapsed_seconds <= 16'd0;
            extension_elapsed <= 16'd0;
            release_remaining <= 16'd0;
            extension_phase <= EXT_NORMAL;
            ped_pending     <= 1'b0;
            ped_return_state <= ST_NS_GREEN;
        end else begin
            if (ped_request && (state != ST_PED_GO))
                ped_pending <= 1'b1;

            if (tick_1s && transition_due) begin
                if ((state == ST_ALL_RED_1) && (next_state == ST_PED_GO))
                    ped_return_state <= ST_NS_GREEN;
                else if ((state == ST_ALL_RED_2) && (next_state == ST_PED_GO))
                    ped_return_state <= ST_EW_GREEN;

                if (state == ST_PED_GO)
                    ped_pending <= 1'b0;

                state           <= next_state;
                elapsed_seconds <= 16'd0;
                extension_elapsed <= 16'd0;
                release_remaining <= 16'd0;
                extension_phase <= EXT_NORMAL;
            end else if (tick_1s) begin
                if (vehicle_green) begin
                    case (extension_phase)
                        EXT_NORMAL: begin
                            elapsed_seconds <= elapsed_seconds + 1'b1;
                            if ((elapsed_seconds + 1'b1 >= GREEN_SECONDS) &&
                                extension_demand &&
                                (EXTENSION_WINDOW_SECONDS != 16'd0)) begin
                                extension_phase   <= EXT_HOLD;
                                extension_elapsed <= 16'd0;
                            end
                        end
                        EXT_HOLD: begin
                            if (!extension_demand ||
                                (extension_elapsed + 1'b1 >=
                                 EXTENSION_WINDOW_SECONDS)) begin
                                extension_phase  <= EXT_RELEASE;
                                release_remaining <=
                                    EXTENSION_RELEASE_SECONDS;
                            end else begin
                                extension_elapsed <=
                                    extension_elapsed + 1'b1;
                            end
                        end
                        EXT_RELEASE: begin
                            if (release_remaining > 16'd1)
                                release_remaining <=
                                    release_remaining - 1'b1;
                        end
                        default: extension_phase <= EXT_NORMAL;
                    endcase
                end else begin
                    elapsed_seconds <= elapsed_seconds + 1'b1;
                end
            end
        end
    end

    always @(*) begin
        if (vehicle_green && (extension_phase == EXT_HOLD))
            remaining_seconds = 16'd0;
        else if (vehicle_green && (extension_phase == EXT_RELEASE))
            remaining_seconds = release_remaining;
        else if (vehicle_green && ped_request_active &&
                 (elapsed_seconds < MIN_GREEN_SECONDS))
            remaining_seconds = MIN_GREEN_SECONDS - elapsed_seconds;
        else if (vehicle_green && ped_request_active)
            remaining_seconds = 16'd1;
        else if (elapsed_seconds < state_duration)
            remaining_seconds = state_duration - elapsed_seconds;
        else
            remaining_seconds = 16'd0;
    end

    always @(*) begin
        // Default to the fail-safe all-red indication.
        ew_red   = 1'b1;
        ew_green = 1'b0;
        ns_red   = 1'b1;
        ns_green = 1'b0;
        ped_stop = 1'b1;
        ped_go   = 1'b0;

        case (state)
            ST_EW_GREEN: begin
                ew_red   = 1'b0;
                ew_green = 1'b1;
            end
            ST_EW_YELLOW: begin
                ew_red   = 1'b1;
                ew_green = 1'b1;
            end
            ST_NS_GREEN: begin
                ns_red   = 1'b0;
                ns_green = 1'b1;
            end
            ST_NS_YELLOW: begin
                ns_red   = 1'b1;
                ns_green = 1'b1;
            end
            ST_PED_GO: begin
                ped_stop = 1'b0;
                ped_go   = 1'b1;
            end
            default: begin
                ew_red   = 1'b1;
                ns_red   = 1'b1;
            end
        endcase
    end

endmodule
