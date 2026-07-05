module producer (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       enable,
    output logic [7:0] data,
    output logic       valid
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data  <= 8'h00;
            valid <= 1'b0;
        end else begin
            valid <= enable;
            if (enable) begin
                data <= data + 8'h01;
            end
        end
    end
endmodule
