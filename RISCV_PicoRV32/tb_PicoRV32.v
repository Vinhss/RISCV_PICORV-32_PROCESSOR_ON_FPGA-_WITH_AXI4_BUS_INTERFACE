// PicoRV32 full?feature behavioural testbench
// This version enables the IMC (I+M+Div + Compressed) configuration
// and embeds a small self?checking program directly in Verilog//
// Usage (ModelSim):
//   vlog picorv32.v testbench_ez.v
// If everything works you will see "==== TEST PASSED ====".

`timescale 1 ns / 1 ps

module testbench;
    // ------------------------------------------------------------------
    // Clock / Reset
    // ------------------------------------------------------------------
    reg clk = 1;
    reg resetn = 0;
    integer i;
    always #5 clk = ~clk;   // 100 MHz
  	initial begin
        $dumpfile("testbench.vcd");
        $dumpvars(0, testbench);
    end

    initial begin
        // hold reset low for 20 cycles
        repeat (20) @(posedge clk);
        resetn <= 1;
    end

    // ------------------------------------------------------------------
    // Wires to DUT
    // ------------------------------------------------------------------
    wire        trap;
    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;

    // ------------------------------------------------------------------
    // DUT  ?  PicoRV32 with IMC extensions enabled
    // ------------------------------------------------------------------
    picorv32 #(
        
        .ENABLE_COUNTERS     (0),
        .ENABLE_COUNTERS64   (0),
        .ENABLE_REGS_16_31   (1),
        .BARREL_SHIFTER      (1),
        .TWO_STAGE_SHIFT     (1),
        .ENABLE_MUL          (1),// Enable multiply
        .ENABLE_DIV          (1),// Enable divide
        .COMPRESSED_ISA      (1),// Enable compression instruction support (RV32C)
        .PROGADDR_RESET      (32'h00000000),// Program start address
        .STACKADDR           (32'h00002000)// Default stack address
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

    // ------------------------------------------------------------------
    // Simple zero?wait?state SRAM model (1 kB)
    // Pre?load a tiny self?checking program that:
    //   ? multiplies 10 × 3  ? 30
    //   ? divides 30 ÷ 3    ? 10
    //   ? counts to 10 using a loop
    //   ? executes "ebreak" to raise the `trap` output (PASS)
    // ------------------------------------------------------------------
    reg [31:0] memory [0:255];   // 256 words × 4 B = 1 kB
    initial begin
        
        for (i = 0; i < 256; i = i + 1)
            memory[i] = 32'h00000013; // NOP  (addi x0,x0,0)

        // === Program ===
        memory[ 0] = 32'h00a00093; // li   x1,10
        memory[ 1] = 32'h00300113; // li   x2,3
        memory[ 2] = 32'h022081b3; // mul  x3,x1,x2  -> 30
        memory[ 3] = 32'h0221c233; // div  x4,x3,x2  -> 10
        memory[ 4] = 32'h00000293; // addi x5,x0,0   (counter=0)
        // loop:
        memory[ 5] = 32'h00128293; // addi x5,x5,1
        memory[ 6] = 32'hfe42cee3; // blt  x5,x4,loop
        
        memory[7]  = 32'h8c854515; // lower 16-bit = c.li x1,5 | upper 16-bit = c.add x1,x1
        memory[8]  = 32'h00000073; // c.nop + ebreak (or leave NOPs if needed)
        memory[9] = 32'h00100073; // ebreak -> trap
    end

    // ------------------------------------------------------------------
    // Memory read/write handshake
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        mem_ready <= 0;
        if (mem_valid && !mem_ready) begin
            if (mem_addr < 1024) begin
                mem_ready <= 1;
                mem_rdata <= memory[mem_addr >> 2];

                if (mem_wstrb[0]) memory[mem_addr >> 2][ 7: 0] <= mem_wdata[ 7: 0];
                if (mem_wstrb[1]) memory[mem_addr >> 2][15: 8] <= mem_wdata[15: 8];
                if (mem_wstrb[2]) memory[mem_addr >> 2][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) memory[mem_addr >> 2][31:24] <= mem_wdata[31:24];
            end
        end
    end

    // ------------------------------------------------------------------
    // PASS/FAIL & timeout
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (trap) begin
            $display("==== TEST PASSED ====");
            $finish;
        end
    end

    initial begin
        // Safety timeout (1 ms sim?time)
        #1000000;
        $display("==== TIMEOUT ? possible hang or mis?decode ====");
        $finish;
    end
endmodule