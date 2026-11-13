`timescale 1ns / 1ps

module tb_manager_gara();

    // ---------------------------------------------------------
    // 1. Semnale interne pentru Testbench
    // ---------------------------------------------------------
    // Intrari catre DUT (Device Under Test)
    reg         pclk;
    reg         presetn;
    
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [3:0]  paddr;
    reg  [15:0] pwdata;
    
    reg         out_ready;
    
    reg  [5:0]  cai_ferate_in_lucru;
    reg  [5:0]  cereri_trenuri;
    reg  [2:0]  tren0, tren1, tren2, tren3;

    // Iesiri din DUT
    wire [15:0] prdata;
    wire        pready;
    wire        pslverr;
    
    wire        out_valid;
    wire [4:0]  out_data;
    
    wire [5:0]  semafor_iesire;
    wire [5:0]  semafor_intrare;
    wire [2:0]  peron_alocat;
    wire [7:0]  comanda_acceptata;


    // 2. Instantierea Modulului (DUT - Device Under Test)
  
    manager_gara_dut dut (
        .pclk               (pclk),
        .presetn            (presetn),
        .psel               (psel),
        .penable            (penable),
        .pwrite             (pwrite),
        .paddr              (paddr),
        .pwdata             (pwdata),
        .prdata             (prdata),
        .pready             (pready),
        .pslverr            (pslverr),
        .out_ready          (out_ready),
        .out_valid          (out_valid),
        .out_data           (out_data),
        .cai_ferate_in_lucru(cai_ferate_in_lucru),
        .cereri_trenuri     (cereri_trenuri),
        .tren0              (tren0),
        .tren1              (tren1),
        .tren2              (tren2),
        .tren3              (tren3),
        .semafor_iesire     (semafor_iesire),
        .semafor_intrare    (semafor_intrare),
        .peron_alocat       (peron_alocat),
        .comanda_acceptata  (comanda_acceptata)
    );

    
    // 3. Generarea Ceasului (Clock)
   
    initial begin
        pclk = 0;
        forever #5 pclk = ~pclk; // Perioada de 10ns (100 MHz)
    end

 
    // 4. Task-uri pentru Magistrala APB
 
    // Task pentru Scriere APB (Setup Phase -> Access Phase)
    task apb_write;
        input [3:0]  addr;
        input [15:0] data;
        begin
            @(posedge pclk);
            psel    = 1;
            pwrite  = 1;
            paddr   = addr;
            pwdata  = data;
            penable = 0; // Faza de setup
            
            @(posedge pclk);
            penable = 1; // Faza de access
            
            @(posedge pclk);
            psel    = 0;
            penable = 0; // Finalizare tranzactie
        end
    endtask

    // Task pentru Citire APB
    task apb_read;
        input  [3:0] addr;
        output [15:0] data;
        begin
            @(posedge pclk);
            psel    = 1;
            pwrite  = 0;
            paddr   = addr;
            penable = 0; // Faza de setup
            
            @(posedge pclk);
            penable = 1; // Faza de access
            
            @(posedge pclk);
            data    = prdata; // Citim datele returnate
            psel    = 0;
            penable = 0;
        end
    endtask

    // ---------------------------------------------------------
    // 5. Scenariul de Test (Main block)
    // ---------------------------------------------------------
    reg [15:0] read_val;

    initial begin
        // A. Initializarea semnalelor
        presetn = 0;
        psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
        out_ready = 0;
        cai_ferate_in_lucru = 6'b000000; // Toate caile sunt functionale
        cereri_trenuri = 0; tren0 = 0; tren1 = 0; tren2 = 0; tren3 = 0;

        // B. Aplicarea Reset-ului
        #20 presetn = 1; // Scoatem modulul din reset
        #20;

        // C. Configurare initiala (Setam durata vagoanelor)
        $display("[%0t] Configuram duratele vagoanelor...", $time);
        apb_write(4'h5, 16'd2); // ADR_DURATA_VAGON_A = 2 tick-uri
        apb_write(4'h6, 16'd3); // ADR_DURATA_VAGON_B = 3 tick-uri
        apb_write(4'h7, 16'd4); // ADR_DURATA_VAGON_C = 4 tick-uri

        // D. Test 1: Cerere pentru Trenul 0 (Incarcatura de tip C - Persoane, 3 vagoane)
        $display("[%0t] Trimitem cerere pentru Trenul 0...", $time);
        apb_write(4'h8, 16'd3); // Setam nr_vagoane = 3 (ADR_CMD_CERERE_VAGON)
        // CMD_CERERE: [4:2] = COD (3'd2 pt Persoane), [1:0] = ID (0) => {3'd2, 2'd0} = 8'b0000_1000 = 8'h08
        apb_write(4'h4, 16'h08); 
        
        // Verificam statusul
        apb_read(4'h0, read_val);
        $display("[%0t] Status Tren 0 citit pe APB: %h", $time, read_val);

        // Asteptam ca timerul sa expire (3 vagoane * 4 ticks = 12 ticks)
        wait (out_valid == 1'b1);
        $display("[%0t] Trenul 0 e gata de plecare (out_valid = 1). Date: %b", $time, out_data);
        
        // Raspundem cu ready pentru a permite plecarea
        @(posedge pclk);
        out_ready = 1'b1;
        @(posedge pclk);
        out_ready = 1'b0;

        // E. Test 2: Verificare Arbitru Round Robin
        // Trimitem inca 3 trenuri consecutive de Persoane (care pot intra pe peroanele 2..5)
        $display("[%0t] Testam Round Robin-ul trimitand Trenurile 1, 2 si 3...", $time);
        
        // Trenul 1 (nr vagoane = 1)
        apb_write(4'h8, 16'd1);
        apb_write(4'h4, 16'h09); // COD = 2, ID = 1 => 8'h09
        
        // Asteptam putin sa se inregistreze (nu il lasam inca sa plece)
        #10;
        
        // Trenul 2
        apb_write(4'h8, 16'd1);
        apb_write(4'h4, 16'h0A); // COD = 2, ID = 2 => 8'h0A
        
        // Testul se poate extinde aici cu `wait` pentru a elibera si aceste trenuri
        
        #100;
        $display("[%0t] Test finalizat.", $time);
        $finish; // Opreste simularea
    end

endmodule