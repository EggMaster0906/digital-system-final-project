`timescale 1ns/1ps

// Fixed-time traffic-light controller for a two-direction intersection.
module traffic_controller #(
    parameter [15:0] GREEN_SECONDS    = 16'd10,
    parameter [15:0] MIN_GREEN_SECONDS = 16'd5,
    parameter [15:0] YELLOW_SECONDS   = 16'd3,
    parameter [15:0] ALL_RED_SECONDS  = 16'd1,
    parameter [15:0] PED_SECONDS      = 16'd5
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        tick_1s,
    input  wire        ped_request,
    output reg  [2:0]  state,
    output reg  [15:0] remaining_seconds,
    output reg         ped_pending,
    output reg  [2:0]  ped_return_state,
    output reg         ew_red,
    output reg         ew_green,
    output reg         ns_red,
    output reg         ns_green,
    output reg         ped_stop,
    output reg         ped_go
);

    localparam [2:0] ST_EW_GREEN  = 3'd0;
    localparam [2:0] ST_EW_YELLOW = 3'd1;
    localparam [2:0] ST_ALL_RED_1 = 3'd2;
    localparam [2:0] ST_NS_GREEN  = 3'd3;
    localparam [2:0] ST_NS_YELLOW = 3'd4;
    localparam [2:0] ST_ALL_RED_2 = 3'd5;
    localparam [2:0] ST_PED_GO    = 3'd6;
    localparam [2:0] ST_PED_CLEAR = 3'd7;

    reg [15:0] elapsed_seconds;
    reg [15:0] state_duration;
    reg [2:0]  next_state;
    reg        transition_due;
    wire       ped_request_active = ped_pending | ped_request;

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

        // A waiting pedestrian may shorten only a vehicle green phase, and
        // never below the configured minimum safe green time.
        if (((state == ST_EW_GREEN) || (state == ST_NS_GREEN)) &&
            ped_request_active &&
            (elapsed_seconds + 1'b1 >= MIN_GREEN_SECONDS))
            transition_due = 1'b1;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= ST_EW_GREEN;
            elapsed_seconds <= 16'd0;
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
            end else if (tick_1s) begin
                elapsed_seconds <= elapsed_seconds + 1'b1;
            end
        end
    end

    always @(*) begin
        if (((state == ST_EW_GREEN) || (state == ST_NS_GREEN)) &&
            ped_request_active && (elapsed_seconds < MIN_GREEN_SECONDS))
            remaining_seconds = MIN_GREEN_SECONDS - elapsed_seconds;
        else if (((state == ST_EW_GREEN) || (state == ST_NS_GREEN)) &&
                 ped_request_active)
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
