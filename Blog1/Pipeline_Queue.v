module Pipeline_queue #(parameter data_width = 16, max_entries = 4)(
    //Inputs
    input clk, rst, 
    input valid1, valid2,
    input [15:0] data1, data2,
    input [1:0] stall_in,
    input FLUSH,
    //Outputs
    output reg valid_out1, valid_out2,
    output reg [15:0] data_out1, data_out2,
    output reg [1:0] stall_out
    );
    
    localparam DATA_WIDTH = data_width, ADDR_WIDTH = $clog2(max_entries);
    
    reg [DATA_WIDTH - 1:0] data [max_entries - 1:0];
    reg [ADDR_WIDTH - 1:0] head, tail;
    reg [ADDR_WIDTH - 1:0] next_head, next_tail;
    wire [max_entries - 1:0] Busy;
    reg [max_entries - 1:0] Busy1, Busy2;
    wire full, empty;
    reg n_valid1, n_valid2;
    
    //Required variables
    assign full = ((sum(!Busy) - valid_out1 - valid_out2) == max_entries);
    assign empty = ((sum(!Busy) - valid1 - valid2) == 0);
    assign Busy = Busy1 ^ Busy2;
    
    //Tail Logic (Data IN)
    always @ (*) begin
        if (rst) next_tail <= 0;
        else begin
            if (!full) begin
                if (valid1 & valid2) next_tail <= tail + 2;
                else if (valid1 & !valid2) next_tail <= tail + 1;
                else next_tail <= tail;
            end
            else next_tail <= tail;
        end
    end
    always @ (posedge clk) begin
        if (rst | FLUSH) tail <= 0;
        else tail <= next_tail;
    end
    always @ (posedge clk) begin
        if (rst | FLUSH) Busy1 <= {max_entries{1'b1}};
        else begin
            if (!full) begin
                if (valid1 & valid2) {Busy1[tail], Busy1[tail + 1]} <= {!Busy1[tail], !Busy[tail + 1]};
                else if (valid1 & valid2) Busy1[tail] <= !Busy1[tail];
                else Busy1 <= Busy;
            end
            else Busy1 <= Busy1;
        end
    end
    
    //Head Logic (Data OUT)
    always @ (*) begin
        if (rst) next_head <= 0;
        else begin
            if (!empty) begin
                if (!(|stall_in)) begin
                    if ((Busy[head] & Busy[head + 1]) | (Busy[head] & valid1) | (valid1 & valid2)) next_head <= head + 2;
                    else if (Busy[head] | valid1) next_head <= head + 1;
                    else next_head <= head;
                end
                else if (&stall_in) next_head <= head;
                else if (stall_in[1] & (Busy[head] | valid1)) next_head <= head + 1;
                else next_head <= head;
            end
            else next_head <= head;
        end
    end
    always @ (posedge clk) begin
        if (rst | FLUSH) Busy2 <= {max_entries{1'b1}};
        else begin
            if (!empty) begin
                if (!(|stall_in)) begin
                    if ((Busy[head] & Busy[head + 1]) | (Busy[head] & valid1) | (valid1 & valid2))
                        {Busy2[head], Busy2[head + 1]} <= {!Busy2[head], Busy2[head + 1]};
                    else if (Busy[head] | valid1)
                        Busy2[head] <= !Busy[head];
                    else Busy2 <= Busy2;
                end
                else if (&stall_in) Busy2 <= Busy2;
                else if (stall_in[1] & (Busy[head] | valid1)) Busy2[head] <= !Busy2[head];
                else Busy2 <= Busy2;
            end
            else Busy2 <= Busy2;
        end
    end
    always @ (posedge clk) begin
        if (rst | FLUSH) head <= 0;
        else head <= next_head;
    end
    
    //Data Output
    always @ (*) begin
        if (rst | FLUSH) {n_valid1, n_valid2} <= 2'b00;
        else begin
            if (Busy[head] & Busy[head + 1]) {n_valid1, n_valid2} <= 2'b11;
            else if (Busy[head] & valid1) {n_valid1, n_valid2} <= 2'b11;
            else if (valid1 & valid2) {n_valid1, n_valid2} <= 2'b11;
            else if (Busy[head]) {n_valid1, n_valid2} <= 2'b10;
            else if (valid1) {n_valid1, n_valid2} <= 2'b10;
            else {n_valid1, n_valid2} <= 2'b00;
        end
    end
    always @ (posedge clk) begin
        if (rst | FLUSH) {valid_out1, valid_out2} <= 2'b00;
        else {valid_out1, valid_out2} <= {n_valid1 & !stall_in[0], n_valid2 & !stall_in[1]};
    end
    always @ (posedge clk) begin
        if (rst | FLUSH) begin
            data_out1 <= {DATA_WIDTH{1'b0}};
            data_out2 <= {DATA_WIDTH{1'b0}};
        end
        else begin
            if (Busy[head] & Busy[head + 1]) begin
                data_out1 <= data[head];
                data_out2 <= data[head + 1];
            end
            else if (Busy[head] & valid1) begin
                data_out1 <= data[head];
                data_out2 <= data1;
            end
            else if (valid1 & valid2) begin
                data_out1 <= data1;
                data_out2 <= data2;
            end
            else if (Busy[head]) begin
                data_out1 <= data[head];
                data_out2 <= {DATA_WIDTH{1'b0}};
            end
            else if (valid1) begin
                data_out1 <= data1;
                data_out2 <= {DATA_WIDTH{1'b0}};
            end
            else begin
                data_out1 <= {DATA_WIDTH{1'b0}};
                data_out2 <= {DATA_WIDTH{1'b0}};
            end
        end
    end
    
    //Stall Logic (To stall preceding pipeline stage)
    always @ (*) begin
        if (sum(Busy) <= 1) begin
            if (sum(Busy) == 3'd0) begin
                stall_out <= 2'b11;
            end
            else if (sum(Busy) == 3'd1) begin
                if (n_valid2) stall_out <= 2'b10;
                else stall_out <= 2'b00;
            end
            else stall_out <= 2'b00;
        end
        else stall_out <= 2'b00;
    end
    
    //Sum Function
    function [ADDR_WIDTH:0] sum(input [max_entries-1:0] a);
        integer i;
        reg [ADDR_WIDTH:0] count;
        begin
            count = 0;
            for (i = 0; i < max_entries; i = i + 1) begin
                count = count + a[i];
            end
            sum = count;
        end
    endfunction

endmodule