PROCESSOR 18F4550
#include <xc.inc>

; --- CONFIGURACIÓN DE FUSIBLES ---
config FOSC = INTOSC_EC  ; Oscilador interno 8MHz
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
delay_cnt:       DS 1

; --- VECTORES DE INTERRUPCIÓN Y RESET ABSOLUTOS ---
psect resetVec, class=CODE, delta=1, abs
org 0x0000
resetVec:
    goto MAIN

psect intCodeHi, class=CODE, delta=1, abs
org 0x0008
intCodeHi:
    goto ISR_HIGH

; --- CÓDIGO PRINCIPAL Y TABLA ---
psect code, class=CODE, delta=1, reloc=2

TABLA_7SEG_DATA:
    db 0b00111111  ; 0
    db 0b00000110  ; 1
    db 0b01011011  ; 2
    db 0b01001111  ; 3
    db 0b01100110  ; 4
    db 0b01101101  ; 5
    db 0b01111101  ; 6
    db 0b00000111  ; 7
    db 0b01111111  ; 8
    db 0b01101111  ; 9

MAIN:
    movlw   0b01110000      ; Oscilador interno a 8 MHz
    movwf   OSCCON, c

    call    CONFIG_PUERTOS
    call    CONFIG_INTERRUPCIONES
    call    CONFIG_ADC
    call    CONFIG_TIMER0

    ; Lectura inicial
    bsf     ADCON0, 1, c
ESPERAR_ADC_INIT:
    btfsc   ADCON0, 1, c
    goto    ESPERAR_ADC_INIT
    
    ; Lectura 10-bits dividida entre 2 (Resolución exactitud 1°C)
    bcf     STATUS, 0, c
    rrcf    ADRESH, w, c
    rrcf    ADRESL, w, c
    movwf   temp_celsius, c

MAIN_LOOP:
    call    CALCULAR_DIGITOS
    call    MULTIPLEXAR_DISPLAYS
    goto    MAIN_LOOP

TABLA_7SEG:
    andlw   0x0F
    movwf   TBLPTRL, c
    movlw   low(TABLA_7SEG_DATA)
    addwf   TBLPTRL, f, c
    movlw   high(TABLA_7SEG_DATA)
    movwf   TBLPTRH, c
    btfsc   STATUS, 0, c
    incf    TBLPTRH, f, c
    clrf    TBLPTRU, c
    tblrd*
    movf    TABLAT, w, c
    return

CONFIG_PUERTOS:
    bsf     TRISB, 0, c  ; RB0, RB1, RB2 Entradas
    bsf     TRISB, 1, c
    bsf     TRISB, 2, c
    bsf     TRISA, 0, c  ; RA0 Entrada LM35

    clrf    TRISC, c     ; PORTC Salidas
    clrf    TRISD, c     ; PORTD Salidas para 7SEG
    clrf    LATC, c
    clrf    LATD, c
    return

CONFIG_INTERRUPCIONES:
    bcf     INTCON2, 7, c  ; Pull-ups en Puerto B
    bcf     INTCON, 1, c
    bcf     INTCON3, 0, c
    bcf     INTCON3, 1, c

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
    ; Display 1 (Decenas - RC0)
    bcf     LATC, 1, c
    movf    decenas, w, c
    call    TABLA_7SEG
    movwf   LATD, c
    bsf     LATC, 0, c
    call    DELAY_RAPIDO

    ; Display 2 (Unidades - RC1)
    bcf     LATC, 0, c
    movf    unidades, w, c
    call    TABLA_7SEG
    movwf   LATD, c
    bsf     LATC, 1, c
    call    DELAY_RAPIDO
    return

DELAY_RAPIDO:
    movlw   15             ; Retardo ultra liviano para evitar saturar Proteus
    movwf   delay_cnt, c
DELAY_LOOP:
    decfsz  delay_cnt, f, c
    goto    DELAY_LOOP
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

    retfie  1

ATENDER_INT0:
    btg     LATC, 2, c          ; LED Alarma (RC2)
    bcf     INTCON, 1, c
    retfie  1

ATENDER_INT1:
    btg     LATC, 6, c          ; LED Ventilador (RC6)
    bcf     INTCON3, 0, c
    retfie  1

ATENDER_INT2:
    btg     modo_pantalla, 0, c ; Alternar °C / °F
    bcf     INTCON3, 1, c
    retfie  1

ATENDER_TIMER0:
    bcf     INTCON, 2, c
    
    ; Conversión de 10 bits dividida por 2 = °C exactos
    bcf     STATUS, 0, c
    rrcf    ADRESH, w, c
    rrcf    ADRESL, w, c
    movwf   temp_celsius, c

    ; Fahrenheit = (Celsius * 2) + 32
    rlncf   WREG, w, c
    addlw   32
    movwf   temp_fahrenheit, c

    ; Control de ventilador (>35°C)
    movlw   35
    subwf   temp_celsius, w, c
    btfsc   STATUS, 0, c
    bsf     LATC, 6, c

    bsf     ADCON0, 1, c        ; Iniciar nueva conversión
    retfie  1

END resetVec

