------------------------------------------------------------
-- QPSK generator for Metop, Aqua and NOAA20.
-- @ Rob Alblas, werkgroep Kunstmanen, 1-6-2022
-- Inputs: dec_type: 11=Metop, 10=Aqua, 01=NOAA20
-- Copied and adapted from generator used in GODIL decoder/generator
------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
package satdecgen_pkg is
--  constant t_hrpt: std_logic_vector(2 downto 0):="000";
  constant t_no20: std_logic_vector(2 downto 0):="001";
  constant t_aqua: std_logic_vector(2 downto 0):="010";
--  constant t_met2: std_logic_vector(2 downto 0):="011";
  constant t_metp: std_logic_vector(2 downto 0):="011";
  constant t_fy3c: std_logic_vector(2 downto 0):="101"; -- 2.6 ms/s
  constant t_fy3a: std_logic_vector(2 downto 0):="110"; -- 2.8 Ms/s
--  constant t_lrit: std_logic_vector(2 downto 0):="110";
--  constant t_dump: std_logic_vector(2 downto 0):="111";


  function is_qpsk(dtype: std_logic_vector(2 downto 0)) return boolean;
  function is_vitpunct(dtype: std_logic_vector(2 downto 0)) return boolean;
  function is_fy(dtype: std_logic_vector(2 downto 0)) return boolean;
end package satdecgen_pkg;

package body satdecgen_pkg is
  function is_qpsk(dtype: std_logic_vector(2 downto 0)) return boolean is
  begin
    if dtype=t_metp or dtype=t_fy3a or dtype=t_fy3c or 
       dtype=t_no20 or dtype=t_aqua then
      return true;
    else
      return false;
    end if;  
  end function is_qpsk;

  function is_vitpunct(dtype: std_logic_vector(2 downto 0)) return boolean is
  begin
    if dtype=t_metp or dtype=t_fy3a or dtype=t_fy3c then
      return true;
    else
      return false;
    end if;  
  end function is_vitpunct;

  function is_fy(dtype: std_logic_vector(2 downto 0)) return boolean is
  begin
    if dtype=t_fy3a or dtype=t_fy3c then
      return true;
    else
      return false;
    end if;  
  end function is_fy;
end package body;


library std;
use std.textio.all;

-- punct  : divfact=16 ==> 50/16==3.12 MHz
-- nopunct: divfact=24 ==> 50/24==2 MHz

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.satdecgen_pkg.all;
entity qpskgen is
  PORT
  (
    dec_type    : in     std_logic_vector(1 downto 0);      -- choose generator type
    rand_on     : in     std_logic;                         -- normally on
    clk         : in     std_logic;                         -- clock 50 MHz
    do          : buffer std_logic_vector(1 downto 0):="00" --  Q / I
  );
end entity qpskgen;
architecture b of qpskgen is
  type do_type is array(integer range <>) of std_logic_vector(1 downto 0);
  type vitshifttype is array(integer range <>) of std_logic_vector(6 downto 0);

  constant sync : std_logic_vector(31 downto 0):=x"1acffc1d";
  constant g1   : std_logic_vector( 6 downto 0):="1111001"; -- 171
  constant g2   : std_logic_vector( 6 downto 0):="1011011"; -- 133


  signal dat_cnt  : natural range 0 to 2047; -- nrcps;
  signal nrcps    : natural range 0 to 2047;
  signal frmcnt   : natural range 0 to 1023;
  signal bitcnt   : natural range 0 to 7;
  signal psrnd    : std_logic_vector(8 downto 1);
  signal punccnt  : natural range 0 to 2:=2;
  signal bocnt    : natural range 0 to 2;
  signal dop      : do_type(0 to 1); 
  signal dox      : do_type(0 to 1); 
  signal vitshift : vitshifttype(0 to 1);
  signal byte2    : std_logic_vector(7 downto 0);
  signal bitje    : std_logic_vector(1 downto 0);
  signal bitje_d  : std_logic_vector(1 downto 0);
  signal ena,ena0,ena1    : std_logic:='0';

--  type frac is array(1 to 2) of integer range 0 to 2047;
--  constant dt_metp  : frac:=(1024,875);
--  constant dt_fy3ab : frac:=(256,175);
--  constant dt_fy3c  : frac:=(1024,975);
----  constant dt_no20  : frac:=(367,112); -- df=33 Hz, 1314,401: df=18 Hz; 1681,513: df=7 Hz
--  constant dt_no20  : frac:=(367,224); -- 
--  constant dt_aqua  : frac:=(367,224); -- see  div2!

  type frac is array(1 to 2) of integer range 0 to 127;
  constant dt_metp  : frac:=(100,84);
  constant dt_no20  : frac:=(10,6); -- 
  constant dt_aqua  : frac:=(10,6); -- see  div2!

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
--    d<=(d+dab(2)) MOD dab(1);
  end procedure frac_cnt;
  signal cnt: unsigned(10 downto 0):=(others=>'0'); 

--  constant cntmax: natural:=45; -- 1 omloop: ?ongeveer 2.3333/0.6654 
  constant cntmax: natural:=2; -- 
  constant dcntmax: natural:=15; -- 24
  signal   lcnt   : natural range 0 to cntmax; 
  signal   dcnt  : natural range 0 to dcntmax;
  signal   inv   : boolean;
  constant ymax: natural:=8;
  signal ycnt: natural range 0 to ymax-1;
signal punct_on: std_logic:='0';
signal div2: std_logic:='0';
signal dectype: std_logic_vector(2 downto 0);
begin
  dectype<='0' & dec_type;
  gen: process

  procedure fgen
  (
    byte         : inout std_logic_vector(7 downto 0);
    start        : boolean;
    metop0_fy31  : boolean;
    inv          : boolean;
    code         : std_logic_vector(7 downto 0);
    frmcnt       : natural range 0 to 1023;
    signal dcnt  : inout natural range 0 to dcntmax
  ) is
  constant sync : std_logic_vector(31 downto 0):=x"1acffc1d";
  type datarr is array(integer range <>) of std_logic_vector(7 downto 0);

  constant metdata: datarr(0 to 24):=(x"1f",x"cf",x"e5",x"f5",x"fc",x"9e",x"c7",x"f3",
                                      x"f9",x"7d",x"7f",x"27",x"b1",x"fc",x"fe",x"5f",
                                      x"5f",x"c9",x"ec",x"7f",x"3f",x"97",x"d7",x"f2",x"7b");
  variable data: std_logic_vector(7 downto 0);
  begin
    data:= metdata(dcnt);
--    data:= (OTHERS=>'0');
    case frmcnt is
      when 0 => byte:=sync(31 downto 24); --y_cnt<=y_cnt+1;
      when 1 => byte:=sync(23 downto 16);
      when 2 => byte:=sync(15 downto  8);
      when 3 => byte:=sync( 7 downto  0);
      when 4 => byte:=x"00"; -- apid
      when 5 => byte:=code; 
      -- when 6 => byte:=x"00"; -- apid
      -- when 7 => byte:=std_logic_vector(cnt(15 downto 8));
      -- when 8 => byte:=std_logic_vector(cnt(7 downto 0));
      when 6|7|8|9|10|11 => byte:=x"00";
      when others =>
        if start then
          case frmcnt is
            when 12 => byte:=x"00";
            when 13 => byte:=x"00";
            when 14 => byte:=x"08";
            when 15 => byte:=x"67";
            when 16 => byte:=x"c0"; -- + cnt2 6 MSB's
            when 17 => byte:=x"00"; -- + cnt2 8 LSB's
            -- when 18 => byte:=x"32";                    -- ccsds[4] = pcktlen
            -- when 19 => byte:=x"9f";                    -- ccsds[5] = pcktlen
            when others => 
              if frmcnt=18 then dcnt<=0; end if;
              if frmcnt>=34 and frmcnt<882+14 then
                byte:=data;
                if dcnt<dcntmax then dcnt<=dcnt+1; else dcnt<=0; end if;
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
                if dcnt<dcntmax then dcnt<=dcnt+1; else dcnt<=0; end if;
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
  variable metop0_fy31: boolean:=false;
  begin
    wait until clk='1';

    case dectype is
      when t_no20 =>
        punct_on<='0';
        nrcps <= 1;
--ena0<='0'; if cnt<5 then cnt<=cnt+"1"; else cnt<=(OTHERS=>'0'); ena0<='1'; end if;
        frac_cnt(dt_no20,cnt,ena0);  -- 49.152000*224/367 / 2 =15 * 1 
                                     -- 50*6/10/2
      when t_aqua =>
        punct_on<='0';
        nrcps <= 1;
        frac_cnt(dt_aqua,cnt,ena0);  -- 49.152000*224/367 / 2 =15* 1 ; see div2 
                                     -- 50*6/10/2
      when others => -- metop
        punct_on<='1';
        nrcps <= 6;
        frac_cnt(dt_metp,cnt,ena0);  -- 49.152000*875/1024  / 2 =3.5 * 6
                                     -- 50*84/100
    end case;



    if dectype=t_metp or dectype=t_no20 then
      code:=x"09";
      frmpl:=15;
    else
      code:=x"05";
      frmpl:=31;
    end if;

    ena1<=ena0;
    if ena0='1' and ena1='0' then ena<='1'; else ena<='0'; end if;
    if ena='1' then
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
            fgen(byte,true,metop0_fy31,inv,code,frmcnt,dcnt);
            if frmcnt=0 then
              ycnt<=(ycnt+1) mod ymax;
              if ycnt=ymax-1 then
                inv<=not inv;
              end if;
            end if;

--          elsif lcnt<frmpl then
--            fgen(byte,false,metop0_fy31,inv,code,frmcnt,dcnt);
          else
            fgen(byte,true,metop0_fy31,inv,x"02",frmcnt,dcnt);
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
        bitje_d(0)<=byte2(bitcnt);

        if dectype=t_aqua then
          div2<=not div2;
          if div2='1' then
            dop(0)(0)<=bitje_d(0);  -- bits to I/Q resp.
          else
            dop(0)(1)<=bitje_d(0);
          end if;
        else
          -- Viterbi encoder
          punccnt<=(punccnt+1) MOD 3;
          for j in 0 to 1 loop
            vitshift(j)<=bitje_d(j) & vitshift(j)(vitshift(j)'left downto 1);
            gt1:='0'; gt2:='0';
            for i in vitshift(j)'left downto vitshift(j)'right loop
              gt1:=gt1 XOR (vitshift(j)(i) AND g1(i));
              gt2:=gt2 XOR (vitshift(j)(i) AND g2(i));
            end loop;
            if punct_on='1' then
              -- puncturing: metop: a,b / c,d / e,f ==> a,b / e,d
              --             fy3:   a,b / c,d / e,f ==> a,b / d,e
              case punccnt is
                when 1 =>
                  dop(j)(1)<=gt2;
                when 2 =>
                  dop(j)(0)<=gt1;
                when others =>
                  dop(j)(0)<=gt1;
                  dop(j)(1)<=gt2;
              end case;
            else -- punct_on='0'
              dop(j)(0)<=gt1;
              dop(j)(1)<=gt2;
            end if;

          end loop;
        end if;
      end if;
    end if; -- dat_cnt<nrcps-1

    -- equal divide 3->2 pairs in time;
    -- METOP:
    --  datcnt 0123456789abcd0123456789abcd0123456789abcd012345678
    --  bitcnt 777777777777776666666666666655555555555555444444444
    --  pnccnt 000000000000001111111111111122222222222222000000000
    --  dop    Z             X             y             Z
    --  dox           Z                    X                    Z     
    --
    -- FY3:
    --  datcnt 0123456789abcd0123456789abcd0123456789abcd0123456789abcd0123456789abcd0123456789abcd012
    --  bitcnt 777777777777776666666666666655555555555555444444444444443333333333333322222222222222111
    --  pnccnt 000000000000000000000000000011111111111111111111111111112222222222222222222222222222000
    --  dop    Z                           X                           y                           Z
    --  dox                  Z                    .                    X                    .
    --

    if dectype=t_aqua then
      if ena='1' and div2='1' then       -- change I/Q output at the same time
        do(1)<=dop(0)(1);
        do(0)<=dop(0)(0);
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

      if punct_on='1' then
        do(1)<=dox(0)(0);
        do(0)<=dox(0)(1);
      else
        do(1)<=dox(0)(0);
        do(0)<=dox(0)(1);
        end if;
    end if;
  end process gen;
end b;
