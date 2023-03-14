# QPSK-generator
I/Q generator for Metop, Aqua and NOAA20.
Using external oscillator any datarate up to 55 MHz (or more) can be realized.

Fits in EPM240 CPLD; use Quartus lite (free software) to synthesize and load the code.

Direct programming: use files in the zip-file, vhdl files not needed.
For Windows, use the .bat file; check the full path to the quartus_pgm.exe program!

Pinning: 2=I, 4=Q, 18/20: 11=Metop, 01=Aqua, 10=NOAA20, 14=external clock, 16=switch internal/external clock
