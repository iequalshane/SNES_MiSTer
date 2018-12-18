library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library STD;
use IEEE.NUMERIC_STD.ALL;


entity SCPU is
	port(
		CLK				: in std_logic;
		RST_N				: in std_logic;
		ENABLE			: in std_logic;
		
		CA       		: out std_logic_vector(23 downto 0);
		CPURD_N			: out std_logic;
		CPUWR_N			: out std_logic;
		
		PA					: out std_logic_vector(7 downto 0);
		PARD_N			: out std_logic;
		PAWR_N			: out std_logic;
		DI					: in std_logic_vector(7 downto 0);
		DO					: out std_logic_vector(7 downto 0);
		
		RAMSEL_N			: out std_logic;
		ROMSEL_N			: out std_logic;
		
		JPIO67			: out std_logic_vector(7 downto 6);
		REFRESH			: out std_logic;
		
		SYSCLK			: out std_logic;
		SYSCLKF_CE		: out std_logic;
		SYSCLKR_CE		: out std_logic;

		HBLANK			: in std_logic;
		VBLANK			: in std_logic;
		
		IRQ_N				: in std_logic;
		
		JOY1_DI			: in std_logic_vector(1 downto 0);
		JOY2_DI			: in std_logic_vector(1 downto 0);
		JOY_STRB			: out std_logic;
		JOY1_CLK			: out std_logic;
		JOY2_CLK			: out std_logic;
		
		DBG_CPU_BRK 	: out std_logic;
		DBG_REG			: in std_logic_vector(7 downto 0);
		DBG_DAT			: out std_logic_vector(7 downto 0);
		DBG_DAT_IN		: in std_logic_vector(7 downto 0);
		DBG_CPU_DAT		: out std_logic_vector(7 downto 0);
		DBG_CPU_WR		: in std_logic
	);
end SCPU;

architecture rtl of SCPU is

	--clocks
	signal INT_CLK : std_logic;
	signal EN : std_logic;
	signal INT_CLKR_CE, INT_CLKF_CE, DOT_CLK_CE : std_logic;
	signal P65_CLK_CNT : unsigned(3 downto 0);
	signal DMA_CLK_CNT : unsigned(2 downto 0);
	signal DOT_CLK_CNT : unsigned(1 downto 0);
	signal CPU_ACTIVEr, DMA_ACTIVEr : std_logic;
	signal H_CNT : unsigned(8 downto 0);
	signal V_CNT : unsigned(8 downto 0);
	signal FIELD : std_logic;

	--65C816
	signal P65_R_WN : std_logic;
	signal P65_A : std_logic_vector(23 downto 0);
	signal P65_DO : std_logic_vector(7 downto 0);
	signal P65_DI : std_logic_vector(7 downto 0);
	signal P65_NMI_N, P65_IRQ_N : std_logic;
	signal P65_EN, P65_EN_CE : std_logic;
	signal P65_VPA, P65_VDA : std_logic;
	signal P65_BRK : std_logic;

	type speed_t is (
		XSLOW,
		SLOW,
		FAST,
		SLOWFAST
	);
	signal SPEED : speed_t; 

	--CPU BUS
	signal INT_A : std_logic_vector(23 downto 0);
	signal INT_CPUWR_N, INT_CPURD_N : std_logic;
	signal IO_SEL : std_logic;
	signal CPU_WR, CPU_RD : std_logic;

	--DMA BUS
	signal DMA_A, HDMA_A : std_logic_vector(23 downto 0);
	signal DMA_B, HDMA_B : std_logic_vector(7 downto 0);
	signal DMA_A_WR, HDMA_A_WR, DMA_A_RD, HDMA_A_RD : std_logic;
	signal DMA_B_WR, DMA_B_RD, HDMA_B_WR, HDMA_B_RD	: std_logic;

	-- CPU IO Registers
	signal MDR : std_logic_vector(7 downto 0);
	signal NMI_EN : std_logic;
	signal HVIRQ_EN : std_logic_vector(1 downto 0);
	signal AUTO_JOY_EN : std_logic;
	signal WRIO	: std_logic_vector(7 downto 0);
	signal WRMPYA : std_logic_vector(7 downto 0);
	signal WRMPYB : std_logic_vector(7 downto 0);
	signal WRDIVA : std_logic_vector(15 downto 0);
	signal WRDIVB : std_logic_vector(7 downto 0);
	signal HTIME : std_logic_vector(8 downto 0) := (others => '1');
	signal VTIME : std_logic_vector(8 downto 0) := (others => '1');
	signal MDMAEN : std_logic_vector(7 downto 0);
	signal HDMAEN : std_logic_vector(7 downto 0);
	signal MEMSEL : std_logic;
	signal RDDIV, RDMPY : std_logic_vector(15 downto 0);

	signal IRQ_FLAG_RST, IRQ_FLAG_RSTr : std_logic;
	signal NMI_FLAG, IRQ_FLAG, NMI : std_logic;
	signal MUL_REQ, DIV_REQ : std_logic;
	signal REFRESHED : std_logic;
	signal MUL_CNT	: unsigned(3 downto 0);
	signal MATH_TEMP	: std_logic_vector(22 downto 0);
	signal VBLANKr, VBLANKrr : std_logic;
	signal IRQ_VALIDr, IRQ_VALIDrr : std_logic;

	-- DMA registers
	type DmaReg8 is array (0 to 7) of std_logic_vector(7 downto 0);
	type DmaReg16 is array (0 to 7) of std_logic_vector(15 downto 0);
	signal DMAP	: DmaReg8;
	signal BBAD	: DmaReg8;
	signal A1T	: DmaReg16;
	signal A1B	: DmaReg8;
	signal DAS	: DmaReg16;
	signal DASB	: DmaReg8;
	signal A2A	: DmaReg16;
	signal NTLR	: DmaReg8;
	signal UNUSED	: DmaReg8;

	signal DCH, HCH: integer range 0 to 7;
	signal DMA_RUN, HDMA_RUN : std_logic;
	signal DMA_ACTIVE : std_logic;
	signal HDMA_CH_WORK, HDMA_CH_RUN, HDMA_CH_DO: std_logic_vector(7 downto 0);
	signal HDMA_INIT_EXEC, HDMA_RUN_EXEC, HDMA_RUN_EXEC2 : std_logic;

	type ds_t is (
		DS_IDLE,
		DS_CH_SEL,
		DS_TRANSFER
	);
	signal DS : ds_t; 

	type hds_t is (
		HDS_IDLE,
		HDS_PRE_INIT,
		HDS_INIT,
		HDS_INIT_IND,
		HDS_PRE_TRANSFER,
		HDS_TRANSFER
	);
	signal HDS	: hds_t; 

	signal HDMA_INIT_STEP: unsigned(1 downto 0);
	signal DMA_TRMODE_STEP, HDMA_TRMODE_STEP: unsigned(1 downto 0);
	signal HDMA_FIRST_INIT : std_logic;
	type DmaTransMode is array (0 to 7, 0 to 3) of unsigned(1 downto 0);
	constant DMA_TRMODE_TAB	: DmaTransMode := (
	("00","00","00","00"),
	("00","01","00","01"),
	("00","00","00","00"),
	("00","00","01","01"),
	("00","01","10","11"),
	("00","01","00","01"),
	("00","00","00","00"),
	("00","00","01","01")
	);
	type DmaTransLenth is array (0 to 7) of unsigned(1 downto 0);
	constant DMA_TRMODE_LEN	: DmaTransLenth := ("00","01","01","11","11","11","01","11");

	impure function NextDMACh(data: std_logic_vector(7 downto 0)) return integer is
		variable res: integer range 0 to 7; 
	begin
		if data(0) = '1' then
			res := 0;
		elsif data(1) = '1' then
			res := 1;
		elsif data(2) = '1' then
			res := 2;
		elsif data(3) = '1' then
			res := 3;
		elsif data(4) = '1' then
			res := 4;
		elsif data(5) = '1' then
			res := 5;
		elsif data(6) = '1' then
			res := 6;
		elsif data(7) = '1' then
			res := 7;
		else
			res := 0;
		end if;
		return res;
	end function;

	impure function IsLastHDMACh(data: std_logic_vector(7 downto 0); ch: integer range 0 to 7) return std_logic is
		variable res: std_logic; 
		variable temp: unsigned(7 downto 0); 
	begin
		temp := unsigned(data) srl (ch+1);
		if temp = x"00" then
			res := '1';
		else
			res := '0';
		end if;
		return res;
	end function;

	-- JOY
	signal JOY1_DATA, JOY2_DATA, JOY3_DATA, JOY4_DATA : std_logic_vector(15 downto 0);
	signal AUTO_JOY_CLK: std_logic;
	signal OLD_JOY_STRB, AUTO_JOY_STRB: std_logic;
	signal OLD_JOY1_CLK, OLD_JOY2_CLK : std_logic;
	signal JOY_POLL_CLK : unsigned(5 downto 0);
	signal JOY_POLL_CNT : unsigned(4 downto 0);
	signal JOY_POLL_STRB : std_logic;
	signal JOYRD_BUSY : std_logic;
	signal JOY_POLL_RUN: std_logic;

	--debug
	signal FRAME_CNT: unsigned(15 downto 0);
	signal P65_RDY: std_logic;
	signal DBG_HDMA_CNT: unsigned(7 downto 0);

begin

	DMA_ACTIVE <= DMA_RUN or HDMA_RUN;

	process( RST_N, CLK )
		variable CPU_CYCLES : unsigned(3 downto 0);
	begin
		if RST_N = '0' then
			P65_CLK_CNT <= (others => '0');
			DMA_CLK_CNT <= (others => '0');
			INT_CLK <= '1';
			INT_CLKF_CE <= '0';
			INT_CLKR_CE <= '0';
			DOT_CLK_CE <= '0';
			CPU_ACTIVEr <= '1';
			DMA_ACTIVEr <= '0';
		elsif rising_edge(CLK) then
			if REFRESHED = '1' and CPU_ACTIVEr = '1' then
				CPU_CYCLES := x"8";
			elsif SPEED = FAST or (SPEED = SLOWFAST and MEMSEL = '1') then
				CPU_CYCLES := x"6";
			elsif SPEED = SLOW or (SPEED = SLOWFAST and MEMSEL = '0') then
				CPU_CYCLES := x"8";
			else
				CPU_CYCLES := x"C";
			end if;
			
			DMA_CLK_CNT <= DMA_CLK_CNT + 1;
			P65_CLK_CNT <= P65_CLK_CNT + 1;
			if P65_CLK_CNT = CPU_CYCLES-1  then
				P65_CLK_CNT <= (others => '0');
			end if;
			
			if DMA_ACTIVEr = '0' and DMA_ACTIVE = '1' and DMA_CLK_CNT = 7 and REFRESHED = '0' then
				DMA_ACTIVEr <= '1';
			elsif DMA_ACTIVEr = '1' and DMA_ACTIVE = '0' and REFRESHED = '0' then
				DMA_ACTIVEr <= '0';
			end if;
			
			if CPU_ACTIVEr = '1' and DMA_ACTIVE = '1' and DMA_ACTIVEr = '0' and REFRESHED = '0' then
				CPU_ACTIVEr <= '0';
			elsif CPU_ACTIVEr = '0' and DMA_ACTIVE = '0' and P65_CLK_CNT = CPU_CYCLES-1 and REFRESHED = '0' then
				CPU_ACTIVEr <= '1';
			end if;
			
			DOT_CLK_CE <= '0';
			if DMA_CLK_CNT(1 downto 0) = 4-1-1 then
				DOT_CLK_CE <= '1';
			end if;
				
			INT_CLKF_CE <= '0';
			INT_CLKR_CE <= '0';
			if DMA_ACTIVEr = '1' or ENABLE = '0' then
				if DMA_CLK_CNT = 4-1 then
					INT_CLK <= '1';
				elsif DMA_CLK_CNT = 8-1 then
					INT_CLK <= '0';
				end if;
				
				if DMA_CLK_CNT = 4-1-1 then
					INT_CLKR_CE <= '1';
				elsif DMA_CLK_CNT = 8-1-1 then
					INT_CLKF_CE <= '1';
				end if;
			elsif CPU_ACTIVEr = '1' then
				if P65_CLK_CNT = 3-1 then
					INT_CLK <= '1';
				elsif P65_CLK_CNT = CPU_CYCLES-1  then
					INT_CLK <= '0';
				end if;
				
				if P65_CLK_CNT = 3-1-1 then
					INT_CLKR_CE <= '1';
				elsif P65_CLK_CNT = CPU_CYCLES-1-1  then
					INT_CLKF_CE <= '1';
				end if;
			end if;
		end if;
	end process;

	EN <= ENABLE and (not REFRESHED);
	P65_EN <= not DMA_ACTIVE and EN;
	P65_EN_CE <= not DMA_ACTIVE and EN and INT_CLKF_CE;

	SYSCLK <= INT_CLK; 
	SYSCLKF_CE <= INT_CLKF_CE;
	SYSCLKR_CE <= INT_CLKR_CE;


	-- 65C816
	P65C816: entity work.P65C816 
	port map (
		CLK         => CLK,
		RST_N       => RST_N,
		WE          => P65_R_WN,
		D_IN     	=> P65_DI,
		D_OUT    	=> P65_DO,
		A_OUT			=> P65_A,
		RDY_IN      => P65_EN_CE,
		NMI_N       => P65_NMI_N,    
		IRQ_N       => P65_IRQ_N,
		ABORT_N     => '1',
		VPA      	=> P65_VPA,
		VDA      	=> P65_VDA,
		RDY_OUT     => P65_RDY,
		
		BRK_OUT     => P65_BRK,
		DBG_REG     => DBG_REG,
		DBG_DAT_IN	=> DBG_DAT_IN,
		DBG_DAT_OUT	=> DBG_CPU_DAT,
		DBG_DAT_WR	=> DBG_CPU_WR
	); 


	process(P65_A, P65_VPA, P65_VDA)
	begin
		SPEED <= SLOW;
		
		if P65_VPA = '0' and P65_VDA = '0' then 
			SPEED <= FAST;
		elsif P65_A(22) = '0' then 																	--$00-$3F, $80-$BF | System Area 
			if P65_A(15 downto 9) = "0100000" then 												--$4000-$41FF | XSlow
				SPEED <= XSLOW;
			elsif P65_A(15 downto 8) <= x"1F" or 													--$0000-$1FFF | Slow
					(P65_A(15 downto 8) >= x"60" and P65_A(15 downto 8) <= x"7F") then 	--$6000-$7FFF | Slow
				SPEED <= SLOW;
			elsif P65_A(15) = '1' then 																--$8000-$FFFF | Fast,Slow
				if P65_A(23) = '0' then											
					SPEED <= SLOW;
				else
					SPEED <= SLOWFAST;
				end if;
			else
				SPEED <= FAST;
			end if;
		elsif P65_A(23 downto 16) >= x"40" and P65_A(23 downto 16) <= x"7F"  then		--$40-$7D | $0000-$FFFF | Slow
			SPEED <= SLOW;																					--$7E-$7F | $0000-$FFFF | Slow
		elsif P65_A(23 downto 16) >= x"C0" and P65_A(23 downto 16) <= x"FF"  then		--$C0-$FF | $0000-$FFFF | Fast,Slow
			SPEED <= SLOWFAST;
		end if;
	end process;


	INT_A <= HDMA_A when HDMA_RUN = '1' else
				DMA_A when DMA_RUN = '1' else
				P65_A;
			
	process(INT_A)
	begin
		RAMSEL_N <= '1';
		ROMSEL_N <= '1';
		
		CA <= INT_A;

		if INT_A(22) = '0' then 																		--$00-$3F, $80-$BF
			if INT_A(15 downto 8) <= x"1F" then														--$0000-$1FFF | Slow  | Address Bus A + /WRAM (mirror $7E:0000-$1FFF)
				CA(23 downto 13) <= x"7E" & "000";
				RAMSEL_N <= '0';
			elsif INT_A(15) = '1' then	 																--$8000-$FFFF | Slow  | Address Bus A + /CART
				ROMSEL_N <= '0';
			end if;
		else																									--$40-$7F, $C0-$FF
			if (INT_A(23 downto 16) >= x"40" and INT_A(23 downto 16) <= x"7D") or		--$40-$7D | $0000-$FFFF | Slow  | Address Bus A + /CART
				(INT_A(23 downto 16) >= x"C0" and INT_A(23 downto 16) <= x"FF") then		--$C0-$FF | $0000-$FFFF | Fast,Slow | Address Bus A + /CART
				ROMSEL_N <= '0';
			elsif INT_A(23 downto 17) = "0111111" then											--$7E-$7F | $0000-$FFFF | Slow  | Address Bus A + /WRAM
				RAMSEL_N <= '0';
			end if;
		end if;
	end process;


	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			CPU_WR <= '0';
			CPU_RD <= '0';
		elsif rising_edge(CLK) then
			if EN = '1' then
				if P65_EN = '1' and (P65_VPA = '1' or P65_VDA = '1') and INT_CLKR_CE = '1' then
					CPU_WR <= not P65_R_WN;
					CPU_RD <= P65_R_WN;
				elsif INT_CLKF_CE = '1' then
					CPU_WR <= '0';
					CPU_RD <= '0';
				end if;
			end if;
		end if;
	end process;
	
	process(P65_A, EN, CPU_RD, CPU_WR, DMA_B, DMA_B_RD, DMA_B_WR, DMA_A_RD, DMA_A_WR, 
			  HDMA_B, HDMA_A_RD, HDMA_A_WR, HDMA_B_RD, HDMA_B_WR, DMA_RUN, HDMA_RUN, P65_EN)
	begin
		if HDMA_RUN = '1' and EN = '1' then
			PA <= HDMA_B;
			PARD_N <= not HDMA_B_RD;
			PAWR_N <= not HDMA_B_WR;
		elsif DMA_RUN = '1' and EN = '1' then
			PA <= DMA_B;
			PARD_N <= not DMA_B_RD;
			PAWR_N <= not DMA_B_WR;
		elsif P65_A(22) = '0' and P65_A(15 downto 8) = x"21" and P65_EN = '1' then
			PA <= P65_A(7 downto 0);
			PARD_N <= not CPU_RD;
			PAWR_N <= not CPU_WR;
		else
			PA <= x"FF";
			PARD_N <= '1';
			PAWR_N <= '1';
		end if;
		
		if HDMA_RUN = '1' and EN = '1' then
			INT_CPURD_N <= not HDMA_A_RD;
			INT_CPUWR_N <= not HDMA_A_WR; 
		elsif DMA_RUN = '1' and EN = '1' then
			INT_CPURD_N <= not DMA_A_RD;
			INT_CPUWR_N <= not DMA_A_WR;
		elsif P65_EN = '1' then
			INT_CPURD_N <= not CPU_RD;
			INT_CPUWR_N <= not CPU_WR; 
		else
			INT_CPURD_N <= '1';
			INT_CPUWR_N <= '1'; 
		end if;
	end process;
	
	CPURD_N <= INT_CPURD_N;
	CPUWR_N <= INT_CPUWR_N; 

	
	--IO Registers
	IO_SEL <= '1' when P65_EN = '1' and P65_A(22) = '0' and P65_A(15 downto 10) = "010000" and (P65_VPA = '1' or P65_VDA = '1') else '0';	--$00-$3F/$80-$BF:$4000-$43FF

	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			HVIRQ_EN <= (others => '0');
			NMI_EN <= '0';
			AUTO_JOY_EN <= '0';
			WRIO <= (others => '1');
			WRMPYA <= (others => '1');
			WRMPYB <= (others => '0');
			WRDIVA <= (others => '1');
			WRDIVB <= (others => '0');
			MEMSEL <= '0';
			RDDIV <= (others => '0');
			RDMPY <= (others => '0');
			HTIME <= (others => '1');
			VTIME <= (others => '1');

			NMI_FLAG <= '0'; 
			NMI <= '0';
			VBLANKrr <= '0';
			IRQ_FLAG_RST <= '0';
			
			MUL_REQ <= '0';
			DIV_REQ <= '0';
			MUL_CNT <= (others => '0');
			MATH_TEMP <= (others => '0');
			
		elsif rising_edge(CLK) then
			if ENABLE = '1' and INT_CLKF_CE = '1' then
				VBLANKrr <= VBLANK;

				if VBLANK = '1' and VBLANKrr = '0' then
					NMI_FLAG <= '1';
				elsif VBLANK = '0' and VBLANKrr = '1' then
					NMI_FLAG <= '0';
					NMI <= '0';
				elsif P65_R_WN = '1' and P65_A(15 downto 0) = x"4210" and IO_SEL = '1' then
					NMI_FLAG <= '0'; 
					NMI <= '0';
				end if;
				
				if NMI_FLAG = '1' and NMI = '0' and DMA_ACTIVE = '0' and NMI_EN = '1' then
					NMI <= '1';
				end if;

				if MUL_REQ = '1' then
					if RDDIV(0) = '1' then
						RDMPY <= std_logic_vector(unsigned(RDMPY) + unsigned(MATH_TEMP(15 downto 0)));
					end if;
					RDDIV <= "0" & RDDIV(15 downto 1);
					MATH_TEMP <= MATH_TEMP(21 downto 0) & "0";
					MUL_CNT <= MUL_CNT + 1;
					if MUL_CNT = 7 then
						MUL_REQ <= '0';
					end if;
				end if;
				
				if DIV_REQ = '1' then
					if unsigned(RDMPY) >= unsigned(MATH_TEMP) then
						RDMPY <= std_logic_vector(unsigned(RDMPY) - unsigned(MATH_TEMP(15 downto 0)));
						RDDIV <= RDDIV(14 downto 0) & "1";
					else
						RDDIV <= RDDIV(14 downto 0) & "0";
					end if;
					MATH_TEMP <= "0" & MATH_TEMP(22 downto 1);
					MUL_CNT <= MUL_CNT + 1;
					if MUL_CNT = 15 then
						DIV_REQ <= '0';
					end if;
				end if;
		
				IRQ_FLAG_RST <= '0';
				if P65_A(15 downto 8) = x"42" and IO_SEL = '1' then
					if P65_R_WN = '0' then
						case P65_A(7 downto 0) is
							when x"00" =>
								NMI_EN <= P65_DO(7);
								HVIRQ_EN <= P65_DO(5 downto 4);
								AUTO_JOY_EN <= P65_DO(0);
								if P65_DO(5 downto 4) = "00" then
									IRQ_FLAG_RST <= '1';
								end if;
							when x"01" =>
								WRIO <= P65_DO;
							when x"02" =>
								WRMPYA <= P65_DO;
							when x"03" =>
								WRMPYB <= P65_DO;
								RDMPY <= (others => '0');
								RDDIV <= P65_DO & WRMPYA;
								MATH_TEMP <= "000000000000000" & P65_DO;
								MUL_CNT <= (others => '0');
								MUL_REQ <= '1';
							when x"04" =>
								WRDIVA(7 downto 0) <= P65_DO;
							when x"05" =>
								WRDIVA(15 downto 8) <= P65_DO;
							when x"06" =>
								WRDIVB <= P65_DO;
								RDMPY <= WRDIVA;
								RDDIV <= (others => '0');
								MATH_TEMP <= P65_DO & "000000000000000";
								MUL_CNT <= (others => '0');
								DIV_REQ <= '1';
							when x"07" =>
								HTIME(7 downto 0) <= P65_DO;
							when x"08" =>
								HTIME(8) <= P65_DO(0);
							when x"09" =>
								VTIME(7 downto 0) <= P65_DO;
							when x"0A" =>
								VTIME(8) <= P65_DO(0);
							when x"0D" =>
								MEMSEL <= P65_DO(0);
							when others => null;
						end case;
					else
						case P65_A(7 downto 0) is
							when x"10" =>
							when x"11" =>
								IRQ_FLAG_RST <= '1';
							when others => null;
						end case;
					end if;
				end if;
			end if;
		end if;
	end process;
	
	process( P65_A, IO_SEL, DI, NMI_FLAG, IRQ_FLAG, MDR, VBLANK, HBLANK, 
				RDDIV, RDMPY, JOYRD_BUSY, JOY1_DATA, JOY2_DATA, JOY3_DATA, JOY4_DATA, JOY1_DI, JOY2_DI,
				DMAP, BBAD, A1T, A1B, DAS, DASB, A2A, NTLR, UNUSED, AUTO_JOY_EN)
	variable i : integer range 0 to 7;
	begin
		P65_DI <= DI;
		if IO_SEL = '1' then
			P65_DI <= MDR;
			if P65_A(15 downto 8) = x"42" then
				case P65_A(7 downto 0) is
					when x"10" =>
						P65_DI <= NMI_FLAG & MDR(6 downto 4) & "0010";					--RDNMI
					when x"11" =>
						P65_DI <= IRQ_FLAG & MDR(6 downto 0);								--TIMEUP
					when x"12" =>
						P65_DI <= VBLANK & HBLANK & MDR(5 downto 1) & JOYRD_BUSY;	--HVBJOY
					when x"13" =>
						P65_DI <= x"00";															--RDIO
					when x"14" =>
						P65_DI <= RDDIV(7 downto 0);											--RDDIVL
					when x"15" =>
						P65_DI <= RDDIV(15 downto 8);											--RDDIVH
					when x"16" =>
						P65_DI <= RDMPY(7 downto 0);											--RDMPYL
					when x"17" =>
						P65_DI <= RDMPY(15 downto 8);											--RDMPYH
					when x"18" =>
						P65_DI <= JOY1_DATA(7 downto 0);										--JOY1L
					when x"19" =>
						P65_DI <= JOY1_DATA(15 downto 8);									--JOY1H
					when x"1A" =>
						P65_DI <= JOY2_DATA(7 downto 0);										--JOY2L
					when x"1B" =>
						P65_DI <= JOY2_DATA(15 downto 8);									--JOY2H
					when x"1C" =>
						P65_DI <= JOY3_DATA(7 downto 0);										--JOY3L
					when x"1D" =>
						P65_DI <= JOY3_DATA(15 downto 8);									--JOY3H
					when x"1E" =>
						P65_DI <= JOY4_DATA(7 downto 0);										--JOY4L
					when x"1F" =>
						P65_DI <= JOY4_DATA(15 downto 8);									--JOY4H
					when others => 
						P65_DI <= MDR;
				end case;
			elsif P65_A(15 downto 8) = x"43" then
				i := to_integer(unsigned(P65_A(6 downto 4)));
				case P65_A(3 downto 0) is
					when x"0" =>
						P65_DI <= DMAP(i);														--DMAPx
					when x"1" =>
						P65_DI <= BBAD(i);														--BBADx
					when x"2" =>
						P65_DI <= A1T(i)(7 downto 0);											--A1TxL
					when x"3" =>
						P65_DI <= A1T(i)(15 downto 8);										--A1TxH
					when x"4" =>
						P65_DI <= A1B(i);															--A1Bx
					when x"5" =>
						P65_DI <= DAS(i)(7 downto 0);											--DASxL
					when x"6" =>
						P65_DI <= DAS(i)(15 downto 8);										--DASxH
					when x"7" =>
						P65_DI <= DASB(i);														--DASBx
					when x"8" =>
						P65_DI <= A2A(i)(7 downto 0);											--A2AxL
					when x"9" =>
						P65_DI <= A2A(i)(15 downto 8);										--A2AxH
					when x"A" =>
						P65_DI <= NTLR(i);														--NTLRx
					when x"B" =>
						P65_DI <= UNUSED(i);														--UNUSEDx
					when others => 
						P65_DI <= MDR;
				end case;
			elsif P65_A(15 downto 8) = x"40" then
				case P65_A(7 downto 0) is
					when x"16" =>
						P65_DI <= MDR(7 downto 2) & (not JOY1_DI(1)) & ((not JOY1_DI(0)));-- or AUTO_JOY_EN
					when x"17" =>
						P65_DI <= MDR(7 downto 5) & "111" & (not JOY2_DI(1)) & ((not JOY2_DI(0)));-- or AUTO_JOY_EN
					when others => 
						P65_DI <= MDR;
				end case;
			end if;
		end if;
	end process;

	JPIO67 <= WRIO(7 downto 6);

	
	--MDR
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			MDR <= (others => '1');
		elsif rising_edge(CLK) then
			if INT_CLKR_CE = '1' then
				if P65_EN = '1' and (P65_VPA = '1' or P65_VDA = '1') and P65_R_WN = '0' then
					MDR <= P65_DO;
				end if;
			elsif INT_CLKF_CE = '1' then
				if P65_EN = '1' and (P65_VPA = '1' or P65_VDA = '1') and P65_R_WN = '1' then
					MDR <= P65_DI;
				elsif DMA_ACTIVE = '1' and EN = '1' then
					MDR <= DI;
				end if;
			end if;
		end if;
	end process; 
 
	DO <= MDR;


	-- H/V Counters
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			H_CNT <= (others => '0');
			V_CNT <= (others => '0');
			FIELD <= '0';
			FRAME_CNT <= (others => '0');
			VBLANKr <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' and DOT_CLK_CE = '1' then
				VBLANKr <= VBLANK;
				if H_CNT = 340 or (VBLANK = '0' and VBLANKr = '1') then
					H_CNT <= (others => '0');
					if VBLANK = '0' and VBLANKr = '1' then
						V_CNT <= (others => '0');
						H_CNT <= (others => '0');
						FIELD <= not FIELD;
						FRAME_CNT <= FRAME_CNT + 1;
					else
						V_CNT <= V_CNT + 1;	
					end if;
				else
					H_CNT <= H_CNT + 1;
				end if;
			end if;
		end if;
	end process;

	-- IRQ
	process( RST_N, CLK )
		variable IRQ_VALID : std_logic;
	begin
		if RST_N = '0' then
			IRQ_FLAG <= '0';
			IRQ_VALIDr <= '0';
			IRQ_FLAG_RSTr <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' and DOT_CLK_CE = '1' then
				if HVIRQ_EN = "01" and H_CNT = unsigned(HTIME) + 2 then--H-IRQ:  every scanline, H=HTIME+~3.5
					IRQ_VALID := '1';
				elsif HVIRQ_EN = "10" and H_CNT >= 2 and V_CNT = unsigned(VTIME) then--V-IRQ:  V=VTIME, H=~2.5--H_CNT <= 4 and
					IRQ_VALID := '1';
				elsif HVIRQ_EN = "11" and H_CNT = unsigned(HTIME) + 2 and V_CNT = unsigned(VTIME) then--HV-IRQ: V=VTIME, H=HTIME+~3.5
					IRQ_VALID := '1';
				else
					IRQ_VALID := '0';
				end if;
				
				IRQ_VALIDr <= IRQ_VALID;
				IRQ_FLAG_RSTr <= IRQ_FLAG_RST;
				if IRQ_FLAG = '0' and IRQ_VALID = '1' and IRQ_VALIDr = '0' then
					IRQ_FLAG <= '1';
				elsif IRQ_FLAG = '1' and IRQ_FLAG_RST = '1' and IRQ_FLAG_RSTr = '0' then
					IRQ_FLAG <= '0';
				end if;
			end if;
		end if;
	end process; 

	P65_NMI_N <= not NMI;
	P65_IRQ_N <= not IRQ_FLAG and IRQ_N; 


	--WRAM refresh
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			REFRESHED <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' and INT_CLKF_CE = '1' then
				if REFRESHED = '0' and H_CNT >= 132 and H_CNT < 132 + 10 then
					REFRESHED <= '1';
				elsif REFRESHED = '1' and H_CNT >= 132 + 10 then
					REFRESHED <= '0';
				end if;
			end if;
		end if;
	end process;

	REFRESH <= REFRESHED and INT_CLK;


	--DMA/HDMA
	process( RST_N, CLK )
		variable i : integer range 0 to 7;
		variable NEXT_NTLR : std_logic_vector(7 downto 0);
	begin
		if RST_N = '0' then
			MDMAEN <= (others => '0');
			HDMAEN <= (others => '0');
			
			DMAP <= (others => (others => '1'));
			BBAD <= (others => (others => '1'));
			A1T <= (others => (others => '1'));
			A1B <= (others => (others => '1'));
			DAS <= (others => (others => '1'));
			DASB <= (others => (others => '1'));
			A2A <= (others => (others => '1'));
			NTLR <= (others => (others => '1'));
			UNUSED <= (others => (others => '1'));
			
			DMA_RUN <= '0';
			HDMA_RUN <= '0';
			HDMA_CH_RUN <= (others => '0');
			HDMA_CH_DO <= (others => '0');
			HDMA_CH_WORK <= (others => '0');
			DMA_TRMODE_STEP <= (others => '0');
			HDMA_TRMODE_STEP <= (others => '0');
			HDMA_INIT_STEP <= (others => '0');
			HDMA_FIRST_INIT <= '0';
			DS <= DS_IDLE;
			HDS <= HDS_IDLE;
			
			HDMA_INIT_EXEC <= '1';
			HDMA_RUN_EXEC <= '0';
		elsif rising_edge(CLK) then
			if P65_R_WN = '0' and IO_SEL = '1' and INT_CLKF_CE = '1' then
				if P65_A(15 downto 8) = x"42" then
					case P65_A(7 downto 0) is
						when x"0B" =>
							MDMAEN <= P65_DO;
						when x"0C" =>
							HDMAEN <= P65_DO;
						when others => null;
					end case;
				elsif P65_A(15 downto 8) = x"43" then
					i := to_integer(unsigned(P65_A(6 downto 4)));
					case P65_A(3 downto 0) is
						when x"0" =>
							DMAP(i) <= P65_DO;
						when x"1" =>
							BBAD(i) <= P65_DO;
						when x"2" =>
							A1T(i)(7 downto 0) <= P65_DO;
						when x"3" =>
							A1T(i)(15 downto 8) <= P65_DO;
						when x"4" =>
							A1B(i) <= P65_DO;
						when x"5" =>
							DAS(i)(7 downto 0) <= P65_DO;
						when x"6" =>
							DAS(i)(15 downto 8) <= P65_DO;
						when x"7" =>
							DASB(i) <= P65_DO;
						when x"8" =>
							A2A(i)(7 downto 0) <= P65_DO;
						when x"9" =>
							A2A(i)(15 downto 8) <= P65_DO;
						when x"A" =>
							NTLR(i) <= P65_DO;
						when x"B" =>
							UNUSED(i) <= P65_DO;
						when others => null;
					end case;
				end if;
			end if;
				
			if EN = '1' and INT_CLKF_CE = '1' then
				--DMA
				if HDMA_RUN = '0' then
					case DS is
						when DS_IDLE =>
							if MDMAEN /= x"00" then
								DMA_RUN <= '1';
								DS <= DS_CH_SEL;
							end if;
							
						when DS_CH_SEL =>
							if MDMAEN /= x"00" then
								DAS(DCH) <= std_logic_vector(unsigned(DAS(DCH)) - 1);
								DMA_TRMODE_STEP <= (others => '0');
								DS <= DS_TRANSFER;
							else
								DMA_RUN <= '0';
								DS <= DS_IDLE;
							end if;
							
						when DS_TRANSFER =>
							case DMAP(DCH)(4 downto 3) is
								when "00" => A1T(DCH) <= std_logic_vector(unsigned(A1T(DCH)) + 1);
								when "10" => A1T(DCH) <= std_logic_vector(unsigned(A1T(DCH)) - 1);
								when others => null;
							end case;
							if DAS(DCH) /= x"0000" then
								DAS(DCH) <= std_logic_vector(unsigned(DAS(DCH)) - 1);
								DMA_TRMODE_STEP <= DMA_TRMODE_STEP + 1;
							else
								MDMAEN(DCH) <= '0';
								DS <= DS_CH_SEL;
							end if;
							
						when others => null;
					end case;
				end if;
				
				--HDMA
				case HDS is
					when HDS_IDLE =>
						if H_CNT >= 4 and V_CNT = 0 and HDMA_INIT_EXEC = '0' then
							HDMA_CH_RUN <= (others => '1');
							HDMA_CH_DO <= (others => '0'); 
							if HDMAEN /= x"00" then
								HDMA_RUN <= '1';
								HDS <= HDS_PRE_INIT;
							end if;
							HDMA_INIT_EXEC <= '1';
						elsif V_CNT /= 0 and HDMA_INIT_EXEC = '1' then
							HDMA_INIT_EXEC <= '0';
						end if;
						
						if H_CNT >= 275 and VBLANK = '0' and HDMA_RUN_EXEC = '0' then
							if (HDMA_CH_RUN and HDMAEN) /= x"00" then
								HDMA_RUN <= '1';
								HDS <= HDS_PRE_TRANSFER;
								DBG_HDMA_CNT <= (others => '0'); 
							end if;
							HDMA_RUN_EXEC <= '1';
						elsif H_CNT < 275 and VBLANK = '0' and HDMA_RUN_EXEC = '1' then
							HDMA_RUN_EXEC <= '0';
						end if;

					when HDS_PRE_INIT =>
						for i in 0 to 7 loop
							if HDMAEN(i) = '1' then
								A2A(i) <= A1T(i);
								NTLR(i) <= (others => '0'); 
								MDMAEN(i) <= '0';
							end if;
						end loop;
						HDMA_CH_WORK <= HDMAEN;
						HDMA_FIRST_INIT <= '1';
						HDS <= HDS_INIT;
						
					when HDS_INIT =>
						NEXT_NTLR := std_logic_vector(unsigned(NTLR(HCH)) - 1); 
						if NEXT_NTLR(6 downto 0) = "0000000" or HDMA_FIRST_INIT = '1' then
							NTLR(HCH) <= DI;
							
							if DI = x"00" then
								HDMA_CH_RUN(HCH) <= '0';
								HDMA_CH_DO(HCH) <= '0';
							else
								HDMA_CH_DO(HCH) <= '1';
							end if;
							
							if DMAP(HCH)(6) = '0' then
								HDMA_CH_WORK(HCH) <= '0';
								if IsLastHDMACh(HDMA_CH_WORK, HCH) = '1' then
									HDMA_RUN <= '0';
									HDS <= HDS_IDLE;
								end if;
							else
								HDMA_INIT_STEP <= (others => '0');
								HDS <= HDS_INIT_IND;
							end if;
							A2A(HCH) <= std_logic_vector(unsigned(A2A(HCH)) + 1);
						else
							NTLR(HCH) <= NEXT_NTLR; 
							HDMA_CH_DO(HCH) <= NEXT_NTLR(7); 
							
							HDMA_CH_WORK(HCH) <= '0';
							if IsLastHDMACh(HDMA_CH_WORK, HCH) = '1' then
								HDMA_RUN <= '0';
								HDS <= HDS_IDLE;
							end if;
						end if;	
						DBG_HDMA_CNT <= DBG_HDMA_CNT + 1; 
				
					when HDS_INIT_IND =>
						DAS(HCH) <= DI & DAS(HCH)(15 downto 8);
						HDMA_INIT_STEP <= HDMA_INIT_STEP + 1;
						A2A(HCH) <= std_logic_vector(unsigned(A2A(HCH)) + 1);
						if HDMA_INIT_STEP(0) = '1' then
							HDMA_CH_WORK(HCH) <= '0';
							if IsLastHDMACh(HDMA_CH_WORK, HCH) = '1' then
								HDMA_RUN <= '0';
								HDS <= HDS_IDLE;
							else
								HDS <= HDS_INIT;
							end if;
						end if;
						DBG_HDMA_CNT <= DBG_HDMA_CNT + 1; 
						
					when HDS_PRE_TRANSFER =>
						for i in 0 to 7 loop
							if HDMA_CH_RUN(i) = '1' and HDMAEN(i) = '1' then
								MDMAEN(i) <= '0';
							end if;
						end loop;

						HDMA_FIRST_INIT <= '0';
						
						if HDMA_CH_DO /= x"00" then
							HDMA_CH_WORK <= HDMA_CH_DO and HDMAEN;
							HDMA_TRMODE_STEP <= (others => '0');
							HDS <= HDS_TRANSFER;
						else
							HDMA_CH_WORK <= HDMA_CH_RUN and HDMAEN;
							HDS <= HDS_INIT;
						end if;
						DBG_HDMA_CNT <= DBG_HDMA_CNT + 1; 
						
					when HDS_TRANSFER =>
						HDMA_TRMODE_STEP <= HDMA_TRMODE_STEP + 1;
						if DMAP(HCH)(6) = '0' then
							A2A(HCH) <= std_logic_vector(unsigned(A2A(HCH)) + 1);
						else
							DAS(HCH) <= std_logic_vector(unsigned(DAS(HCH)) + 1);
						end if;
						
						if HDMA_TRMODE_STEP = DMA_TRMODE_LEN(to_integer(unsigned(DMAP(HCH)(2 downto 0)))) then
							HDMA_TRMODE_STEP <= (others => '0');
							HDMA_CH_WORK(HCH) <= '0';
							if IsLastHDMACh(HDMA_CH_WORK, HCH) = '1' then
								HDMA_CH_WORK <= HDMA_CH_RUN and HDMAEN;
								HDMA_INIT_STEP <= (others => '0');
								HDS <= HDS_INIT;
							end if;
						end if;
						DBG_HDMA_CNT <= DBG_HDMA_CNT + 1; 
						
					when others => null;
				end case;
			end if;
		end if;
	end process;

	HCH <= NextDMACh(HDMA_CH_WORK);
	DCH <= NextDMACh(MDMAEN);

	DMA_A <= A1B(DCH) & A1T(DCH) when DS = DS_TRANSFER else (others => '1');
	DMA_B <= std_logic_vector( unsigned(BBAD(DCH)) + DMA_TRMODE_TAB(to_integer(unsigned(DMAP(DCH)(2 downto 0))),to_integer(DMA_TRMODE_STEP)) ) when DS = DS_TRANSFER else (others => '1');
					
	HDMA_A <= DASB(HCH) & std_logic_vector(unsigned(DAS(HCH))) when DMAP(HCH)(6) = '1' and HDS = HDS_TRANSFER else 
				 A1B(HCH) & std_logic_vector(unsigned(A2A(HCH))) when DMAP(HCH)(6) = '0' and HDS = HDS_TRANSFER else 
				 A1B(HCH) & std_logic_vector(unsigned(A2A(HCH))) when HDS = HDS_INIT or HDS = HDS_INIT_IND else 
				 (others => '1');
	HDMA_B <= std_logic_vector( unsigned(BBAD(HCH)) + DMA_TRMODE_TAB(to_integer(unsigned(DMAP(HCH)(2 downto 0))),to_integer(HDMA_TRMODE_STEP)) ) when HDS = HDS_TRANSFER else (others => '1');

	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			DMA_A_WR <= '0';
			DMA_A_RD <= '0';
			DMA_B_WR <= '0';
			DMA_B_RD <= '0';
			HDMA_A_WR <= '0';
			HDMA_A_RD <= '0';
			HDMA_B_WR <= '0';
			HDMA_B_RD <= '0';	
		elsif rising_edge(CLK) then
			if EN = '1' then
				if DS = DS_TRANSFER and INT_CLKR_CE = '1' then
					DMA_A_WR <= DMAP(DCH)(7);
					DMA_A_RD <= not DMAP(DCH)(7);
					DMA_B_WR <= not DMAP(DCH)(7);
					DMA_B_RD <= DMAP(DCH)(7);
				elsif INT_CLKF_CE = '1' then
					DMA_A_WR <= '0';
					DMA_A_RD <= '0';
					DMA_B_WR <= '0';
					DMA_B_RD <= '0';
				end if;
				
				if HDS = HDS_TRANSFER and INT_CLKR_CE = '1' then
					HDMA_A_WR <= DMAP(HCH)(7);
					HDMA_A_RD <= not DMAP(HCH)(7);
					HDMA_B_WR <= not DMAP(HCH)(7);
					HDMA_B_RD <= DMAP(HCH)(7);
				elsif (HDS = HDS_INIT or HDS = HDS_INIT_IND) and INT_CLKR_CE = '1' then
					HDMA_A_WR <= '0';
					HDMA_A_RD <= '1';
					HDMA_B_WR <= '0';
					HDMA_B_RD <= '0';
				elsif INT_CLKF_CE = '1' then
					HDMA_A_WR <= '0';
					HDMA_A_RD <= '0';
					HDMA_B_WR <= '0';
					HDMA_B_RD <= '0';
				end if;
			end if;
		end if;
	end process;
			
	
	--Joy old
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			OLD_JOY_STRB <= '0';
			OLD_JOY1_CLK <= '0';
			OLD_JOY2_CLK <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' and INT_CLKF_CE = '1' then
				OLD_JOY1_CLK <= '0';
				OLD_JOY2_CLK <= '0';
				if P65_A(15 downto 8) = x"40" and IO_SEL = '1' then
					if P65_R_WN = '0' then
						case P65_A(7 downto 0) is
							when x"16" =>
								OLD_JOY_STRB <= P65_DO(0);
							when others => null;
						end case;
					else
						case P65_A(7 downto 0) is
							when x"16" =>
								OLD_JOY1_CLK <= '1';
							when x"17" =>
								OLD_JOY2_CLK <= '1';
							when others => null;
						end case;
					end if;
				end if;
			end if;
		end if;
	end process;

	-- Joy auto 
	process( RST_N, CLK )
	begin
		if RST_N = '0' then
			JOY1_DATA <= (others => '0');
			JOY2_DATA <= (others => '0');
			JOY3_DATA <= (others => '0');
			JOY4_DATA <= (others => '0');
			JOY_POLL_CLK <= (others => '0');
			JOY_POLL_CNT <= (others => '0');
			JOY_POLL_RUN <= '0';
			JOYRD_BUSY <= '0';
			AUTO_JOY_STRB <= '0';
			AUTO_JOY_CLK <= '0';
		elsif rising_edge(CLK) then
			if ENABLE = '1' and DOT_CLK_CE = '1' then
				if V_CNT = 0 then
					JOY_POLL_CNT <= (others => '0');
				end if;
				
				JOY_POLL_CLK <= JOY_POLL_CLK + 1;
				if JOY_POLL_CLK = 63 and VBLANK = '1' and JOY_POLL_RUN = '0' and JOY_POLL_CNT = 0 and AUTO_JOY_EN = '1' then
					JOY_POLL_RUN <= '1';
				elsif JOY_POLL_CLK(4 downto 0) = 31 and JOY_POLL_RUN = '1' then
					if JOY_POLL_STRB = '0' then
						if JOY_POLL_CLK(5) = '0' then
							AUTO_JOY_STRB <= '1';
							JOYRD_BUSY <= '1';
						else
							AUTO_JOY_STRB <= '0';
							JOY_POLL_STRB <= '1';
						end if;
					else
						if JOY_POLL_CLK(5) = '0' then
							JOY1_DATA(15 downto 0) <= JOY1_DATA(14 downto 0) & not JOY1_DI(0);
							JOY2_DATA(15 downto 0) <= JOY2_DATA(14 downto 0) & not JOY2_DI(0);
							JOY3_DATA(15 downto 0) <= JOY3_DATA(14 downto 0) & not JOY1_DI(1);
							JOY4_DATA(15 downto 0) <= JOY4_DATA(14 downto 0) & not JOY2_DI(1);
							AUTO_JOY_CLK <= '1';
						else
							AUTO_JOY_CLK <= '0';
							JOY_POLL_CNT <= JOY_POLL_CNT + 1;
							if JOY_POLL_CNT = 15 then
								JOYRD_BUSY <= '0';
								JOY_POLL_RUN <= '0';
								JOY_POLL_STRB <= '0';
							end if;
						end if;
					end if;
				end if;
			end if;
		end if;
	end process; 

	JOY_STRB <= OLD_JOY_STRB or AUTO_JOY_STRB;
	JOY1_CLK <= OLD_JOY1_CLK or AUTO_JOY_CLK;
	JOY2_CLK <= OLD_JOY2_CLK or AUTO_JOY_CLK;

	--debug
	process( CLK )
		variable i : integer range 0 to 7;
	begin
		if rising_edge(CLK) then
			if DBG_REG(7) = '0' then
				case DBG_REG is
					when x"00" => DBG_DAT <= NMI_EN & "0" & HVIRQ_EN & "000" & AUTO_JOY_EN;
					when x"01" => DBG_DAT <= WRIO;
					when x"02" => DBG_DAT <= WRMPYA;
					when x"03" => DBG_DAT <= WRMPYB(7 downto 0);
					when x"04" => DBG_DAT <= WRDIVA(7 downto 0);
					when x"05" => DBG_DAT <= WRDIVA(15 downto 8);
					when x"06" => DBG_DAT <= WRDIVB(7 downto 0);
					when x"07" => DBG_DAT <= HTIME(7 downto 0);
					when x"08" => DBG_DAT <= "0000000" & HTIME(8);
					when x"09" => DBG_DAT <= VTIME(7 downto 0);
					when x"0A" => DBG_DAT <= "0000000" & VTIME(8);
					when x"0B" => DBG_DAT <= "0000000" & MEMSEL;
					when x"0C" => DBG_DAT <= MDMAEN;
					when x"0D" => DBG_DAT <= HDMAEN;
					when x"0E" => DBG_DAT <= x"00";
					when x"0F" => DBG_DAT <= x"00";
					when x"10" => DBG_DAT <= NMI_FLAG & "0000000";
					when x"11" => DBG_DAT <= IRQ_FLAG & "0000000";
					when x"12" => DBG_DAT <= VBLANK & HBLANK & "00000" & JOYRD_BUSY;
					when x"13" => DBG_DAT <= RDDIV(7 downto 0);
					when x"14" => DBG_DAT <= RDDIV(15 downto 8);
					when x"15" => DBG_DAT <= RDMPY(7 downto 0);
					when x"16" => DBG_DAT <= RDMPY(15 downto 8);
					when x"17" => DBG_DAT <= MDR;
					when x"18" => DBG_DAT <= std_logic_vector(H_CNT(7 downto 0));
					when x"19" => DBG_DAT <= "0000000" & H_CNT(8);
					when x"1A" => DBG_DAT <= std_logic_vector(V_CNT(7 downto 0));
					when x"1B" => DBG_DAT <= "0000000" & V_CNT(8);
					when x"1C" => DBG_DAT <= "0000000" & FIELD;
					when x"1D" => DBG_DAT <= JOY1_DATA(7 downto 0);
					when x"1E" => DBG_DAT <= JOY1_DATA(15 downto 8);
					when x"1F" => DBG_DAT <= std_logic_vector(FRAME_CNT(7 downto 0));
					when x"20" => DBG_DAT <= std_logic_vector(FRAME_CNT(15 downto 8));
					when x"21" => DBG_DAT <= ENABLE & CPU_ACTIVEr & DMA_ACTIVEr & P65_RDY & REFRESHED & DMA_RUN & HDMA_RUN & P65_EN;
					when x"22" => DBG_DAT <= std_logic_vector(DBG_HDMA_CNT);
					when others => DBG_DAT <= x"00";
				end case;
			else
				i := to_integer(unsigned(DBG_REG(6 downto 4)));
				case DBG_REG(3 downto 0) is
					when x"0" => DBG_DAT <= DMAP(i);
					when x"1" => DBG_DAT <= BBAD(i);
					when x"2" => DBG_DAT <= A1T(i)(7 downto 0);
					when x"3" => DBG_DAT <= A1T(i)(15 downto 8);
					when x"4" => DBG_DAT <= A1B(i);
					when x"5" => DBG_DAT <= DAS(i)(7 downto 0);
					when x"6" => DBG_DAT <= DAS(i)(15 downto 8);
					when x"7" => DBG_DAT <= DASB(i);
					when x"8" => DBG_DAT <= A2A(i)(7 downto 0);
					when x"9" => DBG_DAT <= A2A(i)(15 downto 8);
					when x"A" => DBG_DAT <= NTLR(i);
					when others => DBG_DAT <= x"00";
				end case;
			end if;
		end if;
	end process; 

	DBG_CPU_BRK <= P65_BRK and (not DMA_ACTIVE) and (not REFRESHED);
	
end rtl;