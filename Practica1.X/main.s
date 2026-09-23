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
delay_cnt1:      DS 1
delay_cnt2:      DS 1
temp_div:        DS 1

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

    ; Lectura inicial ADC
    bsf     ADCON0, 1, c
ESPERAR_ADC_INIT:
    btfsc   ADCON0, 1, c
    goto    ESPERAR_ADC_INIT
    
    bcf     STATUS, 0, c
    rrcf    ADRESH, w, c
    rrcf    ADRESL, w, c
    movwf   temp_celsius, c ; Lectura directa en °C (sin multiplicar x2)
    call    CALCULAR_FAHRENHEIT

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
    bcf     INTCON2, 7, c  ; Activar Pull-ups internos de PORTB
    
    ; Detección por Flanco de BAJADA
    bcf     INTCON2, 6, c  ; INTEDG0 = 0
    bcf     INTCON2, 5, c  ; INTEDG1 = 0
    bcf     INTCON2, 4, c  ; INTEDG2 = 0

    ; Limpiar banderas
    bcf     INTCON, 1, c
    bcf     INTCON3, 0, c
    bcf     INTCON3, 1, c

    ; Habilitar Interrupciones Externas
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
    rlncf   WREG, w, c       
    rlncf   WREG, w, c       ; WREG = C * 4
    
    clrf    temp_div, c
DIV_LOOP:
    addlw   -5              
    btfss   STATUS, 0, c    
    goto    FIN_DIV
    incf    temp_div, f, c  
    goto    DIV_LOOP

FIN_DIV:
    movf    temp_celsius, w, c
    addwf   temp_div, w, c   ; C + (4*C)/5
    addlw   32               ; + 32
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
    ; Apagar ambos displays primero (Anti-parpadeo / Blanking)
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
    movlw   8
    movwf   delay_cnt1, c
LOOP_OUTER:
    movlw   100
    movwf   delay_cnt2, c
LOOP_INNER:
    decfsz  delay_cnt2, f, c
    goto    LOOP_INNER
    decfsz  delay_cnt1, f, c
    goto    LOOP_OUTER
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
    call    DELAY_DEBOUNCE
    btfss   PORTB, 0, c          ; Confirmar presión en GND
    btg     LATC, 2, c           ; Toggle Alarma / LED
    bcf     INTCON, 1, c
    retfie

ATENDER_INT1:
    call    DELAY_DEBOUNCE
    btfss   PORTB, 1, c          ; Confirmar presión en GND
    btg     LATC, 6, c           ; Toggle Ventilador
    bcf     INTCON3, 0, c
    retfie

ATENDER_INT2:
    call    DELAY_DEBOUNCE
    btfss   PORTB, 2, c          ; Confirmar presión en GND
    btg     modo_pantalla, 0, c  ; Alternar °C / °F
    bcf     INTCON3, 1, c
    retfie

ATENDER_TIMER0:
    bcf     INTCON, 2, c
    
    ; Lectura ADC directa en °C
    bcf     STATUS, 0, c
    rrcf    ADRESH, w, c
    rrcf    ADRESL, w, c
    movwf   temp_celsius, c     ; Lectura correcta sin rlncf
    call    CALCULAR_FAHRENHEIT

    ; Encendido automático del ventilador al superar 35°C
    movlw   35
    subwf   temp_celsius, w, c
    btfsc   STATUS, 0, c
    bsf     LATC, 6, c

    bsf     ADCON0, 1, c        ; Iniciar nueva conversión ADC
    retfie

DELAY_DEBOUNCE:
    movlw   80
    movwf   delay_cnt1, c
D_L1:
    movlw   100
    movwf   delay_cnt2, c
D_L2:
    decfsz  delay_cnt2, f, c
    goto    D_L2
    decfsz  delay_cnt1, f, c
    goto    D_L1
    return

END resetVec