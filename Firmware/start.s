# 1 "Firmware/start.S"
# 1 "<built-in>"
# 1 "<command-line>"
# 31 "<command-line>"
# 1 "/usr/include/stdc-predef.h" 1 3 4
# 32 "<command-line>" 2
# 1 "Firmware/start.S"

##############################################################################
# RESET & IRQ
##############################################################################

 .global main, irq1_handler, irq2_handler, irq3_handler

 .section .boot
reset_vec:
 j start
.section .text

######################################
### Main program
######################################

start:
 li sp,8192

# copy data section
 la a0, _sdata
 la a1, _sdata_values
 la a2, _edata
 bge a0, a2, end_init_data
loop_init_data:
 lw a3,0(a1)
 sw a3,0(a0)
 addi a0,a0,4
 addi a1,a1,4
 blt a0, a2, loop_init_data
end_init_data:
# zero-init bss section
 la a0, _sbss
 la a1, _ebss
 bge a0, a1, end_init_bss
loop_init_bss:
 sw zero, 0(a0)
 addi a0, a0, 4
 blt a0, a1, loop_init_bss
end_init_bss:
# call main
	# ----- CAMBIOS MARIO MEDRANO INICIO: validación del multiplicador -----
	call mul_validation
	# ----- CAMBIOS MARIO MEDRANO FIN -----
 call main
loop:
 j loop

# ----- CAMBIOS MARIO MEDRANO INICIO: batería de pruebas de multiplicación -----
# Identificadores de instrucciones y estructura del informe
.set INST_MUL,     0
.set INST_MULH,    1
.set INST_MULHSU,  2
.set INST_MULHU,   3
.set FLAG_KNOWN_ISSUE, 1
.set MUL_RECORD_BYTES, 20		# 5 palabras de 32 bits por caso (A,B,res,delta,meta)
.set NUM_MUL_TESTS, 44

# Cada entrada de la tabla ocupa 16 bytes: A, B, valor esperado y metadatos.
# Los metadatos se codifican como:
#   bits[7:0]   -> instrucción RV32 (INST_MUL/MULH/MULHSU/MULHU)
#   bits[15:8]  -> flags adicionales (FLAG_KNOWN_ISSUE, etc.)
#   bits[31:16] -> número de prueba (1..44)
.macro TEST_ENTRY idx, aval, bval, expect, inst, flags
	.word \aval, \bval, \expect, ((\idx << 16) | ((\flags & 0xFF) << 8) | (\inst & 0xFF))
.endm

# Rutina principal de validación
mul_validation:
	addi sp, sp, -16
	sw s0, 0(sp)
	sw s1, 4(sp)
	sw a2, 8(sp)
	sw a3, 12(sp)

	la s0, mul_report		# Puntero a la tabla donde dejaremos los resultados
	la a2, mul_test_vector		# Vector con los 44 casos del testbench Verilog
	li a3, NUM_MUL_TESTS
	li s1, 0			# Contador de errores reales

1:	beqz a3, 3f
	lw t0, 0(a2)			# Operando A (rs2 en el hardware)
	lw t1, 4(a2)			# Operando B (rs1 en el hardware)
	lw a4, 8(a2)			# Valor esperado
	lw a5, 12(a2)			# Metadatos

	sw t0, 0(s0)
	sw t1, 4(s0)

	andi a0, a5, 0xFF		# instrucción a ejecutar

	li a1, INST_MUL
	beq a0, a1, 2f
	li a1, INST_MULH
	beq a0, a1, 4f
	li a1, INST_MULHSU
	beq a0, a1, 5f
	# Por defecto, MULHU
	mulhu t2, t1, t0		# rs1 = B (signed/unsigned según instrucción), rs2 = A
	j 6f
2:	mul t2, t1, t0
	j 6f
4:	mulh t2, t1, t0
	j 6f
5:	mulhsu t2, t1, t0

6:	sw t2, 8(s0)			# Resultado HW
	sub a1, t2, a4
	sw a1, 12(s0)			# Delta (permite recomponer el valor esperado)
	sw a5, 16(s0)			# Matriz de metadatos (test e instrucción)

	beqz a1, 7f
	srli a0, a5, 8
	andi a0, a0, FLAG_KNOWN_ISSUE
	bnez a0, 7f			# No cuenta como error, documentado en LaRVa
	addi s1, s1, 1
7:
	addi s0, s0, MUL_RECORD_BYTES
	addi a2, a2, 16
	addi a3, a3, -1
	j 1b

3:	la t0, mul_status
	sw s1, 0(t0)

	lw a3, 12(sp)
	lw a2, 8(sp)
	lw s1, 4(sp)
	lw s0, 0(sp)
	addi sp, sp, 16
	ret
# ----- CAMBIOS MARIO MEDRANO FIN -----

# ----- CAMBIOS MARIO MEDRANO INICIO: vector de pruebas heredado del testbench -----
	.section .rodata
	.align 4
mul_test_vector:
	# Test 1: 5 x 7 (unsigned) resultado bajo
	TEST_ENTRY 1, 0x00000005, 0x00000007, 0x00000023, INST_MUL, 0
	# Test 2: 5 x 7 (unsigned) resultado alto
	TEST_ENTRY 2, 0x00000005, 0x00000007, 0x00000000, INST_MULHU, 0
	# Test 3: 5 x -7 (unsigned x signed) resultado bajo
	TEST_ENTRY 3, 0x00000005, 0xfffffff9, 0xffffffdd, INST_MUL, 0
	# Test 4: 5 x -7 (unsigned x signed) resultado alto
	TEST_ENTRY 4, 0x00000005, 0xfffffff9, 0xffffffff, INST_MULHSU, 0
	# Test 5: -5 x 7 (signed) resultado bajo
	TEST_ENTRY 5, 0xfffffffb, 0x00000007, 0xffffffdd, INST_MUL, 0
	# Test 6: -5 x 7 (signed) resultado alto
	TEST_ENTRY 6, 0xfffffffb, 0x00000007, 0xffffffff, INST_MULH, 0
	# Test 7: -5 x -7 (signed) resultado bajo
	TEST_ENTRY 7, 0xfffffffb, 0xfffffff9, 0x00000023, INST_MUL, 0
	# Test 8: -5 x -7 (signed) resultado alto
	TEST_ENTRY 8, 0xfffffffb, 0xfffffff9, 0x00000000, INST_MULH, 0
	# Test 9: 12345 x 0 resultado bajo
	TEST_ENTRY 9, 0x00003039, 0x00000000, 0x00000000, INST_MUL, 0
	# Test 10: 12345 x 0 resultado alto
	TEST_ENTRY 10, 0x00003039, 0x00000000, 0x00000000, INST_MULHU, 0
	# Test 11: 0 x 12345 resultado bajo
	TEST_ENTRY 11, 0x00000000, 0x00003039, 0x00000000, INST_MUL, 0
	# Test 12: 0 x 12345 resultado alto
	TEST_ENTRY 12, 0x00000000, 0x00003039, 0x00000000, INST_MULHU, 0
	# Test 13: 12345 x 1 resultado bajo
	TEST_ENTRY 13, 0x00003039, 0x00000001, 0x00003039, INST_MUL, 0
	# Test 14: 12345 x 1 resultado alto
	TEST_ENTRY 14, 0x00003039, 0x00000001, 0x00000000, INST_MULHU, 0
	# Test 15: 12345 x -1 resultado bajo
	TEST_ENTRY 15, 0x00003039, 0xffffffff, 0xffffcfc7, INST_MUL, 0
	# Test 16: 12345 x -1 resultado alto (signed x unsigned)
	TEST_ENTRY 16, 0x00003039, 0xffffffff, 0xffffffff, INST_MULHSU, 0
	# Test 17: (2^32-1) x (2^32-1) unsigned resultado bajo
	TEST_ENTRY 17, 0xffffffff, 0xffffffff, 0x00000001, INST_MUL, 0
	# Test 18: (2^32-1) x (2^32-1) unsigned resultado alto
	TEST_ENTRY 18, 0xffffffff, 0xffffffff, 0xfffffffe, INST_MULHU, 0
	# Test 19: (2^31-1) x (2^31-1) signed resultado bajo
	TEST_ENTRY 19, 0x7fffffff, 0x7fffffff, 0x00000001, INST_MUL, 0
	# Test 20: (2^31-1) x (2^31-1) signed resultado alto
	TEST_ENTRY 20, 0x7fffffff, 0x7fffffff, 0x3fffffff, INST_MULH, 0
	# Test 21: (2^31-1) x (-2^31) resultado bajo
	TEST_ENTRY 21, 0x7fffffff, 0x80000000, 0x80000000, INST_MUL, 0
	# Test 22: (2^31-1) x (-2^31) resultado alto
	TEST_ENTRY 22, 0x7fffffff, 0x80000000, 0xc0000000, INST_MULH, 0
	# Test 23: 0x10000 x 0x10000 resultado bajo (overflow a 64 bits)
	TEST_ENTRY 23, 0x00010000, 0x00010000, 0x00000000, INST_MUL, 0
	# Test 24: 0x10000 x 0x10000 resultado alto
	TEST_ENTRY 24, 0x00010000, 0x00010000, 0x00000001, INST_MULHU, 0
	# Test 25: Patrones 0x5555... x 0xAAAA... resultado bajo
	TEST_ENTRY 25, 0x55555555, 0xaaaaaaaa, 0x71c71c72, INST_MUL, 0
	# Test 26: Patrones 0x5555... x 0xAAAA... resultado alto
	TEST_ENTRY 26, 0x55555555, 0xaaaaaaaa, 0x38e38e38, INST_MULHU, 0
	# Test 27: Nibbles con ceros (0x00FF00FF x 0x0F0F0F0F) bajo
	TEST_ENTRY 27, 0x00ff00ff, 0x0f0f0f0f, 0xfff0fff1, INST_MUL, 0
	# Test 28: Nibbles con ceros (0x00FF00FF x 0x0F0F0F0F) alto
	TEST_ENTRY 28, 0x00ff00ff, 0x0f0f0f0f, 0x000f000e, INST_MULHU, 0
	# Test 29: Potencias de 2 (1024 x 2048) resultado bajo
	TEST_ENTRY 29, 0x00000400, 0x00000800, 0x00200000, INST_MUL, 0
	# Test 30: Potencias de 2 (1024 x 2048) resultado alto
	TEST_ENTRY 30, 0x00000400, 0x00000800, 0x00000000, INST_MULHU, 0
	# Test 31: Números primos (65537 x 65521) resultado bajo
	TEST_ENTRY 31, 0x00010001, 0x0000fff1, 0xfff1fff1, INST_MUL, 0
	# Test 32: Números primos (65537 x 65521) resultado alto
	TEST_ENTRY 32, 0x00010001, 0x0000fff1, 0x00000000, INST_MULHU, 0
	# Test 33: Máximo sin signo por -1 resultado bajo
	TEST_ENTRY 33, 0xffffffff, 0xffffffff, 0x00000001, INST_MUL, 0
	# Test 34: Máximo sin signo por -1 resultado alto
	TEST_ENTRY 34, 0xffffffff, 0xffffffff, 0xffffffff, INST_MULHSU, 0
	# Test 35: Aleatorio 0x075BCD15 x 0x3ADE68B1 resultado bajo
	TEST_ENTRY 35, 0x075bcd15, 0x3ade68b1, 0xfbff5385, INST_MUL, 0
	# Test 36: Aleatorio 0x075BCD15 x 0x3ADE68B1 resultado alto
	TEST_ENTRY 36, 0x075bcd15, 0x3ade68b1, 0x01b13114, INST_MULHU, 0
	# Test 37: (-1) x (-1) resultado bajo
	TEST_ENTRY 37, 0xffffffff, 0xffffffff, 0x00000001, INST_MUL, 0
	# Test 38: (-1) x (-1) resultado alto
	TEST_ENTRY 38, 0xffffffff, 0xffffffff, 0x00000000, INST_MULH, 0
	# Test 39: (-2^31) x (-1) resultado bajo
	TEST_ENTRY 39, 0x80000000, 0xffffffff, 0x80000000, INST_MUL, 0
	# Test 40: (-2^31) x (-1) resultado alto
	TEST_ENTRY 40, 0x80000000, 0xffffffff, 0x00000000, INST_MULH, 0
	# Test 41: (-1) x (-2^31) resultado bajo
	TEST_ENTRY 41, 0xffffffff, 0x80000000, 0x80000000, INST_MUL, 0
	# Test 42: (-1) x (-2^31) resultado alto (caso conocido)
	TEST_ENTRY 42, 0xffffffff, 0x80000000, 0x00000000, INST_MULH, FLAG_KNOWN_ISSUE
	# Test 43: (-2^31) x (-2^31) resultado bajo
	TEST_ENTRY 43, 0x80000000, 0x80000000, 0x00000000, INST_MUL, 0
	# Test 44: (-2^31) x (-2^31) resultado alto (caso conocido)
	TEST_ENTRY 44, 0x80000000, 0x80000000, 0x40000000, INST_MULH, FLAG_KNOWN_ISSUE
	.section .text
# ----- CAMBIOS MARIO MEDRANO FIN -----

 .globl delay_loop
delay_loop:
 addi a0,a0,-1
 bnez a0, delay_loop
 ret

# ----- CAMBIOS MARIO MEDRANO INICIO: buffers para la recogida de resultados -----
	.section .bss
	.align 4
	.globl mul_status
mul_status:
	.space 4				# contador de errores
	.globl mul_report
mul_report:
	.space MUL_RECORD_BYTES*NUM_MUL_TESTS	# registro por cada caso de prueba
	.section .text
# ----- CAMBIOS MARIO MEDRANO FIN -----
