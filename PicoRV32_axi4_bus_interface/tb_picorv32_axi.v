// ============================================================================
//  PicoRV32 AXI‑Lite Testbench (pure Verilog, no .hex) – RV32IMC feature sweep
//  * Tests PicoRV32 with IMC extensions (I+M+Div + Compressed)
//  * Drives a minimal AXI‑Lite SRAM (4 KiB) that responds in a single cycle
//  * Program is hard‑coded below – exercises I‑subset, MUL/DIV, and
//    a pair of compressed instructions (C.ADDI & C.MV)
//  * Results are written to word addresses 0x100 – 0x110 and verified
//  * Pass/Fail + plenty of wave‑friendly $display traces
// ============================================================================

module picorv32_axi_tb;

    // ----------------------------------------------------------------------
    //  Clock & Reset
    // ----------------------------------------------------------------------
    reg clk;
    reg resetn;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;    // 100 MHz
    end

    // hold reset for a few cycles
    initial begin
        resetn = 0;
        #40;
        resetn = 1;
    end

    // ----------------------------------------------------------------------
    //  DUT <-> AXI4‑Lite signals
    // ----------------------------------------------------------------------
    wire        mem_axi_awvalid;
    wire        mem_axi_awready;
    wire [31:0] mem_axi_awaddr;
    wire [ 2:0] mem_axi_awprot;

    wire        mem_axi_wvalid;
    wire        mem_axi_wready;
    wire [31:0] mem_axi_wdata;
    wire [ 3:0] mem_axi_wstrb;

    wire        mem_axi_bvalid;
    wire        mem_axi_bready;

    wire        mem_axi_arvalid;
    wire        mem_axi_arready;
    wire [31:0] mem_axi_araddr;
    wire [ 2:0] mem_axi_arprot;

    wire        mem_axi_rvalid;
    wire        mem_axi_rready;
    wire [31:0] mem_axi_rdata;

    // IRQ & Trace (unused)
    reg  [31:0] irq;
    wire [31:0] eoi;
    wire        trace_valid;
    wire [35:0] trace_data;

    // ----------------------------------------------------------------------
    //  Simple AXI‑Lite slave memory (4 KiB – 1024×32)
    // ----------------------------------------------------------------------
    reg [31:0] memory [0:1023];

    // handshake flags
    reg awready, wready, bvalid;
    reg arready, rvalid;
    reg [31:0] rdata;

    assign mem_axi_awready = awready;
    assign mem_axi_wready  = wready;
    assign mem_axi_bvalid  = bvalid;
    assign mem_axi_arready = arready;
    assign mem_axi_rvalid  = rvalid;
    assign mem_axi_rdata   = rdata;

    initial begin
      $dumpfile("picorv32_tb.vcd");   
      $dumpvars(0, picorv32_axi_tb);  
  end
  
    // ----------------------------------------------------------------------
    //  DUT: PicoRV32 wrapped with AXI‑Lite adapter
    // ----------------------------------------------------------------------
    wire trap;
    picorv32_axi #(
        .ENABLE_COUNTERS      (1),
        .ENABLE_COUNTERS64    (1),
        .ENABLE_REGS_16_31    (1),
        .ENABLE_REGS_DUALPORT (1),
        .TWO_STAGE_SHIFT      (1),
        .BARREL_SHIFTER       (0),
        .TWO_CYCLE_COMPARE    (0),
        .TWO_CYCLE_ALU        (0),
        .COMPRESSED_ISA       (1),
        .CATCH_MISALIGN       (1),
        .CATCH_ILLINSN        (1),
        .ENABLE_PCPI          (0),
        .ENABLE_MUL           (1),
        .ENABLE_FAST_MUL      (0),
        .ENABLE_DIV           (1),
        .ENABLE_IRQ           (0),
        .PROGADDR_RESET       (32'h0000_0000),
        .STACKADDR            (32'h0000_1000)
    ) dut (
        .clk                 (clk),
        .resetn              (resetn),
        .trap                (trap),

        // AXI
        .mem_axi_awvalid     (mem_axi_awvalid),
        .mem_axi_awready     (mem_axi_awready),
        .mem_axi_awaddr      (mem_axi_awaddr),
        .mem_axi_awprot      (mem_axi_awprot),

        .mem_axi_wvalid      (mem_axi_wvalid),
        .mem_axi_wready      (mem_axi_wready),
        .mem_axi_wdata       (mem_axi_wdata),
        .mem_axi_wstrb       (mem_axi_wstrb),

        .mem_axi_bvalid      (mem_axi_bvalid),
        .mem_axi_bready      (mem_axi_bready),

        .mem_axi_arvalid     (mem_axi_arvalid),
        .mem_axi_arready     (mem_axi_arready),
        .mem_axi_araddr      (mem_axi_araddr),
        .mem_axi_arprot      (mem_axi_arprot),

        .mem_axi_rvalid      (mem_axi_rvalid),
        .mem_axi_rready      (mem_axi_rready),
        .mem_axi_rdata       (mem_axi_rdata),

        .irq                 (irq),
        .eoi                 (eoi),
        .trace_valid         (trace_valid),
        .trace_data          (trace_data)
    );

    // ----------------------------------------------------------------------
    //  AXI4‑Lite Slave – Write channel
    // ----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            awready <= 0; wready <= 0; bvalid <= 0;
        end else begin
            // ready strobes – respond immediately
            if (mem_axi_awvalid && !awready) awready <= 1;
            if (mem_axi_wvalid  && !wready)  wready  <= 1;

            // perform write when address & data are accepted in same cycle
            if (mem_axi_awvalid && awready && mem_axi_wvalid && wready) begin
                $display("[WRITE] @%8t   addr=%08h  data=%08h  wstrb=%b", $time,
                         mem_axi_awaddr, mem_axi_wdata, mem_axi_wstrb);
                if (mem_axi_wstrb[0]) memory[mem_axi_awaddr[11:2]][ 7: 0] <= mem_axi_wdata[ 7: 0];
                if (mem_axi_wstrb[1]) memory[mem_axi_awaddr[11:2]][15: 8] <= mem_axi_wdata[15: 8];
                if (mem_axi_wstrb[2]) memory[mem_axi_awaddr[11:2]][23:16] <= mem_axi_wdata[23:16];
                if (mem_axi_wstrb[3]) memory[mem_axi_awaddr[11:2]][31:24] <= mem_axi_wdata[31:24];
                awready <= 0; wready <= 0; bvalid <= 1;    // send response
            end
            if (bvalid && mem_axi_bready) bvalid <= 0;
        end
    end

    // ----------------------------------------------------------------------
    //  AXI4‑Lite Slave – Read channel
    // ----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            arready <= 0; rvalid <= 0; rdata <= 0;
        end else begin
            if (mem_axi_arvalid && !arready) arready <= 1;
            if (mem_axi_arvalid && arready) begin
                rdata <= memory[mem_axi_araddr[11:2]];
                $display("[READ ] @%8t   addr=%08h  data=%08h", $time,
                         mem_axi_araddr, rdata);
                arready <= 0; rvalid <= 1;
            end
            if (rvalid && mem_axi_rready) rvalid <= 0;
        end
    end

    // ----------------------------------------------------------------------
    //  Program ROM (hard‑coded instructions)
    // ----------------------------------------------------------------------
    initial begin
        integer i;
        for (i = 0; i < 1024; i = i + 1) memory[i] = 32'h0000_0000;

        //  [0] addi  x5,  x0, 5
        memory[0]  = 32'h0050_0293;
        //  [1] addi  x6,  x0, 10
        memory[1]  = 32'h00A0_0313;
        //  [2] mul   x7,  x5, x6    -> 50
        memory[2]  = 32'h0262_83B3;
        //  [3] div   x8,  x6, x5    -> 2
        memory[3]  = 32'h0253_4433;
        //  [4] rem   x9,  x6, x5    -> 0
        memory[4]  = 32'h0253_64B3;
        //  [5] c.addi x10,1  |  c.mv x11,x7   (two 16‑bit insns)
        memory[5]  = 32'h859E_4505;  // c.li x10, 1  |  c.mv x11, x7
        //  [6..10] write results to RAM
        memory[6]  = 32'h1070_2023;  // sw x7,  256(x0)
        memory[7]  = 32'h1080_2223;  // sw x8,  260(x0)
        memory[8]  = 32'h1090_2423;  // sw x9,  264(x0)
        memory[9]  = 32'h10A0_2623;  // sw x10, 268(x0)
        memory[10] = 32'h10B0_2823;  // sw x11, 272(x0)
        //  [11] jal  x0, 0 (infinite loop)
        memory[11] = 32'h0000_006F;

        $display("Program loaded – starting simulation\n");
    end

    // ----------------------------------------------------------------------
    //  Simulation control & self‑check
    // ----------------------------------------------------------------------
    initial begin
        irq = 0;
        // wait for software to finish (first SW to 0x100)
        wait (memory[64] == 32'd50);
        #1000;  // give some slack for remaining stores

        $display("\n--- RESULT CHECK ---------------------------------------------");
        if (memory[64] == 32'd50) $display("PASS: MUL result 50 OK");
        else                      $display("FAIL: MUL result ≠50 (got %0d)", memory[64]);

        if (memory[65] == 32'd2)  $display("PASS: DIV result 2 OK");
        else                      $display("FAIL: DIV result ≠2  (got %0d)", memory[65]);

        if (memory[66] == 32'd0)  $display("PASS: REM result 0 OK");
        else                      $display("FAIL: REM result ≠0  (got %0d)", memory[66]);

        if (memory[67] == 32'd1)  $display("PASS: C.ADDI result 1 OK");
        else                      $display("FAIL: C.ADDI result ≠1 (got %0d)", memory[67]);

        if (memory[68] == 32'd50) $display("PASS: C.MV result 50 OK");
        else                      $display("FAIL: C.MV result ≠50 (got %0d)", memory[68]);

        if (!trap) $display("PASS: No TRAP detected");
        else       $display("FAIL: TRAP asserted unexpectedly");

        $display("--------------------------------------------------------------\n");
        $finish;
    end

    // ----------------------------------------------------------------------
    //  Optional Verbose CPU Trace
    // ----------------------------------------------------------------------
    // Uncomment for deep dive – beware of console spam.
    /*
    initial begin
        forever @(posedge clk) begin
            $display("PC=%08h  mem_valid=%b  mem_ready=%b  state=%0d", dut.picorv32_core.reg_pc,
                     dut.picorv32_core.mem_valid, dut.picorv32_core.mem_ready, dut.picorv32_core.cpu_state);
        end
    end
    */

endmodule