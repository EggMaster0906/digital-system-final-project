`timescale 1ns/1ps

// Synchronizes and debounces an active-low push button, then emits one pulse
// for each complete press. Holding the button low cannot retrigger the pulse.
module button_conditioner #(
    parameter integer DEBOUNCE_CYCLES = 1_000_000
)(
    input  wire clk,
    input  wire reset_n,
    input  wire button_n,
    output reg  press_pulse
);

    reg        sync_meta;
    reg        sync_button_n;
    reg        stable_button_n;
    reg [31:0] debounce_count;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sync_meta       <= 1'b1;
            sync_button_n   <= 1'b1;
            stable_button_n <= 1'b1;
            debounce_count  <= 32'd0;
            press_pulse     <= 1'b0;
        end else begin
            sync_meta     <= button_n;
            sync_button_n <= sync_meta;
            press_pulse   <= 1'b0;

            if (sync_button_n == stable_button_n) begin
                debounce_count <= 32'd0;
            end else if ((DEBOUNCE_CYCLES <= 1) ||
                         (debounce_count >= DEBOUNCE_CYCLES - 1)) begin
                stable_button_n <= sync_button_n;
                debounce_count  <= 32'd0;

                if (!sync_button_n)
                    press_pulse <= 1'b1;
            end else begin
                debounce_count <= debounce_count + 1'b1;
            end
        end
    end

endmodule
