@ DualDS test ROM — ARM9 program. Original work, GPL-3.0-or-later (part of DualDS).
@ Top screen (engine A, VRAM display mode): red while A is released, green while A is held.
@ Bottom screen (engine B): blue backdrop.
    .arm
    .global _start
_start:
    ldr   r0, =0x04000304      @ POWCNT1
    ldr   r1, =0x8203          @ LCD on, 2D A, 2D B, engine A on top screen
    strh  r1, [r0]
    ldr   r0, =0x04000240      @ VRAMCNT_A
    mov   r1, #0x80            @ enable, MST=0 (LCDC)
    strb  r1, [r0]
    ldr   r0, =0x04000000      @ DISPCNT A
    ldr   r1, =0x00020000      @ display mode 2: VRAM A
    str   r1, [r0]
    ldr   r0, =0x04001000      @ DISPCNT B
    ldr   r1, =0x00010000      @ display mode 1: normal (backdrop only)
    str   r1, [r0]
    ldr   r0, =0x05000400      @ engine B palette entry 0 (backdrop)
    ldr   r1, =0x7C00          @ blue (BGR555)
    strh  r1, [r0]
loop:
    ldr   r0, =0x04000130      @ KEYINPUT (active low)
    ldrh  r1, [r0]
    tst   r1, #1               @ bit 0 = A
    ldrne r2, =0x001F          @ released: red
    ldreq r2, =0x03E0          @ held: green
    orr   r2, r2, r2, lsl #16
    ldr   r0, =0x06800000      @ VRAM A (LCDC)
    ldr   r3, =(256*192/2)
fill:
    str   r2, [r0], #4
    subs  r3, r3, #1
    bne   fill
    b     loop
    .pool
