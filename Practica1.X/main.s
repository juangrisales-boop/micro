PROCESSOR 18F4550
#include <xc.inc>

; --- CONFIGURACIÓN DE FUSIBLES COMPATIBLES ---
config FOSC = INTOSC_EC
config WDT = OFF
config LVP = OFF
config PBADEN = OFF
config MCLRE = ON

; --- MEMORIA RAM ---
psect udata_acs
temp_celsius:    DS 1
temp_fahrenheit: DS 1
modo_pantalla:   DS 1
decenas:         DS 1
unidades:        DS 1
delay_cnt1:      DS 1
delay_cnt2:      DS 1

; --- VECTORES DE INTERRUPCIÓN Y RESET ABSOLUTOS ---
psect resetVec, class=CODE, delta=1, abs
org 0x0000
resetVec:
    goto MAIN

psect intCodeHi, class=CODE, delta=1, abs
org 0x0008
intCodeHi:
    goto ISR_HIGH

; --- CÓDIGO PRINCIPAL Y TABLAS ---
psect code, class=CODE, delta=1, reloc=2

; Tabla 7 Segmentos Cátodo Común mediante salto relativo directo (Garantiza lectura exacta)
TABLA_7SEG:
    andlw   0x0F
    rlncf   WREG, w, c       ; W = W * 2 (Cada instrucción retlw ocupa 2 bytes)
    addwf   PCL, f, c        ; Salto directo en la tabla
    retlw   0b00111111       ; 0
    retlw   0b00000110       ; 1
    retlw   0b01011011       ; 2
    retlw   0b01001111       ; 3
    retlw   0b01100110       ; 4
    retlw   0b01101101       ; 5
    retlw   0b01111101       ; 6
    retlw   0b00000111       ; 7
    retlw   0b01111111       ; 8
    retlw   0b01101111       ; 9

MAIN:
    movlw   0b01110000      ; Oscilador interno a 8 MHz
    movwf   OSCCON, c

    call    CONFIG_PUERTOS
    call    CONFIG_INTERRUPCIONES
    call    CONFIG_ADC
    call    CONFIG_TIMER0

    clrf    modo_pantalla, c

    ; Lectura inicial del sensor ADC
    bsf     ADCON0, 1, c
ESPERAR_ADC_INIT:
    btfsc   ADCON0, 1, c
    goto    ESPERAR_ADC_INIT
    
    bcf     STATUS, 0, c
    rrcf    ADRESH, w, c
    rrcf    ADRESL, w, c
    movwf   temp_celsius, c
    call    CALCULAR_FAHRENHEIT

MAIN_LOOP:
    call    CALCULAR_DIGITOS
    call    MULTIPLEXAR_DISPLAYS
    goto    MAIN_LOOP

CONFIG_PUERTOS:
    bsf     TRISB, 0, c  ; RB0 (INT0), RB1 (INT1), RB2 (INT2)
    bsf     TRISB, 1, c
    bsf     TRISB, 2, c
    bsf     TRISA, 0, c  ; RA0 Entrada LM35

    clrf    TRISC, c     ; PORTC Salidas (RC0: Decenas, RC1: Unidades, RC2: LED, RC6: Ventilador)
    clrf    TRISD, c     ; PORTD Salidas para 7SEG
    clrf    LATC, c
    clrf    LATD, c
    return

CONFIG_INTERRUPCIONES:
    bcf     INTCON2, 7, c  ; Pull-ups internos PORTB
    
    ; Flanco de bajada
    bcf     INTCON2, 6, c  ; INTEDG0 = 0
    bcf     INTCON2, 5, c  ; INTEDG1 = 0
    bcf     INTCON2, 4, c  ; INTEDG2 = 0

    ; Limpiar banderas
    bcf     INTCON, 1, c
    bcf     INTCON3, 0, c
    bcf     INTCON3, 1, c

    ; Habilitar Interrupciones Externas y Globales
    bsf     INTCON, 4, c   ; INT0
    bsf     INTCON3, 3, c  ; INT1
    bsf     INTCON3, 4, c  ; INT2
    bsf     INTCON, 7, c   ; GIE
    return

CONFIG_ADC:
    movlw   0b00001110     ; AN0 analógico
    movwf   ADCON1, c
    movlw   0b10101010     ; Justificación DERECHA (10 bits), 12 TAD, Fosc/32
    movwf   ADCON2, c
    movlw   0b00000001     ; Activar ADC
    movwf   ADCON0, c
    return

CONFIG_TIMER0:
    movlw   0b11000111     ; Prescaler 1:256 (~32ms)
    movwf   T0CON, c
    clrf    TMR0L, c
    bcf     INTCON, 2, c
    bsf     INTCON, 5, c   ; Habilitar Int Timer0
    return

CALCULAR_FAHRENHEIT:
    movf    temp_celsius, w, c
    mullw   9               ; PRODL = temp_celsius * 9
    movf    PRODL, w, c
    
    clrf    delay_cnt1, c   ; Usado como cociente temporal
DIV_5:
    addlw   -5
    btfss   STATUS, 0, c
    goto    FIN_DIV_5
    incf    delay_cnt1, f, c
    goto    DIV_5

FIN_DIV_5:
    movf    delay_cnt1, w, c
    addlw   32
    movwf   temp_fahrenheit, c
    return

CALCULAR_DIGITOS:
    btfsc   modo_pantalla, 0, c
    goto    USAR_FAHRENHEIT
    movf    temp_celsius, w, c
    goto    SEPARAR_DEC_UNI

USAR_FAHRENHEIT:
    movf    temp_fahrenheit, w, c

SEPARAR_DEC_UNI:
    clrf    decenas, c
    movwf   unidades, c

BUCLE_DEC:
    movlw   10
    subwf   unidades, w, c
    btfss   STATUS, 0, c
    goto    FIN_BCD
    movwf   unidades, c
    incf    decenas, f, c
    goto    BUCLE_DEC

FIN_BCD:
    return

MULTIPLEXAR_DISPLAYS:
    ; Apagar ambos displays primero (Blanking)
    bcf     LATC, 0, c
    bcf     LATC, 1, c

    ; Display 1 (Decenas - RC0)
    movf    decenas, w, c
    call    TABLA_7SEG
    movwf   LATD, c
    bsf     LATC, 0, c
    call    DELAY_DISPLAYS
    bcf     LATC, 0, c

    ; Display 2 (Unidades - RC1)
    movf    unidades, w, c
    call    TABLA_7SEG
    movwf   LATD, c
    bsf     LATC, 1, c
    call    DELAY_DISPLAYS
    bcf     LATC, 1, c
    return

DELAY_DISPLAYS:
    movlw   6
    movwf   delay_cnt1, c
L_OUTER:
    movlw   80
    movwf   delay_cnt2, c
L_INNER:
    decfsz  delay_cnt2, f, c
    goto    L_INNER
    decfsz  delay_cnt1, f, c
    goto    L_OUTER
    return

ISR_HIGH:
    btfsc   INTCON, 1, c
    goto    ATENDER_INT0

    btfsc   INTCON3, 0, c
    goto    ATENDER_INT1

    btfsc   INTCON3, 1, c
    goto    ATENDER_INT2

    btfsc   INTCON, 2, c
    goto    ATENDER_TIMER0

    retfie

ATENDER_INT0:
    btg     LATC, 2, c           ; Toggle Alarma LED (RB0)
    bcf     INTCON, 1, c
    retfie

ATENDER_INT1:
    btg     LATC, 6, c           ; Toggle Ventilador Manual (RB1)
    bcf     INTCON3, 0, c
    retfie

ATENDER_INT2:
    btg     modo_pantalla, 0, c  ; Toggle °C / °F (RB2)
    bcf     INTCON3, 1, c
    retfie

ATENDER_TIMER0:
    bcf     INTCON, 2, c         ; Limpiar bandera Timer0
    
    ; Obtener lectura completa del ADC
    bcf     STATUS, 0, c
    rrcf    ADRESH, w, c
    rrcf    ADRESL, w, c
    movwf   temp_celsius, c
    call    CALCULAR_FAHRENHEIT

    ; Encendido automático por alta temperatura (>= 35°C)
    movlw   35
    subwf   temp_celsius, w, c
    btfsc   STATUS, 0, c
    bsf     LATC, 6, c

    bsf     ADCON0, 1, c        ; Iniciar nueva conversión ADC
    retfie

END resetVec