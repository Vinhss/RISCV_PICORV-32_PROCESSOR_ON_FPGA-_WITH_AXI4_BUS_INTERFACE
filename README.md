# RISC-V PicoRV32 Processor on FPGA with AXI4 Bus Interface
![Verilog](https://img.shields.io/badge/Language-Verilog-blue)
![FPGA](https://img.shields.io/badge/Platform-FPGA-orange)
![RISC-V](https://img.shields.io/badge/Architecture-RISC--V-green)

## About The Project

This project implements a 32-bit RISC-V PicoRV32 soft-core processor on an FPGA platform. The core uses the AXI4-Lite bus interface to connect its native memory ports to the on-chip block RAM (BRAM) . The core is highly parameterized, enabling or disabling features such as compressed instruction support (RVC) and hardware multiply/divide blocks to balance resource utilization and performance. A customized bus adapter module translates the core's native memory to standard AXI4-Lite read/write transactions .

## Key Features

*   **PicoRV32 Core Architecture:** Operates on a 5-stage pipeline including Instruction Fetch, Instruction Decode, Execute, Memory Access, and Write Back.
*   **Instruction Set Support:** Fully supports the RISC-V RV32IMC configuration (Integer, Multiply/Divide, and Compressed extensions).
*   **Bus Interface Integration:** Implements an AXI4 adapter module that bridges the PicoRV32 Native Memory Interface to the AMBA AXI4-Lite protocol.
*   **Comprehensive Verification:** Each functional component was individually verified using Verilog testbenches and waveforms before full top-level system integration.
*   **High Functional Accuracy:** Full system simulation demonstrates flawless instruction fetches, data load/store transactions, and loop executions . It confirms the core correctly implements unprivileged RV32I instructions and complies with the AXI4-Lite handshake protocol.

## Acknowledgments & Open-Source References

This project builds upon and integrates existing open-source hardware designs. We would like to acknowledge the following original works that made this implementation possible:

* **PicoRV32 RISC-V CPU:** The core processor implementation used in this project is referenced and integrated from the official open-source repository by Claire Wolf ([@cliffordwolf/picorv32](https://github.com/YosysHQ/picorv32)). 
* **Purpose of our work:** While the core CPU utilizes the proven open-source Verilog RTL from the repository above, our contributions focus on designing the custom AXI4-Lite bus adapter, building the testbench verification environments, performing hardware-software co-design simulation via ModelSim, and implementing successful physical deployment on the Altera Cyclone II FPGA.

## Hardware & Software Specifications

*   **FPGA Development Kit:** Altera Cyclone II EP2C35F672C6 (DE2 Board) .
*   **EDA Software & Simulation Tools:** Quartus II 9.0 and ModelSim-Altera .

## System Architecture

### 1. PicoRV32 Core Architecture
The CPU core is based on the open-source **PicoRV32**, a size-optimized RISC-V soft processor. 

<img width="623" height="406" alt="image" src="https://github.com/user-attachments/assets/49311f7f-6401-46e8-91a8-e71975e12743" />

* **Internal Structure:** The core integrates an Instruction Fetch/Decode unit, a 32-bit ALU, and a Register File (supporting 32 general-purpose registers).
* **State Machine Control:** It employs a centralized multi-cycle Control Logic state machine to orchestrate pipeline stages, shifting sequentially from fetching instructions to executing or accessing memory.
* **Native Interface:** Instead of standard system buses, PicoRV32 communicates via a simple **Native Memory Interface** using basic request/acknowledge handshakes (`mem_valid`, `mem_ready`, `mem_wstrb`, etc.) to read instructions and read/write data.

### 2. AXI4-Lite Bus Interface (Figure 2.8)
To allow the processor to communicate with industrial-standard IP peripherals and memory blocks, the native signals must be converted into the **AMBA AXI4-Lite** protocol.

<img width="570" height="269" alt="image" src="https://github.com/user-attachments/assets/409eb7a5-67f8-475c-b451-6c683d7fbb25" />

The system features the RISC-V PicoRV32 processor at its core, communicating with external peripheral RAM via the standard AXI4-Lite protocol . When the core issues signals, the AXI4 adapter packages them into 5 semi-independent AXI4 channels: Write Address (AW), Write Data (W), Write Response (B), Read Address (AR), and Read Data (R) .

The high-level block diagram of the SoC design implemented in this project is shown below:

<img width="612" height="385" alt="image" src="https://github.com/user-attachments/assets/78b24fe3-7fc8-476c-bb8c-861cc03bb180" />

The system features the RISC-V PicoRV32 processor at its core, communicating with external peripheral RAM via the standard AXI4-Lite protocol . When the core issues signals, the AXI4 adapter packages them into 5 semi-independent AXI4 channels: Write Address (AW), Write Data (W), Write Response (B), Read Address (AR), and Read Data (R) .

## Verification & Simulation Results

The system was simulated and evaluated using ModelSim testbenches tailored for the PicoRV32 IMC configuration . Below are key timing waveforms from the verification phase:

<img width="1306" height="314" alt="image" src="https://github.com/user-attachments/assets/d0a08c7e-2a82-4fe5-999b-f6a77c038933" />

Every instruction fetch transaction successfully completes the full `AR -> R` channel handshake sequence (`ARVALID -> ARREADY -> RVALID -> RREADY`) . The flashing `mem_ready` signal confirms that the CPU has captured the instruction from the bus, triggering the decode stage .

### 2. AXI4 Bus Read/Write Transactions

<img width="1579" height="507" alt="image" src="https://github.com/user-attachments/assets/9c381ee7-ae4a-4593-acf5-917493f7a719" />

The `AW -> W -> B` transaction sequence appears sequentially as the CPU writes calculation results (such as MUL/DIV) into RAM . The slave asserts `mem_axi_bvalid` to indicate transaction success, allowing the adapter to drive `mem_ready` high to terminate the transaction cycle properly .

## FPGA Implementation Results

The digital design was synthesized, place-and-routed, and successfully deployed on the target DE2 Cyclone II FPGA board .

### Step-by-Step (Single-Step) Execution

<img width="550" height="309" alt="image" src="https://github.com/user-attachments/assets/dd57ee96-11e9-4253-bece-bd969f8f7da7" />

By utilizing button inputs (`KEY[1]`), users can manually toggle individual clock cycles to execute the RISC-V program step-by-step . The onboard multiplexers, controlled by slide switches `SW[2:0]`, allow the 8-digit 7-segment display (`HEX0-HEX7`) to monitor live bus states such as memory addresses (`mem_addr`), write data (`mem_wdata`), or read data (`mem_rdata`) .

### On-chip AXI4-Lite Transaction Monitoring via LCD

<img width="577" height="320" alt="image" src="https://github.com/user-attachments/assets/57426c1c-0762-45cf-a5bf-28e27acb10e5" />

The characters displayed on the 2-line LCD screen monitor real-time bus metrics, with Line 1 presenting the active memory address (`Addr:`) and Line 2 displaying the stable bus data (`Data:`) in hexadecimal format . Simultaneously, the green LED (`LEDG8`) illuminates to indicate that the read data has been safely captured and stabilized on the bus .

## 🔮 Future Work
*   Upgrade the current implementation to support full AXI4 protocol features (such as burst and pipelined transactions) to achieve higher throughput .
*   Integrate additional advanced IP peripherals (e.g., UART controllers, timers, or GPIO blocks) to expand interconnectivity and build a fully customized, production-ready SoC .
