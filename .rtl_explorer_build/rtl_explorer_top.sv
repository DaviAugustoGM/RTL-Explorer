module rtl_explorer_top(
    input logic u_clock_generator_3__clk,
    input logic u_input_signal_2__out,
    input logic u_input_signal_1__out,
    input logic [7:0] u_input_signal_5__out,
    output logic [7:0] u_producer__data,
    output logic u_producer__valid
);

    logic net_1;
    logic net_2;
    logic net_3;
    logic [7:0] net_4;
    logic net_5;
    logic [7:0] net_6;

    assign net_1 = u_clock_generator_3__clk;
    assign net_2 = u_input_signal_2__out;
    assign net_3 = u_input_signal_1__out;
    assign net_6 = u_input_signal_5__out;
    assign u_producer__data = net_4;
    assign u_producer__valid = net_5;

    producer u_producer (
        .clk(net_1),
        .rst_n(net_2),
        .enable(net_3),
        .data(net_4),
        .valid(net_5)
    );

endmodule
