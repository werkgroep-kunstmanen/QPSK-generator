# QPSK-generator
I/Q generator for Metop, Aqua and NOAA20.
Using external oscillator any datarate up to 55 Msymbols/s (or more) can be realized.

qpskgen.vhd: use generic to add or don't add Metop.

qpskgen_nam: NOAA20, Aqua and Metop. Frame-level is OK, but payload is not valid. So only suitable to check bit- and frame synchronisation.

qpskgen_na: NOAA20 and Aqua. Payload is METOP-like; decoding as if it is metop gives grey-bars with level 0x2aa and 0x155 (10 bits/ pixel).

Fits in EPM240 CPLD; use Quartus lite (free software) to synthesize and load the code.

Direct programming: use files in the zip-file, vhdl files not needed.
For Windows, use the .bat file; check the full path to the quartus_pgm.exe program!

Pinning: 2=I, 4=Q, 21/20: 00,01=Aqua, 10=Metop (version '_nam'), 11=NOAA20, 14=external clock, 16=switch internal/external clock ('1'=internal)
All inputs have pullup's, so not connected = '1'.
