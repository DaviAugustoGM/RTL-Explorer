module adder (
    input  logic [7:0] a,
    input  logic [7:0] b,
    input  logic       carry_in,
    output logic [7:0] sum,
    output logic       carry_out
);
    logic [8:0] result;

    always_comb begin
        result = {1'b0, a} + {1'b0, b} + carry_in;
        sum = result[7:0];
        carry_out = result[8];
    end
endmodule
