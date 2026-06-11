//////////////////////////////////////////////////////////////////////////////////
// Top-level module for AXI4 implementation on Altera DE2 FPGA
// Features:
// 1. AXI4 interface for accessing a 256x32-bit instruction memory
// 2. User input via switches from SW[16:1] (address/data halves, strobe mask) and keys KEY[3:0] (single-step, entry)
// 3. Display outputs on LEDs, 7-segment HEX, and LCD for address, data
// 4. Reset clears memory and registers SW[17]
//////////////////////////////////////////////////////////////////////////////////
module top_fpga_axi4 (
    input  CLOCK_50,
    input  [17:0] SW,
    input  [3:0]  KEY,
    output [17:0] LEDR,
    output [8:0]  LEDG,
    // 8× seven-segment (hi?lo = HEX7..HEX0)
    output [6:0]  HEX0,
    output [6:0]  HEX1,
    output [6:0]  HEX2,
    output [6:0]  HEX3,
    output [6:0]  HEX4,
    output [6:0]  HEX5,
    output [6:0]  HEX6,
    output [6:0]  HEX7,
    // LCD
    output        LCD_ON,
    output        LCD_BLON,
    output        LCD_RW,
    output        LCD_EN,
    output        LCD_RS,
    inout  [7:0]  LCD_DATA
);

//---------------------------------------------------------------------
//  Clock / Reset
//---------------------------------------------------------------------
    wire clk   = CLOCK_50;
    wire resetn = SW[17];

//---------------------------------------------------------------------
//  User-input half-select (SW0) & strobe mask (SW4..1)
//---------------------------------------------------------------------
    wire        half_select = SW[0];               // 0 = lower 16-bit, 1 = upper 16-bit
    wire [3:0]  mem_wstrb   = {SW[4], SW[3], SW[2], SW[1]};

//---------------------------------------------------------------------
//  Internal holding registers for 32-bit addr & wdata (split 16/16)
//---------------------------------------------------------------------
    reg [15:0]  addr_low  , addr_high;
    reg [15:0]  data_low  , data_high;

    wire [31:0] mem_addr  = {addr_high, addr_low};
    wire [31:0] mem_wdata = {data_high, data_low};

//---------------------------------------------------------------------
//  Native PicoRV32 bus (write/read driven by KEY0 single-step FSM)
//---------------------------------------------------------------------
    reg         mem_valid_reg;   // asserted one cycle per KEY0 press
    wire        mem_valid = mem_valid_reg;
    wire        mem_instr = 1'b0;    // always data-type access (single instruction memory)

    wire        mem_ready;
    wire [31:0] mem_rdata;
    reg  [31:0] stable_rdata;    // latched for display / LCD

//---------------------------------------------------------------------
//  AXI4-Lite signals between adapter (master) and local BRAM slave
//---------------------------------------------------------------------
    wire        mem_axi_awvalid, mem_axi_awready;
    wire [31:0] mem_axi_awaddr;
    wire [2:0]  mem_axi_awprot;
    wire        mem_axi_wvalid , mem_axi_wready;
    wire [31:0] mem_axi_wdata;
    wire [3:0]  mem_axi_wstrb;
    wire        mem_axi_bvalid , mem_axi_bready;
    wire        mem_axi_arvalid, mem_axi_arready;
    wire [31:0] mem_axi_araddr;
    wire [2:0]  mem_axi_arprot;
    wire        mem_axi_rvalid , mem_axi_rready;
    wire [31:0] mem_axi_rdata;

//---------------------------------------------------------------------
//  Single instruction memory (256×32).  Cleared on reset.
//---------------------------------------------------------------------
    reg [31:0] instruction_memory [0:255];
    reg [7:0]  rst_ctr;
    reg        rst_mem_active;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            rst_ctr        <= 0;
            rst_mem_active <= 1;
        end else if (rst_mem_active) begin
            instruction_memory[rst_ctr] <= 32'h0;
            if (rst_ctr == 8'd255)
                rst_mem_active <= 0;
            else
                rst_ctr <= rst_ctr + 1'b1;
        end else begin

            if (mem_axi_wvalid && mem_axi_wready) begin
                if (mem_wstrb[0]) instruction_memory[mem_axi_awaddr[7:0]][ 7:0] <= mem_axi_wdata[ 7:0];
                if (mem_wstrb[1]) instruction_memory[mem_axi_awaddr[7:0]][15:8] <= mem_axi_wdata[15:8];
                if (mem_wstrb[2]) instruction_memory[mem_axi_awaddr[7:0]][23:16] <= mem_axi_wdata[23:16];
                if (mem_wstrb[3]) instruction_memory[mem_axi_awaddr[7:0]][31:24] <= mem_axi_wdata[31:24];
            end

            if (mem_axi_arvalid && mem_axi_arready) begin
                stable_rdata <= instruction_memory[mem_axi_araddr[7:0]]; // latch for display/LCD
            end
        end
    end

//---------------------------------------------------------------------
//  Debounce & single-step logic (KEY0)
//---------------------------------------------------------------------
    reg [1:0] key0_sync;
    reg       key0_pressed;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            key0_sync     <= 2'b11;
            key0_pressed  <= 1'b0;
            mem_valid_reg <= 1'b0;
        end else begin
            key0_sync <= {key0_sync[0], KEY[0]};
            // detect falling edge (pressed)
            if (key0_sync == 2'b10) begin
                key0_pressed  <= 1'b1;
                mem_valid_reg <= 1'b1;
            end else if (mem_ready && key0_pressed) begin
                key0_pressed  <= 1'b0;
                mem_valid_reg <= 1'b0;
            end
        end
    end

//---------------------------------------------------------------------
//  Manual entry of 16-bit halves via KEY1 (addr) & KEY2 (data)
//---------------------------------------------------------------------
    reg mode_addr, mode_data;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            addr_low <= 0; addr_high <= 0;
            data_low <= 0; data_high <= 0;
            mode_addr <= 0; mode_data <= 0;
        end else if (!rst_mem_active) begin
            // latch address half
            if (~KEY[1] && KEY[1] !== 1'bx) begin
                if (!half_select) addr_low  <= SW[16:1];
                else               addr_high <= SW[16:1];
                mode_addr <= 1'b1;
            end
            // latch data half
            if (~KEY[3] && KEY[3] !== 1'bx) begin
                if (!half_select) data_low  <= SW[16:1];
                else               data_high <= SW[16:1];
                mode_data <= 1'b1;
            end
            // clear mode indicators when keys released
            if (KEY[1] && KEY[3]) begin
                mode_addr <= 1'b0;
                mode_data <= 1'b0;
            end
        end
    end

//---------------------------------------------------------------------
//  AXI-Lite slave (simple handshake model)
//---------------------------------------------------------------------
    assign mem_axi_awready = mem_axi_awvalid;  // accept immediately
    assign mem_axi_wready  = mem_axi_wvalid;
    assign mem_axi_arready = mem_axi_arvalid;
    assign mem_axi_bvalid  = mem_axi_wvalid & mem_axi_wready; // 1-cycle write response
    assign mem_axi_rvalid  = mem_axi_arvalid & mem_axi_arready;
    assign mem_axi_rdata   = instruction_memory[mem_axi_araddr[7:0]];

//---------------------------------------------------------------------
//  Instantiate AXI adapter (master side driving signals above)
//---------------------------------------------------------------------
    wire trigger_read      = 1'b0;    // removed complex FSM; simple single-step only
    wire mem_valid_combined = mem_valid; // no auto-readback

    picorv32_axi_adapter dut (
        .clk(clk),
        .resetn(resetn),
        .mem_axi_awvalid(mem_axi_awvalid),
        .mem_axi_awready(mem_axi_awready),
        .mem_axi_awaddr(mem_axi_awaddr),
        .mem_axi_awprot(mem_axi_awprot),
        .mem_axi_wvalid(mem_axi_wvalid),
        .mem_axi_wready(mem_axi_wready),
        .mem_axi_wdata(mem_axi_wdata),
        .mem_axi_wstrb(mem_axi_wstrb),
        .mem_axi_bvalid(mem_axi_bvalid),
        .mem_axi_bready(mem_axi_bready),
        .mem_axi_arvalid(mem_axi_arvalid),
        .mem_axi_arready(mem_axi_arready),
        .mem_axi_araddr(mem_axi_araddr),
        .mem_axi_arprot(mem_axi_arprot),
        .mem_axi_rvalid(mem_axi_rvalid),
        .mem_axi_rready(mem_axi_rready),
        .mem_axi_rdata(mem_axi_rdata),
        .mem_valid(mem_valid_combined),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata)
    );

//---------------------------------------------------------------------
//  LED / 7-segment diagnostics
//---------------------------------------------------------------------
    assign LEDR[16:1] = mode_addr ? (half_select ? addr_high : addr_low)
                         : mode_data ? (half_select ? data_high : data_low)
                         : 16'h0000;
    assign LEDR[17] = 1'b0;
    assign LEDR[0]  = 1'b0;

    assign LEDG[0] = mem_valid_combined;
    assign LEDG[1] = mem_ready;
    assign LEDG[2] = mem_axi_awvalid;
    assign LEDG[3] = mem_axi_arvalid;
    assign LEDG[4] = mem_axi_bvalid;
    assign LEDG[5] = mem_axi_rvalid;
    assign LEDG[6] = half_select;  // shows which half is selected
    assign LEDG[7] = 1'b0;         // free
    assign LEDG[8] = |stable_rdata;

    // split mem_rdata (live) for 8×HEX
    wire [3:0] hex0_data = mem_rdata[ 3: 0];
    wire [3:0] hex1_data = mem_rdata[ 7: 4];
    wire [3:0] hex2_data = mem_rdata[11: 8];
    wire [3:0] hex3_data = mem_rdata[15:12];
    wire [3:0] hex4_data = mem_rdata[19:16];
    wire [3:0] hex5_data = mem_rdata[23:20];
    wire [3:0] hex6_data = mem_rdata[27:24];
    wire [3:0] hex7_data = mem_rdata[31:28];

    hex_display h0 (.in(hex0_data), .out(HEX0));
    hex_display h1 (.in(hex1_data), .out(HEX1));
    hex_display h2 (.in(hex2_data), .out(HEX2));
    hex_display h3 (.in(hex3_data), .out(HEX3));
    hex_display h4 (.in(hex4_data), .out(HEX4));
    hex_display h5 (.in(hex5_data), .out(HEX5));
    hex_display h6 (.in(hex6_data), .out(HEX6));
    hex_display h7 (.in(hex7_data), .out(HEX7));

//---------------------------------------------------------------------
//  LCD (unchanged)
//---------------------------------------------------------------------
    wire DLY_RST;
    reset_delay r0 (.iCLK(CLOCK_50), .oRESET(DLY_RST));

    assign LCD_ON  = 1'b1;
    assign LCD_BLON= 1'b1;

    LCD_message lcd_m (
        .iCLK(CLOCK_50),
        .iRST_N(DLY_RST),
        .iADDR(mem_addr),
        .iDATA(stable_rdata),
        .LCD_DATA(LCD_DATA),
        .LCD_RW(LCD_RW),
        .LCD_EN(LCD_EN),
        .LCD_RS(LCD_RS)
    );

endmodule


module LCD_message (
    input iCLK,
    input iRST_N,
    input [31:0] iADDR,
    input [31:0] iDATA,
    output [7:0] LCD_DATA,
    output LCD_RW,
    output LCD_EN,
    output LCD_RS
);

    reg [5:0] LUT_INDEX;
    reg [8:0] LUT_DATA;
    reg [5:0] mLCD_ST;
    reg [17:0] mDLY;
    reg mLCD_Start;
    reg [7:0] mLCD_DATA;
    reg mLCD_RS;
    wire mLCD_Done;
    reg [25:0] refresh_counter;

    parameter LCD_INITIAL = 0;
    parameter LCD_LINE1 = 5;
    parameter LCD_CH_LINE = LCD_LINE1 + 13;
    parameter LCD_LINE2 = LCD_CH_LINE + 1;
    parameter LUT_SIZE = LCD_LINE2 + 14;
    parameter REFRESH_WAIT = 26'd50_000_000;

    reg [7:0] addr_chars [0:7];
    reg [7:0] data_chars [0:7];
    integer i;
    always @(*) begin
        for (i = 0; i < 8; i = i + 1) begin
            case (iADDR[31-i*4 -: 4])
                4'h0: addr_chars[i] = 8'h30;
                4'h1: addr_chars[i] = 8'h31;
                4'h2: addr_chars[i] = 8'h32;
                4'h3: addr_chars[i] = 8'h33;
                4'h4: addr_chars[i] = 8'h34;
                4'h5: addr_chars[i] = 8'h35;
                4'h6: addr_chars[i] = 8'h36;
                4'h7: addr_chars[i] = 8'h37;
                4'h8: addr_chars[i] = 8'h38;
                4'h9: addr_chars[i] = 8'h39;
                4'hA: addr_chars[i] = 8'h41;
                4'hB: addr_chars[i] = 8'h42;
                4'hC: addr_chars[i] = 8'h43;
                4'hD: addr_chars[i] = 8'h44;
                4'hE: addr_chars[i] = 8'h45;
                4'hF: addr_chars[i] = 8'h46;
                default: addr_chars[i] = 8'h3F;
            endcase
            case (iDATA[31-i*4 -: 4])
                4'h0: data_chars[i] = 8'h30;
                4'h1: data_chars[i] = 8'h31;
                4'h2: data_chars[i] = 8'h32;
                4'h3: data_chars[i] = 8'h33;
                4'h4: data_chars[i] = 8'h34;
                4'h5: data_chars[i] = 8'h35;
                4'h6: data_chars[i] = 8'h36;
                4'h7: data_chars[i] = 8'h37;
                4'h8: data_chars[i] = 8'h38;
                4'h9: data_chars[i] = 8'h39;
                4'hA: data_chars[i] = 8'h41;
                4'hB: data_chars[i] = 8'h42;
                4'hC: data_chars[i] = 8'h43;
                4'hD: data_chars[i] = 8'h44;
                4'hE: data_chars[i] = 8'h45;
                4'hF: data_chars[i] = 8'h46;
                default: data_chars[i] = 8'h3F;
            endcase
        end
    end

    always @(posedge iCLK or negedge iRST_N) begin
        if (!iRST_N) begin
            LUT_INDEX <= 0;
            mLCD_ST <= 0;
            mDLY <= 0;
            mLCD_Start <= 0;
            mLCD_DATA <= 0;
            mLCD_RS <= 0;
            refresh_counter <= 0;
        end else begin
            if (refresh_counter < REFRESH_WAIT) begin
                refresh_counter <= refresh_counter + 1;
                if (LUT_INDEX < LUT_SIZE) begin
                    case (mLCD_ST)
                        0: begin
                            mLCD_DATA <= LUT_DATA[7:0];
                            mLCD_RS <= LUT_DATA[8];
                            mLCD_Start <= 1;
                            mLCD_ST <= 1;
                        end
                        1: begin
                            if (mLCD_Done) begin
                                mLCD_Start <= 0;
                                mLCD_ST <= 2;
                            end
                        end
                        2: begin
                            if (mDLY < 18'h7FFFF) begin
                                mDLY <= mDLY + 1;
                            end else begin
                                mDLY <= 0;
                                mLCD_ST <= 3;
                            end
                        end
                        3: begin
                            LUT_INDEX <= LUT_INDEX + 1;
                            mLCD_ST <= 0;
                        end
                    endcase
                end
            end else begin
                LUT_INDEX <= 5;
                refresh_counter <= 0;
            end
        end
    end

    always @(posedge iCLK) begin
        case (LUT_INDEX)
            LCD_INITIAL+0: LUT_DATA <= 9'h038;
            LCD_INITIAL+1: LUT_DATA <= 9'h00C;
            LCD_INITIAL+2: LUT_DATA <= 9'h001;
            LCD_INITIAL+3: LUT_DATA <= 9'h006;
            LCD_INITIAL+4: LUT_DATA <= 9'h080;
            LCD_LINE1+0:  LUT_DATA <= 9'h141;
            LCD_LINE1+1:  LUT_DATA <= 9'h164;
            LCD_LINE1+2:  LUT_DATA <= 9'h164;
            LCD_LINE1+3:  LUT_DATA <= 9'h172;
            LCD_LINE1+4:  LUT_DATA <= 9'h13A;
            LCD_LINE1+5:  LUT_DATA <= {1'b1, addr_chars[0]};
            LCD_LINE1+6:  LUT_DATA <= {1'b1, addr_chars[1]};
            LCD_LINE1+7:  LUT_DATA <= {1'b1, addr_chars[2]};
            LCD_LINE1+8:  LUT_DATA <= {1'b1, addr_chars[3]};
            LCD_LINE1+9:  LUT_DATA <= {1'b1, addr_chars[4]};
            LCD_LINE1+10: LUT_DATA <= {1'b1, addr_chars[5]};
            LCD_LINE1+11: LUT_DATA <= {1'b1, addr_chars[6]};
            LCD_LINE1+12: LUT_DATA <= {1'b1, addr_chars[7]};
            LCD_CH_LINE:  LUT_DATA <= 9'h0C0;
            LCD_LINE2+0:  LUT_DATA <= 9'h144;
            LCD_LINE2+1:  LUT_DATA <= 9'h161;
            LCD_LINE2+2:  LUT_DATA <= 9'h174;
            LCD_LINE2+3:  LUT_DATA <= 9'h161;
            LCD_LINE2+4:  LUT_DATA <= 9'h13A;
            LCD_LINE2+5:  LUT_DATA <= {1'b1, data_chars[0]};
            LCD_LINE2+6:  LUT_DATA <= {1'b1, data_chars[1]};
            LCD_LINE2+7:  LUT_DATA <= {1'b1, data_chars[2]};
            LCD_LINE2+8:  LUT_DATA <= {1'b1, data_chars[3]};
            LCD_LINE2+9:  LUT_DATA <= {1'b1, data_chars[4]};
            LCD_LINE2+10: LUT_DATA <= {1'b1, data_chars[5]};
            LCD_LINE2+11: LUT_DATA <= {1'b1, data_chars[6]};
            LCD_LINE2+12: LUT_DATA <= {1'b1, data_chars[7]};
            default:      LUT_DATA <= 9'h000;
        endcase
    end

    lcd_controller u0 (
        .iDATA(mLCD_DATA),
        .iRS(mLCD_RS),
        .iStart(mLCD_Start),
        .oDone(mLCD_Done),
        .iCLK(iCLK),
        .iRST_N(iRST_N),
        .LCD_DATA(LCD_DATA),
        .LCD_RW(LCD_RW),
        .LCD_EN(LCD_EN),
        .LCD_RS(LCD_RS)
    );

endmodule

module lcd_controller (
    input [7:0] iDATA,
    input iRS,
    input iStart,
    output reg oDone,
    input iCLK,
    input iRST_N,
    output [7:0] LCD_DATA,
    output LCD_RW,
    output reg LCD_EN,
    output LCD_RS
);

    parameter CLK_Divide = 24;

    reg [4:0] Cont;
    reg [1:0] ST;
    reg preStart, mStart;

    assign LCD_DATA = iDATA;
    assign LCD_RW = 1'b0;
    assign LCD_RS = iRS;

    always @(posedge iCLK or negedge iRST_N) begin
        if (!iRST_N) begin
            oDone <= 1'b0;
            LCD_EN <= 1'b0;
            preStart <= 1'b0;
            mStart <= 1'b0;
            Cont <= 0;
            ST <= 0;
        end else begin
            preStart <= iStart;
            if ({preStart, iStart} == 2'b01) begin
                mStart <= 1'b1;
                oDone <= 1'b0;
            end
            if (mStart) begin
                case (ST)
                    0: ST <= 1;
                    1: begin
                        LCD_EN <= 1'b1;
                        ST <= 2;
                    end
                    2: begin
                        if (Cont < CLK_Divide) begin
                            Cont <= Cont + 1;
                        end else begin
                            ST <= 3;
                        end
                    end
                    3: begin
                        LCD_EN <= 1'b0;
                        mStart <= 1'b0;
                        oDone <= 1'b1;
                        Cont <= 0;
                        ST <= 0;
                    end
                endcase
            end
        end
    end

endmodule

module reset_delay (
    input iCLK,
    output reg oRESET
);

    reg [20:0] Cont;

    always @(posedge iCLK) begin
        if (Cont != 21'h1FFFFF) begin
            Cont <= Cont + 1;
            oRESET <= 1'b0;
        end else begin
            oRESET <= 1'b1;
        end
    end

endmodule

module hex_display (
    input [3:0] in,
    output reg [6:0] out
);
    always @(*) begin
        case (in)
            4'h0: out = 7'b1000000;
            4'h1: out = 7'b1111001;
            4'h2: out = 7'b0100100;
            4'h3: out = 7'b0110000;
            4'h4: out = 7'b0011001;
            4'h5: out = 7'b0010010;
            4'h6: out = 7'b0000010;
            4'h7: out = 7'b1111000;
            4'h8: out = 7'b0000000;
            4'h9: out = 7'b0010000;
            4'hA: out = 7'b0001000;
            4'hB: out = 7'b0000011;
            4'hC: out = 7'b1000110;
            4'hD: out = 7'b0100001;
            4'hE: out = 7'b0000110;
            4'hF: out = 7'b0001110;
            default: out = 7'b1111111;
        endcase
    end
endmodule
