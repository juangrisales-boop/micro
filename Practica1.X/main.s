PROCESSOR 18F4550
#include <xc.inc>

; --- CONFIGURACIÓN DE FUSIBLES (Bits de Configuración) ---
config FOSC = INTOSC_EC  ; Oscilador interno
config WDT = OFF        ; Watchdog Timer desactivado
config LVP = OFF        ; Programación de bajo voltaje desactivada
config PBADEN = OFF     ; Puertos B0-B4 como entradas digitales al reset

; --- RESERVA DE MEMORIA RAM (Variables) ---
psect udata_acs
temp_celsius:    DS 1    ; Lectura en Celsius
temp_fahrenheit: DS 1    ; Lectura en Fahrenheit
modo_pantalla:   DS 1    ; 0 = Celsius, 1 = Fahrenheit
estado_sistema:  DS 1    ; Bit 0: Alarma, Bit 1: Ventilador

; --- VECTOR DE RESET ---
psect resetVec, class=CODE, reloc=2
resetVec:
    goto MAIN

; --- VECTOR DE INTERRUPCIÓN ALTA PRIORIDAD ---
psect intCodeHi, class=CODE, reloc=2
intCodeHi:
    goto ISR_HIGH

; --- CÓDIGO PRINCIPAL ---
psect code, class=CODE, reloc=2
MAIN:
    call CONFIG_PUERTOS
    call CONFIG_INTERRUPCIONES
    call CONFIG_ADC
    call CONFIG_TIMER0

MAIN_LOOP:
    ; Aquí irá la rutina de refresco para los 2 displays de 7 segmentos
    goto MAIN_LOOP

; --- RUTINAS DE CONFIGURACIÓN ---
CONFIG_PUERTOS:
    ; Configurar RB0, RB1, RB2 como entradas (Pulsadores INT0, INT1, INT2)
    bsf TRISB, 0, c
    bsf TRISB, 1, c
    bsf TRISB, 2, c
    return

CONFIG_INTERRUPCIONES:
    return

CONFIG_ADC:
    return

CONFIG_TIMER0:
    return

; --- RUTINA DE SERVICIO DE INTERRUPCIÓN (ISR) ---
ISR_HIGH:
    ; Verificar origen de interrupción (INT0, INT1, INT2, Timer0)
    retfie 1

END resetVec


