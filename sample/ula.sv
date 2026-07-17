module ula (
    input  logic [7:0] a,
    input  logic [7:0] b,
    input  logic [2:0] op,
    output logic [7:0] result,
    output logic       zero,
    output logic       carry,
    output logic       negative
);
    logic [8:0] extended;

    always_comb begin
        extended = 9'd0;
        result = 8'd0;
        carry = 1'b0;

        unique case (op)
            3'b000: begin
                extended = {1'b0, a} + {1'b0, b};
                result = extended[7:0];
                carry = extended[8];
            end
            3'b001: begin
                extended = {1'b0, a} - {1'b0, b};
                result = extended[7:0];
                carry = extended[8];
            end
            3'b010: result = a & b;
            3'b011: result = a | b;
            3'b100: result = a ^ b;
            3'b101: result = a << 1;
            3'b110: result = a >> 1;
            default: result = b;
        endcase
    end

    assign zero = (result == 8'd0);
    assign negative = result[7];
endmodule
