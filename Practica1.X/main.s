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
temp_anterior:   DS 1  ; Para detectar transiciones del ventilador
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

; Tabla 7 Segmentos (Cátodo Común: 1 = Encendido)
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

    clrf    modo_pantalla, c
    clrf    temp_anterior, c

    ; Lectura inicial ADC (LM35 en AN0)
    bsf     ADCON0, 1, c
ESPERAR_ADC_INIT:
    btfsc   ADCON0, 1, c
    goto    ESPERAR_ADC_INIT
    
    ; Lectura limpia: ADRESL / 2 da directamente los °C
    bcf     STATUS, 0, c
    rrcf    ADRESL, w, c
    movwf   temp_celsius, c
    movwf   temp_anterior, c
    call    CALCULAR_FAHRENHEIT

MAIN_LOOP:
    call    CALCULAR_DIGITOS
    call    MULTIPLEXAR_DISPLAYS
    goto    MAIN_LOOP

; Subrutina de lectura de tabla segura en PIC18
TABLA_7SEG:
    andlw   0x0F
    addlw   low(TABLA_7SEG_DATA)
    movwf   TBLPTRL, c
    movlw   high(TABLA_7SEG_DATA)
    movwf   TBLPTRH, c
    btfsc   STATUS, 0, c
    incf    TBLPTRH, f, c
    clrf    TBLPTRU, c
    tblrd*
    movf    TABLAT, w, c
    return

CONFIG_PUERTOS:
    bsf     TRISB, 0, c  ; RB0 (INT0 - Alarma), RB1 (INT1 - Ventilador), RB2 (INT2 - C/F)
    bsf     TRISB, 1, c
    bsf     TRISB, 2, c
    bsf     TRISA, 0, c  ; RA0 Entrada LM35

    clrf    TRISC, c     ; PORTC Salidas (RC0: Decenas, RC1: Unidades, RC2: Alarma, RC6: Ventilador)
    clrf    TRISD, c     ; PORTD Salidas para 7SEG
    clrf    LATC, c
    clrf    LATD, c
    return

CONFIG_INTERRUPCIONES:
    bcf     INTCON2, 7, c  ; Activar Pull-ups internos PORTB
    
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

; Fórmula: F = (C * 9 / 5) + 32 (Con prevención de overflow 16 bits)
CALCULAR_FAHRENHEIT:
    movf    temp_celsius, w, c
    mullw   9               ; PRODH:PRODL = C * 9
    clrf    temp_div, c     ; Limpiar el cociente

DIV_16_BITS:
    movf    PRODH, w, c
    bnz     RESTAR_5        
    movlw   5
    cpfslt  PRODL, c        
    goto    RESTAR_5
    goto    FIN_DIV         

RESTAR_5:
    movlw   5
    subwf   PRODL, f, c     
    btfss   STATUS, 0, c    
    decf    PRODH, f, c     
    incf    temp_div, f, c  
    goto    DIV_16_BITS

FIN_DIV:
    movf    temp_div, w, c
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
    movwf   unidades, c
    
    ; --- PROTECCIÓN CONTRA DESBORDAMIENTO (>99) ---
    movlw   100
    subwf   unidades, w, c
    btfss   STATUS, 0, c        ; ¿El valor es >= 100?
    goto    INICIAR_BCD
    movlw   99                  ; Si es >= 100, truncar en 99
    movwf   unidades, c

INICIAR_BCD:
    clrf    decenas, c

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
    bcf     LATC, 0, c
    bcf     LATC, 1, c

    ; Display 1 (Decenas - Pin RC0)
    movf    decenas, w, c
    call    TABLA_7SEG
    movwf   LATD, c
    bsf     LATC, 0, c
    call    DELAY_DISPLAYS
    bcf     LATC, 0, c

    ; Display 2 (Unidades - Pin RC1)
    movf    unidades, w, c
    call    TABLA_7SEG
    movwf   LATD, c
    bsf     LATC, 1, c
    call    DELAY_DISPLAYS
    bcf     LATC, 1, c
    return

DELAY_DISPLAYS:
    movlw   4
    movwf   delay_cnt1, c
LOOP_OUTER:
    movlw   60
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
    bcf     INTCON, 1, c
    btg     LATC, 2, c           ; Toggle Alarma LED (Pin RC2)
    retfie

ATENDER_INT1:
    bcf     INTCON3, 0, c
    btg     LATC, 6, c           ; Toggle Ventilador Manual (Pin RC6)
    retfie

ATENDER_INT2:
    bcf     INTCON3, 1, c
    btg     modo_pantalla, 0, c  ; Alternar °C / °F
    retfie

ATENDER_TIMER0:
    bcf     INTCON, 2, c         ; Limpiar bandera Timer0
    
    ; Guardar estado anterior
    movff   temp_celsius, temp_anterior 

    ; Lectura analógica en segundo plano
    bcf     STATUS, 0, c
    rrcf    ADRESL, w, c         ; Valor en °C directo
    movwf   temp_celsius, c
    call    CALCULAR_FAHRENHEIT

    ; --- CONTROL INTELIGENTE DE VENTILADOR (POR TRANSICIÓN) ---
    ; Verifica si ANTES era < 35
    movlw   35
    subwf   temp_anterior, w, c
    btfsc   STATUS, 0, c         
    goto    REVISAR_BAJADA       ; Si ya era >= 35, vamos a ver si bajó

    ; Si antes era < 35, verificamos si AHORA es >= 35
    movlw   35
    subwf   temp_celsius, w, c
    btfss   STATUS, 0, c         
    goto    FIN_TIMER0_ADC       ; No cruzó hacia arriba, ignorar
    
    bsf     LATC, 6, c           ; ¡Cruzó hacia arriba! Encendido automático
    goto    FIN_TIMER0_ADC

REVISAR_BAJADA:
    ; Si estamos aquí, ANTES era >= 35. Verificamos si AHORA es < 35
    movlw   35
    subwf   temp_celsius, w, c
    btfsc   STATUS, 0, c         
    goto    FIN_TIMER0_ADC       ; Sigue arriba, ignorar

    bcf     LATC, 6, c           ; ¡Cruzó hacia abajo! Apagado automático

FIN_TIMER0_ADC:
    bsf     ADCON0, 1, c         ; Iniciar siguiente conversión ADC
    retfie

END resetVec