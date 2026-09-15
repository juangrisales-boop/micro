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
    ; Entradas para pulsadores: RB0(INT0), RB1(INT1), RB2(INT2)
    bsf     TRISB, 0, c
    bsf     TRISB, 1, c
    bsf     TRISB, 2, c
    
    ; Salidas: RD0 para LED Alarma, RD1 para Ventilador
    bcf     TRISD, 0, c
    bcf     TRISD, 1, c
    
    ; Apagar salidas al inicio
    bcf     LATD, 0, c
    bcf     LATD, 1, c
    return

 CONFIG_INTERRUPCIONES:
    ; 1. INTCON2: Activar pull-ups internas y flanco de bajada (al presionar)
    bcf     INTCON2, 7, c  ; RBPU = 0 (Pull-ups habilitadas en Puerto B)
    bcf     INTCON2, 6, c  ; INTEDG0 = 0 (Flanco de bajada RB0)
    bcf     INTCON2, 5, c  ; INTEDG1 = 0 (Flanco de bajada RB1)
    bcf     INTCON2, 4, c  ; INTEDG2 = 0 (Flanco de bajada RB2)

    ; 2. Limpiar banderas de interrupción antes de activar
    bcf     INTCON, 1, c   ; INT0IF = 0
    bcf     INTCON3, 0, c  ; INT1IF = 0
    bcf     INTCON3, 1, c  ; INT2IF = 0

    ; 3. Habilitar habilitadores de interrupción
    bsf     INTCON, 4, c   ; INT0IE = 1 (Habilita INT0)
    bsf     INTCON3, 3, c  ; INT1IE = 1 (Habilita INT1)
    bsf     INTCON3, 4, c  ; INT2IE = 1 (Habilita INT2)

    ; 4. INTCON: Habilitar interrupciones globales
    bsf     INTCON, 7, c   ; GIE = 1
    return

CONFIG_ADC:
    return

CONFIG_TIMER0:
    return

; --- RUTINA DE SERVICIO DE INTERRUPCIÓN (ISR) ---
 ISR_HIGH:
    ; ¿Fue INT0? (RB0 - Alarma)
    btfsc   INTCON, 1, c
    goto    ATENDER_INT0

    ; ¿Fue INT1? (RB1 - Ventilador)
    btfsc   INTCON3, 0, c
    goto    ATENDER_INT1

    ; ¿Fue INT2? (RB2 - Escala °C / °F)
    btfsc   INTCON3, 1, c
    goto    ATENDER_INT2

    retfie 1

ATENDER_INT0:
    btg     LATD, 0, c          ; Alterna estado del LED Alarma (RD0)
    bcf     INTCON, 1, c        ; Limpia bandera INT0IF
    retfie 1

ATENDER_INT1:
    btg     LATD, 1, c          ; Alterna estado del Ventilador (RD1)
    bcf     INTCON3, 0, c       ; Limpia bandera INT1IF
    retfie 1

ATENDER_INT2:
    btg     modo_pantalla, 0, c ; Alterna entre °C (0) y °F (1)
    bcf     INTCON3, 1, c       ; Limpia bandera INT2IF
    retfie 1

END resetVec


