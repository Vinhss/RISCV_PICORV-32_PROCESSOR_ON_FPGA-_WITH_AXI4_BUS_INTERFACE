

module top_fpga_picorv32 (
    input         CLOCK_50,        // 50 MHz clock
    input  [3:0]  KEY,            // Active-low pushbuttons
    input  [17:0] SW,             // Switches
    output [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7, // Seven-segment displays
    output [17:0] LEDR,           // Red LEDs
    output [7:0]  LEDG            // Green LEDs
);

    // Internal signals
    reg        clk;
    wire       resetn;
    wire       trap;
    wire       mem_valid;
    wire       mem_instr;
    reg       mem_ready;
    wire [31:0] mem_addr;         // Directly use PicoRV32's mem_addr
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;
    integer i;

    // Debouncing for KEY[1] (clock control) using CLOCK_50
    reg [19:0] debounce_counter_k1;
    reg        key1_debounced;
    reg        key1_prev;
    reg        key1_pulse;

    always @(posedge CLOCK_50) begin
        if (KEY[1] != key1_prev) begin
            debounce_counter_k1 <= 20'h0;
        end else if (debounce_counter_k1 < 20'hFFFFF) begin
            debounce_counter_k1 <= debounce_counter_k1 + 1;
        end else begin
            key1_debounced <= KEY[1];
        end
        key1_prev <= KEY[1];
    end

    // Generate single-cycle pulse on KEY[1] press (active-low)
    reg key1_debounced_prev;
    always @(posedge CLOCK_50) begin
        key1_debounced_prev <= key1_debounced;
        key1_pulse <= (key1_debounced_prev == 1'b1 && key1_debounced == 1'b0);
    end

    // Debouncing for KEY[0] (step control) using CLOCK_50
    reg [19:0] debounce_counter_k0;
    reg        key0_debounced;
    reg        key0_prev;
    reg        key0_pulse;

    always @(posedge CLOCK_50) begin
        if (KEY[0] != key0_prev) begin
            debounce_counter_k0 <= 20'h0;
        end else if (debounce_counter_k0 < 20'hFFFFF) begin
            debounce_counter_k0 <= debounce_counter_k0 + 1;
        end else begin
            key0_debounced <= KEY[0];
        end
        key0_prev <= KEY[0];
    end

    // Generate single-cycle pulse on KEY[0] press (active-low)
    reg key0_debounced_prev;
    always @(posedge CLOCK_50) begin
        key0_debounced_prev <= key0_debounced;
        key0_pulse <= (key0_debounced_prev == 1'b1 && key0_debounced == 1'b0);
    end

    // Count KEY[1] presses
    reg [7:0] key1_count;
    always @(posedge CLOCK_50) begin
        if (SW[17]) begin
            key1_count <= 8'h0; // Reset count when SW[17] is HIGH
        end else if (key1_pulse) begin
            key1_count <= key1_count + 1; // Increment on KEY[1] press
        end
    end

    // Clock generation: Toggle on KEY[0] or KEY[1] press
    always @(posedge CLOCK_50) begin
        if (key1_pulse || key0_pulse) begin
            clk <= ~clk; // Toggle clock on debounced KEY[1] or KEY[0] press
        end
    end

    // Asynchronous reset using SW[17] (active-low for PicoRV32)
    assign resetn = ~SW[17]; // Changed to active-low (LOW when SW[17] is HIGH)

    // Instantiate the PicoRV32 DUT
    picorv32 #(
        .ENABLE_COUNTERS     (0),
        .ENABLE_COUNTERS64   (0),
        .ENABLE_REGS_16_31   (1),
        .BARREL_SHIFTER      (1),
        .TWO_STAGE_SHIFT     (1),
        .ENABLE_MUL          (1),
        .ENABLE_DIV          (1),
        .COMPRESSED_ISA      (1),
        .PROGADDR_RESET      (32'h00000000),
        .STACKADDR           (32'h00002000)
    ) uut (
        .clk        (clk),
        .resetn     (resetn),
        .trap       (trap),
        .mem_valid  (mem_valid),
        .mem_instr  (mem_instr),
        .mem_ready  (mem_ready),
        .mem_addr   (mem_addr), 
        .mem_wdata  (mem_wdata),
        .mem_wstrb  (mem_wstrb),
        .mem_rdata  (mem_rdata)
    );

    // SRAM model (1 kB)
    reg [31:0] memory [0:255];

    // Pre-load program
    initial begin
        for (i = 0; i < 256; i = i + 1)
            memory[i] = 32'h00000013; // NOP
            
        memory[ 0] = 32'h00a00093; // li   x1,10
        memory[ 1] = 32'h00300113; // li   x2,3
        memory[ 2] = 32'h022081b3; // mul  x3,x1,x2  -> 30
        memory[ 3] = 32'h0221c233; // div  x4,x3,x2  -> 10
        // ---- NEW: test Data-Memory Access ----
        memory[ 4] = 32'h00302023; // sw   x3,0(x0)   ; ghi 30 xu?ng ??a ch? 0
        memory[ 5] = 32'h00002303; // lw   x6,0(x0)   ; ??c l?i 30 vào x6
        memory[ 6] = 32'h00000293; // addi x5,x0,0   (counter=0)
        // loop:
        memory[ 7] = 32'h00128293; // addi x5,x5,1
        memory[ 8] = 32'hfe42cee3; // blt  x5,x4,loop
        
        memory[9]  = 32'hc0054591; // lower 16-bit = c.li x1,5 
        memory[10]  = 32'h00000073; // c.nop + ebreak (or leave NOPs if needed)
        memory[11] = 32'h00100073; // ebreak -> trap
    end

    // Memory read/write handshake
    always @(posedge clk) begin
        mem_ready <= 0;
        if (mem_valid && !mem_ready) begin
            if (mem_addr < 1024) begin
                mem_ready <= 1;
                mem_rdata <= memory[mem_addr >> 2];
                if (mem_wstrb[0]) memory[mem_addr >> 2][7:0]   <= mem_wdata[7:0];
                if (mem_wstrb[1]) memory[mem_addr >> 2][15:8]  <= mem_wdata[15:8];
                if (mem_wstrb[2]) memory[mem_addr >> 2][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) memory[mem_addr >> 2][31:24] <= mem_wdata[31:24];
            end
        end
    end

    // Multiplexer for signal selection
    reg [31:0] display_data;
    always @(*) begin
        case (SW[2:0])
            3'b000: display_data = mem_addr;    // Memory address
            3'b001: display_data = mem_wdata;   // Write data
            3'b010: display_data = {28'b0, mem_wstrb}; // Write strobe
            3'b011: display_data = mem_rdata;   // Read data
            3'b100: display_data = memory[2];    // show result
            default: display_data = 32'h0;
        endcase
    end

    // Seven-segment decoders
    seg7_decoder hex0 (.data(display_data[3:0]),   .seg(HEX0));
    seg7_decoder hex1 (.data(display_data[7:4]),   .seg(HEX1));
    seg7_decoder hex2 (.data(display_data[11:8]),  .seg(HEX2));
    seg7_decoder hex3 (.data(display_data[15:12]), .seg(HEX3));
    seg7_decoder hex4 (.data(display_data[19:16]), .seg(HEX4));
    seg7_decoder hex5 (.data(display_data[23:20]), .seg(HEX5));
    seg7_decoder hex6 (.data(display_data[27:24]), .seg(HEX6));
    seg7_decoder hex7 (.data(display_data[31:28]), .seg(HEX7));

    // LEDR outputs for signals and debug
    assign LEDR[0] = mem_valid;    // mem_valid
    assign LEDR[1] = mem_instr;    // mem_instr
    assign LEDR[2] = mem_ready;    // mem_ready
    assign LEDR[3] = trap;         // trap
    assign LEDR[4] = clk;          // Debug: Show clock state
    assign LEDR[5] = key0_pulse;   // Debug: Show KEY[0] pulse
    assign LEDR[6] = key1_pulse;   // Debug: Show KEY[1] pulse
    assign LEDR[16:7] = SW[16:7];  // Mirror switches
    assign LEDR[17] = 1'b0;        // SW[17] used for reset

    // LEDG outputs for KEY[1] press count
    assign LEDG[7:0] = key1_count;


endmodule

// Seven-segment decoder module
module seg7_decoder (
	input  [3:0] data,
	output reg [6:0] seg
);
	always @(*) begin
		case (data)
			4'h0: seg = 7'b1000000; // 0
			4'h1: seg = 7'b1111001; // 1
			4'h2: seg = 7'b0100100; // 2
			4'h3: seg = 7'b0110000; // 3
			4'h4: seg = 7'b0011001; // 4
			4'h5: seg = 7'b0010010; // 5
			4'h6: seg = 7'b0000010; // 6
			4'h7: seg = 7'b1111000; // 7
			4'h8: seg = 7'b0000000; // 8
			4'h9: seg = 7'b0010000; // 9
			4'hA: seg = 7'b0001000; // A
			4'hB: seg = 7'b0000011; // b
			4'hC: seg = 7'b1000110; // C
			4'hD: seg = 7'b0100001; // d
			4'hE: seg = 7'b0000110; // E
			4'hF: seg = 7'b0001110; // F
			default: seg = 7'b1111111; // Off
		endcase
	end
endmodule


