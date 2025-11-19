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
# Etiquetas para identificar cada instrucción en los registros almacenados
.set TAG_MUL,     0
.set TAG_MULH,    1
.set TAG_MULHSU,  2
.set TAG_MULHU,   3
.set MUL_RECORD_BYTES, 24		# 6 palabras de 32 bits por caso

# Macro reutilizable para generar una entrada en la tabla de resultados.
# Guarda operandos, resultado, valor esperado, delta y el identificador de la instrucción.
.macro RUN_MUL_TEST tag, opcode, aval, bval, expect
	li t0, \aval			# Operando A (t0 = x5)
	li t1, \bval			# Operando B (t1 = x6)
	sw t0, 0(s0)
	sw t1, 4(s0)
	\opcode t2, t0, t1		# Resultado de la instrucción (t2 = x7)
	sw t2, 8(s0)
	li a0, \expect			# Valor esperado calculado a mano (a0 = x10)
	sw a0, 12(s0)
	sub a1, t2, a0			# Diferencia (a1 = x11, debe ser cero)
	sw a1, 16(s0)
	li a2, \tag
	sw a2, 20(s0)
	bnez a1, 1f			# Contabiliza error si la diferencia no es cero
	j 2f
1:
	addi s1, s1, 1
2:
	addi s0, s0, MUL_RECORD_BYTES
.endm

# Rutina principal de validación
mul_validation:
	addi sp, sp, -8
	sw s0, 0(sp)
	sw s1, 4(sp)

	la s0, mul_report		# Puntero a la tabla de resultados
	li s1, 0			# Contador de errores

	# Casos para MUL (resultado palabra baja)
	RUN_MUL_TEST TAG_MUL, mul, 5, -7, -35
	RUN_MUL_TEST TAG_MUL, mul, 0x00000400, 0x00000021, 0x00008400

	# Casos para MULH (palabra alta firmada)
	RUN_MUL_TEST TAG_MULH, mulh, 0x12345678, 0x0FEDCBA9, 0x0121FA00
	RUN_MUL_TEST TAG_MULH, mulh, 0xFFF1E240, 0x00ABCDEF, 0xFFFFF686

	# Casos para MULHSU (primer operando con signo, segundo sin signo)
	RUN_MUL_TEST TAG_MULHSU, mulhsu, 0xFFFFFFFB, 0x80000000, 0xFFFFFFFD
	RUN_MUL_TEST TAG_MULHSU, mulhsu, 0x80000000, 0x00000002, 0xFFFFFFFF

	# Casos para MULHU (ambos operandos sin signo)
	RUN_MUL_TEST TAG_MULHU, mulhu, 0xFEDCBA98, 0x01020304, 0x0100DD74
	RUN_MUL_TEST TAG_MULHU, mulhu, 0x12345678, 0x9ABCDEF0, 0x0B00EA4E

	# Guarda el número total de fallos para consultarlo en GTKWave / memoria
	la t0, mul_status
	sw s1, 0(t0)

	lw s1, 4(sp)
	lw s0, 0(sp)
	addi sp, sp, 8
	ret
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
	.space MUL_RECORD_BYTES*8	# ocho registros de 24 bytes
	.section .text
# ----- CAMBIOS MARIO MEDRANO FIN -----
