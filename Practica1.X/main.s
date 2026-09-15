 PROCESSOR 18F4550
#include <xc.inc>

; --- CONFIGURACIÓN DE FUSIBLES ---
config FOSC = INTOSC_EC  ; Oscilador interno
config WDT = OFF        ; Watchdog desactivado
config LVP = OFF        ; Programación de bajo voltaje desactivada
config PBADEN = OFF     ; Puertos B0-B4 digitales

; --- RESERVA DE MEMORIA RAM ---
psect udata_acs
temp_celsius:    DS 1    ; Lectura en Celsius
temp_fahrenheit: DS 1    ; Lectura en Fahrenheit
modo_pantalla:   DS 1    ; 0 = Celsius, 1 = Fahrenheit
decenas:         DS 1    ; Dígito de decenas
unidades:        DS 1    ; Dígito de unidades

; --- VECTOR DE RESET ---
psect resetVec, class=CODE, reloc=2
resetVec:
    goto MAIN

; --- VECTOR DE INTERRUPCIÓN ---
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
    call CALCULAR_DIGITOS
    call MULTIPLEXAR_DISPLAYS
    goto MAIN_LOOP

; --- TABLA 7 SEGMENTOS (CÁTODO COMÚN: 0-9) ---
TABLA_7SEG:
    movf    WREG, w, c
    addwf   PCL, f, c
    retlw   0b00111111  ; 0
    retlw   0b00000110  ; 1
    retlw   0b01011011  ; 2
    retlw   0b01001111  ; 3
    retlw   0b01100110  ; 4
    retlw   0b01101101  ; 5
    retlw   0b01111101  ; 6
    retlw   0b00000111  ; 7
    retlw   0b01111111  ; 8
    retlw   0b01101111  ; 9

; --- RUTINAS DE CONFIGURACIÓN ---
CONFIG_PUERTOS:
    ; Entradas: RB0, RB1, RB2 (Pulsadores) | RA0 (LM35)
    bsf     TRISB, 0, c
    bsf     TRISB, 1, c
    bsf     TRISB, 2, c
    bsf     TRISA, 0, c

    ; Salidas: LATC (Segmentos A-G) | LATD (RD0: Alarma, RD1: Vent, RD2: Disp1, RD3: Disp2)
    clrf    TRISC, c
    clrf    TRISD, c
    clrf    LATC, c
    clrf    LATD, c
    return

CONFIG_INTERRUPCIONES:
    bcf     INTCON2, 7, c  ; RBPU habilitado
    bcf     INTCON2, 6, c
    bcf     INTCON2, 5, c
    bcf     INTCON2, 4, c

    bcf     INTCON, 1, c
    bcf     INTCON3, 0, c
    bcf     INTCON3, 1, c

    bsf     INTCON, 4, c   ; INT0IE
    bsf     INTCON3, 3, c  ; INT1IE
    bsf     INTCON3, 4, c  ; INT2IE
    bsf     INTCON, 7, c   ; GIE
    return

CONFIG_ADC:
    movlw   0b00001110
    movwf   ADCON1, c
    movlw   0b10101010
    movwf   ADCON2, c
    movlw   0b00000001
    movwf   ADCON0, c
    return

CONFIG_TIMER0:
    movlw   0b10000111
    movwf   T0CON, c
    clrf    TMR0H, c
    clrf    TMR0L, c
    bcf     INTCON, 2, c
    bsf     INTCON, 5, c
    return

; --- LÓGICA DE MULTIPLEXACIÓN Y BCD ---
CALCULAR_DIGITOS:
    ; Cargar la temperatura según el modo seleccionado (°C o °F)
    btfsc   modo_pantalla, 0, c
    goto    USAR_FAHRENHEIT

    movf    temp_celsius, w, c
    goto    SEPARAR_DEC_UNI

USAR_FAHRENHEIT:
    movf    temp_fahrenheit, w, c

SEPARAR_DEC_UNI:
    ; Restas sucesivas de 10 para obtener decenas y unidades
    clrf    decenas, c
BUCLE_DEC:
    sublw   10
    btfss   STATUS, 0, c  ; ¿Resultado negativo?
    goto    FIN_BCD
    incf    decenas, f, c
    goto    BUCLE_DEC
FIN_BCD:
    addlw   10
    movwf   unidades, c
    return

MULTIPLEXAR_DISPLAYS:
    ; 1. Mostrar Decenas en Display 1 (RD2)
    bcf     LATD, 3, c          ; Apaga Display 2
    movf    decenas, w, c
    call    TABLA_7SEG
    movwf   LATC, c             ; Envia segmentos a Puerto C
    bsf     LATD, 2, c          ; Enciende Display 1
    
    ; 2. Mostrar Unidades en Display 2 (RD3)
    bcf     LATD, 2, c          ; Apaga Display 1
    movf    unidades, w, c
    call    TABLA_7SEG
    movwf   LATC, c             ; Envia segmentos a Puerto C
    bsf     LATD, 3, c          ; Enciende Display 2
    return

; --- ISR ---
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
    btg     LATD, 0, c
    bcf     INTCON, 1, c
    retfie  1

ATENDER_INT1:
    btg     LATD, 1, c
    bcf     INTCON3, 0, c
    retfie  1

ATENDER_INT2:
    btg     modo_pantalla, 0, c
    bcf     INTCON3, 1, c
    retfie  1

 ATENDER_TIMER0:
    bcf     INTCON, 2, c        ; Limpia bandera TMR0IF
    bsf     ADCON0, 1, c        ; Inicia conversión del ADC
    movf    ADRESH, w, c
    movwf   temp_celsius, c     ; Guarda lectura en °C
    
    ; Conversión aprox a Fahrenheit: °F = (°C * 2) + 32
    rlncf   WREG, w, c          ; Multiplica °C por 2
    addlw   32                  ; Suma 32
    movwf   temp_fahrenheit, c

    ; Alerta automática: Si Temp >= 35°C activa el Ventilador (RD1)
    movlw   35
    subwf   temp_celsius, w, c
    btfsc   STATUS, 0, c        ; ¿Es mayor o igual a 35°C?
    bsf     LATD, 1, c          ; Enciende el ventilador automáticamente

    retfie  1

END resetVec


