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
temp_celsius:      DS 1
temp_fahrenheit:   DS 1
contador_muestreo: DS 1  
estado_umbral:     DS 1  
modo_pantalla:     DS 1
bloqueo_botones:   DS 1  
contador_rebote:   DS 1  ; Temporizador estricto para botones (Antirrebote)
decenas:           DS 1
unidades:          DS 1
delay_cnt1:        DS 1
delay_cnt2:        DS 1
temp_div:          DS 1

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

; Tabla 7 Segmentos (Cátodo Común)
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
    clrf    estado_umbral, c
    clrf    bloqueo_botones, c
    clrf    contador_rebote, c
    
    movlw   1               
    movwf   contador_muestreo, c 

    ; Lectura inicial ADC
    bsf     ADCON0, 1, c
ESPERAR_ADC_INIT:
    btfsc   ADCON0, 1, c
    goto    ESPERAR_ADC_INIT
    
    ; Lectura analógica inicial
    bcf     STATUS, 0, c     ; Limpiar Carry obligatoriamente antes de rotar
    rrcf    ADRESL, w, c     ; Dividir por 2 limpiamente para obtener °C
    movwf   temp_celsius, c
    call    CALCULAR_FAHRENHEIT

MAIN_LOOP:
    call    CALCULAR_DIGITOS
    call    MULTIPLEXAR_DISPLAYS
    goto    MAIN_LOOP

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
    bsf     TRISB, 0, c  ; RB0 (INT0 - Alarma)
    bsf     TRISB, 1, c  ; RB1 (INT1 - Ventilador)
    bsf     TRISB, 2, c  ; RB2 (INT2 - C/F)
    bsf     TRISA, 0, c  ; RA0 Entrada LM35

    clrf    TRISC, c     ; PORTC Salidas
    clrf    TRISD, c     ; PORTD Salidas para 7SEG
    clrf    LATC, c
    clrf    LATD, c
    return

CONFIG_INTERRUPCIONES:
    bcf     INTCON2, 7, c  ; Activar Pull-ups internos PORTB
    
    ; Flanco de bajada para los botones
    bcf     INTCON2, 6, c  
    bcf     INTCON2, 5, c  
    bcf     INTCON2, 4, c  

    bcf     INTCON, 1, c   ; Limpiar banderas
    bcf     INTCON3, 0, c
    bcf     INTCON3, 1, c

    bsf     INTCON, 4, c   ; Habilitar INT0
    bsf     INTCON3, 3, c  ; Habilitar INT1
    bsf     INTCON3, 4, c  ; Habilitar INT2
    bsf     INTCON, 7, c   ; Habilitar Globales
    return

CONFIG_ADC:
    movlw   0b00001110     ; AN0 analógico
    movwf   ADCON1, c
    movlw   0b10101010     ; Justificación DERECHA
    movwf   ADCON2, c
    movlw   0b00000001     ; Activar módulo ADC
    movwf   ADCON0, c
    return

CONFIG_TIMER0:
    movlw   0b11000111     ; Prescaler 1:256 (~32ms)
    movwf   T0CON, c
    clrf    TMR0L, c
    bcf     INTCON, 2, c
    bsf     INTCON, 5, c   ; Habilitar interrupción de Timer0
    return

CALCULAR_FAHRENHEIT:
    movf    temp_celsius, w, c
    mullw   9               
    clrf    temp_div, c     

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
    clrf    decenas, c

BUCLE_DEC:
    movlw   10
    subwf   unidades, w, c
    btfss   STATUS, 0, c
    goto    MODULO_DECENAS
    movwf   unidades, c
    incf    decenas, f, c
    goto    BUCLE_DEC

MODULO_DECENAS:
    movlw   10
    subwf   decenas, w, c
    btfss   STATUS, 0, c
    return                       
    movwf   decenas, c           
    goto    MODULO_DECENAS

MULTIPLEXAR_DISPLAYS:
    bcf     LATC, 0, c
    bcf     LATC, 1, c

    movf    decenas, w, c
    call    TABLA_7SEG
    movwf   LATD, c
    bsf     LATC, 0, c
    call    DELAY_DISPLAYS
    bcf     LATC, 0, c

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

; --- ANTIRREBOTE DE BOTONES 100% ESTABLE ---
ATENDER_INT0:
    bcf     INTCON, 1, c
    btfsc   bloqueo_botones, 0, c  
    retfie
    btg     LATC, 2, c             
    bsf     bloqueo_botones, 0, c  
    movlw   8                      ; Activar bloqueo por ~250ms
    movwf   contador_rebote, c
    retfie

ATENDER_INT1:
    bcf     INTCON3, 0, c
    btfsc   bloqueo_botones, 1, c  
    retfie
    btg     LATC, 6, c             
    bsf     bloqueo_botones, 1, c  
    movlw   8                      
    movwf   contador_rebote, c
    retfie

ATENDER_INT2:
    bcf     INTCON3, 1, c
    btfsc   bloqueo_botones, 2, c  
    retfie
    btg     modo_pantalla, 0, c    
    bsf     bloqueo_botones, 2, c  
    movlw   8                      
    movwf   contador_rebote, c
    retfie

ATENDER_TIMER0:
    bcf     INTCON, 2, c         
    
    ; --- LÓGICA DE LIBERACIÓN DE BOTONES ---
    movf    contador_rebote, w, c
    bz      VERIFICAR_MUESTREO     ; Si ya es 0, no restar
    decfsz  contador_rebote, f, c  ; Restar 1 al contador
    goto    VERIFICAR_MUESTREO     ; Si no ha llegado a 0, continuar
    clrf    bloqueo_botones, c     ; Si llegó a 0, liberar todos los botones

VERIFICAR_MUESTREO:
    ; --- TEMPORIZADOR DE ESTABILIZACIÓN ADC (~500ms) ---
    decfsz  contador_muestreo, f, c
    retfie                       

    movlw   16                   
    movwf   contador_muestreo, c

    ; --- LECTURA ANALÓGICA ---
    bcf     STATUS, 0, c         ; IMPORTANTE: Limpiar acarreo antes de rotar
    rrcf    ADRESL, w, c         
    movwf   temp_celsius, c
    call    CALCULAR_FAHRENHEIT

    ; --- CONTROL DE VENTILADOR CON HISTÉRESIS ---
    btfsc   estado_umbral, 0, c
    goto    REVISAR_BAJADA       

REVISAR_SUBIDA:
    movlw   35
    subwf   temp_celsius, w, c
    btfss   STATUS, 0, c
    goto    FIN_TIMER0_ADC       
    
    bsf     estado_umbral, 0, c  
    bsf     LATC, 6, c           
    goto    FIN_TIMER0_ADC

REVISAR_BAJADA:
    movlw   34
    subwf   temp_celsius, w, c
    btfsc   STATUS, 0, c
    goto    FIN_TIMER0_ADC       

    bcf     estado_umbral, 0, c  
    bcf     LATC, 6, c           

FIN_TIMER0_ADC:
    bsf     ADCON0, 1, c         
    retfie

END resetVec