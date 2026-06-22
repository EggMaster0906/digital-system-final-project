`timescale 1ns/1ps

// Produces a one-clock-cycle pulse at a configurable interval.
module clock_divider #(
    parameter integer CLOCK_HZ = 50_000_000
)(
    input  wire clk,
    input  wire reset_n,
    output reg  tick_1s
);

    reg [31:0] clock_count;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            clock_count <= 32'd0;
            tick_1s     <= 1'b0;
        end else if (clock_count >= CLOCK_HZ - 1) begin
            clock_count <= 32'd0;
            tick_1s     <= 1'b1;
        end else begin
            clock_count <= clock_count + 1'b1;
            tick_1s     <= 1'b0;
        end
    end

endmodule
