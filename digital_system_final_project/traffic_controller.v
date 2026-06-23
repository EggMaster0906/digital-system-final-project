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
    parameter [15:0] PED_SECONDS      = 16'd5,
    parameter [15:0] FLASH_SECONDS    = 16'd1
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        tick_1s,
    input  wire        ped_request,
    input  wire        smart_mode,
    input  wire        ew_vehicle,
    input  wire        ns_vehicle,
    input  wire        night_mode,
    input  wire        fault_mode,
    input  wire        config_mode,
    input  wire [15:0] min_red_seconds,
    input  wire [15:0] green_seconds,
    input  wire [15:0] yellow_seconds,
    input  wire [15:0] ped_seconds,
    output reg  [3:0]  state,
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

    localparam [3:0] ST_EW_GREEN    = 4'd0;
    localparam [3:0] ST_EW_YELLOW   = 4'd1;
    localparam [3:0] ST_ALL_RED_1   = 4'd2;
    localparam [3:0] ST_NS_GREEN    = 4'd3;
    localparam [3:0] ST_NS_YELLOW   = 4'd4;
    localparam [3:0] ST_ALL_RED_2   = 4'd5;
    localparam [3:0] ST_PED_GO      = 4'd6;
    localparam [3:0] ST_PED_CLEAR   = 4'd7;
    localparam [3:0] ST_NIGHT       = 4'd8;
    localparam [3:0] ST_NIGHT_CLEAR = 4'd9;
    localparam [3:0] ST_FAULT       = 4'd10;
    localparam [3:0] ST_FAULT_CLEAR = 4'd11;
    localparam [3:0] ST_CONFIG_ENTER = 4'd12;
    localparam [3:0] ST_CONFIG       = 4'd13;
    localparam [3:0] ST_CONFIG_EXIT  = 4'd14;

    localparam [1:0] EXT_NORMAL  = 2'd0;
    localparam [1:0] EXT_HOLD    = 2'd1;
    localparam [1:0] EXT_RELEASE = 2'd2;
    reg [15:0] elapsed_seconds;
    reg [15:0] extension_elapsed;
    reg [15:0] release_remaining;
    reg [1:0]  extension_phase;
    reg [15:0] flash_elapsed_seconds;
    reg        flash_on;
    reg [15:0] state_duration;
    reg [3:0]  next_state;
    reg        transition_due;
    reg        transition_allowed;
    reg        config_pending;
    reg [15:0] ew_red_elapsed;
    reg [15:0] ns_red_elapsed;
    reg [15:0] base_remaining;
    reg [15:0] red_remaining;
    wire       ped_request_active = ped_pending | ped_request;
    wire       vehicle_green =
        (state == ST_EW_GREEN) || (state == ST_NS_GREEN);
    wire [15:0] extension_window_seconds =
        (MAX_GREEN_SECONDS > green_seconds) ?
        (MAX_GREEN_SECONDS - green_seconds) : 16'd0;
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
                state_duration = green_seconds;
                next_state     = ST_EW_YELLOW;
            end
            ST_EW_YELLOW: begin
                state_duration = yellow_seconds;
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
                state_duration = green_seconds;
                next_state     = ST_NS_YELLOW;
            end
            ST_NS_YELLOW: begin
                state_duration = yellow_seconds;
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
                state_duration = ped_seconds;
                next_state     = ST_PED_CLEAR;
            end
            ST_PED_CLEAR: begin
                // Keep vehicles all-red and return the pedestrian signal to
                // STOP before releasing the next vehicle direction.
                state_duration = ALL_RED_SECONDS;
                next_state     = ped_return_state;
            end
            ST_NIGHT: begin
                state_duration = FLASH_SECONDS;
                next_state     = ST_NIGHT;
            end
            ST_NIGHT_CLEAR: begin
                state_duration = ALL_RED_SECONDS;
                if (config_mode)
                    next_state = ST_CONFIG_ENTER;
                else if (night_mode)
                    next_state = ST_NIGHT;
                else
                    next_state = ST_EW_GREEN;
            end
            ST_FAULT: begin
                state_duration = FLASH_SECONDS;
                next_state     = ST_FAULT;
            end
            ST_FAULT_CLEAR: begin
                state_duration = ALL_RED_SECONDS;
                if (config_mode)
                    next_state = ST_CONFIG_ENTER;
                else if (night_mode)
                    next_state = ST_NIGHT;
                else
                    next_state = ST_EW_GREEN;
            end
            ST_CONFIG_ENTER: begin
                state_duration = ALL_RED_SECONDS;
                if (config_mode)
                    next_state = ST_CONFIG;
                else
                    next_state = ST_CONFIG_EXIT;
            end
            ST_CONFIG: begin
                state_duration = 16'hffff;
                next_state     = ST_CONFIG;
            end
            ST_CONFIG_EXIT: begin
                state_duration = ALL_RED_SECONDS;
                if (config_mode)
                    next_state = ST_CONFIG_ENTER;
                else if (night_mode)
                    next_state = ST_NIGHT;
                else
                    next_state = ST_EW_GREEN;
            end
            default: begin
                state_duration = ALL_RED_SECONDS;
                next_state     = ST_EW_GREEN;
            end
        endcase


        transition_due = (elapsed_seconds + 1'b1 >= state_duration);
        transition_allowed = 1'b1;

        if (vehicle_green) begin
            case (extension_phase)
                EXT_NORMAL: begin
                    // A waiting pedestrian may shorten a vehicle green, but
                    // never below the configured minimum safe green time.
                    if (ped_request_active &&
                        (elapsed_seconds + 1'b1 >= MIN_GREEN_SECONDS))
                        transition_due = 1'b1;
                    else if ((elapsed_seconds + 1'b1 >= green_seconds) &&
                             extension_demand &&
                             (extension_window_seconds != 16'd0))
                        transition_due = 1'b0;
                end
                EXT_HOLD:
                    transition_due = ped_request_active;
                EXT_RELEASE:
                    transition_due = ped_request_active ||
                                     (release_remaining <= 16'd1);
                default:
                    transition_due = 1'b1;
            endcase
        end

        // A direction may receive green only after its configured minimum red
        // time. The current tick is included because it completes one red
        // second before the state transition is observed.
        if ((next_state == ST_EW_GREEN) &&
            (ew_red_elapsed + 1'b1 < min_red_seconds))
            transition_allowed = 1'b0;
        if ((next_state == ST_NS_GREEN) &&
            (ns_red_elapsed + 1'b1 < min_red_seconds))
            transition_allowed = 1'b0;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= ST_EW_GREEN;
            elapsed_seconds <= 16'd0;
            extension_elapsed <= 16'd0;
            release_remaining <= 16'd0;
            extension_phase <= EXT_NORMAL;
            flash_elapsed_seconds <= 16'd0;
            flash_on        <= 1'b1;
            ped_pending     <= 1'b0;
            ped_return_state <= ST_NS_GREEN;
            config_pending  <= 1'b0;
            ew_red_elapsed  <= 16'd0;
            ns_red_elapsed  <= 16'd0;
        end else begin
            // Extension state is meaningful only in an ordinary vehicle-green
            // phase. Any higher-priority mode request cancels it immediately.
            if (!vehicle_green || fault_mode || config_mode || night_mode) begin
                extension_elapsed <= 16'd0;
                release_remaining <= 16'd0;
                extension_phase   <= EXT_NORMAL;
            end

            if (tick_1s) begin
                if ((state == ST_EW_GREEN) || (state == ST_EW_YELLOW) ||
                    (state == ST_NIGHT))
                    ew_red_elapsed <= 16'd0;
                else if (ew_red_elapsed != 16'hffff)
                    ew_red_elapsed <= ew_red_elapsed + 1'b1;

                if ((state == ST_NS_GREEN) || (state == ST_NS_YELLOW))
                    ns_red_elapsed <= 16'd0;
                else if (ns_red_elapsed != 16'hffff)
                    ns_red_elapsed <= ns_red_elapsed + 1'b1;
            end

            if (ped_request && (state != ST_PED_GO))
                ped_pending <= 1'b1;

            // A synchronized fault has priority over every operating mode and
            // may immediately replace the current indication with flashing
            // red. Its timer is independent of the paused normal sequence.
            if (fault_mode && (state != ST_FAULT)) begin
                state                 <= ST_FAULT;
                elapsed_seconds       <= 16'd0;
                flash_elapsed_seconds <= 16'd0;
                flash_on              <= 1'b1;
            end else if (state == ST_FAULT) begin
                elapsed_seconds <= 16'd0;

                if (!fault_mode) begin
                    // Always insert a complete all-red interval after a fault.
                    // A still-active night request is considered only after
                    // this clearance has completed.
                    state                 <= ST_FAULT_CLEAR;
                    flash_elapsed_seconds <= 16'd0;
                    flash_on              <= 1'b0;
                end else if (tick_1s) begin
                    if (flash_elapsed_seconds + 1'b1 >= FLASH_SECONDS) begin
                        flash_elapsed_seconds <= 16'd0;
                        flash_on              <= ~flash_on;
                    end else begin
                        flash_elapsed_seconds <= flash_elapsed_seconds + 1'b1;
                    end
                end
            end else if (state == ST_CONFIG) begin
                elapsed_seconds       <= 16'd0;
                flash_elapsed_seconds <= 16'd0;
                flash_on              <= 1'b1;
                config_pending        <= 1'b0;

                if (!config_mode) begin
                    state           <= ST_CONFIG_EXIT;
                    elapsed_seconds <= 16'd0;
                end
            end else if ((state == ST_FAULT_CLEAR) ||
                         (state == ST_NIGHT_CLEAR) ||
                         (state == ST_CONFIG_ENTER) ||
                         (state == ST_CONFIG_EXIT)) begin
                flash_elapsed_seconds <= 16'd0;
                flash_on              <= 1'b1;

                if (tick_1s && transition_due && transition_allowed) begin
                    state           <= next_state;
                    elapsed_seconds <= 16'd0;
                    if (next_state == ST_CONFIG_ENTER)
                        config_pending <= 1'b0;
                end else if (tick_1s) begin
                    elapsed_seconds <= elapsed_seconds + 1'b1;
                end
            // A settings request from green first enters yellow. From yellow,
            // it waits for that warning interval to finish. All other modes
            // can safely move directly to a fresh all-red entry interval.
            end else if (config_mode || config_pending) begin
                flash_elapsed_seconds <= 16'd0;
                flash_on              <= 1'b1;

                if (state == ST_EW_GREEN) begin
                    state            <= ST_EW_YELLOW;
                    elapsed_seconds  <= 16'd0;
                    config_pending   <= 1'b1;
                end else if (state == ST_NS_GREEN) begin
                    state            <= ST_NS_YELLOW;
                    elapsed_seconds  <= 16'd0;
                    config_pending   <= 1'b1;
                end else if ((state == ST_EW_YELLOW) ||
                             (state == ST_NS_YELLOW)) begin
                    config_pending <= 1'b1;
                    if (tick_1s && transition_due) begin
                        state           <= ST_CONFIG_ENTER;
                        elapsed_seconds <= 16'd0;
                        config_pending  <= 1'b0;
                    end else if (tick_1s) begin
                        elapsed_seconds <= elapsed_seconds + 1'b1;
                    end
                end else begin
                    state           <= ST_CONFIG_ENTER;
                    elapsed_seconds <= 16'd0;
                    config_pending  <= 1'b0;
                end
            // Night mode has priority over the normal traffic and pedestrian
            // sequence after fault and configuration requests are handled.
            end else if (night_mode && (state != ST_NIGHT)) begin
                state                 <= ST_NIGHT;
                elapsed_seconds       <= 16'd0;
                flash_elapsed_seconds <= 16'd0;
                flash_on              <= 1'b1;
            end else if (state == ST_NIGHT) begin
                elapsed_seconds <= 16'd0;

                if (!night_mode) begin
                    // Leaving night mode always inserts a full all-red safety
                    // interval before restarting from EW green.
                    state                 <= ST_NIGHT_CLEAR;
                    flash_elapsed_seconds <= 16'd0;
                    flash_on              <= 1'b0;
                end else if (tick_1s) begin
                    if (flash_elapsed_seconds + 1'b1 >= FLASH_SECONDS) begin
                        flash_elapsed_seconds <= 16'd0;
                        flash_on              <= ~flash_on;
                    end else begin
                        flash_elapsed_seconds <= flash_elapsed_seconds + 1'b1;
                    end
                end
            end else begin
                flash_elapsed_seconds <= 16'd0;
                flash_on              <= 1'b1;

                if (tick_1s && transition_due && transition_allowed) begin
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
                                if ((elapsed_seconds + 1'b1 >= green_seconds) &&
                                    extension_demand &&
                                    (extension_window_seconds != 16'd0)) begin
                                    extension_phase   <= EXT_HOLD;
                                    extension_elapsed <= 16'd0;
                                end
                            end
                            EXT_HOLD: begin
                                if (!extension_demand ||
                                    (extension_elapsed + 1'b1 >=
                                     extension_window_seconds)) begin
                                    extension_phase    <= EXT_RELEASE;
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
                            default: begin
                                extension_elapsed <= 16'd0;
                                release_remaining <= 16'd0;
                                extension_phase   <= EXT_NORMAL;
                            end
                        endcase
                    end else begin
                        elapsed_seconds <= elapsed_seconds + 1'b1;
                    end
                end
            end
        end
    end

    always @(*) begin
        base_remaining = 16'd0;
        red_remaining  = 16'd0;

        if ((state == ST_NIGHT) || (state == ST_FAULT) ||
            (state == ST_CONFIG)) begin
            remaining_seconds = 16'd0;
        end else if (vehicle_green && (extension_phase == EXT_HOLD)) begin
            remaining_seconds = 16'd0;
        end else if (vehicle_green && (extension_phase == EXT_RELEASE)) begin
            remaining_seconds = release_remaining;
        end else if (vehicle_green &&
                     ped_request_active &&
                     (elapsed_seconds < MIN_GREEN_SECONDS)) begin
            remaining_seconds = MIN_GREEN_SECONDS - elapsed_seconds;
        end else if (vehicle_green && ped_request_active) begin
            remaining_seconds = 16'd1;
        end else begin
            if (elapsed_seconds < state_duration)
                base_remaining = state_duration - elapsed_seconds;

            if ((next_state == ST_EW_GREEN) &&
                (ew_red_elapsed < min_red_seconds))
                red_remaining = min_red_seconds - ew_red_elapsed;
            else if ((next_state == ST_NS_GREEN) &&
                     (ns_red_elapsed < min_red_seconds))
                red_remaining = min_red_seconds - ns_red_elapsed;

            if (red_remaining > base_remaining)
                remaining_seconds = red_remaining;
            else
                remaining_seconds = base_remaining;
        end
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
            ST_NIGHT: begin
                ew_red   = flash_on;
                ew_green = flash_on;
                ns_red   = flash_on;
                ns_green = 1'b0;
            end
            ST_FAULT: begin
                ew_red   = flash_on;
                ew_green = 1'b0;
                ns_red   = flash_on;
                ns_green = 1'b0;
            end
            default: begin
                ew_red   = 1'b1;
                ns_red   = 1'b1;
            end
        endcase
    end

endmodule
