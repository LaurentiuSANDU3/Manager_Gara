module manager_gara_dut (
    input   wire              pclk,
    input   wire              presetn,

    // ---------------- interfata APB (acces la registre) ----------------
    //master
    input   wire              psel,     // selectie periferic
    input   wire              penable,
    input   wire              pwrite,   // 1 write , 0 read
    input   wire [4-1:0]      paddr,
    input   wire [16-1:0]     pwdata,
    //slave
    output  reg  [16-1:0]     prdata,
    output  wire              pready,
    output  wire              pslverr,

    // ---------------- interfata valid_ready ----------------
    input  wire       out_ready, // consumatorul poate accepta trenul
    output reg        out_valid, // 1 = trenul e gata de plecare
    output reg [4:0]  out_data,  // [4:2] = Peronul de la care pleaca, [1:0] = ID Tren

    // ---------------- interfata trenuri ----------------
    input   wire [6-1:0]      cai_ferate_in_lucru, // 1 = cale in lucru
    input   wire [6-1:0]      cereri_trenuri,      // cate un bit per cale
    input   wire [3-1:0]      tren0,
    input   wire [3-1:0]      tren1,
    input   wire [3-1:0]      tren2,
    input   wire [3-1:0]      tren3,
    output  reg  [6-1:0]      semafor_iesire,      // 1 verde | 0 rosu
    output  reg  [6-1:0]      semafor_intrare,     // 1 verde | 0 rosu
    output  reg  [3-1:0]      peron_alocat,
    output  reg  [8-1:0]      comanda_acceptata
);

// ---------------- harta de adrese ----------------
localparam [4-1:0] ADR_STATUS_TREN0     = 4'h0;
localparam [4-1:0] ADR_STATUS_TREN1     = 4'h1;
localparam [4-1:0] ADR_STATUS_TREN2     = 4'h2;
localparam [4-1:0] ADR_STATUS_TREN3     = 4'h3;
localparam [4-1:0] ADR_CMD_CERERE       = 4'h4;
localparam [4-1:0] ADR_DURATA_VAGON_A   = 4'h5;
localparam [4-1:0] ADR_DURATA_VAGON_B   = 4'h6;
localparam [4-1:0] ADR_DURATA_VAGON_C   = 4'h7;
localparam [4-1:0] ADR_CMD_CERERE_VAGON = 4'h8;   // NOU: adresa pentru cmd_cerere_vagon

// codurile tipurilor de incarcatura (COD_INCARCATURA, 3 biti)
localparam [3-1:0] COD_A_MINEREURI      = 3'd0;  // merge pe calea 0
localparam [3-1:0] COD_B_CEREALE        = 3'd1;  // merge pe calea 1
localparam [3-1:0] COD_C_PERSOANE       = 3'd2;  // merge pe caile 2..5

// ---------------- registre (toate pe 8 biti) ----------------
reg [8-1:0] status_tren0;      // RO: [4] BUSY, [3:1] COD_PERON, [0] COMANDA_ACCEPTATA
reg [8-1:0] status_tren1;      // RO
reg [8-1:0] status_tren2;      // RO
reg [8-1:0] status_tren3;      // RO
reg [8-1:0] cmd_cerere;        // RW: [4:2] COD_INCARCATURA, [1:0] ID_TREN
reg [8-1:0] cmd_cerere_vagon;  // RW: [3:0] NR_VAGOANE
reg [8-1:0] durata_vagon_A;    // RW
reg [8-1:0] durata_vagon_B;    // RW
reg [8-1:0] durata_vagon_C;    // RW

// ---------------- protocol APB ----------------
wire apb_access = psel & penable;
assign pready  = 1'b1;
assign pslverr = 1'b0;   // NOU: pslverr nu era driveuit deloc

// citire: prdata se incarca in prima faza (setup), deci e valid in a doua faza (access)
always @(posedge pclk or negedge presetn) begin   
    if (~presetn)
        prdata <= 16'b0;                          
    else if (psel && ~penable && ~pwrite) begin
        case (paddr)
        
            ADR_STATUS_TREN0:     prdata <= {8'b0, status_tren0};
            ADR_STATUS_TREN1:     prdata <= {8'b0, status_tren1};
            ADR_STATUS_TREN2:     prdata <= {8'b0, status_tren2};
            ADR_STATUS_TREN3:     prdata <= {8'b0, status_tren3};
            ADR_CMD_CERERE:       prdata <= {8'b0, cmd_cerere};
            ADR_CMD_CERERE_VAGON: prdata <= {8'b0, cmd_cerere_vagon};   // NOU
            ADR_DURATA_VAGON_A:   prdata <= {8'b0, durata_vagon_A};
            ADR_DURATA_VAGON_B:   prdata <= {8'b0, durata_vagon_B};
            ADR_DURATA_VAGON_C:   prdata <= {8'b0, durata_vagon_C};
            default:              prdata <= 16'b0;
        endcase
    end
end

// scriere: se face in faza access (psel & penable)
always @(posedge pclk or negedge presetn) begin
    if (~presetn) begin
        cmd_cerere       <= 8'b0;   // MODIFICAT: era 9'b0
        cmd_cerere_vagon <= 8'b0;   // NOU
        durata_vagon_A   <= 8'b0;
        durata_vagon_B   <= 8'b0;
        durata_vagon_C   <= 8'b0;
    end
    else if (apb_access && pwrite) begin
        case (paddr)
            ADR_CMD_CERERE:       cmd_cerere       <= pwdata[7:0];   // MODIFICAT: era [8:0]
            ADR_CMD_CERERE_VAGON: cmd_cerere_vagon <= pwdata[7:0];   // NOU
            ADR_DURATA_VAGON_A:   durata_vagon_A   <= pwdata[7:0];
            ADR_DURATA_VAGON_B:   durata_vagon_B   <= pwdata[7:0];
            ADR_DURATA_VAGON_C:   durata_vagon_C   <= pwdata[7:0];
            default: ;
        endcase
    end
end

// decodificare cerere tren 
wire [2-1:0] id_tren         = cmd_cerere[1:0];
wire [3-1:0] cod_incarcatura = cmd_cerere[4:2];
wire [4-1:0] nr_vagoane      = cmd_cerere_vagon[3:0];   // MODIFICAT: nu mai e cmd_cerere[8:5]


wire cerere_scrisa = apb_access && pwrite && (paddr == ADR_CMD_CERERE);
reg  cerere_noua;
always @(posedge pclk or negedge presetn) begin
    if (~presetn) cerere_noua <= 1'b0;
    else          cerere_noua <= cerere_scrisa;
end

reg [6-1:0] cai_permise;
always @(*) begin
    case (cod_incarcatura)
        COD_A_MINEREURI: cai_permise = 6'b000001;  // doar calea 0
        COD_B_CEREALE:   cai_permise = 6'b000010;  // doar calea 1
        COD_C_PERSOANE:  cai_permise = 6'b111100;  // caile 2..5
        default:         cai_permise = 6'b000000;  // cod necunoscut
    endcase
end

// peron liber
wire [6-1:0] peron_liber;
assign peron_liber[0] = (semafor_intrare[0] == 1'b1 && semafor_iesire[0] == 1'b0) ? 1'b1 : 1'b0;
assign peron_liber[1] = (semafor_intrare[1] == 1'b1 && semafor_iesire[1] == 1'b0) ? 1'b1 : 1'b0;
assign peron_liber[2] = (semafor_intrare[2] == 1'b1 && semafor_iesire[2] == 1'b0) ? 1'b1 : 1'b0;
assign peron_liber[3] = (semafor_intrare[3] == 1'b1 && semafor_iesire[3] == 1'b0) ? 1'b1 : 1'b0;
assign peron_liber[4] = (semafor_intrare[4] == 1'b1 && semafor_iesire[4] == 1'b0) ? 1'b1 : 1'b0;
assign peron_liber[5] = (semafor_intrare[5] == 1'b1 && semafor_iesire[5] == 1'b0) ? 1'b1 : 1'b0;

wire [6-1:0] cai_eligibile = cai_permise & ~cai_ferate_in_lucru & peron_liber;
wire         cale_libera   = |cai_eligibile;

reg [3-1:0] peron_selectat;
always @(*) begin
    if      (cai_eligibile[0] == 1'b1) peron_selectat = 3'd0;
    else if (cai_eligibile[1] == 1'b1) peron_selectat = 3'd1;
    else if (cai_eligibile[2] == 1'b1) peron_selectat = 3'd2;
    else if (cai_eligibile[3] == 1'b1) peron_selectat = 3'd3;
    else if (cai_eligibile[4] == 1'b1) peron_selectat = 3'd4;
    else if (cai_eligibile[5] == 1'b1) peron_selectat = 3'd5;
    else                               peron_selectat = 3'd7; // 7 = niciun peron gasit / eroare
end

// timp de stationare = nr_vagoane * durata per vagon
reg [12-1:0] timp_stationare_total; // 4 biti (vagoane) * 8 biti (durata) = max 12 biti
always @(*) begin
    case (cod_incarcatura)
        COD_A_MINEREURI: timp_stationare_total = nr_vagoane * durata_vagon_A;
        COD_B_CEREALE:   timp_stationare_total = nr_vagoane * durata_vagon_B;
        COD_C_PERSOANE:  timp_stationare_total = nr_vagoane * durata_vagon_C;
        default:         timp_stationare_total = 12'd0;
    endcase
end

// ---------------- FSM - LOGICA DE STATIONARE SI PLECARE ----------------
localparam [1:0] ST_IDLE    = 2'd0;
localparam [1:0] ST_WAITING = 2'd1; // Trenul sta la peron (timer)
localparam [1:0] ST_DEPART  = 2'd2; // Trenul vrea sa plece, asteapta out_ready

reg [1:0]    state;
reg [12-1:0] timer;
reg [3-1:0]  peron_activ;
reg [1:0]    tren_activ_id;

//registru stare
always @(posedge pclk or negedge presetn) begin
    if (~presetn) begin
        state <= ST_IDLE;
    end else begin
        case (state)
            ST_IDLE:    if (cerere_noua && cale_libera) state <= ST_WAITING;
            ST_WAITING: if (timer == 0)                 state <= ST_DEPART;
            ST_DEPART:  if (out_valid && out_ready)     state <= ST_IDLE;
            default:                                    state <= ST_IDLE;
        endcase
    end
end

// timer-ul de stationare
always @(posedge pclk or negedge presetn) begin
    if (~presetn) begin
        timer <= 12'd0;
    end else begin
        case (state)
            ST_IDLE: begin
                if (cerere_noua && cale_libera) timer <= timp_stationare_total;
            end
            ST_WAITING: begin
                if (timer > 0) timer <= timer - 1;
            end
        endcase
    end
end
// peron activ
always @(posedge pclk or negedge presetn) begin
    if (~presetn) peron_alocat <= 3'd0;
    else if (state == ST_IDLE && cerere_noua && cale_libera) peron_alocat <= peron_selectat;
end

always @(posedge pclk or negedge presetn) begin
    if (~presetn) peron_activ <= 3'd0;
    else if (state == ST_IDLE && cerere_noua && cale_libera) peron_activ <= peron_selectat;
end

always @(posedge pclk or negedge presetn) begin
    if (~presetn) tren_activ_id <= 2'd0;
    else if (state == ST_IDLE && cerere_noua && cale_libera) tren_activ_id <= id_tren;
end


// semnale de iesire 
always @(posedge pclk or negedge presetn) begin
    if (~presetn) begin
        out_valid <= 1'b0;
    end else begin
        case (state)
            ST_IDLE: begin
                out_valid <= 1'b0; // Evitam trimiterea de date false
            end
            ST_WAITING: begin
                if (timer == 0) out_valid <= 1'b1; // Handshake inițiat
            end
            ST_DEPART: begin
                if (out_valid && out_ready) out_valid <= 1'b0; // Handshake complet
            end
        endcase
    end
end
always @(posedge pclk or negedge presetn) begin
    if (~presetn) begin
        out_data <= 5'b0;
    end else begin
        case (state)
            ST_WAITING: begin
                if (timer == 0) out_data <= {peron_activ, tren_activ_id};
            end
        endcase
    end
end

// semafoare 
always @(posedge pclk or negedge presetn) begin
    if (~presetn) begin
        semafor_intrare <= 6'b111111; // 1 = Liber
    end else begin
        case (state)
            ST_IDLE: begin
                if (cerere_noua && cale_libera) semafor_intrare[peron_selectat] <= 1'b0; // Roșu
            end
            ST_DEPART: begin
                if (out_valid && out_ready) semafor_intrare[peron_activ] <= 1'b1; // Verde
            end
        endcase
    end
end
always @(posedge pclk or negedge presetn) begin
    if (~presetn) begin
        semafor_iesire <= 6'b000000; // 0 = Oprit
    end else begin
        case (state)
            ST_WAITING: begin
                if (timer == 0) semafor_iesire[peron_activ] <= 1'b1; // Verde
            end
            ST_DEPART: begin
                if (out_valid && out_ready) semafor_iesire[peron_activ] <= 1'b0; // Roșu
            end
        endcase
    end
end
// implementare Round Robin
endmodule