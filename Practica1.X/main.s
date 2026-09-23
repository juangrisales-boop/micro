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
contador_rebote:   DS 1  
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
    bcf     STATUS, 0, c
    rrcf    ADRESL, w, c
    movwf   temp_celsius, c
    
    ; --- CALIBRACIÓN DE OFFSET (AJUSTE DE TIERRA PROTOBOARD) ---
    movlw   7                    ; Ajuste de 7 grados
    cpfslt  temp_celsius, c      ; Si la temp es menor a 7, no restar
    subwf   temp_celsius, f, c   ; temp_celsius = temp_celsius - 7
    
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
    bsf     TRISB, 0, c  
    bsf     TRISB, 1, c  
    bsf     TRISB, 2, c  
    bsf     TRISA, 0, c  

    clrf    TRISC, c     
    clrf    TRISD, c     
    clrf    LATC, c
    clrf    LATD, c
    return

CONFIG_INTERRUPCIONES:
    bcf     INTCON2, 7, c  ; Pull-ups internos
    
    ; Flanco de bajada
    bcf     INTCON2, 6, c  
    bcf     INTCON2, 5, c  
    bcf     INTCON2, 4, c  

    bcf     INTCON, 1, c   
    bcf     INTCON3, 0, c
    bcf     INTCON3, 1, c

    bsf     INTCON, 4, c   
    bsf     INTCON3, 3, c  
    bsf     INTCON3, 4, c  
    bsf     INTCON, 7, c   
    return

CONFIG_ADC:
    movlw   0b00001110     ; AN0 analógico
    movwf   ADCON1, c
    movlw   0b10101010     ; Justificación DERECHA
    movwf   ADCON2, c
    movlw   0b00000001     
    movwf   ADCON0, c
    return

CONFIG_TIMER0:
    movlw   0b11000111     ; Prescaler 1:256
    movwf   T0CON, c
    clrf    TMR0L, c
    bcf     INTCON, 2, c
    bsf     INTCON, 5, c   
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

; --- INTERRUPCIONES CON FILTRO ANTI-EMI ---
ATENDER_INT0:
    bcf     INTCON, 1, c
    btfsc   PORTB, 0, c            ; Verificar que siga presionado (Filtro Ruido)
    retfie
    btfsc   bloqueo_botones, 0, c  
    retfie
    btg     LATC, 2, c             
    bsf     bloqueo_botones, 0, c  
    movlw   8                      
    movwf   contador_rebote, c
    retfie

ATENDER_INT1:
    bcf     INTCON3, 0, c
    btfsc   PORTB, 1, c            ; <-- FILTRO EMI CRÍTICO PARA EL MOTOR
    retfie
    btfsc   bloqueo_botones, 1, c  
    retfie
    btg     LATC, 6, c             
    bsf     bloqueo_botones, 1, c  
    movlw   8                      
    movwf   contador_rebote, c
    retfie

ATENDER_INT2:
    bcf     INTCON3, 1, c
    btfsc   PORTB, 2, c            ; Filtro ruido C/F
    retfie
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
    bz      VERIFICAR_MUESTREO     
    decfsz  contador_rebote, f, c  
    goto    VERIFICAR_MUESTREO     
    clrf    bloqueo_botones, c     

VERIFICAR_MUESTREO:
    decfsz  contador_muestreo, f, c
    retfie                       

    movlw   16                   
    movwf   contador_muestreo, c

    ; --- LECTURA ANALÓGICA CON CALIBRACIÓN ---
    bcf     STATUS, 0, c         
    rrcf    ADRESL, w, c         
    movwf   temp_celsius, c
    
    ; Resta el desfase de tierra
    movlw   7
    cpfslt  temp_celsius, c
    subwf   temp_celsius, f, c

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