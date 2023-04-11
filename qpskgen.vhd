------------------------------------------------------------
-- QPSK generator for Metop, Aqua and NOAA20.
-- @ Rob Alblas, werkgroep Kunstmanen, 1-6-2022
-- I/Q-coding: NOAA20, Aqua or METOP (if add_metop-true)
-- Payload for all sats: metop-like, bars 0x155/0x2aa (only if add_metop=false!)
--
-- Inputs: dec_type: 11=NOAA20, 01,00=Aqua, 10=metop (add_metop=true), NOAA20 (add_metop=false)
--   add_metop=true: no visible test picture
--   add_metop=false: visible test picture (payload metop-formatted)
-- 
-- Based on generator used in GODIL decoder/generator
------------------------------------------------------------
--
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
entity qpskgen is
  GENERIC
  (
    constant add_metop: boolean:=false
  );
  PORT
  (
    dec_type    : in     std_logic_vector(1 downto 0);      -- choose generator type
    rand_on     : in     std_logic;                         -- normally on
    clk_int     : in     std_logic;                         -- clock 50 MHz
    clk_ext     : in     std_logic;                         -- clock ext.
    clk_sw      : in     std_logic;                         -- '0'=ext. clock, no div.
    do          : buffer std_logic_vector(1 downto 0):="00" --  Q / I
  );
end entity qpskgen;
architecture b of qpskgen is
  constant frames_per_line: natural:=45;
  constant reduced_frames_per_line: natural:=6;
  function size_line
  (
    constant add_metop  : boolean
  )  return natural is
  variable ret: natural;
  begin
    if add_metop then
      ret:=reduced_frames_per_line;  -- only valid frames, no payload (if bigger cpld than 240: make 45
    else
      ret:=frames_per_line;          -- valid metop payload; test picture
    end if;
    return ret;
  end function size_line;

  constant cntmax: natural:=size_line(add_metop); 

  constant t_no20: std_logic_vector(2 downto 0):="001";
  constant t_aqua: std_logic_vector(2 downto 0):="010";
  constant t_metp: std_logic_vector(2 downto 0):="011";  -- only if add_metop=true

  constant g1   : std_logic_vector( 6 downto 0):="1111001"; -- 171
  constant g2   : std_logic_vector( 6 downto 0):="1011011"; -- 133

  constant ymax: natural:=32;

  constant dat_cnt_max: natural:=6;

  signal cnt      : unsigned(10 downto 0):=(others=>'0');  -- for fractional divider
  signal dat_cnt  : natural range 0 to dat_cnt_max; 
  signal bitcnt   : natural range 0 to 7;
  signal frmcnt   : natural range 0 to 1023;
  signal lcnt     : natural range 0 to cntmax;    -- line counter (counts through one line)
  signal ycnt     : natural range 0 to ymax-1;    -- y counter (for generating bars)

  signal nrcps    : natural range 0 to dat_cnt_max;
  signal psrnd    : std_logic_vector(8 downto 1):=(others=>'0');
  signal punccnt  : natural range 0 to 2:=2;
  signal dop      : std_logic_vector(1 downto 0); 
  signal dox      : std_logic_vector(1 downto 0); 
  signal vitshift : std_logic_vector(6 downto 0);
  signal byte2    : std_logic_vector(7 downto 0):=(others=>'0');
  signal bitje_d  : std_logic; -- _vector(1 downto 0):=(others=>'0');

  signal inv      : boolean;        -- generates bars
  signal punct_on : std_logic:='0';
  signal div2     : std_logic;
  signal dectype  : std_logic_vector(2 downto 0);

  signal clk      : std_logic;         -- input clock generator
  signal clk_div  : std_logic:='0';    -- divided main clock

  type frac is array(1 to 2) of integer range 0 to 127;
  constant dt_metp    : frac:=(100,84);
  constant dt_no20aqa : frac:=(10,6);  -- see  div2!

  procedure frac_cnt
  (
    constant dab  : in    frac;
    signal d:       inout unsigned;
    signal fo:      inout std_logic
  ) is
  variable vd: unsigned(d'left+1 downto d'right) ;
  begin
    vd:=('0' & d)+dab(2);
    if vd >= dab(1) then
      vd:=vd-dab(1);
      fo<=not fo;
    end if;
    d<=vd(d'left downto d'right);
  end procedure frac_cnt;


begin
  -- pin 21,20 = dectype(1:0)
  --             01, 11=noaa
  --             00    =aqua
  --             10    =metop (aqua if add_metop=false)
  dectype<=t_metp when add_metop and dec_type="10" else t_aqua when dec_type(1)='0' else t_no20;
  clk<=clk_div when clk_sw='1' else clk_ext;

  div: process
  begin
    wait until clk_int='1';

  if add_metop then
    case dectype is
      when t_no20 | t_aqua =>
        punct_on<='0';
        nrcps <= 1;
        frac_cnt(dt_no20aqa,cnt,clk_div);  -- 50*6/10/2 =15
      when others => -- metop
        punct_on<='1';
        nrcps <= 6;
        frac_cnt(dt_metp,cnt,clk_div);     -- 50*84/100/2  =3.5 * 6
    end case;
  else
    punct_on<='0';
    nrcps <= 1;
    frac_cnt(dt_no20aqa,cnt,clk_div);  -- 50*6/10/2 =15
  end if;
  end process div;


  gen: process

  procedure fgen
  (
    byte         : inout std_logic_vector(7 downto 0);
    start        : boolean;
    inv          : boolean;
    code         : std_logic_vector(7 downto 0);
    frmcnt       : natural range 0 to 1023
  ) is
  constant sync : std_logic_vector(31 downto 0):=x"1acffc1d";
  type datarr is array(integer range <>) of std_logic_vector(7 downto 0);

  variable data: std_logic_vector(7 downto 0);
  begin
    if inv then
      data:=x"55";
    else
      data:=x"aa";
    end if;
    case frmcnt is
      when 0 => byte:=sync(31 downto 24); --y_cnt<=y_cnt+1;
      when 1 => byte:=sync(23 downto 16);
      when 2 => byte:=sync(15 downto  8);
      when 3 => byte:=sync( 7 downto  0);
      when 4 => byte:=x"00"; -- apid
      when 5 => byte:=code; 
      when 6|7|8|9|10|11 => byte:=x"00";
      when others =>
        if start then
          case frmcnt is
            when 12 => byte:=x"00";
            when 13 => byte:=x"00";
            when 14 => byte:=x"08";
            when 15 => byte:=x"67";                      -- code 103 nodig
            when 16 => byte:=x"c0";   -- + cnt2 6 MSB's  -- seq_flg = 0xc0>>6 = 3
            when 17 => byte:=x"00"; -- + cnt2 8 LSB's
            when others => 
              if frmcnt>=34 and frmcnt<882+14 then
                byte:=data;
              else
                byte:=x"00";
              end if;
          end case;
        else
          case frmcnt is
            when 12 => byte:=x"07";
            when 13 => byte:=x"ff";
            when others => 
              if frmcnt >=14 and frmcnt<896 then
                byte:=data;
              else
                byte:=x"00";
              end if;
          end case;
        end if;
    end case;
  end procedure fgen;
-- 0:  3.50 MHz=metop
-- 1: 15    MHz=NOAA20
-- 2:  7.5  MHz=aqua
  variable byte   : std_logic_vector(7 downto 0);
  variable fb     : std_logic;
  variable gt1,gt2: std_logic;
  variable bitje_o: std_logic_vector(1 downto 0);
  variable code   : std_logic_vector(7 downto 0);
  variable frmpl  : natural;      -- frames per lijn
  begin
    wait until clk='1';
    code:=x"09";
    frmpl:=15;

      if nrcps>1 and dat_cnt<nrcps-1 then
        dat_cnt<=dat_cnt + 1;
      else
        dat_cnt<=0;

        bitcnt<=(bitcnt-1) MOD 8;
        if bitcnt=1 then
          frmcnt<=(frmcnt+1) MOD 1024;
          if frmcnt=1023 then
            if lcnt<cntmax then
              lcnt<=lcnt+1;
            else
              lcnt<=0;
            end if;
          end if;

          if lcnt=0 then
            fgen(byte,true,inv,code,frmcnt);
            if frmcnt=0 then
              ycnt<=(ycnt+1) mod ymax;
              if ycnt=ymax-1 then
                inv<=not inv;
              end if;
            end if;

          elsif lcnt<frmpl then
            fgen(byte,false,inv,code,frmcnt);
          else
            fgen(byte,true,inv,x"02",frmcnt);
          end if;

          -- einde data generator

        end if;
        -- start scrambling
        if (frmcnt>=1 and frmcnt<=4) or rand_on='0' then
          psrnd<=(OTHERS=>'1');
          if bitcnt=0 then
            byte2<=byte;
          end if;
        else
          fb:=psrnd(8) XOR psrnd(5) XOR psrnd(3) XOR psrnd(1);
          psrnd(8 downto 1)<=psrnd(7 downto 1) & fb;

          if bitcnt=0 then
            byte2<=byte XOR psrnd(8 downto 1);
          end if;
        end if;

        -- par2ser
        bitje_d<=byte2(bitcnt);

        if dectype=t_aqua then  -- no viterbi; even bits -> I, odd bits to Q
          div2<=not div2;
          if bitcnt=0 then
            div2<='0';
          end if;
          if div2='1' then
            dop(1)<=bitje_d;  -- bits to I/Q resp., I=even, Q=odd
          else
            dop(0)<=bitje_d;
          end if;
        else
          -- Viterbi encoder
          punccnt<=(punccnt+1) MOD 3;
          vitshift<=bitje_d & vitshift(vitshift'left downto 1);
          gt1:='0'; gt2:='0';
          for i in vitshift'left downto vitshift'right loop
            gt1:=gt1 XOR (vitshift(i) AND g1(i));
            gt2:=gt2 XOR (vitshift(i) AND g2(i));
          end loop;
          if punct_on='1' then
            -- puncturing: metop: a,b / c,d / e,f ==> a,b / e,d
            --             fy3:   a,b / c,d / e,f ==> a,b / d,e
            case punccnt is
              when 1 =>
                dop(1)<=gt2;     -- forget gt1
              when 2 =>
                dop(0)<=gt1;     -- forget gt2
              when others =>
                dop(0)<=gt1;
                dop(1)<=gt2;
            end case;
          else -- punct_on='0'
            dop(0)<=gt1;
            dop(1)<=gt2;
          end if;

        end if;
      end if;

    -- equal divide 3->2 pairs in time;
    -- METOP:
    --  datcnt 0123456789abcd0123456789abcd0123456789abcd012345678
    --  bitcnt 777777777777776666666666666655555555555555444444444
    --  pnccnt 000000000000001111111111111122222222222222000000000
    --  dop    Z             X             y             Z
    --  dox           Z                    X                    Z     
    --
    if dectype=t_aqua then
      if div2='1' then       -- change I/Q output at the same time
        dox(1)<=dop(1);
        dox(0)<=dop(0);
      end if;
      -- OQPSK: Q = do(1) shifted
      if div2='1' then
        do(1)<=dox(1);
      else
        do(0)<=dox(0);
      end if;
    else
      if punct_on='1' then
        if punccnt=1 and dat_cnt=nrcps-1 then
          dox<=dop;
        elsif punccnt=0 and dat_cnt=nrcps/2-1 then
          dox<=dop;
        end if;
      else
        dox<=dop;
      end if;

      do(1)<=dox(0);
      do(0)<=dox(1);
    end if;
  end process gen;
end b;
