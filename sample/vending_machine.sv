module vending_machine (
    input  logic clk,
    input  logic rst,

    // Entrada de moedas
    input  logic [1:0] coin,
    // 00 = nenhuma
    // 01 = R$1
    // 10 = R$2
    // 11 = reservado

    // Seleção de produtos
    input  logic selA,
    input  logic selB,
    input  logic selC,

    // Produtos disponíveis
    output logic produtoA_ok,
    output logic produtoB_ok,
    output logic produtoC_ok,

    // Produto liberado
    output logic vend,

    // Crédito atual
    output logic [2:0] credito
);

logic [2:0] credito_next;
logic       vend_next;

//====================================================
// Registradores
//====================================================
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        credito <= 3'd0;
        vend    <= 1'b0;
    end
    else begin
        credito <= credito_next;
        vend    <= vend_next;
    end
end

//====================================================
// Lógica combinacional
//====================================================
always_comb begin

    // Valores padrão
    credito_next = credito;
    vend_next    = 1'b0;

    // Inserção de moedas
    case (coin)
        2'b01: credito_next = credito_next + 3'd1;
        2'b10: credito_next = credito_next + 3'd2;
        default: ;
    endcase

    // Compra dos produtos
    if (selA && (credito_next >= 1)) begin
        credito_next = credito_next - 3'd1;
        vend_next = 1'b1;
    end
    else if (selB && (credito_next >= 2)) begin
        credito_next = credito_next - 3'd2;
        vend_next = 1'b1;
    end
    else if (selC && (credito_next >= 3)) begin
        credito_next = credito_next - 3'd3;
        vend_next = 1'b1;
    end

    // Produtos disponíveis
    produtoA_ok = (credito_next >= 1);
    produtoB_ok = (credito_next >= 2);
    produtoC_ok = (credito_next >= 3);

end

endmodule
