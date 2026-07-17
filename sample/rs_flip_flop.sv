module rs_flip_flop (
    input  logic clk,
    input  logic rst,
    input  logic set,
    input  logic reset,
    output logic q,
    output logic q_n,
    output logic invalid
);
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            q <= 1'b0;
        end else begin
            unique case ({set, reset})
                2'b10: q <= 1'b1;
                2'b01: q <= 1'b0;
                2'b00: q <= q;
                default: q <= q;
            endcase
        end
    end

    assign q_n = ~q;
    assign invalid = set && reset;
endmodule
