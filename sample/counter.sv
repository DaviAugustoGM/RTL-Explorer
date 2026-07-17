module counter (
    input  logic       clk,
    input  logic       rst,
    input  logic       enable,
    input  logic       up,
    output logic [3:0] count,
    output logic       carry
);
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            count <= 4'd0;
        end else if (enable) begin
            if (up) begin
                count <= count + 4'd1;
            end else begin
                count <= count - 4'd1;
            end
        end
    end

    assign carry = enable && ((up && count == 4'hF) || (!up && count == 4'h0));
endmodule
